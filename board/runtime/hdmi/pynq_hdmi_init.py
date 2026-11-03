#!/usr/bin/env python3
"""Strict real PYNQ userspace HDMI candidate; no programming or kernel unbind.

API: s = HdmiSession(loaded_overlay); s.init(); s.start(); s.service(); s.close().
Native calls run in an isolated Linux worker so the caller has bounded waits.
Forced worker termination means hardware state UNKNOWN, never a successful stop.
"""
import atexit
import hashlib
import json
import math
import multiprocessing
import os
from pathlib import Path
import platform
import time

try:
    from .pynq_prepare_library import hwh_profile
    from .hdmi_iic import Journal, ExactIIC, RegisterBus, verify_initial_config, checked_idt_type
    from .board_validation import TX_ADDRESS, probe_identities, verify_dp, checked_dp_type, validate_edid, pio_snapshot
except ImportError:
    from pynq_prepare_library import hwh_profile
    from hdmi_iic import Journal, ExactIIC, RegisterBus, verify_initial_config, checked_idt_type
    from board_validation import TX_ADDRESS, probe_identities, verify_dp, checked_dp_type, validate_edid, pio_snapshot

HERE = Path(__file__).resolve().parent
IPS = {'v014_hdmi_tx_ss': (0x82000000, 0x20000, 'xilinx.com:ip:v_hdmi_tx_ss:3.2'),
       'v014_vid_phy': (0x82020000, 0x10000, 'xilinx.com:ip:vid_phy_controller:2.2'),
       'v014_fmch_iic': (0x82030000, 0x10000, 'xilinx.com:ip:axi_iic:2.1')}


class HdmiError(RuntimeError):
    pass


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def matching_profile(compiled, hardware):
    # M12 constant output changes HWH hash, not the TX/PHY driver configuration.
    return all(compiled.get(k) == hardware.get(k) for k in ['schema', 'pynq', 'embeddedsw', 'tx', 'phy', 'iic_base', 'mode'])


def check_descriptions(ip_dict):
    for name, (address, size, kind) in IPS.items():
        item = ip_dict.get(name)
        if not item or item.get('type') != kind or int(item.get('phys_addr', -1)) != address or int(item.get('addr_range', 0)) != size:
            raise HdmiError('Overlay IP metadata mismatch: ' + name)


def check_ownership(sysfs=Path('/sys')):
    devices = sysfs / 'bus/platform/devices'
    if not devices.is_dir():
        raise HdmiError('Platform sysfs unavailable; cannot establish kernel ownership')
    for device in devices.iterdir():
        if not (device / 'driver').is_symlink():
            continue
        resource = device / 'resource'
        try:
            rows = resource.read_text().splitlines() if resource.is_file() else []
        except OSError as e:
            raise HdmiError('Cannot inspect driver resources: ' + str(e))
        matched_name = any(device.name.startswith('%x.' % base) for base, _, _ in IPS.values())
        collision = False
        for row in rows:
            fields = row.split()
            if len(fields) != 3:
                raise HdmiError('Malformed platform resource: ' + str(resource))
            start, end, flags = (int(v, 16) for v in fields)
            if flags & 0x200:
                collision |= any(start < base + size and base <= end for base, size, _ in IPS.values())
        if matched_name or collision:
            raise HdmiError('Kernel driver owns HDMI/PHY/IIC resources: ' + str(device))
    return True


def check_library(path, hardware):
    path = Path(path).resolve(strict=True)
    raw = path.read_bytes()
    if raw[:6] != b'\x7fELF\x02\x01' or len(raw) < 20 or int.from_bytes(raw[18:20], 'little') != 183:
        raise HdmiError('Library is not ELF64 little-endian AArch64')
    receipt = json.loads(path.with_name('build-receipt.json').read_text(encoding='utf-8'))
    if receipt.get('library_sha256') != hashlib.sha256(raw).hexdigest():
        raise HdmiError('Native library SHA-256 does not match its build receipt')
    if not matching_profile(receipt.get('profile', {}), hardware):
        raise HdmiError('Native PHY/TX profile does not match actual HWH; stock PYNQ RX/NIDRU configuration is rejected')
    abi = receipt.get('dynamic_abi', {})
    if abi.get('needed') != ['libc.so.6'] or abi.get('version_needs') != ['GLIBC_2.17']:
        raise HdmiError('Strict candidate requires the audited libc-only/GLIBC_2.17 build receipt')
    return receipt


