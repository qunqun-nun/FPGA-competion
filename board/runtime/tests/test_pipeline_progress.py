"""Targeted CLI regressions: real hardware is never opened by these tests."""
import contextlib
import io
import json
from pathlib import Path
import runpy
import signal
import sys
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch
import numpy as np

RUNTIME = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(RUNTIME))
import pl_runtime
from test_pl_runtime import Clock


class FakeBoard:
    def __init__(self, requests, ddr=True):
        self.requests = dict(requests)
        self.ddr = ddr
        self.sent = {}
        self.published = []
        self.closed = False

    def start(self):
        pass

    def send(self, gray):
        self.sent[len(self.sent)] = gray.copy()

    def request(self):
        frame_id = self.requests.pop(len(self.sent), None)
        return None if frame_id is None else (len(self.sent), frame_id, 0, 1)

    def read_rgb(self, request):
        rgb = np.full((640, 640, 3), 114, np.uint8)
        rgb[80:560] = self.sent[request[1]][:, :, None]
        return rgb

    def publish(self, request, detections):
        self.published.append(request)

    def snapshot(self):
        return {'completed': len(self.sent) if self.ddr else 0}

    def close(self):
        self.closed = True


class PipelineProgressTests(unittest.TestCase):
    def invoke(self, board, frames):
        clock = Clock()
        calls = []

        def resize(*a, **kw):
            calls.append(True)
            return np.full((480, 640), len(calls) % 256, np.uint8)

        cv = SimpleNamespace(IMREAD_GRAYSCALE=0, INTER_LINEAR=1,
                             imread=lambda *a: np.zeros((480, 640), np.uint8), resize=resize)
        detector = SimpleNamespace(detect_pl_rgb888=lambda rgb: [])
        out, err = io.StringIO(), io.StringIO()
        with tempfile.TemporaryDirectory() as tmp:
            result = Path(tmp) / 'results.jsonl'
            args = ['run_pipeline.py', '--image', 'synthetic', '--frames', str(frames),
                    '--fps', '1000', '--output', str(result)]
            with patch.object(pl_runtime, 'Board', return_value=board), \
                    patch.dict(sys.modules, {'pl_clock':SimpleNamespace(assert_clock=lambda *a: {},record=lambda *a: None),'cv2': cv, 'inference': SimpleNamespace(Detector=lambda **k: detector)}), \
                    patch.object(sys, 'argv', args), patch.object(signal, 'signal'), \
                    patch('time.monotonic', clock.monotonic), patch('time.sleep', clock.sleep), \
                    contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
                try:
                    runpy.run_path(str(RUNTIME / 'run_pipeline.py'), run_name='__main__')
                    code = 0
                except SystemExit as exc:
                    code = exc.code
            records = [json.loads(line) for line in result.read_text().splitlines()]
        self.assertTrue(board.closed)
        return code, out.getvalue(), err.getvalue(), records

    def test_zero_inferences_is_failure_even_if_ddr_completed(self):
        code, out, err, records = self.invoke(FakeBoard({}), 3)
        self.assertEqual(code, 1)
        self.assertIn('No DPU inference/result commit', err)
        self.assertNotIn('PL_PIPELINE_STOPPED', out)
        self.assertEqual(records, [])

    def test_zero_ddr_completion_is_not_dma_success(self):
        code, out, err, records = self.invoke(FakeBoard({1: 0}, ddr=False), 1)
        self.assertEqual(code, 1)
        self.assertIn('No completed DDR frame', err)
        self.assertNotIn('PL_PIPELINE_STOPPED', out)

    def test_latest_complete_request_uses_its_own_image(self):
        # On third input, request the second complete image, which differs from
        # both the first and currently submitted third images.
        board = FakeBoard({1: 0, 3: 1})
        code, out, err, records = self.invoke(board, 3)
        self.assertEqual((code, err), (0, ''))
        self.assertEqual([r['frame_id'] for r in records], [0, 1])
        self.assertEqual(len(board.published), 2)
        self.assertIn('PL_PIPELINE_STOPPED', out)

    def test_legitimate_tracking_gap_is_allowed(self):
        code, out, err, records = self.invoke(FakeBoard({1: 0, 17: 15}), 18)
        self.assertEqual((code, err), (0, ''))
        self.assertEqual(len(records), 2)

    def test_continuous_camera_without_requests_hits_watchdog(self):
        code, out, err, records = self.invoke(FakeBoard({}), 70)
        self.assertEqual(code, 1)
        self.assertIn('No DPU request/result progress', err)
        self.assertNotIn('PL_PIPELINE_STOPPED', out)


if __name__ == '__main__':
    unittest.main()
