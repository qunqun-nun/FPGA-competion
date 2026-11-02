#!/usr/bin/env python3
"""Probe the loaded design; --initialize/--start explicitly configure HDMI.

Default: device register reads only (IIC register-pointer sends are required).
Never downloads an overlay, changes boot files, scans a bus or toggles reset.
"""
import argparse
import hashlib
import json
import multiprocessing
import os
from pathlib import Path
import platform
import sys
import time

ROOT = Path(__file__).resolve().parent.parent


def probe_worker(description, device, output, connection):
    try:
        import fcntl
        from pynq.lib.iic import AxiIIC
        from pynq.lib.video import clocks
        from hdmi.hdmi_iic import Journal, ExactIIC, RegisterBus
        from hdmi.board_validation import TX_ADDRESS, probe_identities
        from hdmi.pynq_hdmi_init import check_ownership
        with open('/run/lock/fengyan-hdmi.lock', 'a+') as lock:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            check_ownership()
            description['device'] = device
            log = Journal(output)
            master = ExactIIC(AxiIIC(description), log)
            bus = RegisterBus(master, clocks._ffi, log)
            log('probe_begin', registers=master.snapshot(), no_device_configuration_writes=True)
            dp, status = probe_identities(bus, clocks, log)
            config = {hex(r): bus.read(0x6c, r, 2) for r in (0xa, 0xc, 0xd, 0x26, 0x45, 0x47, 0x70)}
            connection.send(dict(phase='PROBE_COMPLETE', identity=status, dp159=dp, tx_address=TX_ADDRESS,
                                 idt_sample=config, hdmi_verified=False))
    except BaseException as error:
        connection.send(dict(phase='FAILED', error=type(error).__name__ + ': ' + str(error)))
    finally:
        connection.close()


def probe(overlay, output):
    from hdmi.pynq_hdmi_init import IPS, check_descriptions, HdmiError
    check_descriptions(overlay.ip_dict)
    context = multiprocessing.get_context('fork')
    parent, child = context.Pipe(duplex=False)
    process = context.Process(target=probe_worker, args=(dict(overlay.ip_dict['v014_fmch_iic']),
                              overlay.device, str(output), child))
    process.start()
    child.close()
    try:
        if not parent.poll(15):
            raise HdmiError('IIC probe timeout; hardware state UNKNOWN_REBOOT_REQUIRED')
        result = parent.recv()
        if result['phase'] == 'FAILED':
            raise HdmiError(result['error'])
        return result
    finally:
        if process.is_alive():
            process.join(0.2)
        if process.is_alive():
            process.terminate()
            process.join(0.5)
        if process.is_alive():
            process.kill()
            process.join(0.5)
        parent.close()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--out', type=Path, required=True)
    parser.add_argument('--initialize', action='store_true', help='Write official IDT configuration, then verify it')
    parser.add_argument('--start', action='store_true', help='Also configure 720p60 and test PHY/stream; requires --initialize')
    args = parser.parse_args()
    if args.start and not args.initialize:
        parser.error('--start requires --initialize')
    if platform.system() != 'Linux' or platform.machine() != 'aarch64' or os.geteuid() != 0:
        parser.error('Run as root on ZCU104, using the PYNQ environment')
    args.out.mkdir(parents=True, exist_ok=False)
    result = dict(software='V0.17.3', phase='BEGIN', picture_verified=False)
    session = None
    code = 1
    try:
        if (ROOT / 'state/pipeline.pid').exists():
            raise RuntimeError('Stop the pipeline using runtime/stop.sh before probing')
        from verify_package import verify
        verify(ROOT)
        import pynq
        from pynq import Overlay
        from package_config import hardware_paths
        from pl_clock import assert_clock
        from hdmi.pynq_hdmi_init import HdmiSession
        config, files = hardware_paths()
        result.update(pynq=pynq.__version__, python=sys.version, uname=platform.uname()._asdict(),
                      clock_before=assert_clock(files['hwh']),
                      hardware_sha256={k: hashlib.sha256(v.read_bytes()).hexdigest() for k, v in files.items()})
        overlay = Overlay(str(files['bit']), download=False)
        if not overlay.is_loaded():
            raise RuntimeError('Package overlay is not loaded; use runtime/collect_pl_clock.py --load first')
        result['probe'] = probe(overlay, args.out / 'probe_iic.jsonl')
        if args.initialize:
            session = HdmiSession(overlay, journal_path=args.out / 'init_iic.jsonl')
            result['initialization'] = session.init()
            print('HDMI_INIT_OK', flush=True)
            if args.start:
                result['stream'] = session.start()
                for i in range(5):
                    result['last_service'] = session.service()
                    time.sleep(1)
                print('HDMI_STREAM_STATUS ' + json.dumps(result['stream']), flush=True)
        result['clock_after'] = assert_clock(files['hwh'])
        result['phase'] = 'STREAM_VERIFIED_PICTURE_PENDING' if args.start else (
            'INITIAL_CONFIG_VERIFIED_STREAM_PENDING' if args.initialize else 'PROBE_COMPLETE_NOT_HDMI_ACCEPTANCE')
        code = 0
    except BaseException as error:
        result.update(phase='FAILED', error=type(error).__name__ + ': ' + str(error))
    finally:
        if session is not None:
            try:
                result['cleanup'] = session.close()
            except BaseException as error:
                result.update(cleanup_error=str(error), phase='FAILED_CLEANUP_UNKNOWN_REBOOT_REQUIRED')
                code = 1
        (args.out / 'result.json').write_text(json.dumps(result, indent=2), encoding='utf-8')
        print(json.dumps(result, indent=2), flush=True)
    return code


if __name__ == '__main__':
    sys.exit(main())
