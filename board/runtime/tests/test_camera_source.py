"""LatestCamera offline thread tests using controlled captures, no UVC/OpenCV.

Queues and Events coordinate reads; no real camera or device file is opened.
"""
import contextlib
import io
import json
from pathlib import Path
import queue
import runpy
import signal
import sys
import tempfile
import threading
import time
from types import ModuleType, SimpleNamespace
import unittest
from unittest.mock import Mock, patch
import numpy as np

RUNTIME=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(RUNTIME))
from camera_source import LatestCamera
EVIDENCE=Path(__file__).resolve().parent/'evidence'


class ControlledCapture:
    """read() blocks until the test feeds a frame/failure; release logs races."""
    def __init__(self):
        self.items=queue.Queue()
        self.condition=threading.Condition()
        self.read_calls=0
        self.read_active=threading.Event()
        self.release_calls=0
        self.released_during_read=False
        self.release_thread=None
    def read(self):
        self.read_active.set()
        with self.condition:
            self.read_calls+=1
            self.condition.notify_all()
        try:
            value=self.items.get(timeout=5)
            if isinstance(value,Exception): raise value
            return value
        finally:
            self.read_active.clear()
    def feed(self,frame): self.items.put((True,frame))
    def disconnect(self): self.items.put((False,None))
    def release(self):
        self.released_during_read |= self.read_active.is_set()
        self.release_calls+=1
        self.release_thread=threading.current_thread().name
    def wait_reads(self,count,timeout=2):
        deadline=time.monotonic()+timeout
        with self.condition:
            while self.read_calls<count:
                left=deadline-time.monotonic()
                if left<=0: raise AssertionError('capture did not enter read #%d'%count)
                self.condition.wait(left)


def await_sequence(camera,sequence,timeout=2):
    deadline=time.monotonic()+timeout
    with camera.condition:
        while camera.sequence<sequence and camera.error is None:
            left=deadline-time.monotonic()
            if left<=0: raise AssertionError('camera did not publish sequence %d'%sequence)
            camera.condition.wait(left)
        if camera.error: raise AssertionError('unexpected capture failure: '+str(camera.error))


