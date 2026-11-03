"""Offline PL protocol tests based on V0.16 RTL, never open /dev/mem.

Run: python -m unittest discover -s runtime/tests -p test_pl_runtime.py -v
R1/R2/R3 are ordinary regression tests against the repaired implementation.
The model implements the externally visible protocol, not an RTL simulator.
"""
import ctypes
import contextlib
import io
from pathlib import Path
import runpy
import signal
import struct
import sys
import tempfile
import unittest
from types import SimpleNamespace
from unittest.mock import patch
from unittest.mock import Mock
import numpy as np

RUNTIME = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(RUNTIME))
import pl_runtime as pl
EVIDENCE = Path(__file__).resolve().parent / 'evidence'
EVIDENCE.mkdir(exist_ok=True)


class Clock:
    def __init__(self): self.now = 0.0
    def monotonic(self): return self.now
    def sleep(self, seconds): self.now += max(seconds, 0.01)
    def advance(self, seconds): self.now += seconds


class CtrlModel:
    """RTL S00_AXI: pending ACK, active identity, shadow/atomic commit.

    Owner timeout represents profiler(100M cycles @100MHz)->recovery cancel.
    Its age starts on dispatch, and ACK deliberately does NOT reset it.
    """
    def __init__(self, clock):
        self.clock = clock
        self.values = {0x58: 0, 0x10: 0, 0x24: 0}
        self.writes = []
        self.committed = []
        self.shadow = {}
        self.dispatched = None
        self.on_read = None
        self.on_write = None
        self.cancel_on_commit = False
        self.reject_commit = False

    def dispatch(self, seq=1, frame=17, slot=1, generation=3):
        self.identity = (seq, frame, slot, generation)
        self.values.update(dict(zip((0x10,0x14,0x18,0x1c), self.identity)))
        self.values[0x24] = 0x1b  # exists,pending,unseen,active
        self.dispatched = self.clock.now
        return self.identity

    def expire(self):
        self.values[0x24] &= ~0x1a  # pending/unseen/active cleared
        self.values[0x24] |= 4
        self.values[0xb4] = self.values.get(0xb4,0) + 1
        self.values[0xb8] = 4
        self.values[0xd0] = 1  # recovery reason DPU_TIMEOUT
        self.values[0xd8] = self.values.get(0xd8,0) + 1
        self.dispatched = None

    def tick(self):
        if (self.dispatched is not None and self.values[0x24] & 0x10 and
                self.clock.now - self.dispatched >= 1.0):
            self.expire()

    def read(self, offset):
        self.tick()
        if self.on_read: self.on_read(offset)
        return self.values.get(offset, 0)

    def write(self, offset, value):
        self.tick()
        self.writes.append((offset,value))
        if self.on_write: self.on_write(offset,value)
        if offset in range(0x30,0x54,4):
            self.shadow[offset] = value
        elif offset == 0x64 and value & 1:
            self.values[0x24] = (self.values[0x24] & ~0xa) | 4
        elif offset == 0x54 and value & 1:
            if self.cancel_on_commit: self.expire()
            identity = tuple(self.values.get(o,0) for o in (0x14,0x18,0x1c))
            shadow_id = tuple(self.shadow.get(o,0) for o in (0x30,0x34,0x38))
            if self.values[0x24] & 0x10 and identity == shadow_id and not self.reject_commit:
                self.committed.append(dict(self.shadow))
                self.values[0x58] = (self.values[0x58] + 1) & 0xffffffff
                self.values[0x24] &= ~0x10
            else:
                # RTL flags stale/error but does NOT increment result_seq.
                self.values[4] = self.values.get(4,0) | (1<<10) | (1<<5)
                self.values[0xc] = 2
        else:
            self.values[offset] = value


class DmaModel:
    """Simple DMA: IRQ bits12..14 W1C; fault causes RO; LENGTH starts."""
    def __init__(self, statuses=(0x1002,)):
        self.control = 1
        self.status = 0x1002  # previous transfer's IOC + idle
        self.statuses = list(statuses)
        self.writes = []
        self.status_reads = []
        self.started = False
        self.reset_stuck = False
    def read(self, offset):
        if offset == 0:
            if self.control & 4 and not self.reset_stuck: self.control = 0
            return self.control
        if offset == 4:
            if self.started and self.statuses:
                self.status = self.statuses.pop(0)
            self.status_reads.append(self.status)
            return self.status
        return 0
    def write(self, offset, value):
        self.writes.append((offset,value))
        if offset == 0: self.control = value
        elif offset == 4: self.status &= ~(value & 0x7000)
        elif offset == 0x28: self.started = True


