"""ZCU104 board evidence and HDMI validation; no hardware imports or writes."""
try:
    from .hdmi_iic import IicError
except ImportError:
    from hdmi_iic import IicError

TX_ADDRESS = 0x5e  # This board: observed DP159; 0x5c is the RX TMDS181.
IDT_ADDRESS = 0x6c


def idt_profiles(clocks):
    class Image(clocks.IDT_8T49N24):
        def __init__(self):
            self.image = {2: 0, 3: 0x60, 4: 0x60}
            super().__init__(None, IDT_ADDRESS)
        def _read(self, r):
            return self.image.get(r, 0)
        def _write(self, r, v):
            self.image[r] = (v & 0x7c) if r == 6 else v
    model = Image()
    profiles = {'PINNED_INITIAL_CONFIG': bytes(model.image.get(i, 0) for i in range(16))}
    # Finite clock states relevant to the fixed 720p60 TX/PHY mode. No arbitrary divider acceptance.
    for frequency in (37125000, 74250000, 148500000, 297000000):
        model = Image()
        model.set_clock(frequency, 742500000)
        profiles['PINNED_CLOCK_%d' % frequency] = bytes(model.image.get(i, 0) for i in range(16))
    return profiles


def validate_idt(first, second, profiles):
    first, second = bytes(first), bytes(second)
    if len(first) != 16 or len(second) != 16:
        raise IicError('IDT requires two complete 16-byte blocks')
    if first != second:
        raise IicError('IDT configuration changed between two reads')
    if first == bytes([255]*16) or (first[6] & 127) != IDT_ADDRESS:
        raise IicError('IDT invalid all-FF block or address readback')
    identity = ((first[2] & 15) << 12) | (first[3] << 4) | (first[4] >> 4)
    if identity == 0x0606:
        evidence = 'FACTORY_ID_AND_ADDRESS'
    elif identity == 0xffff:
        evidence = next((name for name, value in profiles.items() if value == first), None)
        if evidence is None:
            raise IicError('IDT FFFF lacks a recognized full driver-state signature; preserve block for review')
    else:
        raise IicError('Unsupported IDT ID: 0x%04x' % identity)
    return dict(device_id=identity, evidence=evidence, registers_0000_000f=list(first), stable_two_reads=True)


def validate_tx(identity, address=TX_ADDRESS):
    if address != TX_ADDRESS or bytes(identity) != b'DP159   ':
        raise IicError('Expected this board TX DP159 at 0x5e; do not configure RX TMDS181 at 0x5c')


def probe_identities(bus, clocks, log):
    dp = list(bus.read_block(TX_ADDRESS, 0, 1, 8))
    validate_tx(dp)
    first = bus.read_block(IDT_ADDRESS, 0, 2, 16)
    second = bus.read_block(IDT_ADDRESS, 0, 2, 16)
    status = validate_idt(first, second, idt_profiles(clocks))
    log('identity_verified', tx_address=TX_ADDRESS, dp159=dp, idt=status)
    return dp, status


def verify_dp(read, written, log):
    # TI Rev G tables 7/8/9: 0A bit2 is write-only apply; 0B bit1 is DDC-updated.
    masks = {0x09: 0xcf, 0x0a: 0xfb, 0x0b: 0xf9, 0x0c: 255, 0x0d: 0x3f}
    result = []
    for register, value in written.items():
        if register not in masks:
            raise IicError('Unaudited DP159 register: 0x%x' % register)
        actual, mask = int(read(register)), masks[register]
        item = dict(register=register, expected=int(value), actual=actual, mask=mask)
        log('dp159_readback', **item)
        if (actual & mask) != (int(value) & mask):
            raise IicError('DP159 stable-field mismatch at 0x%02x; check I2C_EN/PIN and mode: %s' % (register, item))
        result.append(item)
    return result