class LatestCameraTests(unittest.TestCase):
    def make_camera(self):
        capture=ControlledCapture()
        camera=LatestCamera(capture)
        def cleanup():
            # Wake a blocked fake read BEFORE joining, so no leaked test threads.
            if camera.worker.is_alive(): capture.disconnect()
            if camera.worker.is_alive() or not capture.release_calls: camera.close()
            camera.worker.join(timeout=2)
            self.assertFalse(camera.worker.is_alive(),'fake worker leaked')
            self.assertFalse(capture.released_during_read)
        self.addCleanup(cleanup)
        capture.wait_reads(1)
        return capture,camera

    def test_latest_replaces_older_frames_and_returns_copy(self):
        capture,camera=self.make_camera()
        frames=[np.full((3,4,3),n,np.uint8) for n in (11,22,33)]
        for frame in frames: capture.feed(frame)
        await_sequence(camera,3)
        capture.wait_reads(4)  # three frames consumed without a main-loop next()
        sequence,latest=camera.next(after=0,timeout=.1)
        self.assertEqual(sequence,3)
        np.testing.assert_array_equal(latest,33)
        latest[:]=99
        # Consumers cannot mutate the stored latest image.
        seq2,again=camera.next(after=2,timeout=.1)
        self.assertEqual(seq2,3); np.testing.assert_array_equal(again,33)
        np.testing.assert_array_equal(frames[-1],33)

    def test_after_sequence_waits_for_new_frame_instead_of_replaying(self):
        capture,camera=self.make_camera()
        capture.feed(np.full((2,2),7,np.uint8)); await_sequence(camera,1)
        self.assertEqual(camera.next(timeout=.1)[0],1)
        with self.assertRaisesRegex(TimeoutError,'frame timeout'):
            camera.next(after=1,timeout=.03)
        capture.feed(np.full((2,2),8,np.uint8)); await_sequence(camera,2)
        sequence,frame=camera.next(after=1,timeout=.1)
        self.assertEqual(sequence,2); np.testing.assert_array_equal(frame,8)

    def test_next_timeout_is_bounded_without_any_frame(self):
        capture,camera=self.make_camera()
        begin=time.monotonic()
        with self.assertRaisesRegex(TimeoutError,'UVC camera frame timeout'):
            camera.next(timeout=.04)
        elapsed=time.monotonic()-begin
        self.assertGreaterEqual(elapsed,.025)
        self.assertLess(elapsed,.75)
        self.assertTrue(camera.worker.is_alive())
        self.assertEqual(capture.release_calls,0)
        with self.assertRaises(TimeoutError): camera.next(timeout=0)

    def test_disconnect_propagates_instead_of_returning_cached_frame(self):
        capture,camera=self.make_camera()
        capture.feed(np.full((2,2),5,np.uint8)); await_sequence(camera,1)
        capture.disconnect(); camera.worker.join(timeout=2)
        self.assertFalse(camera.worker.is_alive())
        with self.assertRaisesRegex(RuntimeError,'failed or disconnected'):
            camera.next(after=0,timeout=.1)
        camera.close()
        self.assertEqual(capture.release_calls,1)
        self.assertFalse(capture.released_during_read)

    def test_backend_exception_wakes_waiting_consumer(self):
        capture,camera=self.make_camera()
        outcomes=[]; entered=threading.Event()
        def consume():
            entered.set()
            try: camera.next(timeout=2)
            except Exception as exc: outcomes.append(exc)
        consumer=threading.Thread(target=consume,name='test-consumer')
        consumer.start(); self.assertTrue(entered.wait(1))
        capture.items.put(OSError('synthetic backend disconnected'))
        consumer.join(timeout=1)
        self.assertFalse(consumer.is_alive())
        self.assertEqual(len(outcomes),1)
        self.assertIsInstance(outcomes[0],RuntimeError)
        self.assertIn('synthetic backend disconnected',str(outcomes[0]))

    def test_close_waits_for_read_then_releases_once_without_race(self):
        capture,camera=self.make_camera()
        entered=threading.Event(); consumed=threading.Event(); outcomes=[]
        def consume():
            entered.set()
            try: camera.next(timeout=3)
            except Exception as exc: outcomes.append(exc)
            finally: consumed.set()
        consumer=threading.Thread(target=consume,name='test-consumer')
        consumer.start(); self.assertTrue(entered.wait(1))
        with camera.condition:
            # Ensures stop notification is observed before the fake read completes.
            closer=threading.Thread(target=camera.close,name='test-close')
            closer.start()
        deadline=time.monotonic()+1
        with camera.condition:
            while not camera.stopped:
                left=deadline-time.monotonic()
                self.assertGreater(left,0)
                camera.condition.wait(left)
        self.assertTrue(capture.read_active.is_set())
        self.assertEqual(capture.release_calls,0)
        self.assertTrue(closer.is_alive())
        self.assertTrue(consumed.wait(1),'close did not wake waiting next()')
        capture.disconnect()  # let read return so join may complete safely
        closer.join(timeout=2); consumer.join(timeout=2)
        self.assertFalse(closer.is_alive()); self.assertFalse(consumer.is_alive())
        self.assertFalse(camera.worker.is_alive())
        self.assertEqual(capture.release_calls,1)
        self.assertEqual(capture.release_thread,'test-close')
        self.assertFalse(capture.released_during_read)
        self.assertEqual(len(outcomes),1)
        self.assertIsInstance(outcomes[0],RuntimeError)
        self.assertIn('stopped',str(outcomes[0]))

    def test_close_is_bounded_and_does_not_release_stalled_read(self):
        capture,camera=self.make_camera()
        begin=time.monotonic()
        camera.close()  # the fake backend deliberately stays inside read()
        elapsed=time.monotonic()-begin
        self.assertLess(elapsed,2.5)
        self.assertTrue(camera.worker.is_alive())
        self.assertTrue(capture.read_active.is_set())
        self.assertEqual(capture.release_calls,0)
        self.assertFalse(capture.released_during_read)
        with self.assertRaisesRegex(RuntimeError,'stopped'): camera.next(timeout=.1)
        capture.disconnect(); camera.worker.join(timeout=2)
        self.assertFalse(camera.worker.is_alive())
        # A subsequent explicit close can release after the stalled read exits.
        camera.close(); self.assertEqual(capture.release_calls,1)