def wait_state(predicate, pump, desired, deadline, label, sleep=time.sleep, clock=time.monotonic):
    while True:
        if bool(predicate()) == desired:
            return
        if clock() >= deadline:
            raise HdmiError('Timed out waiting for ' + label)
        pump()
        sleep(0.001)


def _worker(connection, descriptions, device, library, expected, timeout_s, inherited_lock, peer_connection, journal_path):
    peer_connection.close()
    tx = phy = lib = None
    started = False
    journal = None
    def stage(name):
        if journal is not None:
            journal('stage', stage=name)
        connection.send(dict(kind='stage', stage=name))
    def cleanup():
        nonlocal tx, phy
        if tx is not None and tx.handle:
            lib.HdmiTx_stop(tx.handle)
            lib.HdmiTx_free(tx.handle)
            tx.handle = None
        if phy is not None and getattr(phy, 'handle', None):
            lib.HdmiPhy_free(phy.handle)
            phy.handle = None
    try:
        journal = Journal(journal_path)
        journal('session_begin', software='V0.17.3', pid=os.getpid())
        stage('PYNQ_ABI')
        import pynq
        from pynq.lib.video import xilinx_hdmi as hd
        from pynq.lib.video import clocks
        from pynq.lib import iic as iic_module
        if pynq.__version__ != '3.0.1':
            raise HdmiError('Strict compatibility requires PYNQ 3.0.1')
        for module, reference in [(hd, 'pynq/lib/video/xilinx_hdmi.py'), (clocks, 'pynq/lib/video/clocks.py'),
                                  (iic_module, 'pynq/lib/iic.py')]:
            actual = Path(module.__file__).read_bytes().replace(b'\r\n', b'\n')
            if actual != (HERE / 'pynq-reference-v3.0.1' / reference).read_bytes().replace(b'\r\n', b'\n'):
                raise HdmiError('Installed PYNQ source differs from pinned reference: ' + reference)
        from pynq.lib.video import constants
        if Path(constants.__file__).read_bytes().replace(b'\r\n', b'\n') != (HERE / 'pynq-reference-v3.0.1/pynq/lib/video/constants.py').read_bytes().replace(b'\r\n', b'\n'):
            raise HdmiError('Installed PYNQ clock constants differ from pinned reference')
        ffi = hd._hdmi_ffi
        ffi.cdef('const char* FengyanHdmi_profile(void); unsigned int FengyanHdmi_refclk(void*); '
                 'unsigned int FengyanHdmi_version(void*); int FengyanHdmi_pll_locked(void*);')
        lib = ffi.dlopen(library)
        if not matching_profile(json.loads(ffi.string(lib.FengyanHdmi_profile()).decode()), expected):
            raise HdmiError('Actual loaded native ABI/profile mismatch')
        for symbol in ['HdmiPhy_new', 'HdmiPhy_free', 'HdmiTx_new', 'HdmiTx_free', 'HdmiTx_set_format',
                       'HdmiTx_start', 'HdmiTx_stop', 'HdmiTx_ready', 'HdmiTx_connected', 'HdmiTx_handle_events',
                       'HdmiTx_line_rate', 'HdmiTx_read_edid', 'FengyanHdmi_refclk', 'FengyanHdmi_pll_locked']:
            getattr(lib, symbol)
        hd._hdmi_lib = lib  # Worker-local; stock PYNQ and other processes unchanged.
        stage('PL_CLOCK')
        actual_axi = float(pynq.Clocks.fclk0_mhz) * 1000000
        nominal = expected['tx']['AXI_LITE_FREQ_HZ']
        if not math.isfinite(actual_axi) or abs(actual_axi - nominal) > nominal * 0.005:
            raise HdmiError('PL0 clock disagrees with HWH: ' + str(actual_axi))
        def description(name):
            result = dict(descriptions[name])
            result['device'] = device
            return result
        raw_iic = iic_module.AxiIIC(description('v014_fmch_iic'))
        master = ExactIIC(raw_iic, journal)
        bus = RegisterBus(master, clocks._ffi, journal)
        stage('TX_5E_IDT_TWO_BLOCKS_NO_CONFIGURATION_WRITE')
        dp_identity, identity_status = probe_identities(bus, clocks, journal)
        identity = identity_status['device_id']
        journal('identity_policy', **identity_status)
        # TI SN65DP159 datasheet section 9.5.4.1, registers 0x00..0x07.
        stage('PHY_AND_TX_BIND')
        phy = hd.Vphy(description('v014_vid_phy'))
        phy.initialize()
        if not phy.handle:
            raise HdmiError('HdmiPhy_new returned NULL')
        tx = hd.HdmiTxSs(description('v014_hdmi_tx_ss'))
        tx.set_phy(phy)
        if not tx.handle:
            raise HdmiError('HdmiTx_new returned NULL')
        CheckedIDT = checked_idt_type(clocks, bus)
        CheckedDP = checked_dp_type(clocks, journal)
        stage('OFFICIAL_IDT_SYNTH_CONFIG')
        dp = CheckedDP(master, TX_ADDRESS)
        idt = CheckedIDT(master, 0x6c)
        stage('IDT_INITIAL_CONFIG_READBACK')
        verify_initial_config(idt._read, constants.IDT_Synth, journal)
        tx.clocks = [dp, idt]
        initial = dict(phase='INITIALIZED', axi_clock_hz=actual_axi, idt_device_id=identity,
                       idt_identity=identity_status, idt_initial_config_readback=True,
                       iic_journal=str(journal_path), dp159_identity_bytes=dp_identity,
                       tx_redriver_address=TX_ADDRESS, pio=pio_snapshot(tx),
                       reset=expected['reset_control'], picture_verified=False)
        connection.send(dict(kind='result', status=initial))
        while True:
            if not connection.poll(0.01):
                if started:
                    lib.HdmiTx_handle_events(tx.handle)
                continue
            command = connection.recv()
            if command == 'close':
                stage('STOP')
                cleanup()
                connection.send(dict(kind='result', status=dict(phase='CLOSED', output_gated=True,
                    note='Official HdmiTx_stop gates TMDS output; IDT configuration is not rolled back')))
                return
            if command == 'start':
                if started:
                    raise HdmiError('Already started')
                deadline = time.monotonic() + timeout_s
                stage('HPD_CONNECT')
                journal('pio_before_connect', **pio_snapshot(tx))
                pump = lambda: lib.HdmiTx_handle_events(tx.handle)
                wait_state(lambda: lib.HdmiTx_connected(tx.handle), pump, True, deadline, 'HPD')
                initial['pio_after_connect'] = pio_snapshot(tx)
                stage('EDID_READ_AND_VALIDATE')
                edid_buffer = ffi.new('unsigned char[256]')
                edid_error = int(lib.HdmiTx_read_edid(tx.handle, edid_buffer))
                if edid_error:
                    raise HdmiError('HDMI EDID read failed: %s' % edid_error)
                edid_raw = bytes(ffi.buffer(edid_buffer, 256))
                Path(journal_path).with_suffix('.edid.bin').write_bytes(edid_raw)
                initial['edid'] = validate_edid(edid_raw)
                journal('edid_validated', **initial['edid'])
                stage('SET_FORMAT_720P60')
                frequency = int(lib.HdmiTx_set_format(tx.handle, 1280, 720, 60))
                line_rate = int(lib.HdmiTx_line_rate(tx.handle))
                if not 8000 <= frequency <= 400000000 or not 0 < line_rate <= 5940000000:
                    raise HdmiError('Native mode/PHY clock calculation failed: %s/%s' % (frequency, line_rate))
                stage('EXTERNAL_CLOCKS')
                for clock in tx.clocks:
                    clock.written = {}
                    clock.set_clock(frequency, line_rate)
                stage('CLOCK_REGISTER_READBACK')
                for register, value in idt.written.items():
                    if register != 0x70 and idt._read(register) != value:
                        raise HdmiError('IDT clock register readback mismatch: 0x%x' % register)
                if idt._read(0x70) & 5:
                    raise HdmiError('IDT output enable/calibration bits not released')
                initial['dp159_readback'] = verify_dp(dp._read, dp.written, journal)
                stage('TX_STREAM_START')
                if int(lib.HdmiTx_start(tx.handle)) != 1:
                    raise HdmiError('HdmiTx_start failed')
                started = True
                # Preserve official event order: stream down, then up.
                wait_state(lambda: lib.HdmiTx_ready(tx.handle), pump, False, deadline, 'stream down')
                wait_state(lambda: lib.HdmiTx_ready(tx.handle), pump, True, deadline, 'stream up')
                stage('BRIDGE_LOCK')
                wait_state(lambda: pio_snapshot(tx)['bridge_locked'], pump, True,
                           deadline, 'video bridge lock')
                initial['pio'] = pio_snapshot(tx)
                journal('pio_stream_up', **initial['pio'])
                measured = int(lib.FengyanHdmi_refclk(phy.handle))
                locked = bool(lib.FengyanHdmi_pll_locked(phy.handle))
                if not locked or abs(measured - frequency) > frequency * 0.01:
                    raise HdmiError('PLL/refclk readback mismatch: %sHz, lock=%s, requested=%s' % (measured, locked, frequency))
                initial.update(phase='STREAM_UP', connected=True, stream_up=True, pll_locked=locked,
                               requested_refclk_hz=frequency, measured_refclk_hz=measured, line_rate_hz=line_rate,
                               phy_version=int(lib.FengyanHdmi_version(phy.handle)), mode=[1280, 720, 60],
                               idt_registers_readback=True, dp159_registers_readback=True)
                connection.send(dict(kind='result', status=dict(initial)))
            elif command == 'service':
                if not started:
                    raise HdmiError('start() has not completed')
                lib.HdmiTx_handle_events(tx.handle)
                if not lib.HdmiTx_connected(tx.handle) or not lib.HdmiTx_ready(tx.handle):
                    raise HdmiError('HDMI disconnected or stream lost; stopped, explicit reinitialization required')
                initial['measured_refclk_hz'] = int(lib.FengyanHdmi_refclk(phy.handle))
                initial['pll_locked'] = bool(lib.FengyanHdmi_pll_locked(phy.handle))
                initial['pio'] = pio_snapshot(tx)
                if not initial['pio']['bridge_locked']:
                    raise HdmiError('Video bridge lost lock')
                if not initial['pll_locked'] or abs(initial['measured_refclk_hz'] - initial['requested_refclk_hz']) > initial['requested_refclk_hz'] * 0.01:
                    raise HdmiError('PLL/reference clock lost')
                connection.send(dict(kind='result', status=dict(initial)))
            else:
                raise HdmiError('Unknown session command')
    except BaseException as e:
        if journal is not None:
            journal('session_error', error=type(e).__name__ + ': ' + str(e))
        # If native cleanup itself stalls, the parent watchdog handles it and
        # reports UNKNOWN_REBOOT_REQUIRED rather than claiming a successful stop.
        try:
            stage('FAILURE_CLEANUP')
            cleanup()
            connection.send(dict(kind='error', error=type(e).__name__ + ': ' + str(e), output_gated=tx is not None))
        except BaseException:
            pass
    finally:
        connection.close()


