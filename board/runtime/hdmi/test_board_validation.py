import sys
from pathlib import Path
import unittest
from types import SimpleNamespace
HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import test_hdmi_iic as transport_tests
clocks = transport_tests.clocks
from board_validation import (idt_profiles, validate_idt, validate_tx, probe_identities,
                              verify_dp, checked_dp_type, validate_edid, pio_snapshot)
from hdmi_iic import checked_idt_type, IicError


def edid(extension=True):
    base = bytearray(128)
    base[:8] = bytes.fromhex('00ffffffffffff00')
    base[18:20] = bytes([1, 3])
    base[126] = int(extension)
    base[127] = -sum(base) & 255
    ext = bytearray(128)
    ext[:6] = bytes([2, 3, 6, 0, 0x41, 4])
    ext[127] = -sum(ext) & 255
    return base + ext if extension else base


class BoardTests(unittest.TestCase):
    def test_actual_board_addresses_and_no_rx_configuration(self):
        raw, events, master, bus, log = transport_tests.IicTests().setup_bus()
        raw.memory[6] = 0x6c
        dp, status = probe_identities(bus, clocks, log)
        self.assertEqual(bytes(dp), b'DP159   ')
        self.assertEqual(status['device_id'], 0x0606)
        self.assertEqual(bus.read_block(0x5c, 0, 1, 8), b'TMDS181 ')
        with self.assertRaises(IicError): validate_tx(b'TMDS181 ')
        self.assertTrue(all(len(p) == (2 if a == 0x6c else 1) for a, p, o in raw.transfers))

    def test_observed_block_and_each_corrupted_byte(self):
        profiles = idt_profiles(clocks)
        sample = bytes.fromhex('fffffffffffE6c000300310004890000')
        self.assertEqual(validate_idt(sample, sample, profiles)['device_id'], 65535)
        for i in range(16):
            changed = bytearray(sample); changed[i] ^= 1
            if bytes(changed) not in profiles.values():
                with self.subTest(offset=i), self.assertRaises(IicError):
                    validate_idt(changed, changed, profiles)

    def test_all_ff_short_unstable_and_wrong_address(self):
        p = idt_profiles(clocks)
        sample = next(iter(p.values()))
        cases = [(bytes([255]*16), bytes([255]*16)), (sample[:15], sample[:15]),
                 (sample, bytes(16)), (sample[:6]+b'\x7c'+sample[7:],)*2]
        for a, b in cases:
            with self.assertRaises(IicError): validate_idt(a, b, p)

    def test_real_set_clock_then_reprobe_and_reinitialize(self):
        raw, events, master, bus, log = transport_tests.IicTests().setup_bus()
        driver = checked_idt_type(clocks, bus)(master, 0x6c)
        # Model hardware address pin/RO bits at register 6.
        raw.memory[6] = 0x6c
        for frequency in (37125000, 74250000, 148500000, 297000000):
            driver.set_clock(frequency, 742500000)
            probe_identities(bus, clocks, log)
            driver = checked_idt_type(clocks, bus)(master, 0x6c)
            raw.memory[6] = 0x6c

    def test_dp_action_and_dynamic_bits_are_separate(self):
        written = {9:6, 10:0x35, 11:0x80, 12:0x48, 13:0}
        actual = dict(written); actual[10] &= ~4; actual[11] |= 2
        result = verify_dp(actual.__getitem__, written, lambda *a, **k: None)
        self.assertEqual(len(result), 5)
        actual[10] ^= 1
        with self.assertRaises(IicError): verify_dp(actual.__getitem__, written, lambda *a, **k: None)

    def test_real_dp_driver_uses_tx_only_and_toggles_on_mode_change(self):
        raw, events, master, bus, log = transport_tests.IicTests().setup_bus()
        raw.dp_memory[0x0a] = 0x32
        driver = checked_dp_type(clocks, log)(master, 0x5e)
        driver.set_clock(74250000, 742500000)
        verify_dp(driver._read, driver.written, log)
        self.assertTrue(all(a == 0x5e for a, p, o in raw.transfers))
        self.assertIn((0x5e, [9, 14], 0), raw.transfers)
        self.assertIn((0x5e, [9, 6], 0), raw.transfers)
        self.assertTrue(any(e['event'] == 'dp159_mode_power_toggle' for e in events))

    def test_dp_stable_field_failure_still_rejected(self):
        for register in (9, 10, 11, 12, 13):
            written = {9:6, 10:0x35, 11:0x80, 12:0x48, 13:0}
            actual = dict(written); actual[register] ^= (0x80 if register == 11 else 1)
            with self.subTest(register=register), self.assertRaises(IicError):
                verify_dp(actual.__getitem__, written, lambda *a, **k: None)

    def test_edid_cta_vic_and_raw_evidence(self):
        result = validate_edid(edid())
        self.assertTrue(result['supports_720p60'])
        self.assertTrue(result['all_declared_blocks_read'])
        self.assertEqual(result['evidence'], ['CTA_VIC_4'])

    def test_edid_dtd_without_extension(self):
        data = edid(False)
        dtd = bytearray(18)
        dtd[:8] = bytes.fromhex('011d007251d01e20')
        data[54:72] = dtd; data[127] = 0; data[127] = -sum(data) & 255
        self.assertTrue(validate_edid(data)['supports_720p60'])

    def test_edid_invalid_header_checksum_missing_extension_and_no_mode(self):
        invalid = [bytes(256), edid()[:128], edid(False)]
        corrupted = edid(); corrupted[140] ^= 1; invalid.append(corrupted)
        malformed = edid(); malformed[130] = 5; malformed[255] = 0; malformed[255] = -sum(malformed[128:]) & 255
        invalid.append(malformed)
        for value in invalid:
            with self.assertRaises(IicError): validate_edid(value)

    def test_edid_extra_extensions_are_explicitly_unread(self):
        data = edid(); data[126] = 2; data[127] = 0; data[127] = -sum(data[:128]) & 255
        result = validate_edid(data)
        self.assertFalse(result['all_declared_blocks_read'])
        self.assertEqual(result['blocks_read_and_validated'], 2)

    def test_pio_read_offsets_and_reset_context(self):
        regs = {0x44:1, 0x54:3 << 21, 0x64:0x207}
        result = pio_snapshot(SimpleNamespace(read=regs.__getitem__))
        self.assertTrue(result['hpd_sample'] and result['bridge_locked'] and result['pio_running'])
        self.assertEqual(result['external_reset_bits'], 3)


if __name__ == '__main__': unittest.main(verbosity=2)
