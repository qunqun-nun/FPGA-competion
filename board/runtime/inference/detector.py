"""DPU-only runner -> exact NumPy CPU heads -> DFL/sigmoid/NMS.

Hardware programming/camera/MMIO remain the caller's responsibility.
"""
import hashlib
from pathlib import Path
from threading import Lock
import numpy as np

if __package__:
    from .cpu_heads.run_cpu_heads import CpuHeads
    from .postprocess import ImageTransform, decode
else:
    from cpu_heads.run_cpu_heads import CpuHeads
    from postprocess import ImageTransform, decode


def quantize_rgb888(rgb, fix_point=6):
    """Pixels 0..255 -> normalized once -> signed fixed point, DPU_ROUND."""
    rgb = np.asarray(rgb)
    if rgb.dtype != np.uint8 or rgb.shape != (640, 640, 3):
        raise ValueError('Expected raw uint8 RGB pixels [640,640,3], not normalized floats')
    if fix_point != 6:
        raise ValueError('This extracted model requires input fix_point=6')
    scaled = rgb.astype(np.float64) * (2.0 ** fix_point / 255.0)
    return np.ascontiguousarray(np.clip(np.floor(scaled + 0.5), -128, 127).astype(np.int8)[None])


def gray480_to_rgb640(gray):
    gray = np.asarray(gray)
    if gray.dtype != np.uint8 or gray.shape != (480, 640):
        raise ValueError('gray480 must be uint8 [480,640]')
    rgb = np.full((640, 640, 3), 114, dtype=np.uint8)
    rgb[80:560] = gray[:, :, None]
    return rgb


def rgb888_from_ddr(buffer, stride_bytes=1920):
    """Copy a CPU-visible 640x640 packed R,G,B byte buffer, optional row padding.

    Caller must wait for a complete frame and invalidate/sync DMA cache first.
    This does not interpret packed AXI words or map physical addresses.
    """
    if not isinstance(stride_bytes, int) or stride_bytes < 1920:
        raise ValueError('stride_bytes must be an integer >= 1920')
    raw = np.frombuffer(buffer, dtype=np.uint8)
    required = 639 * stride_bytes + 1920
    if raw.size < required:
        raise ValueError('DDR buffer shorter than RGB888 frame')
    rows = np.lib.stride_tricks.as_strided(raw, shape=(640, 1920), strides=(stride_bytes, 1))
    return rows.copy().reshape(640, 640, 3)


def _check_tensor_int8(tensor):
    dtype = getattr(tensor, 'dtype', None)
    if dtype is None and hasattr(tensor, 'get_data_type'):
        dtype = tensor.get_data_type()
    if 'int8' not in str(dtype).lower() or 'uint8' in str(dtype).lower():
        raise ValueError('Expected signed INT8 tensor: ' + tensor.name + ' dtype=' + str(dtype))


