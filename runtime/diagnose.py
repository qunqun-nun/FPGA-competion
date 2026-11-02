#!/usr/bin/env python3
"""Read-only board environment collection: no MMIO, driver loading, or FPGA changes."""
import importlib
import json
import os
import platform
import sys
from pathlib import Path


def main():
    root = Path(__file__).resolve().parent.parent
    result = {'machine': platform.machine(), 'python': sys.version, 'uname': platform.uname()._asdict(),
              'modules': {}, 'video_devices': [str(x) for x in Path('/dev').glob('video*')],
              'drm_devices': [str(x) for x in Path('/dev/dri').glob('*')],
              'board_verified': False,
              'hdmi_runtime': 'package PYNQ userspace TX/PHY initializer; not exercised by this diagnostic'}
    for name in ('numpy', 'cv2', 'pynq', 'pynq_dpu', 'xir', 'vart'):
        try:
            mod = importlib.import_module(name)
            result['modules'][name] = {'version': str(getattr(mod, '__version__', 'not exposed')),
                                       'path': getattr(mod, '__file__', '')}
        except Exception as exc:
            result['modules'][name] = {'error': str(exc)}
    for name, path in (('os_release', '/etc/os-release'), ('vart_config', '/etc/vart.conf'),
                       ('kernel', '/proc/version'), ('bootargs', '/proc/cmdline')):
        try:
            result[name] = Path(path).read_text()
        except OSError as exc:
            result[name] = str(exc)
    try:
        from pl_runtime import check_reserved
        check_reserved()
        result['reserved_memory'] = 'PASS'
    except Exception as exc:
        result['reserved_memory'] = str(exc)
    output = root / 'state/diagnostic.json'
    output.parent.mkdir(exist_ok=True)
    output.write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding='utf-8')
    print(json.dumps(result, ensure_ascii=False, indent=2))
    print('Saved: ' + str(output))


if __name__ == '__main__':
    main()
