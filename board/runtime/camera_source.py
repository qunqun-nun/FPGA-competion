"""Continuously drain UVC buffers; application consumes only the latest frame."""
import threading
import time


class LatestCamera:
    def __init__(self, capture):
        self.capture = capture
        self.condition = threading.Condition()
        self.latest = None
        self.sequence = 0
        self.error = None
        self.stopped = False
        self.worker = threading.Thread(target=self._run, name='UVC-capture', daemon=True)
        self.worker.start()

    def _run(self):
        try:
            while not self.stopped:
                ok, frame = self.capture.read()
                if not ok:
                    raise RuntimeError('UVC capture failed or disconnected')
                with self.condition:
                    self.latest = frame
                    self.sequence += 1
                    self.condition.notify_all()
        except Exception as exc:
            with self.condition:
                self.error = exc
                self.condition.notify_all()

    def next(self, after=0, timeout=3):
        deadline = time.monotonic() + timeout
        with self.condition:
            while self.sequence <= after and self.error is None and not self.stopped:
                left = deadline - time.monotonic()
                if left <= 0:
                    raise TimeoutError('UVC camera frame timeout')
                self.condition.wait(left)
            if self.error:
                raise RuntimeError(str(self.error))
            if self.stopped:
                raise RuntimeError('Camera is stopped')
            return self.sequence, self.latest.copy()

    def close(self):
        self.stopped = True
        with self.condition:
            self.condition.notify_all()
        self.worker.join(timeout=1)
        if not self.worker.is_alive():
            self.capture.release()
        # Do not concurrently call release() while OpenCV is inside read():
        # a stalled backend is left for process teardown, not raced from here.
