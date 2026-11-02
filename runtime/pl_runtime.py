"""V0.16 register-accurate PL transport. No automatic DT changes or RAM guesses."""
import ctypes
import mmap
import os
import struct
import time
from pathlib import Path
import numpy as np

CTRL = 0x80000000
DMA = 0x80010000
INPUT = 0x21000000
FRAMES = 0x20000000
FRAME_BYTES = 640 * 640 * 4


def reserved_ranges(dt_root=Path('/sys/firmware/devicetree/base')):
    root = Path(dt_root) / 'reserved-memory'
    if not root.is_dir():
        return []
    def cells(name, default):
        f = root / name
        return int.from_bytes(f.read_bytes(), 'big') if f.exists() else default
    ac, sc = cells('#address-cells', 2), cells('#size-cells', 2)
    result = []
    for node in root.iterdir():
        if not node.is_dir() or not (node / 'no-map').exists() or (node / 'reusable').exists():
            continue
        if (node / 'status').exists() and (node / 'status').read_bytes().rstrip(b'\0') not in (b'okay', b'ok'):
            continue
        if not (node / 'reg').exists():
            continue
        raw = (node / 'reg').read_bytes()
        step = 4 * (ac + sc)
        if not step or len(raw) % step:
            continue
        for pos in range(0, len(raw), step):
            start = int.from_bytes(raw[pos:pos + 4 * ac], 'big')
            size = int.from_bytes(raw[pos + 4 * ac:pos + step], 'big')
            result.append((start, start + size))
    return result


def check_reserved(dt_root=Path('/sys/firmware/devicetree/base'), iomem='/proc/iomem'):
    ranges = reserved_ranges(dt_root)
    # A live overlay alone cannot reserve pages which Linux allocated at boot.
    # Require both the DT no-map description and Linux's actual reserved map.
    actual = []
    for line in Path(iomem).read_text().splitlines():
        pair, sep, label = line.partition(':')
        if sep and label.strip().lower() == 'reserved':
            lo, hi = pair.strip().split('-')
            actual.append((int(lo, 16), int(hi, 16) + 1))
    for start, size in ((FRAMES, 3 * FRAME_BYTES), (INPUT, 0x200000)):
        if not any(a <= start and start + size <= b for a, b in ranges):
            raise RuntimeError('Boot DT lacks no-map reservation 0x%x+0x%x; see device_tree/' % (start, size))
        if not any(a <= start and start + size <= b for a, b in actual):
            raise RuntimeError('/proc/iomem does not confirm boot reservation 0x%x+0x%x' % (start, size))


class Region:
    def __init__(self, fd, address, length, lib):
        self.mem = mmap.mmap(fd, length, flags=mmap.MAP_SHARED,
                             prot=mmap.PROT_READ | mmap.PROT_WRITE, offset=address)
        self.ptr = ctypes.addressof(ctypes.c_char.from_buffer(self.mem))
        self.lib = lib
        self.length = length

    def read(self, offset):
        if offset % 4 or not 0 <= offset <= self.length - 4:
            raise ValueError('Invalid MMIO offset')
        return self.lib.fy_read32(self.ptr, offset)

    def write(self, offset, value):
        if offset % 4 or not 0 <= offset <= self.length - 4:
            raise ValueError('Invalid MMIO offset')
        self.lib.fy_write32(self.ptr, offset, value)

    def close(self):
        self.mem.close()