class HdmiSession:
    def __init__(self, overlay, *, library_path=None, hwh_path=None, timeout_s=15, journal_path=None):
        if not math.isfinite(timeout_s) or timeout_s <= 0:
            raise ValueError('timeout_s must be positive and finite')
        self.overlay = overlay
        self.library_path = Path(library_path) if library_path else HERE / 'pynq_native/libfengyan_xhdmi.so'
        self.hwh_path = Path(hwh_path) if hwh_path else Path(overlay.bitfile_name).with_suffix('.hwh')
        self.timeout_s = timeout_s
        self.journal_path = Path(journal_path) if journal_path else HERE.parent.parent / 'state/hdmi_iic.jsonl'
        self._process = self._connection = self._lock = None
        self.status = dict(phase='NEW', picture_verified=False)

    def _wait(self, timeout):
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            if self._connection.poll(min(0.05, max(0, deadline - time.monotonic()))):
                try:
                    item = self._connection.recv()
                except EOFError:
                    raise HdmiError('Native worker exited; hardware state UNKNOWN_REBOOT_REQUIRED')
                if item['kind'] == 'stage':
                    self.status['stage'] = item['stage']
                elif item['kind'] == 'error':
                    self.status = dict(phase='FAILED', error=item['error'], output_gated=item.get('output_gated'),
                                       last_observation=self.status, picture_verified=False)
                    raise HdmiError(item['error'] + '; cleanup gate=' + str(item.get('output_gated')))
                else:
                    self.status = item['status']
                    return dict(self.status)
            if not self._process.is_alive() and not self._connection.poll():
                raise HdmiError('Native worker exited; hardware state UNKNOWN_REBOOT_REQUIRED')
        self.status = dict(phase='UNKNOWN_REBOOT_REQUIRED', stage=self.status.get('stage'),
                           last_observation=self.status, picture_verified=False)
        raise HdmiError('Worker timeout at %s; hardware state UNKNOWN_REBOOT_REQUIRED' % self.status.get('stage'))

    def init(self):
        if self._process is not None:
            raise HdmiError('Session already initialized')
        if platform.system() != 'Linux' or platform.machine() != 'aarch64' or os.geteuid() != 0:
            raise HdmiError('Requires root on the real AArch64 Linux board')
        if not self.overlay.is_loaded():
            raise HdmiError('Overlay is not loaded; no programming is performed by HDMI')
        check_descriptions(self.overlay.ip_dict)
        expected = hwh_profile(self.hwh_path)
        if not expected['reset_control']['constant_one']:
            raise HdmiError('Final HWH lacks IDT_8T49N241_RST_OUT connected to a 1-bit constant 1; V0.16 baseline rejected')
        check_library(self.library_path, expected)
        check_ownership()
        import fcntl
        self._lock = open('/run/lock/fengyan-hdmi.lock', 'a+')
        try:
            fcntl.flock(self._lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            check_ownership()
            context = multiprocessing.get_context('fork')
            self._connection, child = context.Pipe()
            descriptions = {n: dict(self.overlay.ip_dict[n]) for n in IPS}
            self._process = context.Process(target=_worker, args=(child, descriptions, self.overlay.device,
                str(self.library_path.resolve()), expected, self.timeout_s, self._lock.fileno(), self._connection,
                str(self.journal_path.resolve())), daemon=True)
            self._process.start()
            child.close()
            atexit.register(self.close)
            return self._wait(self.timeout_s)
        except BaseException:
            self._abort()
            raise

    def _request(self, command):
        if self._process is None or not self._process.is_alive():
            raise HdmiError('No live HDMI worker')
        try:
            self._connection.send(command)
            return self._wait(self.timeout_s)
        except BaseException:
            self._abort()
            raise

    def start(self):
        return self._request('start')

    def service(self):
        return self._request('service')

    poll = service

    def _abort(self):
        if self._process is not None and self._process.is_alive():
            self._process.terminate()
            self._process.join(0.5)
            if self._process.is_alive():
                self._process.kill()
                self._process.join(0.5)
        if self._connection is not None:
            self._connection.close()
        if self._lock is not None:
            self._lock.close()
        self._connection = self._lock = None

    def close(self):
        if self._connection is None:
            return dict(self.status)
        try:
            return self._request('close')
        finally:
            if self._process is not None:
                self._process.join(0.2)
            self._abort()

    stop = close


def initialize(overlay, *, library_path=None, hwh_path=None, timeout_s=15):
    session = HdmiSession(overlay, library_path=library_path, hwh_path=hwh_path, timeout_s=timeout_s)
    try:
        session.init()
        session.start()
        return session
    except BaseException:
        session.close()
        raise