class CopyLib:
    def __init__(self): self.calls=[]; self.after_copy=None
    def fy_copy(self, dst, src, size):
        self.calls.append((dst,src,size))
        ctypes.memmove(dst,src,size)
        if self.after_copy: self.after_copy()


def make_board(clock, statuses=(0x1002,), frames=False):
    b = pl.Board.__new__(pl.Board)
    b.ctrl = CtrlModel(clock)
    b.dma = DmaModel(statuses)
    b.lib = CopyLib()
    b._source_storage = ctypes.create_string_buffer(480*640)
    b.source = SimpleNamespace(ptr=ctypes.addressof(b._source_storage))
    if frames:
        b._frame_storage = ctypes.create_string_buffer(3 * pl.FRAME_BYTES)
        b.frames = SimpleNamespace(ptr=ctypes.addressof(b._frame_storage))
    return b


class ReservationTests(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory(dir=str(EVIDENCE))
        self.addCleanup(self.tmp.cleanup)
        self.root=Path(self.tmp.name)
        self.dt=self.root/'dt'
        self.res=self.dt/'reserved-memory'
        self.res.mkdir(parents=True)
        (self.res/'#address-cells').write_bytes(struct.pack('>I',2))
        (self.res/'#size-cells').write_bytes(struct.pack('>I',2))
        self.iomem=self.root/'iomem'
    def node(self,name,start,size,**flags):
        n=self.res/name; n.mkdir()
        (n/'reg').write_bytes(struct.pack('>QQ',start,size))
        (n/'no-map').write_bytes(b'')
        for k,v in flags.items(): (n/k).write_bytes(v)
        return n
    def valid(self):
        self.frames=self.node('frames@20000000',pl.FRAMES,3*pl.FRAME_BYTES)
        self.source=self.node('input@21000000',pl.INPUT,0x200000)
        self.iomem.write_text('20000000-204affff : reserved\n21000000-211fffff : reserved\n')
    def check(self): return pl.check_reserved(self.dt,self.iomem)
    def test_accept_exact_boot_reservations(self): self.valid(); self.check()
    def test_missing_dt_rejected(self):
        self.iomem.write_text('20000000-211fffff : reserved\n')
        with self.assertRaisesRegex(RuntimeError,'Boot DT'): self.check()
    def test_dt_alone_not_boot_proof(self):
        self.valid(); self.iomem.write_text('20000000-211fffff : System RAM\n')
        with self.assertRaisesRegex(RuntimeError,'iomem'): self.check()
    def test_reusable_disabled_or_not_nomap_rejected(self):
        for kind in ('reusable','disabled','no-map'):
            with self.subTest(kind=kind):
                self.valid() if not hasattr(self,'frames') else None
                if kind=='no-map': (self.frames/'no-map').unlink()
                elif kind=='disabled': (self.frames/'status').write_bytes(b'disabled\0')
                else: (self.frames/'reusable').write_bytes(b'')
                with self.assertRaises(RuntimeError): self.check()
                for f in ('status','reusable'):
                    if (self.frames/f).exists(): (self.frames/f).unlink()
                (self.frames/'no-map').write_bytes(b'')
    def test_short_range_and_unprivileged_zero_iomem_rejected(self):
        self.valid()
        (self.source/'reg').write_bytes(struct.pack('>QQ',pl.INPUT,0x100000))
        with self.assertRaises(RuntimeError): self.check()
        (self.source/'reg').write_bytes(struct.pack('>QQ',pl.INPUT,0x200000))
        self.iomem.write_text('00000000-00000000 : reserved\n')
        with self.assertRaises(RuntimeError): self.check()
    def test_malformed_cells_and_reg_fail_closed(self):
        self.valid(); (self.frames/'reg').write_bytes(b'bad')
        with self.assertRaises(RuntimeError): self.check()
    def test_one_cell_reservations(self):
        self.valid()
        for f in ('#address-cells','#size-cells'): (self.res/f).write_bytes(struct.pack('>I',1))
        (self.frames/'reg').write_bytes(struct.pack('>II',pl.FRAMES,3*pl.FRAME_BYTES))
        (self.source/'reg').write_bytes(struct.pack('>II',pl.INPUT,0x200000))
        self.check()


class ProtocolTests(unittest.TestCase):
    def setUp(self):
        self.clock=Clock()
        self.p=patch.object(pl,'time',self.clock)
        self.p.start(); self.addCleanup(self.p.stop)
        self.board=make_board(self.clock)
    def test_start_reset_source_and_freshness(self):
        b=self.board; b.start()
        self.assertEqual(b.ctrl.writes,[(0,6),(0xe4,1),(0,1)])
        self.assertEqual(b.dma.writes,[(0,4),(0,1)])
        for counter in (8,0x70):
            b=make_board(self.clock); b.ctrl.values[counter]=1
            with self.assertRaisesRegex(RuntimeError,'not fresh'): b.start()
    def test_dma_reset_timeout(self):
        self.board.dma.reset_stuck=True
        with self.assertRaisesRegex(TimeoutError,'DMA reset timeout'): self.board.start()
    def test_dma_ioc_not_idle_and_length_last(self):
        b=make_board(self.clock,[2,2,0x1002])
        frame=np.arange(480*640,dtype=np.uint8).reshape(480,640)
        b.send(frame)
        self.assertEqual(b.dma.status_reads,[2,2,0x1002])
        self.assertEqual(b.dma.writes,[(4,0x7000),(0x18,pl.INPUT),(0x1c,0),(0x28,307200)])
        self.assertEqual(ctypes.string_at(b.source.ptr,frame.nbytes),frame.tobytes())
    def test_dma_idle_without_ioc_times_out(self):
        b=make_board(self.clock,[2])
        with self.assertRaisesRegex(TimeoutError,'DMA frame timeout'): b.send(np.zeros((480,640),np.uint8))
    def test_dma_faults_override_ioc(self):
        for flag in (0x10,0x20,0x40,0x100,0x200,0x400):
            with self.subTest(flag=flag):
                b=make_board(self.clock,[0x1000|flag])
                with self.assertRaisesRegex(RuntimeError,'MM2S error'): b.send(np.zeros((480,640),np.uint8))
    def test_bad_frame_or_stopped_dma_never_start_transfer(self):
        for frame in (np.zeros((640,480),np.uint8),np.zeros((480,640),np.float32)):
            with self.assertRaises(ValueError): self.board.send(frame)
        self.board.dma.control=0
        with self.assertRaisesRegex(RuntimeError,'not running'): self.board.send(np.zeros((480,640),np.uint8))
        self.assertEqual(self.board.dma.writes,[])
        self.assertEqual(self.board.lib.calls,[])
    def test_pl_sticky_error_is_not_dma_success(self):
        self.board.ctrl.values[4]=32
        with self.assertRaisesRegex(RuntimeError,'PL sticky'): self.board.send(np.zeros((480,640),np.uint8))
    def test_no_pending_request(self): self.assertIsNone(self.board.request())
    def test_identity_and_ack_keeps_active(self):
        b=self.board; expected=b.ctrl.dispatch(seq=41,frame=72,slot=2,generation=8)
        self.assertEqual(b.request(),expected)
        self.assertEqual(b.ctrl.writes,[(0x64,1)])
        self.assertEqual(b.ctrl.read(0x24)&0x16,0x14)
        self.assertIsNone(b.request())
    def test_snapshot_sequence_change_and_invalid_slot_rejected(self):
        b=self.board; b.ctrl.dispatch(); count=[0]
        def changed(offset):
            if offset==0x10:
                count[0]+=1
                if count[0]==2: b.ctrl.values[0x10]+=1
        b.ctrl.on_read=changed
        with self.assertRaisesRegex(RuntimeError,'changed/cancelled'): b.request()
        self.assertEqual(b.ctrl.writes,[])
        b=make_board(self.clock); b.ctrl.dispatch(slot=3)
        with self.assertRaisesRegex(RuntimeError,'buffer index'): b.request()
    def test_all_four_identity_fields_checked(self):
        for offset in (0x10,0x14,0x18,0x1c):
            b=make_board(self.clock); req=b.ctrl.dispatch(); b.ctrl.values[offset]+=1
            with self.assertRaisesRegex(RuntimeError,'stale'): b.assert_owner(req)
    def test_rgbx_exact_stride_slot_and_color(self):
        b=make_board(self.clock,frames=True); req=b.ctrl.dispatch(slot=2)
        frame=np.zeros((640,640,4),np.uint8)
        frame[:80,:,:3]=114; frame[560:,:,:3]=114
        frame[80:560,:,:3]=[13,77,201]; frame[:,:,3]=0xa5
        ctypes.memmove(b.frames.ptr+2*pl.FRAME_BYTES,frame.ctypes.data,pl.FRAME_BYTES)
        rgb=b.read_rgb(req)
        np.testing.assert_array_equal(rgb,frame[:,:,:3])
        self.assertTrue(rgb.flags.c_contiguous)
        self.assertEqual(rgb.shape,(640,640,3))
        self.assertEqual(b.lib.calls[0][1:],(b.frames.ptr+2*pl.FRAME_BYTES,pl.FRAME_BYTES))
    def test_padding_mismatch_rejected(self):
        b=make_board(self.clock,frames=True); req=b.ctrl.dispatch()
        with self.assertRaisesRegex(RuntimeError,'padding'): b.read_rgb(req)
    def test_owner_expiry_during_rgb_copy_rejected(self):
        b=make_board(self.clock,frames=True); req=b.ctrl.dispatch()
        b.lib.after_copy=lambda: self.clock.advance(1.01)
        with self.assertRaisesRegex(TimeoutError,'PL owner timeout'): b.read_rgb(req)
    def test_shadow_order_identity_best_box_and_atomic_commit(self):
        b=self.board; req=b.ctrl.dispatch(seq=6,frame=32,slot=2,generation=9)
        b.publish(req,[{'bbox':[3.9,4.2,10.3,20.6],'confidence':0.5},
                       {'bbox':[20.2,30.8,12.1,15.1],'confidence':0.75}])
        expected=list(zip(range(0x30,0x54,4),[32,2,9,20,30,13,16,49151,1]))+[(0x54,1)]
        self.assertEqual(b.ctrl.writes,expected)
        self.assertEqual(len(b.ctrl.committed),1)
        self.assertFalse(b.ctrl.read(0x24)&0x10)
    def test_shadow_writes_alone_not_live(self):
        ctrl=self.board.ctrl; ctrl.dispatch()
        for offset in range(0x30,0x54,4): ctrl.write(offset,1)
        self.assertEqual(ctrl.committed,[]); self.assertEqual(ctrl.read(0x58),0)
    def test_empty_result_clears_all_shadow_payload(self):
        b=self.board; req=b.ctrl.dispatch()
        b.publish(req,[])
        self.assertEqual(list(b.ctrl.committed[0].values()),[17,1,3,0,0,0,0,0,0])
    def test_commit_sequence_wrap_is_success(self):
        b=self.board; req=b.ctrl.dispatch(); b.ctrl.values[0x58]=0xffffffff
        b.publish(req,[]); self.assertEqual(b.ctrl.read(0x58),0)
    def test_hardware_rejects_mismatched_shadow_identity(self):
        ctrl=self.board.ctrl; ctrl.dispatch()
        for offset,value in zip((0x30,0x34,0x38),(17,1,999)): ctrl.write(offset,value)
        ctrl.write(0x54,1)
        self.assertEqual(ctrl.committed,[]); self.assertEqual(ctrl.read(0x58),0)
        self.assertEqual(ctrl.read(0xc),2)
    def test_changed_identity_rejects_before_any_shadow_write(self):
        b=self.board; req=b.ctrl.dispatch(); b.ctrl.values[0x1c]+=1
        with self.assertRaisesRegex(RuntimeError,'stale'): b.publish(req,[])
        self.assertEqual(b.ctrl.writes,[])
    def test_owner_cancel_mid_shadow_no_commit(self):
        b=self.board; req=b.ctrl.dispatch()
        def cancel(offset,value):
            if offset==0x40: b.ctrl.expire()
        b.ctrl.on_write=cancel
        with self.assertRaisesRegex(TimeoutError,'PL owner timeout'): b.publish(req,[])
        self.assertNotIn((0x54,1),b.ctrl.writes)
        self.assertEqual(b.ctrl.committed,[])
    def test_expiry_at_doorbell_never_reports_success(self):
        b=self.board; req=b.ctrl.dispatch(); b.ctrl.cancel_on_commit=True
        with self.assertRaisesRegex(TimeoutError,'commit rejected'): b.publish(req,[])
        self.assertEqual(b.ctrl.committed,[])
    def test_slow_inference_after_one_second_rejected(self):
        b=self.board; req=b.ctrl.dispatch()
        self.clock.advance(.9); self.assertEqual(b.request(),req)
        self.clock.advance(.11)  # ACK at .9 did NOT renew the dispatch deadline.
        with self.assertRaisesRegex(TimeoutError,'PL owner timeout'): b.publish(req,[])
        self.assertEqual(b.ctrl.writes,[(0x64,1)])
        self.assertEqual(b.ctrl.committed,[])
        self.assertEqual(b.ctrl.read(0xd8),1)


class MainLoopTimeoutTests(unittest.TestCase):
    def test_slow_inference_exits_failure_without_success_record(self):
        clock=Clock()
        board=make_board(clock,frames=True)
        frame=np.zeros((640,640,4),np.uint8)
        frame[:80,:,:3]=114; frame[560:,:,:3]=114
        # Main loop will dispatch slot 1 after the real mocked-DMA send.
        ctypes.memmove(board.frames.ptr+pl.FRAME_BYTES,frame.ctypes.data,pl.FRAME_BYTES)
        send=board.send
        def send_and_dispatch(gray):
            send(gray)
            board.ctrl.dispatch(frame=0)
        board.send=send_and_dispatch
        board.close=Mock()
        def slow_detect(rgb):
            clock.advance(1.01)
            return []
        detector=SimpleNamespace(detect_pl_rgb888=slow_detect)
        cv=SimpleNamespace(IMREAD_GRAYSCALE=0,INTER_LINEAR=1,
            imread=lambda *args: np.zeros((480,640),np.uint8),
            resize=lambda image,*args,**kwargs: image)
        with tempfile.TemporaryDirectory(dir=str(EVIDENCE)) as tmp:
            result=Path(tmp)/'results.jsonl'
            args=['run_pipeline.py','--image','synthetic','--frames','1','--output',str(result)]
            out,err=io.StringIO(),io.StringIO()
            with patch.object(pl,'time',clock), patch.object(pl,'Board',return_value=board), \
                    patch.dict(sys.modules,{'pl_clock':SimpleNamespace(assert_clock=lambda *a: {},record=lambda *a: None),'cv2':cv,'inference':SimpleNamespace(Detector=lambda **k:detector)}), \
                    patch.object(sys,'argv',args), patch.object(signal,'signal'), \
                    patch('time.monotonic',clock.monotonic), patch('time.sleep',clock.sleep), \
                    contextlib.redirect_stdout(out),contextlib.redirect_stderr(err):
                with self.assertRaises(SystemExit) as exc:
                    runpy.run_path(str(RUNTIME/'run_pipeline.py'),run_name='__main__')
            self.assertEqual(exc.exception.code,1)
            self.assertIn('PIPELINE_FAILED:',err.getvalue())
            self.assertIn('PL owner timeout',err.getvalue())
            self.assertEqual(result.read_text(),'')
            self.assertNotIn('PL_PIPELINE_STOPPED',out.getvalue())
            self.assertEqual(board.ctrl.committed,[])
            board.close.assert_called_once()


class FixRegressionTests(unittest.TestCase):
    """R1/R2/R3 must pass without exemptions; hardware remains untested."""
    def setUp(self):
        self.clock=Clock()
        p=patch.object(pl,'time',self.clock); p.start(); self.addCleanup(p.stop)
    def test_R1_timeout_must_be_explicit_timeout_exception(self):
        b=make_board(self.clock); req=b.ctrl.dispatch(); self.clock.advance(1.01)
        with self.assertRaisesRegex(TimeoutError,'PL owner timeout'): b.publish(req,[])
        # Old sticky flags alone must not turn another cancellation into timeout.
        for reason,counter in ((0,1),(2,1),(1,0)):
            with self.subTest(reason=reason,counter=counter):
                b=make_board(self.clock); req=b.ctrl.dispatch()
                b.ctrl.values.update({0x24:5,0xD0:reason,0xD8:counter})
                with self.assertRaisesRegex(RuntimeError,'expired/cancelled'): b.publish(req,[])
        b=make_board(self.clock); req=b.ctrl.dispatch()
        b.ctrl.values.update({0x10:req[0]+1,0xD0:1,0xD8:1})
        with self.assertRaisesRegex(RuntimeError,'identity changed'): b.publish(req,[])
    def test_R2_dma_err_irq_must_not_be_accepted_with_ioc(self):
        b=make_board(self.clock,[0x5002])  # IOC + Err_Irq; independent status robustness
        with self.assertRaisesRegex(RuntimeError,'MM2S error'): b.send(np.zeros((480,640),np.uint8))
    def test_R2_dma_irq_ack_should_clear_all_irq_latches(self):
        b=make_board(self.clock,[0x1002]); b.send(np.zeros((480,640),np.uint8))
        value=b.dma.writes[0][1]
        self.assertEqual(value&0x7000,0x7000)
        self.assertEqual(value&0x770,0)  # error causes are RO, not W1C
    def test_R3_wholly_outside_bbox_must_not_become_border_pixel(self):
        for box in ([700,550,10,10],[-20,10,10,10],[650,10,10,10],
                    [10,-20,10,10],[10,490,10,10]):
            with self.subTest(box=box):
                b=make_board(self.clock); req=b.ctrl.dispatch()
                b.publish(req,[{'bbox':box,'confidence':.9}])
                self.assertEqual([b.ctrl.committed[0][o] for o in range(0x3c,0x54,4)],
                                 [0,0,0,0,0,0])


if __name__=='__main__': unittest.main(verbosity=2)
