"""Offline contract tests: synthetic data, no VART, no accuracy claims."""
import unittest
import numpy as np
from detector import Detector, DpuRunner, CpuHeads, gray480_to_rgb640, quantize_rgb888, rgb888_from_ddr
from postprocess import ImageTransform, decode, nms, sigmoid


def empty_logits():
    result = {}
    for i, size in enumerate((80, 40, 20)):
        result['cv2_%d' % i] = np.zeros((1, size, size, 64), np.float32)
        result['cv3_%d' % i] = np.full((1, size, size, 1), -100, np.float32)
    return result


def activate(logits, level, row, col, bins=(2, 3, 4, 5), score=8):
    reg = np.full((4, 16), -100, np.float32)
    for side, value in enumerate(bins):
        reg[side, value] = 100
    logits['cv2_%d' % level][0, row, col] = reg.reshape(64)
    logits['cv3_%d' % level][0, row, col, 0] = score


class Tensor:
    dtype = 'XINT8'
    def __init__(self, name, shape, fp):
        self.name, self.dims, self.fp = name, shape, fp
    def get_attr(self, name):
        if name != 'fix_point': raise KeyError(name)
        return self.fp


class FakeVart:
    def __init__(self):
        self.inputs = [Tensor('input', [1,640,640,3], 6)]
        # Deliberately permute outputs; matching must use names, never indices.
        self.outputs = [Tensor(b['input_name'], b['input_shape'], b['input_fix_point'])
                        for b in reversed(CpuHeads().spec['branches'])]
        self.status = 0
        self.executions = 0
    def get_input_tensors(self): return self.inputs
    def get_output_tensors(self): return self.outputs
    def get_tensor_format(self): return 'TensorFormat.NHWC'
    def execute_async(self, inputs, outputs):
        self.last_input = inputs[0].copy()
        self.executions += 1
        for i, out in enumerate(outputs): out.fill(i)
        return 7
    def wait(self, job):
        assert job == 7
        return self.status