class Board:
    def __init__(self):
        if os.uname().machine != 'aarch64' or os.geteuid() != 0:
            raise RuntimeError('Requires ZCU104 aarch64 Linux and root')
        check_reserved()
        self.lib = ctypes.CDLL(str(Path(__file__).parent / 'native/libmemio.so'))
        self.lib.fy_read32.argtypes = [ctypes.c_void_p, ctypes.c_size_t]
        self.lib.fy_read32.restype = ctypes.c_uint32
        self.lib.fy_write32.argtypes = [ctypes.c_void_p, ctypes.c_size_t, ctypes.c_uint32]
        self.lib.fy_copy.argtypes = [ctypes.c_void_p, ctypes.c_void_p, ctypes.c_size_t]
        self.regions = []
        fd = os.open('/dev/mem', os.O_RDWR | os.O_SYNC)
        try:
            for name, base, length in (('ctrl', CTRL, 0x1000), ('dma', DMA, 0x1000),
                                       ('source', INPUT, 0x100000), ('frames', FRAMES, 3 * FRAME_BYTES)):
                region = Region(fd, base, length, self.lib)
                self.regions.append(region)
                setattr(self, name, region)
        except Exception:
            for r in self.regions:
                r.close()
            raise
        finally:
            os.close(fd)

    def wait(self, predicate, seconds, what):
        deadline = time.monotonic() + seconds
        while time.monotonic() < deadline:
            if predicate():
                return
            time.sleep(0.0005)
        raise TimeoutError(what + ': ' + str(self.snapshot()))

    def start(self):
        if self.ctrl.read(0x08) != 0 or self.ctrl.read(0x70) != 0:
            raise RuntimeError('Frame counters are not fresh. Reload this package overlay before starting.')
        self.ctrl.write(0x00, 0x06)
        time.sleep(0.01)
        self.ctrl.write(0xE4, 1)
        self.dma.write(0x00, 4)
        self.wait(lambda: not self.dma.read(0x00) & 4, 1, 'DMA reset timeout')
        self.dma.write(0x00, 1)
        self.ctrl.write(0x00, 1)

    def send(self, gray):
        gray = np.ascontiguousarray(gray)
        if gray.dtype != np.uint8 or gray.shape != (480, 640):
            raise ValueError('PL input must be uint8 gray[480,640]')
        if not self.dma.read(0x00) & 1:
            raise RuntimeError('DMA is not running')
        self.lib.fy_copy(self.source.ptr, gray.ctypes.data, gray.nbytes)
        # Clear previous completion/errors, then program address before LENGTH.
        self.dma.write(0x04, 0x7000)
        self.dma.write(0x18, INPUT)
        self.dma.write(0x1C, 0)
        self.dma.write(0x28, gray.nbytes)
        def completed():
            status = self.dma.read(0x04)
            if status & 0x4770:
                raise RuntimeError('DMA MM2S error 0x%x' % status)
            return bool(status & 0x1000)  # IOC: not an idle bit left over from before LENGTH
        self.wait(completed, 3, 'DMA frame timeout')
        if self.ctrl.read(0x04) & (1 << 5):
            raise RuntimeError('PL sticky error: ' + str(self.snapshot()))

    def request(self):
        status = self.ctrl.read(0x24)
        if not status & 0x02:
            return None
        request = (self.ctrl.read(0x10), self.ctrl.read(0x14),
                   self.ctrl.read(0x18), self.ctrl.read(0x1C))
        if request[0] != self.ctrl.read(0x10) or not self.ctrl.read(0x24) & 0x10:
            raise RuntimeError('Request changed/cancelled during snapshot')
        if request[2] not in (0, 1, 2):
            raise RuntimeError('Invalid PL frame buffer index')
        self.ctrl.write(0x64, 1)  # ACK pending flag, retain active ownership
        return request

    def read_rgb(self, request):
        self.assert_owner(request)
        data = np.empty(FRAME_BYTES, dtype=np.uint8)
        self.lib.fy_copy(data.ctypes.data, self.frames.ptr + request[2] * FRAME_BYTES, FRAME_BYTES)
        self.assert_owner(request)
        # RTL writes 0x00BBGGRR; little-endian CPU sees R,G,B,0.
        rgb = data.reshape(640, 640, 4)[:, :, :3].copy()
        if not np.all(rgb[:80] == 114) or not np.all(rgb[560:] == 114):
            raise RuntimeError('PL DDR padding mismatch; frame not accepted')
        return rgb

    def assert_owner(self, request):
        current = tuple(self.ctrl.read(o) for o in (0x10, 0x14, 0x18, 0x1C))
        if current != request:
            raise RuntimeError('PL frame identity changed; refusing stale result')
        if not self.ctrl.read(0x24) & 0x10:
            if self.ctrl.read(0xD0) == 1 and self.ctrl.read(0xD8):
                raise TimeoutError('PL owner timeout (~1 second); refusing stale result: ' + str(self.snapshot()))
            raise RuntimeError('PL frame ownership expired/cancelled; refusing stale result')

    def publish(self, request, detections):
        import math
        self.assert_owner(request)
        # V0.16 fusion/mailbox currently transports ONE target, not all NMS boxes.
        best = max(detections, key=lambda b: b['confidence']) if detections else None
        coords, score, state = [0, 0, 0, 0], 0, 0
        if best is not None:
            x, y, w, h = best['bbox']
            if not all(math.isfinite(v) for v in (x, y, w, h, best['confidence'])):
                raise ValueError('Non-finite detection')
            left, top = max(0, math.floor(x)), max(0, math.floor(y))
            right, bottom = min(640, math.ceil(x + w)), min(480, math.ceil(y + h))
            if right > left and bottom > top:
                coords = [left, top, right - left, bottom - top]
                score = round(max(0, min(1, best['confidence'])) * 65535)
                state = 1
        old = self.ctrl.read(0x58)
        values = [request[1], request[2], request[3]] + coords + [score, state]
        for offset, value in zip(range(0x30, 0x54, 4), values):
            self.ctrl.write(offset, value)
        self.assert_owner(request)
        self.ctrl.write(0x54, 1)
        self.wait(lambda: self.ctrl.read(0x58) != old, 0.1, 'Result mailbox commit rejected')

    def snapshot(self):
        return {name: self.ctrl.read(offset) for name, offset in
                (('status', 4), ('frames', 8), ('error', 12), ('request_seq', 0x10),
                 ('request_state', 0x24), ('completed', 0x70), ('dropped', 0x78),
                 ('stale_results', 0x7C), ('aborted', 0x84), ('fusion', 0xF8),
                 ('profiler_timeouts', 0xB4), ('profiler_flags', 0xB8),
                 ('recovery_reason', 0xD0), ('recovery_timeouts', 0xD8))}

    def close(self):
        try:
            self.ctrl.write(0, 0)
            self.dma.write(0, 4)
        finally:
            for region in self.regions:
                region.close()
