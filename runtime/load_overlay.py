#!/usr/bin/env python3
"""Load the packaged matched trio, retaining /etc/vart.conf rollback material."""
import json
import os
import shutil
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def main():
    from verify_package import verify
    verify(ROOT)
    from package_config import hardware_paths
    config, files = hardware_paths()
    if os.uname().machine != 'aarch64' or os.geteuid() != 0:
        raise RuntimeError('Overlay loading requires ZCU104 root')
    from pl_runtime import check_reserved
    check_reserved()  # do not reprogram until boot RAM reservation is checked
    from pynq_dpu import DpuOverlay
    state = ROOT / 'state'
    state.mkdir(exist_ok=True)
    previous = state / ('vart_backup_' + str(time.time_ns()))
    previous.mkdir()
    conf = Path('/etc/vart.conf')
    existed = conf.exists()
    if existed:
        shutil.copy2(str(conf), str(previous / 'vart.conf'))
    (previous / 'backup.json').write_text(json.dumps({'existed': existed}), encoding='utf-8')
    hardware = ROOT / 'hardware'
    # DpuOverlay's default copies into /usr/lib. Keep all firmware in this package
    # and use a DPU-only Runner instead of load_model/check_vart_config overrides.
    class LocalDpuOverlay(DpuOverlay):
        def download(self):
            from pl_clock import prepare_download, assert_clock, record
            record('before_download', prepare_download(self, files['hwh']))
            super().download()
            record('after_download', assert_clock(files['hwh']))

        def copy_xclbin(self):
            pass  # exact firmware already present; no /usr/lib overwrite required
    try:
        conf.write_text('firmware: ' + str(files['xclbin']) + '\n')
        overlay = LocalDpuOverlay(str(files['bit']))
        (state / 'loaded.json').write_text(json.dumps({'hardware': config['hardware_version'], 'backup': str(previous),
                                                     'time': time.time(), 'pid': os.getpid()}))
        print('OVERLAY_LOADED; HDMI initialization and complete-system board acceptance remain separate.')
        return overlay
    except Exception:
        # Hardware programming can partially succeed: preserve correct firmware
        # config and require reboot/explicit rollback, rather than silently point
        # VART at old hardware after an uncertain programming result.
        print('LOAD_FAILED: config backup in ' + str(previous) + '; stop tasks and reboot before old deployment.')
        raise


if __name__ == '__main__':
    main()