class InferenceTests(unittest.TestCase):
    def test_gray_and_quantization_exactly_once(self):
        gray = np.full((480,640),255,np.uint8)
        rgb = gray480_to_rgb640(gray)
        np.testing.assert_array_equal(rgb[80:560],255)
        np.testing.assert_array_equal(rgb[:80],114)
        np.testing.assert_array_equal(rgb[560:],114)
        q = quantize_rgb888(rgb)
        np.testing.assert_array_equal(q[0,80:560],64)
        np.testing.assert_array_equal(q[0,:80],29)
        with self.assertRaises(ValueError): quantize_rgb888(rgb.astype(np.float32)/255)
        with self.assertRaises(ValueError): gray480_to_rgb640(gray.T)

    def test_all_256_input_values(self):
        rgb = np.broadcast_to(np.arange(640,dtype=np.uint16)[None,:,None] % 256,(640,640,3)).astype(np.uint8)
        q = quantize_rgb888(rgb)
        # Independent scalar reference.
        expected = np.array([int(float(v)*64/255+0.5) for v in range(256)],np.int8)
        np.testing.assert_array_equal(q[0,0,:256,0],expected)

    def test_ddr_row_stride_and_rgb_order(self):
        stride = 1936
        raw = np.full((640,stride), 99,np.uint8)
        raw[:,:1920] = np.tile([7,51,203],640)
        rgb = rgb888_from_ddr(raw, stride)
        np.testing.assert_array_equal(rgb[639,639],[7,51,203])
        with self.assertRaises(ValueError): rgb888_from_ddr(b'123')
        with self.assertRaises(ValueError): rgb888_from_ddr(raw, 100)

    def test_empty_and_extreme_logits(self):
        self.assertEqual(decode(empty_logits()),[])
        np.testing.assert_array_equal(sigmoid(np.array([-1e30,1e30],np.float32)),[0,1])

    def test_dfl_each_stride_source_restore(self):
        for level,stride in enumerate((8,16,32)):
            logits = empty_logits()
            activate(logits,level,10,10)
            d = decode(logits)[0]
            cx = cy = 10.5*stride
            x1,y1 = max(0,cx-2*stride),max(0,cy-3*stride-80)
            x2,y2 = min(640,cx+4*stride),min(480,cy+5*stride-80)
            np.testing.assert_allclose(d['bbox'],[x1,y1,x2-x1,y2-y1],atol=1e-4)
            self.assertAlmostEqual(d['confidence'],1/(1+np.exp(-8)),places=6)

    def test_uniform_distribution_expectation(self):
        logits = empty_logits()
        logits['cv3_0'][0,40,40,0] = 5
        # Uniform DFL distribution has expectation 7.5, giving 120x120 box.
        np.testing.assert_allclose(decode(logits)[0]['bbox'],[264,184,120,120])

    def test_scale_restore_and_clip(self):
        logits=empty_logits(); activate(logits,0,30,30)
        transform=ImageTransform(320,240,2,0,80)
        np.testing.assert_allclose(decode(logits,transform)[0]['bbox'],[114,70,24,32])
        activate(logits,0,0,0,score=9)
        # Detection wholly in top letterbox padding is discarded after clipping.
        self.assertEqual(len(decode(logits,transform)),1)

    def test_nms_and_limits(self):
        boxes=np.array([[0,0,10,10],[1,1,11,11],[30,30,40,40]],np.float32)
        np.testing.assert_array_equal(nms(boxes,np.array([.9,.8,.7])),[0,2])
        np.testing.assert_array_equal(nms(boxes,np.array([.9,.8,.7]),max_detections=1),[0])
        np.testing.assert_array_equal(nms(np.empty((0,4)),np.empty(0)),[])
        # Exact threshold is retained (IoU=1 at threshold=1).
        np.testing.assert_array_equal(nms(boxes[:1].repeat(2,axis=0),np.array([1,1]),1),[0,1])

    def test_cross_scale_nms(self):
        logits=empty_logits()
        # Boxes [204,204,284,284] and [200,200,296,296], overlapping across scales.
        activate(logits,0,30,30,(5,5,5,5),score=9)
        activate(logits,1,15,15,(3,3,3,3),score=8)
        self.assertEqual(len(decode(logits)),1)

    def test_decode_rejects_invalid(self):
        logits=empty_logits(); logits['cv2_0'][0,0,0,0]=np.nan
        with self.assertRaises(ValueError): decode(logits)
        with self.assertRaises(ValueError): decode(empty_logits(),confidence=1.1)
        with self.assertRaises(ValueError): ImageTransform(scale=0)
        logits=empty_logits(); logits['cv3_0']=np.zeros((1,1))
        with self.assertRaises(ValueError): decode(logits)

    def test_runner_output_name_mapping_and_errors(self):
        fake=FakeVart(); backend=DpuRunner.from_runner(fake)
        outputs=backend.run(np.zeros((1,640,640,3),np.int8))
        for i,t in enumerate(fake.outputs): np.testing.assert_array_equal(outputs[t.name],i)
        fake.status=-1
        with self.assertRaises(RuntimeError): backend.run(np.zeros((1,640,640,3),np.int8))

    def test_runner_tuple_wait_api(self):
        fake=FakeVart()
        def wait(job):
            if not isinstance(job,tuple): raise TypeError('tuple required')
            self.assertEqual(job,(7,-1))
            return 0
        fake.wait=wait
        backend=DpuRunner.from_runner(fake)
        self.assertEqual(len(backend.run(np.zeros((1,640,640,3),np.int8))),6)
        fake=FakeVart(); fake.outputs[0].name='wrong'
        with self.assertRaises(ValueError): DpuRunner.from_runner(fake)
        fake=FakeVart(); fake.outputs[0].fp=99
        with self.assertRaises(ValueError): DpuRunner.from_runner(fake)
        fake=FakeVart(); fake.inputs[0].dtype='FLOAT32'
        with self.assertRaises(ValueError): DpuRunner.from_runner(fake)

    def test_pipeline_real_cpu_weights_fake_runner(self):
        fake=FakeVart(); detector=Detector(backend=DpuRunner.from_runner(fake),confidence=1)
        self.assertEqual(detector.detect(np.full((480,640),255,np.uint8)),[])
        np.testing.assert_array_equal(fake.last_input[0,80:560],64)
        q=np.full((1,640,640,3),17,np.int8)
        self.assertEqual(detector.detect_quantized(q),[])
        np.testing.assert_array_equal(fake.last_input,q)
        self.assertEqual(fake.executions,2)

    def test_runner_tuple_enqueue_api(self):
        fake=FakeVart()
        enqueue=fake.execute_async
        fake.execute_async=lambda inputs,outputs: (enqueue(inputs,outputs),0)
        backend=DpuRunner.from_runner(fake)
        self.assertEqual(len(backend.run(np.zeros((1,640,640,3),np.int8))),6)
        fake.execute_async=lambda inputs,outputs: (7,-1)
        with self.assertRaises(RuntimeError): backend.run(np.zeros((1,640,640,3),np.int8))


if __name__=='__main__':
    unittest.main(verbosity=2)