class MainLoopLatestCameraTests(unittest.TestCase):
    def test_main_load_hdmi_flags_defaults_and_stub_lifecycle(self):
        # All four flag combinations parse normally; hardware modules are stubs.
        import pl_runtime as pl
        for flags in ([],['--load'],['--hdmi'],['--load','--hdmi']):
            with self.subTest(flags=flags),tempfile.TemporaryDirectory(dir=str(EVIDENCE)) as tmp:
                overlay=object()
                load=Mock(return_value=overlay)
                overlay_factory=Mock(return_value=overlay)
                paths=Mock(return_value=({}, {'bit':Path('synthetic.bit'), 'hwh':Path('synthetic.hwh')}))
                session=SimpleNamespace(init=Mock(),start=Mock(return_value={'synthetic_start':True}),
                    service=Mock(return_value={'synthetic_service':True}),
                    close=Mock(return_value={'synthetic_close':True}))
                session_factory=Mock(return_value=session)
                hdmi_package=ModuleType('hdmi'); hdmi_package.__path__=[]
                hdmi_module=ModuleType('hdmi.pynq_hdmi_init')
                hdmi_module.HdmiSession=session_factory
                board=SimpleNamespace(start=Mock(),send=Mock(),request=Mock(return_value=(1,0,0,3)),
                    read_rgb=Mock(return_value=np.zeros((640,640,3),np.uint8)),
                    publish=Mock(),snapshot=Mock(return_value={'completed':1}),close=Mock())
                fake_cv=SimpleNamespace(IMREAD_GRAYSCALE=0,INTER_LINEAR=1,
                    imread=lambda *a:np.zeros((480,640),np.uint8),
                    resize=lambda image,*a,**k:image)
                output=Path(tmp)/'results.jsonl'
                args=['run_pipeline.py','--image','synthetic','--mode','video','--frames','1',
                      '--fps','10000','--output',str(output)]+flags
                out,err=io.StringIO(),io.StringIO()
                modules={'pl_clock':SimpleNamespace(assert_clock=lambda *a: {},record=lambda *a: None),'cv2':fake_cv,'load_overlay':SimpleNamespace(main=load),
                         'package_config':SimpleNamespace(hardware_paths=paths),
                         'pynq':SimpleNamespace(Overlay=overlay_factory),
                         'hdmi':hdmi_package,'hdmi.pynq_hdmi_init':hdmi_module}
                with patch.object(pl,'Board',return_value=board),patch.object(sys,'argv',args), \
                        patch.object(signal,'signal'),patch.dict(sys.modules,modules), \
                        contextlib.redirect_stdout(out),contextlib.redirect_stderr(err):
                    runpy.run_path(str(RUNTIME/'run_pipeline.py'),run_name='__main__')
                self.assertEqual(err.getvalue(),'')
                board.publish.assert_called_once_with((1,0,0,3),[])
                board.close.assert_called_once()
                self.assertEqual(load.call_count,int('--load' in flags))
                reuse='--hdmi' in flags and '--load' not in flags
                self.assertEqual(paths.call_count,1+int(reuse))
                self.assertEqual(overlay_factory.call_count,int(reuse))
                if reuse: overlay_factory.assert_called_once_with('synthetic.bit',download=False)
                record=json.loads(output.read_text())
                self.assertFalse(record['screen_picture_verified'])
                if '--hdmi' in flags:
                    session_factory.assert_called_once_with(overlay)
                    session.init.assert_called_once(); session.start.assert_called_once()
                    session.close.assert_called_once(); self.assertEqual(session.service.call_count,2)
                    self.assertEqual(record['hdmi'],{'synthetic_service':True})
                    self.assertIn('HDMI_INIT_OK',out.getvalue())
                else:
                    session_factory.assert_not_called(); session.init.assert_not_called()
                    session.start.assert_not_called(); session.service.assert_not_called()
                    session.close.assert_not_called(); self.assertIsNone(record['hdmi'])
                    self.assertNotIn('HDMI_INIT_OK',out.getvalue())

    def test_main_consumes_latest_sequence_and_closes_wrapper(self):
        capture=SimpleNamespace(isOpened=lambda:True,set=Mock(),read=Mock(),release=Mock())
        # A sequence jump represents skipped intermediate camera frames.
        camera=SimpleNamespace(next=Mock(side_effect=[(4,np.full((480,640),4,np.uint8)),
                                                       (9,np.full((480,640),9,np.uint8))]),close=Mock())
        board=SimpleNamespace(start=Mock(),send=Mock(),request=Mock(return_value=None),
                              snapshot=Mock(return_value={'completed':2}),close=Mock())
        fake_cv=SimpleNamespace(VideoCapture=Mock(return_value=capture),CAP_V4L2=200,
            CAP_PROP_FRAME_WIDTH=3,CAP_PROP_FRAME_HEIGHT=4,CAP_PROP_BUFFERSIZE=38,
            INTER_LINEAR=1,resize=lambda image,*a,**k:image)
        import pl_runtime as pl
        with tempfile.TemporaryDirectory(dir=str(EVIDENCE)) as tmp:
            args=['run_pipeline.py','--camera','fake-uvc','--mode','video','--frames','2',
                  '--fps','10000','--output',str(Path(tmp)/'results.jsonl')]
            out,err=io.StringIO(),io.StringIO()
            with patch.object(pl,'Board',return_value=board),patch.object(sys,'argv',args), \
                    patch.object(signal,'signal'), \
                    patch.dict(sys.modules,{'pl_clock':SimpleNamespace(assert_clock=lambda *a: {},record=lambda *a: None),'cv2':fake_cv,
                        'camera_source':SimpleNamespace(LatestCamera=Mock(return_value=camera))}), \
                    contextlib.redirect_stdout(out),contextlib.redirect_stderr(err):
                runpy.run_path(str(RUNTIME/'run_pipeline.py'),run_name='__main__')
        self.assertEqual(camera.next.call_args_list, [unittest.mock.call(0),unittest.mock.call(4)])
        self.assertEqual(board.send.call_count,2)
        np.testing.assert_array_equal(board.send.call_args_list[0][0][0],4)
        np.testing.assert_array_equal(board.send.call_args_list[1][0][0],9)
        capture.read.assert_not_called()
        capture.release.assert_not_called()
        camera.close.assert_called_once(); board.close.assert_called_once()
        self.assertNotIn('PIPELINE_FAILED',err.getvalue())

    def test_main_camera_disconnect_exits_failure_and_closes(self):
        capture=SimpleNamespace(isOpened=lambda:True,set=Mock(),release=Mock())
        camera=SimpleNamespace(next=Mock(side_effect=RuntimeError('UVC capture failed or disconnected')),close=Mock())
        board=SimpleNamespace(start=Mock(),send=Mock(),close=Mock())
        fake_cv=SimpleNamespace(VideoCapture=lambda *a:capture,CAP_V4L2=200,
            CAP_PROP_FRAME_WIDTH=3,CAP_PROP_FRAME_HEIGHT=4,CAP_PROP_BUFFERSIZE=38)
        import pl_runtime as pl
        with tempfile.TemporaryDirectory(dir=str(EVIDENCE)) as tmp:
            args=['run_pipeline.py','--camera','fake-uvc','--mode','video','--frames','1',
                  '--output',str(Path(tmp)/'results.jsonl')]
            out,err=io.StringIO(),io.StringIO()
            with patch.object(pl,'Board',return_value=board),patch.object(sys,'argv',args), \
                    patch.object(signal,'signal'), \
                    patch.dict(sys.modules,{'pl_clock':SimpleNamespace(assert_clock=lambda *a: {},record=lambda *a: None),'cv2':fake_cv,
                        'camera_source':SimpleNamespace(LatestCamera=lambda c:camera)}), \
                    contextlib.redirect_stdout(out),contextlib.redirect_stderr(err):
                with self.assertRaises(SystemExit) as exc:
                    runpy.run_path(str(RUNTIME/'run_pipeline.py'),run_name='__main__')
            self.assertEqual(exc.exception.code,1)
            self.assertEqual((Path(tmp)/'results.jsonl').read_text(),'')
        camera.close.assert_called_once(); board.close.assert_called_once()
        capture.release.assert_not_called(); board.send.assert_not_called()
        self.assertIn('PIPELINE_FAILED: UVC capture failed or disconnected',err.getvalue())
        self.assertNotIn('PL_PIPELINE_STOPPED',out.getvalue())


if __name__=='__main__': unittest.main(verbosity=2)
