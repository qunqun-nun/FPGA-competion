#!/usr/bin/env python3
"""USB/file -> real PL video path -> DDR -> DPU -> PL result mailbox.

HDMI requires the separately documented Linux TX/PHY integration. This program
never calls imshow or labels a successful inference as a successful display.
"""
import argparse
from collections import OrderedDict
import json
import signal
import sys
import time
from pathlib import Path
import numpy as np
from pl_runtime import Board

ROOT = Path(__file__).resolve().parent.parent
STOP = False


def stop(signum, frame):
    global STOP
    STOP = True


def main():
    p = argparse.ArgumentParser(description=__doc__)
    src = p.add_mutually_exclusive_group(required=True)
    src.add_argument('--camera', help='Board UVC camera, e.g. /dev/video0')
    src.add_argument('--image', type=Path)
    p.add_argument('--mode', choices=['video', 'detect'], default='detect')
    p.add_argument('--frames', type=int, default=0, help='0: continuous camera')
    p.add_argument('--fps', type=float, default=5)
    p.add_argument('--confidence', type=float, default=0.25)
    p.add_argument('--load', action='store_true', help='Load the verified package hardware before running')
    p.add_argument('--hdmi', action='store_true', help='Initialize and supervise the real HDMI TX/PHY output')
    p.add_argument('--output', type=Path, default=ROOT / 'state/results.jsonl')
    args = p.parse_args()
    if args.fps <= 0 or args.frames < 0:
        p.error('fps must be positive and frames >= 0')
    overlay = None
    if args.load:
        from load_overlay import main as load
        overlay = load()
    from package_config import hardware_paths
    from pl_clock import assert_clock, record
    _, clock_hardware = hardware_paths()
    def clock_check(stage=None):
        state = assert_clock(clock_hardware['hwh'])
        if stage:
            record(stage, state)
    clock_check('before_hdmi')
    hdmi = None
    if args.hdmi:
        if overlay is None:
            from package_config import hardware_paths
            from pynq import Overlay
            _, hardware = hardware_paths()
            overlay = Overlay(str(hardware['bit']), download=False)
        from hdmi.pynq_hdmi_init import HdmiSession
        hdmi = HdmiSession(overlay)
        hdmi.init()
        clock_check('after_hdmi_init')
        print('HDMI_INIT_OK', flush=True)
    import cv2
    camera = None
    camera_sequence = 0
    if args.camera:
        camera = cv2.VideoCapture(args.camera, cv2.CAP_V4L2)
        if not camera.isOpened():
            raise RuntimeError('Cannot open board UVC camera: ' + args.camera)
        camera.set(cv2.CAP_PROP_FRAME_WIDTH, 640)
        camera.set(cv2.CAP_PROP_FRAME_HEIGHT, 480)
        camera.set(cv2.CAP_PROP_BUFFERSIZE, 1)
        from camera_source import LatestCamera
        camera = LatestCamera(camera)
    else:
        image = cv2.imread(str(args.image), cv2.IMREAD_GRAYSCALE)
        if image is None:
            raise RuntimeError('Cannot decode image: ' + str(args.image))
    detector = None
    if args.mode == 'detect':
        from inference import Detector
        detector = Detector(model_path=ROOT / 'models/tank_yolov8n_relu_latest_six_outputs.xmodel',
                            confidence=args.confidence)
    for sig in (signal.SIGINT, signal.SIGTERM):
        signal.signal(sig, stop)
    board = Board()
    clock_check('after_runner_before_board_start')
    args.output.parent.mkdir(parents=True, exist_ok=True)
    try:
        board.start()
        if hdmi:
            print('HDMI_STREAM_STATUS ' + json.dumps(hdmi.start()), flush=True)
        count = 0
        inferences = 0
        publications = 0
        completed = 0
        last_request_at = time.monotonic()
        last_request_frame = 0
        last_ddr_at = last_request_at
        sent_frames = OrderedDict()
        # Tracking deliberately suppresses DPU requests for multiple frames.
        # The normal re-detect interval is 15: allow 64 submitted frames,
        # including low-FPS cameras, but never report a zero-inference pass.
        request_timeout = max(10.0, 64.0 / args.fps)
        # A supplied image is repeated: tracker initialization needs later frames.
        limit = args.frames or (30 if args.image else 0)
        with args.output.open('a', encoding='utf-8') as logfile:
            while not STOP and (not limit or count < limit):
                clock_check()
                begin = time.monotonic()
                if camera is not None:
                    camera_sequence, frame = camera.next(camera_sequence)
                    gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY) if frame.ndim == 3 else frame
                else:
                    gray = image
                gray = np.ascontiguousarray(cv2.resize(gray, (640, 480), interpolation=cv2.INTER_LINEAR))
                # Fresh-frame dispatch can legally select an earlier completed
                # frame while the current one is still being written. Compare
                # DDR against the image with that frame_id, never the latest UVC
                # frame. Fresh overlay starts IDs at zero; any PL abort/error
                # makes send() fail instead of silently shifting this mapping.
                sent_frames[count & 0xffffffff] = gray.copy()
                while len(sent_frames) > 64:
                    sent_frames.popitem(last=False)
                board.send(gray)
                # DataMover completion may lag MM2S, especially bottom padding.
                deadline = time.monotonic() + 0.2
                request = board.request()
                while request is None and time.monotonic() < deadline and not STOP:
                    time.sleep(0.001)
                    request = board.request()
                if request is not None:
                    rgb = board.read_rgb(request)
                    expected_gray = sent_frames.get(request[1])
                    if expected_gray is None:
                        raise RuntimeError('Request frame_id absent from submitted-frame history')
                    if not np.all(rgb[80:560] == expected_gray[:, :, None]):
                        raise RuntimeError('PL DDR image differs from sent frame; refusing inference')
                    detections = detector.detect_pl_rgb888(rgb) if detector else []
                    if detector:
                        inferences += 1
                    board.publish(request, detections)
                    publications += 1
                    last_request_at = time.monotonic()
                    last_request_frame = count + 1
                    record = {'request_sequence': request[0], 'frame_id': request[1],
                              'buffer_id': request[2], 'generation': request[3],
                              'detections': detections, 'seconds': time.monotonic() - begin,
                              'pl': board.snapshot(), 'hdmi': hdmi.service() if hdmi else None,
                              'screen_picture_verified': False}
                    logfile.write(json.dumps(record) + '\n')
                    logfile.flush()
                    print(json.dumps(record), flush=True)
                count += 1
                snapshot = board.snapshot()
                current_completed = snapshot['completed']
                if current_completed != completed:
                    completed = current_completed
                    last_ddr_at = time.monotonic()
                elif time.monotonic() - last_ddr_at > max(3.0, 2.0 / args.fps):
                    raise TimeoutError('No completed DDR frames; DMA completion alone is insufficient')
                if (detector and count - last_request_frame >= 64 and
                        time.monotonic() - last_request_at > request_timeout):
                    raise TimeoutError('No DPU request/result progress for 64 frames; tracking may be stalled')
                if hdmi:
                    hdmi.service()
                delay = 1 / args.fps - (time.monotonic() - begin)
                if delay > 0:
                    time.sleep(delay)
        if count == 0 or completed == 0:
            raise RuntimeError('No completed DDR frame; pipeline acceptance incomplete')
        if detector and (inferences == 0 or publications == 0):
            raise RuntimeError('No DPU inference/result commit; pipeline acceptance incomplete')
        print('PL_PIPELINE_STOPPED ' + json.dumps(dict(
            submitted_frames=count, completed_frames=completed, inferences=inferences,
            result_commits=publications, screen_picture_verified=False, pl=board.snapshot())))
    finally:
        try:
            board.close()
        finally:
            try:
                if camera is not None:
                    camera.close()
            finally:
                if hdmi is not None:
                    print('HDMI_STOP_STATUS ' + json.dumps(hdmi.close()), flush=True)


if __name__ == '__main__':
    try:
        main()
    except Exception as exc:
        print('PIPELINE_FAILED: ' + str(exc), file=sys.stderr)
        sys.exit(1)
