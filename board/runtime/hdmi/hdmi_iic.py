"""Auditable IIC transactions; caller must provide a process watchdog and lock.

No controller reset, bus scan, EEPROM write, or change to installed PYNQ.
"""
import json
from pathlib import Path
import time


class IicError(RuntimeError):
    pass


class Journal:
    def __init__(self, path):
        path = Path(path)
        path.parent.mkdir(parents=True, exist_ok=True)
        self.file = path.open('a', encoding='utf-8', buffering=1)

    def __call__(self, event, **fields):
        self.file.write(json.dumps(dict(event=event, monotonic=time.monotonic(), **fields),
                                   sort_keys=True) + '\n')
        self.file.flush()


class ExactIIC:
    def __init__(self, raw, log):
        self.raw, self.log = raw, log

    def snapshot(self):
        # XIic low-level header: reads do not consume RX FIFO or clear IRQs.
        return {name: int(self.raw.read(offset)) for name, offset in
                [('iisr', 0x20), ('cr', 0x100), ('sr', 0x104),
                 ('tx_fifo_occupancy', 0x114), ('rx_fifo_occupancy', 0x118)]}

    def _transfer(self, method, address, buffer, length, option):
        fields = dict(operation=method, address=address, length=length, option=option)
        if method == 'send':
            fields['bytes'] = [int(buffer[i]) for i in range(length)]
        self.log('iic_begin', registers=self.snapshot(), **fields)
        try:
            count = getattr(self.raw, method)(address, buffer, length, option)
            if count != length:
                raise IicError('Short IIC %s: address=0x%x expected=%d actual=%s' %
                               (method, address, length, count))
        except BaseException as error:
            self.log('iic_error', error=str(error), registers=self.snapshot(), **fields)
            raise
        self.log('iic_end', count=int(count), data=[int(buffer[i]) for i in range(length)],
                 registers=self.snapshot(), **fields)
        # An RX-final NACK may be normal; do not classify raw ISR bits alone.
        return count

    def send(self, address, buffer, length, option=0):
        return self._transfer('send', address, buffer, length, option)

    def receive(self, address, buffer, length, option=0):
        return self._transfer('receive', address, buffer, length, option)

    def wait(self):
        self.log('wait_begin', registers=self.snapshot())
        self.raw.wait()
        self.log('wait_end', registers=self.snapshot())

    def read(self, offset):
        return self.raw.read(offset)

    def write(self, offset, value):
        if offset != 0x20:
            raise IicError('Unexpected PYNQ IIC register write')
        self.log('clear_interrupts', offset=offset, value=int(value))
        self.raw.write(offset, value)


class RegisterBus:
    def __init__(self, master, ffi, log):
        self.master, self.ffi, self.log = master, ffi, log

    def read(self, address, register, address_bytes=2):
        return self.read_block(address, register, address_bytes, 1)[0]

    def read_block(self, address, register, address_bytes, length):
        if address_bytes not in (1, 2) or not 1 <= length <= 16:
            raise IicError('Unsupported bounded register block')
        pointer = self.ffi.new('unsigned char[2]')
        buffer = self.ffi.new('unsigned char[16]')
        encoded = register.to_bytes(address_bytes, 'big')
        for i, byte in enumerate(encoded):
            pointer[i] = byte
        self.master.send(address, pointer, address_bytes, 1)
        self.master.receive(address, buffer, length, 0)
        self.master.wait()
        value = bytes(int(buffer[i]) for i in range(length))
        self.log('register_read', address=address, register=register, data=list(value))
        return value

    def write(self, address, register, value):
        buffer = self.ffi.new('unsigned char[3]')
        buffer[0], buffer[1], buffer[2] = register >> 8, register & 255, value
        self.master.send(address, buffer, 3, 0)
        self.master.wait()
        self.log('register_write', address=address, register=register, value=int(value))


def identity_policy(raw_id, dp_identity):
    if bytes(dp_identity) != b'DP159   ':
        raise IicError('DP159 identity mismatch: %s; shared bus is not established' % list(dp_identity))
    if len(raw_id) != 3 or any(not 0 <= v <= 255 for v in raw_id):
        raise IicError('Malformed IDT identity bytes')
    identity = ((raw_id[0] & 15) << 12) | (raw_id[1] << 4) | (raw_id[2] >> 4)
    if identity not in (0x0606, 0xffff):
        raise IicError('Unsupported IDT identity: 0x%04x' % identity)
    return dict(device_id=identity, raw_bytes=list(raw_id),
                compatibility='PYNQ_FFFF_COMPATIBILITY' if identity == 0xffff else 'ID_0606',
                id_alone_proves_communication=False, configuration_readback_required=True)


# Writable configuration fields used by the pinned official IDT methods.
# Excludes identity, reserved bits, and self-clearing calibration register 0x70.
INITIAL_MASKS = {0x0a: 0x33, 0x0b: 0x1f, 0x0c: 255, 0x0d: 255,
                 0x25: 1, 0x26: 255, 0x28: 0x1f, 0x29: 255, 0x2a: 255,
                 0x45: 3, 0x46: 255, 0x47: 255, 0x48: 3, 0x49: 255, 0x4a: 255,
                 0x69: 8}


def verify_initial_config(read, values, log):
    observations = []
    for register, mask in INITIAL_MASKS.items():
        expected, actual = int(values[register]), int(read(register))
        item = dict(register=register, expected=expected, actual=actual, mask=mask)
        log('initial_config_readback', **item)
        if (actual & mask) != (expected & mask):
            raise IicError('IDT initial configuration readback mismatch at 0x%04x: expected=0x%02x actual=0x%02x mask=0x%02x' %
                           (register, expected, actual, mask))
        observations.append(item)
    control = int(read(0x70))
    if control & 5:
        raise IicError('IDT output enable/calibration bits not released')
    log('initial_config_verified', registers=len(observations), control_0070=control)
    return observations


def checked_idt_type(clocks, bus):
    class CheckedIDT(clocks.IDT_8T49N24):
        def __init__(self, master, address):
            self.written = {}
            super().__init__(master, address)

        def _read(self, register):
            # No silent 101 retries. The caller's process watchdog bounds C calls.
            return bus.read(self._address, register, 2)

        def _write(self, register, value):
            bus.write(self._address, register, value)
            self.written[register] = value
    return CheckedIDT
