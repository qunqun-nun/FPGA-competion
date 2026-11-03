#!/usr/bin/env python3
"""Prepare config rollback only; does not pretend to restore FPGA hardware."""
import argparse
import json
import os
import shutil
from pathlib import Path


def main():
    p = argparse.ArgumentParser()
    p.add_argument('backup', type=Path)
    p.add_argument('--prepare-reboot', action='store_true', required=True,
                   help='Stop all DPU processes, restore config, then reboot before any inference')
    a = p.parse_args()
    root = Path(__file__).resolve().parent.parent
    folder = a.backup.resolve()
    if (root / 'state').resolve() not in folder.parents or not folder.is_dir():
        raise RuntimeError('Backup must be this package state/vart_backup_* directory')
    if os.geteuid() != 0:
        raise RuntimeError('Requires root')
    if (root / 'state/pipeline.pid').exists():
        raise RuntimeError('Stop pipeline first')
    info = json.loads((folder / 'backup.json').read_text())
    conf = Path('/etc/vart.conf')
    if info['existed']:
        shutil.copy2(str(folder / 'vart.conf'), str(conf))
    elif conf.exists():
        conf.unlink()
    print('Original VART config restored. Reboot now before any DPU application; old FPGA state is NOT restored.')


if __name__ == '__main__':
    main()
