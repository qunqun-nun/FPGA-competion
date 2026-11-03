import copy
import hashlib
import importlib.util
import json
import multiprocessing
from pathlib import Path
import sys
import tempfile
import time
from types import SimpleNamespace
import unittest
from unittest.mock import patch
import xml.etree.ElementTree as ET

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import pynq_hdmi_init as hd
import pynq_prepare_library as build


class HdmiCandidateTests(unittest.TestCase):
    def test_stock_rx_nidru_mismatch_and_reset_only_change(self):
        profile = json.loads((HERE / 'pynq_native/build-receipt.json').read_text())['profile']
        stock = copy.deepcopy(profile)
        stock['phy'].update(RX_PROTOCOL=1, NIDRU=1, NIDRU_REFCLK_SEL=3)
        self.assertFalse(hd.matching_profile(stock, profile))
        changed = copy.deepcopy(profile)
        changed.update(hwh_sha256='new final HWH', reset_control={'constant_one': True})
        self.assertTrue(hd.matching_profile(profile, changed))

    def test_metadata_wrong_address_size_version_rejected(self):
        valid = {n: dict(phys_addr=a, addr_range=s, type=t) for n, (a, s, t) in hd.IPS.items()}
        hd.check_descriptions(valid)
        for field, value in [('phys_addr', 0x80020000), ('addr_range', 4096), ('type', 'xilinx.com:ip:v_hdmi_tx_ss:3.1')]:
            bad = copy.deepcopy(valid)
            bad['v014_hdmi_tx_ss'][field] = value
            with self.assertRaises(hd.HdmiError):
                hd.check_descriptions(bad)

    def test_kernel_ownership_by_resource_not_only_name(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            device = root / 'bus/platform/devices/different-name'
            device.mkdir(parents=True)
            (device / 'driver').mkdir()
            (device / 'resource').write_text('0x82020000 0x8202ffff 0x200\n')
            with patch.object(Path, 'is_symlink', lambda p: p == device / 'driver'):
                with self.assertRaises(hd.HdmiError):
                    hd.check_ownership(root)
            (device / 'resource').write_text('0x80000000 0x8000ffff 0x200\n')
            with patch.object(Path, 'is_symlink', lambda p: p == device / 'driver'):
                self.assertTrue(hd.check_ownership(root))

    def test_event_order_observes_down_before_pumping_up(self):
        state = [False]
        events = []
        def pump():
            events.append('pump')
            state[0] = True
        hd.wait_state(lambda: state[0], pump, False, time.monotonic() + 1, 'down')
        self.assertEqual(events, [])
        hd.wait_state(lambda: state[0], pump, True, time.monotonic() + 1, 'up', sleep=lambda _: None)
        self.assertEqual(events, ['pump'])

    def test_missing_hpd_deadline_is_failure(self):
        with self.assertRaisesRegex(hd.HdmiError, 'HPD'):
            hd.wait_state(lambda: False, lambda: None, True, 0, 'HPD', clock=lambda: 1)

    def test_native_binary_receipt_and_tamper_rejection(self):
        path = HERE / 'pynq_native/libfengyan_xhdmi.so'
        profile = json.loads(path.with_name('build-receipt.json').read_text())['profile']
        hd.check_library(path, profile)
        with tempfile.TemporaryDirectory() as directory:
            target = Path(directory) / 'lib.so'
            target.write_bytes(path.read_bytes() + b'tampered')
            target.with_name('build-receipt.json').write_text(path.with_name('build-receipt.json').read_text())
            with self.assertRaisesRegex(hd.HdmiError, 'SHA-256'):
                hd.check_library(target, profile)

    def test_native_source_closure_hashes_and_glibc_baseline(self):
        directory = HERE / 'pynq_native'
        receipt = json.loads((directory / 'build-receipt.json').read_text())
        for name, digest in receipt['sources'].items():
            self.assertFalse(Path(name).is_absolute())
            self.assertEqual(hashlib.sha256((directory / name).read_bytes()).hexdigest(), digest)
        self.assertEqual(receipt['dynamic_abi']['needed'], ['libc.so.6'])
        self.assertEqual(receipt['dynamic_abi']['version_needs'], ['GLIBC_2.17'])
        self.assertFalse(receipt['dynamic_abi']['glibcxx_required'])
        self.assertEqual(hashlib.sha256((directory / 'common/aarch64/xparameters.h').read_bytes()).hexdigest(),
                         receipt['generated_xparameters_sha256'])

    def test_macro_aliases_fixed_and_incomplete_header_refused(self):
        text = (HERE / 'pynq-reference-v3.0.1/pynq/lib/_pynq/common/aarch64/xparameters.h').read_text()
        profile = json.loads((HERE / 'pynq_native/build-receipt.json').read_text())['profile']
        result, _ = build.patch_parameters(text, profile)
        self.assertIn('#define XPAR_VID_PHY_CONTROLLER_NIDRU 0', result)
        self.assertIn('#define XPAR_VPHY_0_NIDRU 0', result)
        self.assertIn('#define XPAR_VID_PHY_CONTROLLER_RX_PROTOCOL 3', result)
        with self.assertRaises(ValueError):
            build.patch_parameters('#define INCOMPLETE 1\n', profile)

    def test_actual_hwh_const1_required_and_zero_rejected(self):
        # Synthetic copy derived from the archived final audit; original untouched.
        audit = json.loads((HERE / 'hardware-audit.json').read_text(encoding='utf-8'))
        original = next(Path(p) for p in audit['source_hashes'] if p.endswith('fengyan_v016_dpu.hwh'))
        if not original.exists():
            self.skipTest('V0.16 audit source is not installed on this machine')
        before = hashlib.sha256(original.read_bytes()).hexdigest()
        self.assertFalse(build.hwh_profile(original)['reset_control']['constant_one'])
        document = ET.parse(original)
        external = document.getroot().find('EXTERNALPORTS')
        ET.SubElement(external, 'PORT', NAME='IDT_8T49N241_RST_OUT', DIR='O', SIGNAME='const_one_dout')
        with tempfile.TemporaryDirectory() as directory:
            fixture = Path(directory) / 'constant.hwh'
            document.write(fixture)
            self.assertTrue(build.hwh_profile(fixture)['reset_control']['constant_one'])
            for element in document.findall('.//MODULE'):
                if element.get('INSTANCE') == 'const_one':
                    for parameter in element.findall('./PARAMETERS/PARAMETER'):
                        if parameter.get('NAME') == 'CONST_VAL':
                            parameter.set('VALUE', '0')
            document.write(fixture)
            self.assertFalse(build.hwh_profile(fixture)['reset_control']['constant_one'])
        self.assertEqual(before, hashlib.sha256(original.read_bytes()).hexdigest())

    def test_worker_timeout_marks_unknown_not_pass(self):
        session = hd.HdmiSession(SimpleNamespace(bitfile_name='unused.bit'))
        session._connection = SimpleNamespace(poll=lambda *_: False)
        session._process = SimpleNamespace(is_alive=lambda: True)
        with self.assertRaisesRegex(hd.HdmiError, 'UNKNOWN_REBOOT_REQUIRED'):
            session._wait(0.005)
        self.assertEqual(session.status['phase'], 'UNKNOWN_REBOOT_REQUIRED')

    def test_real_process_watchdog_can_terminate_stalled_worker(self):
        context = multiprocessing.get_context('spawn')
        parent, child = context.Pipe()
        process = context.Process(target=time.sleep, args=(10,))
        process.start()
        session = hd.HdmiSession(SimpleNamespace(bitfile_name='unused.bit'))
        session._process, session._connection = process, parent
        try:
            with self.assertRaises(hd.HdmiError):
                session._wait(0.02)
            session._abort()
            self.assertFalse(process.is_alive())
        finally:
            child.close()
            if process.is_alive():
                process.kill()
            process.join(2)

    def test_worker_error_is_explicit(self):
        messages = iter([{'kind': 'stage', 'stage': 'IDT_DEVICE_ID_NO_RESET_WRITE'},
                         {'kind': 'error', 'error': 'IDT invalid', 'output_gated': False}])
        session = hd.HdmiSession(SimpleNamespace(bitfile_name='unused.bit'))
        session._connection = SimpleNamespace(poll=lambda *_: True, recv=lambda: next(messages))
        session._process = SimpleNamespace(is_alive=lambda: True)
        with self.assertRaisesRegex(hd.HdmiError, 'IDT invalid'):
            session._wait(1)
        self.assertEqual(session.status['phase'], 'FAILED')

    def test_platform_rejection_has_no_hardware_side_effects(self):
        session = hd.HdmiSession(SimpleNamespace(bitfile_name='unused.bit'))
        with patch('pynq_hdmi_init.platform.system', return_value='Windows'):
            with self.assertRaises(hd.HdmiError):
                session.init()
        self.assertIsNone(session._process)


if __name__ == '__main__':
    unittest.main(verbosity=2)
