"""Fake transport + real pinned official IDT algorithm; not a board simulation."""
import importlib
from pathlib import Path
import sys
import types
import unittest

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
from hdmi_iic import ExactIIC, RegisterBus, IicError, identity_policy, verify_initial_config, checked_idt_type

package = types.ModuleType('pinned_clock_test')
package.__path__ = [str(HERE / 'pynq-reference-v3.0.1/pynq/lib/video')]
sys.modules[package.__name__] = package
clocks = importlib.import_module(package.__name__ + '.clocks')


class FakeRaw:
    def __init__(self, idt_stuck=None):
        self.memory = {2: 0, 3: 0x60, 4: 0x60, 0x70: 0}
        self.idt_stuck = idt_stuck
        self.pointer = {}
        self.transfers = []
        self.count_delta = 0
        self.dp_memory = {0x0a: 0x31}

    def send(self, address, buffer, length, option=0):
        payload = [int(buffer[i]) for i in range(length)]
        self.transfers.append((address, payload, option))
        if address not in (0x6c, 0x5c, 0x5e):
            raise OSError('Unmapped board address')
        if address == 0x5c and length > 1:
            raise AssertionError('Write to RX TMDS181')
        if address == 0x6c:
            register = (payload[0] << 8) | payload[1]
            self.pointer[address] = register
            if length == 3 and self.idt_stuck is None:
                self.memory[register] = payload[2]
        else:
            self.pointer[address] = payload[0]
            if len(payload) == 2:
                self.dp_memory[payload[0]] = payload[1]
        return length + self.count_delta

    def receive(self, address, buffer, length, option=0):
        register = self.pointer[address]
        for i in range(length):
            if address == 0x6c:
                buffer[i] = self.memory.get(register+i, 0) if self.idt_stuck is None else self.idt_stuck
            else:
                buffer[i] = ((b'DP159   ' if address == 0x5e else b'TMDS181 ')[register+i]
                             if register+i < 8 else self.dp_memory.get(register+i, 0))
        return length + self.count_delta

    def read(self, offset):
        assert offset in (0x20, 0x100, 0x104, 0x114, 0x118), 'destructive status read'
        return 0

    def write(self, offset, value):
        assert offset == 0x20

    def wait(self):
        pass


class IicTests(unittest.TestCase):
    def setup_bus(self, stuck=None):
        raw, events = FakeRaw(stuck), []
        log = lambda event, **fields: events.append(dict(event=event, **fields))
        master = ExactIIC(raw, log)
        return raw, events, master, RegisterBus(master, clocks._ffi, log), log

    def test_real_official_config_changes_id_to_ffff_and_second_init_works(self):
        raw, events, master, bus, log = self.setup_bus()
        self.assertEqual(identity_policy([0, 0x60, 0x60], b'DP159   ')['device_id'], 0x0606)
        driver = checked_idt_type(clocks, bus)(master, 0x6c)
        self.assertEqual([raw.memory[r] for r in (2, 3, 4)], [255, 255, 255])
        self.assertEqual(identity_policy([255]*3, b'DP159   ')['device_id'], 0xffff)
        self.assertEqual(len(verify_initial_config(driver._read, clocks.IDT_Synth, log)), 16)
        again = checked_idt_type(clocks, bus)(master, 0x6c)
        verify_initial_config(again._read, clocks.IDT_Synth, log)
        self.assertIn((0x6c, [0, 2], 1), raw.transfers)

    def test_real_official_set_clock_and_readback_for_720p(self):
        raw, events, master, bus, log = self.setup_bus()
        driver = checked_idt_type(clocks, bus)(master, 0x6c)
        driver.written = {}
        driver.set_clock(74250000, 742500000)
        self.assertGreater(len(driver.written), 20)
        for register, value in driver.written.items():
            self.assertEqual(driver._read(register), value)
        self.assertEqual(driver._read(0x70) & 5, 0)

    def test_idt_all_ff_with_working_dp_is_rejected_by_configuration_readback(self):
        raw, events, master, bus, log = self.setup_bus(255)
        identity_policy([255]*3, b'DP159   ')
        driver = checked_idt_type(clocks, bus)(master, 0x6c)
        with self.assertRaisesRegex(IicError, 'readback mismatch'):
            verify_initial_config(driver._read, clocks.IDT_Synth, log)

    def test_shared_bus_all_ff_and_unexpected_device_rejected(self):
        for identity, dp in [([255]*3, bytes([255]*8)), ([0, 0x12, 0x30], b'DP159   ')]:
            with self.assertRaises(IicError):
                identity_policy(identity, dp)

    def test_short_send_rejected_and_logged(self):
        raw, events, master, bus, log = self.setup_bus()
        raw.count_delta = -1
        with self.assertRaisesRegex(IicError, 'Short IIC send'):
            bus.read(0x6c, 2)
        self.assertEqual(events[-1]['event'], 'iic_error')

    def test_short_receive_rejected_and_logged(self):
        raw, events, master, bus, log = self.setup_bus()
        receive = raw.receive
        raw.receive = lambda *args: receive(*args) - 1
        with self.assertRaisesRegex(IicError, 'Short IIC receive'):
            bus.read(0x6c, 2)

    def test_send_exception_has_no_hidden_retry(self):
        raw, events, master, bus, log = self.setup_bus()
        def fail(*args):
            raise OSError('NACK')
        raw.send = fail
        with self.assertRaisesRegex(OSError, 'NACK'):
            bus.read(0x6c, 2)
        self.assertEqual(sum(e['event'] == 'iic_begin' for e in events), 1)

    def test_configuration_corruption_and_output_disabled_rejected(self):
        raw, events, master, bus, log = self.setup_bus()
        driver = checked_idt_type(clocks, bus)(master, 0x6c)
        raw.memory[0x26] ^= 1
        with self.assertRaisesRegex(IicError, '0x0026'):
            verify_initial_config(driver._read, clocks.IDT_Synth, log)
        raw.memory[0x26] = clocks.IDT_Synth[0x26]
        raw.memory[0x70] = 5
        with self.assertRaisesRegex(IicError, 'not released'):
            verify_initial_config(driver._read, clocks.IDT_Synth, log)


if __name__ == '__main__':
    unittest.main(verbosity=2)
