"""Collect read-only import/device evidence; never download an Overlay."""
import argparse
import json
import os
import platform
import subprocess
import sys
from pathlib import Path


def probe(module, timeout):
    code = '''import importlib,json,sys
m=importlib.import_module(sys.argv[1])
r={'module':sys.argv[1],'file':getattr(m,'__file__',None),'version':str(getattr(m,'__version__','UNKNOWN'))}
if sys.argv[1]=='pynq':
    from pynq.pl_server.device import Device
    devices=Device.devices
    r['device_count']=len(devices)
    r['device_types']=[type(d).__name__ for d in devices]
print(json.dumps(r))
'''
    try:
        p = subprocess.run([sys.executable, '-c', code, module], capture_output=True,
                           text=True, errors='replace', timeout=timeout)
        records = []
        for line in p.stdout.splitlines():
            try:
                value = json.loads(line)
                if isinstance(value, dict) and value.get('module') == module:
                    records.append(value)
            except ValueError:
                pass
        return {'exit_code': p.returncode, 'status': 'PASS' if p.returncode == 0 and records else 'FAIL',
                'details': records[-1] if records else None, 'stdout': p.stdout, 'stderr': p.stderr}
    except subprocess.TimeoutExpired:
        return {'status': 'UNKNOWN_TIMEOUT', 'exit_code': None, 'details': None}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--modules', default='pynq')
    parser.add_argument('--timeout', type=float, default=20)
    parser.add_argument('--out', type=Path, default=Path('pynq_environment.json'))
    args = parser.parse_args()
    modules = [s.strip() for s in args.modules.split(',') if s.strip()]
    if not modules or args.timeout <= 0:
        parser.error('Provide at least one module and a positive timeout')
    report = {'python': sys.executable, 'platform': platform.platform(),
              'environment': {k: os.environ.get(k) for k in ('VIRTUAL_ENV', 'CONDA_PREFIX', 'XILINX_XRT', 'XILINX_VART_FIRMWARE')},
              'modules': {m: probe(m, args.timeout) for m in modules},
              'overlay_download': 'NOT_RUN', 'hardware_execution': 'NOT_RUN'}
    passed = all(r['status'] == 'PASS' for r in report['modules'].values())
    if 'pynq' in report['modules']:
        passed = passed and (report['modules']['pynq'].get('details') or {}).get('device_count', 0) > 0
    report['preflight'] = 'PASS' if passed else 'FAIL_OR_INCOMPLETE'
    args.out.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding='utf-8')
    print(report['preflight'], str(args.out.resolve()))
    return 0 if passed else 2 if any(r['status'] == 'UNKNOWN_TIMEOUT' for r in report['modules'].values()) else 1


if __name__ == '__main__':
    raise SystemExit(main())