class DpuRunner:
    """Strict adapter for this model; imports VART/XIR only on construction."""
    def __init__(self, model_path, heads=None):
        import xir
        import vart
        self.heads = heads or CpuHeads()
        digest = hashlib.sha256(Path(model_path).read_bytes()).hexdigest()
        if digest != self.heads.spec['model_sha256']:
            raise ValueError('XModel SHA256 differs from extracted CPU head weights')
        self.graph = xir.Graph.deserialize(str(model_path))
        def find_dpu(s):
            if s.has_attr('device') and str(s.get_attr('device')).upper() == 'DPU':
                return [s]
            result = []
            for child in s.toposort_child_subgraph():
                result.extend(find_dpu(child))
            return result
        subgraphs = find_dpu(self.graph.get_root_subgraph())
        if len(subgraphs) != 1:
            raise ValueError('Expected exactly one DPU subgraph, found %d' % len(subgraphs))
        self.runner = vart.Runner.create_runner(subgraphs[0], 'run')
        self._validate()

    @classmethod
    def from_runner(cls, runner, heads=None):
        """Inject an already-created DPU-only Runner, also useful for offline fakes.

        Caller must ensure it was constructed from the hash-matched XModel.
        Tensor metadata is still checked; no GraphRunner accepted.
        """
        obj = cls.__new__(cls)
        obj.heads = heads or CpuHeads()
        obj.runner = runner
        obj._validate()
        return obj

    def _validate(self):
        self._lock = Lock()
        inputs = self.runner.get_input_tensors()
        self.outputs = self.runner.get_output_tensors()
        if len(inputs) != 1 or tuple(inputs[0].dims) != (1, 640, 640, 3):
            raise ValueError('Expected one NHWC [1,640,640,3] DPU input')
        _check_tensor_int8(inputs[0])
        self.input_fix_point = int(inputs[0].get_attr('fix_point'))
        if self.input_fix_point != 6:
            raise ValueError('Input fix_point mismatch')
        if hasattr(self.runner, 'get_tensor_format'):
            if 'NHWC' not in str(self.runner.get_tensor_format()).upper():
                raise ValueError('Only NHWC Runner layout supported')
        expected = {b['input_name']: b for b in self.heads.spec['branches']}
        names = [t.name for t in self.outputs]
        if len(names) != 6 or set(names) != set(expected):
            raise ValueError('DPU output names mismatch; actual=' + repr(names))
        for t in self.outputs:
            _check_tensor_int8(t)
            b = expected[t.name]
            if list(t.dims) != b['input_shape'] or int(t.get_attr('fix_point')) != b['input_fix_point']:
                raise ValueError('DPU output shape/fix_point mismatch: ' + t.name)

    def run(self, quantized):
        q = np.asarray(quantized)
        if q.dtype != np.int8 or q.shape != (1, 640, 640, 3):
            raise ValueError('Expected already-quantized INT8 [1,640,640,3]')
        inputs = [np.ascontiguousarray(q)]
        outputs = [np.empty(tuple(t.dims), dtype=np.int8) for t in self.outputs]
        with self._lock:
            job = self.runner.execute_async(inputs, outputs)
            # Installed VART bindings vary: demos use an integer job id,
            # while the 3.5 API also documents (job_id, enqueue_status).
            if isinstance(job, tuple) and len(job) == 2:
                job, enqueue_status = job
                if enqueue_status != 0:
                    raise RuntimeError('DPU enqueue failed: ' + repr(enqueue_status))
            if not isinstance(job, (int, np.integer)) or job < 0:
                raise RuntimeError('DPU enqueue failed: ' + repr(job))
            try:
                status = self.runner.wait(int(job))
            except TypeError:
                # Some Python bindings require documented (jobid, timeout).
                status = self.runner.wait((int(job), -1))
            if status != 0:
                raise RuntimeError('DPU wait failed: ' + repr(status))
        return {t.name: y for t, y in zip(self.outputs, outputs)}


class Detector:
    def __init__(self, model_path=None, backend=None, confidence=0.25,
                 iou_threshold=0.45, max_detections=100):
        if not 0 <= confidence <= 1 or not 0 <= iou_threshold <= 1 or max_detections <= 0:
            raise ValueError('Invalid detector settings')
        self.heads = CpuHeads()
        if backend is None:
            if model_path is None:
                raise ValueError('Supply model_path or an explicit offline backend')
            backend = DpuRunner(model_path, self.heads)
        self.backend = backend
        self.confidence = confidence
        self.iou_threshold = iou_threshold
        self.max_detections = max_detections

    def detect(self, gray480):
        """uint8 [480,640] -> list of bbox xywh/confidence dictionaries."""
        return self.detect_pl_rgb888(gray480_to_rgb640(gray480))

    def detect_pl_rgb888(self, rgb640, transform=None):
        """Already-letterboxed uint8 RGB888 [640,640,3]; no resize/re-padding.

        Defaults to source 640x480 + 80 rows top/bottom. Other geometries
        MUST supply ImageTransform. Pixels are normalized exactly once here.
        """
        fp = getattr(self.backend, 'input_fix_point', 6)
        q = quantize_rgb888(rgb640, fp)
        return self.detect_quantized(q, transform)

    def detect_pl_ddr(self, buffer, stride_bytes=1920, transform=None):
        return self.detect_pl_rgb888(rgb888_from_ddr(buffer, stride_bytes), transform)

    def detect_quantized(self, q, transform=None):
        """INT8 NHWC model input: bypass normalization and quantization."""
        q = np.asarray(q)
        if q.dtype != np.int8 or q.shape != (1, 640, 640, 3):
            raise ValueError('Expected INT8 [1,640,640,3]')
        return self.decode_features(self.backend.run(q), transform)

    def decode_features(self, named_raw_int8_features, transform=None):
        """Offline replay of exact named DPU INT8 outputs, no dequantization here."""
        logits = self.heads.run(named_raw_int8_features)
        return decode(logits, transform, self.confidence, self.iou_threshold, self.max_detections)
