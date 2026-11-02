import types
import unittest
from pathlib import Path
from pl_clock import choose_dividers, prepare_download, assert_clock

HWH=Path(__file__).resolve().parents[2]/'hardware/fengyan_v017_dpu.hwh'

def state(freq,div0=10,div1=1,source=0):
    return dict(fclk0_mhz=freq,div0=div0,div1=div1,source=source,active=True)

class ClockTests(unittest.TestCase):
    def test_boot_pll_mismatch_reproduces_and_corrects(self):
        # HWH /10 on boot IOPLL=1499.985 MHz gives 149.9985 MHz.
        old=state(149.9985)
        o=types.SimpleNamespace(clock_dict={0:dict(enable=1,divisor0=10,divisor1=1)})
        result=prepare_download(o,HWH,read=lambda:old)
        self.assertEqual(result['applied_dividers'],[15,1])
        # Parent PYNQ download now applies /15, rather than overwriting /15 with /10.
        after=state(old['fclk0_mhz']*10/o.clock_dict[0]['divisor0'],15)
        self.assertAlmostEqual(assert_clock(HWH,read=lambda:after)['fclk0_mhz'],99.999,places=5)
    def test_matching_boot_pll_keeps_div10(self):
        self.assertEqual(choose_dividers(state(99.999001),99.999001),(10,1))
    def test_later_override_to_150_rejected(self):
        with self.assertRaises(RuntimeError):assert_clock(HWH,read=lambda:state(149.9985))
    def test_bad_source_rejected(self):
        with self.assertRaises(RuntimeError):choose_dividers(state(100,source=2),100)
    def test_unachievable_frequency_rejected(self):
        with self.assertRaises(RuntimeError):choose_dividers(state(103.7),99.999001)
    def test_hwh_unchanged(self):
        import hashlib
        self.assertEqual(hashlib.sha256(HWH.read_bytes()).hexdigest(),
                         '8a556f2f1ee020932ee10352af887937f704d4637fa6ccd86d39adae191ccca8')

if __name__=='__main__':unittest.main()