def checked_dp_type(clocks, log):
    class CheckedDP(clocks.DP159):
        def __init__(self, master, address):
            self.written = {}
            super().__init__(master, address)

        def set_clock(self, frequency, line_rate):
            previous_mode = self._read(0x0a) & 3
            super().set_clock(frequency, line_rate)
            if previous_mode != (self._read(0x0a) & 3):
                # TI table 7: crossover changes require PD_EN or external HPD toggle.
                control = self._read(0x09)
                self._write(0x09, control | 8)
                self._write(0x09, control & ~8)
                log('dp159_mode_power_toggle', previous_mode=previous_mode,
                    new_mode=self._read(0x0a) & 3)

        def _write(self, register, value):
            super()._write(register, value)
            self.written[register] = value
    return CheckedDP


def _dtd_720(data):
    if len(data) != 18:
        return False
    clock = int.from_bytes(data[:2], 'little') * 10000
    h = data[2] | ((data[4] >> 4) << 8)
    hb = data[3] | ((data[4] & 15) << 8)
    v = data[5] | ((data[7] >> 4) << 8)
    vb = data[6] | ((data[7] & 15) << 8)
    return (clock > 0 and h == 1280 and v == 720 and not (data[17] & 128)
            and h+hb > 0 and v+vb > 0 and abs(clock/((h+hb)*(v+vb)) - 60) < 0.2)


def validate_edid(raw):
    raw = bytes(raw)
    if len(raw) < 128 or raw[:8] != bytes.fromhex('00ffffffffffff00'):
        raise IicError('Invalid EDID header/length')
    extensions = raw[126]
    available = min(extensions+1, len(raw)//128)
    if available < 1 or len(raw) % 128:
        raise IicError('Truncated EDID block')
    if extensions and available < 2:
        raise IicError('EDID declares extension but it was not read')
    reasons = []
    for block_index in range(available):
        block = raw[128*block_index:128*(block_index+1)]
        if sum(block) & 255:
            raise IicError('EDID checksum failed: block %d' % block_index)
        if block_index == 0:
            for i in range(54, 126, 18):
                if _dtd_720(block[i:i+18]): reasons.append('BASE_DTD_720P60')
        elif block[0] == 2:
            end = block[2]
            if end and not 4 <= end <= 127:
                raise IicError('Malformed CTA data-block boundary')
            i = 4
            while end and i < end:
                tag, count = block[i] >> 5, block[i] & 31
                if i+1+count > end:
                    raise IicError('CTA data block exceeds boundary')
                if tag == 2 and any((v & 127) == 4 for v in block[i+1:i+1+count]):
                    reasons.append('CTA_VIC_4')
                i += count+1
            if end:
                for i in range(end, 109, 18):
                    if _dtd_720(block[i:i+18]): reasons.append('CTA_DTD_720P60')
    if not reasons:
        raise IicError('720p60 support not established in the EDID blocks read; no forced fallback')
    return dict(declared_extensions=extensions, blocks_read_and_validated=available,
                all_declared_blocks_read=available == extensions+1, supports_720p60=True,
                evidence=reasons, raw_hex=raw[:available*128].hex(),
                reader_limit_bytes=256, note='Additional extensions, if any, are unread; no claim about their validity')


def pio_snapshot(tx):
    # Matched xparameters: core offset=0; xv_hdmitx_hw.h PIO_BASE=64.
    control, output, inputs = (int(tx.read(r)) for r in (0x44, 0x54, 0x64))
    return dict(control=control, output=output, inputs=inputs, pio_running=bool(control & 1),
                hpd_sample=bool(inputs & 4), link_ready=bool(inputs & 1), video_ready=bool(inputs & 2),
                bridge_locked=bool(inputs & 512), overflow=bool(inputs & 1024), underflow=bool(inputs & 2048),
                external_reset_bits=(output >> 21) & 3,
                note='Raw core sample, not an external voltage measurement; interpret with PIO/reset state')
