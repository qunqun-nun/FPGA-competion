"""Verify packaged upstream bytes and static facts; never executes board code."""
import ast
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import shutil
import struct
import subprocess
import sys
import tarfile

p = Path(__file__).resolve().parent
subprocess.run([sys.executable, str(p / 'audit_v016.py')], check=True)
provenance = json.loads((p / 'provenance.json').read_text(encoding='utf-8'))
raw = (p / 'hdmi-modules-2022.2.tar.gz').read_bytes()
assert hashlib.sha256(raw).hexdigest() == provenance['archive_sha256']
count = 0
with tarfile.open(p / 'hdmi-modules-2022.2.tar.gz') as archive:
    for entry in archive.getmembers():
        if not entry.isfile():
            continue
        parts = PurePosixPath(entry.name).parts
        assert parts[0].endswith(provenance['source_commit'])
        target = p / 'official-2022.2' / Path(*parts[1:])
        target.resolve().relative_to(p.resolve())
        assert archive.extractfile(entry).read() == target.read_bytes(), str(target)
        count += 1
for f in p.glob('*.py'):
    ast.parse(f.read_text(encoding='utf-8'), filename=str(f))
for f in p.glob('*.sh'):
    raw = f.read_bytes()
    assert raw.startswith(b'#!/bin/sh\n') and b'\r' not in raw, str(f)
facts = json.loads((p / 'hardware-audit.json').read_text(encoding='utf-8'))
dts = (p / 'v016-hdmi-audited.dtsi').read_text(encoding='utf-8')
assert dts.count('status = "disabled";') == 3
for value in ['0x82000000', '0x82020000', '0x82030000', '<0 91 4>', '<0 92 4>', '<0 93 4>']:
    assert value in dts, value
assert '"xlnx,v-hdmi-tx-ss-3.1"' in dts
assert facts['gic'] == dict(tx_spi=91, phy_spi=92, iic_spi=93, tx_hwirq=123, phy_hwirq=124, iic_hwirq=125)
# Exercise the boot FDT parser with both mandatory regions and a missing-no-map
# negative case. This is a synthetic parser test, not a board reservation claim.
namespace = {'__name__': 'collector_validation'}
collector = p / 'collect-linux-inputs.py'
exec(compile(collector.read_text(encoding='utf-8'), str(collector), 'exec'), namespace)
u32 = lambda *v: struct.pack('>' + 'I' * len(v), *v)
align = lambda b: b + b'\0' * (-len(b) % 4)
strings = b'#address-cells\0#size-cells\0reg\0no-map\0'
offsets = {name: strings.index(name.encode() + b'\0') for name in ['#address-cells', '#size-cells', 'reg', 'no-map']}
prop = lambda name, value: u32(3, len(value), offsets[name]) + align(value)
node = lambda name, content: u32(1) + align(name.encode() + b'\0') + content + u32(2)
children = b''
for address, size in namespace['EXPECTED']:
    children += node('buffer@%x' % address, prop('reg', u32(0, address, 0, size)) + prop('no-map', b''))
structure = node('', prop('#address-cells', u32(2)) + prop('#size-cells', u32(2)) +
                 node('reserved-memory', prop('#address-cells', u32(2)) + prop('#size-cells', u32(2)) + children)) + u32(9)
blob = u32(0xd00dfeed, 56 + len(structure) + len(strings), 56, 56 + len(structure), 40, 17, 16, 0,
           len(strings), len(structure)) + b'\0' * 16 + structure + strings
parsed = namespace['parse_fdt'](blob)
assert namespace['reserved_ok'](namespace['reservations'](parsed))
del parsed['/reserved-memory/buffer@21000000']['no-map']
assert not namespace['reserved_ok'](namespace['reservations'](parsed))
try:
    namespace['parse_fdt'](blob[:39])
except ValueError:
    pass
else:
    raise AssertionError('Truncated boot FDT accepted')
shell = os.environ.get('HDMI_VERIFY_SH') or shutil.which('sh')
shell_result = 'NOT_RUN: set HDMI_VERIFY_SH or provide sh in PATH'
if shell:
    logs = []
    for f in sorted(p.glob('*.sh')):
        run = subprocess.run([shell, '-n', str(f)], stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        assert run.returncode == 0, run.stdout
        logs.append(f'{f.name}: syntax PASS\n'.encode())
    fixture = p / 'validation-empty-sysfs'
    fixture.mkdir(exist_ok=True)
    env = dict(os.environ, HDMI_SYSFS=fixture.as_posix())
    run = subprocess.run([shell, str(p / 'linux-preflight.sh')], env=env,
                         stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    assert run.returncode == 2 and b'INCOMPLETE:' in run.stdout, run.stdout
    logs.append(b'Empty sysfs negative smoke: exit 2 PASS\n' + run.stdout)
    for name in ['build-linux-modules.sh', 'validate-dts.sh']:
        env = dict(os.environ)
        for key in ['KERNEL_SRC', 'KERNEL_OUT', 'CROSS_COMPILE']:
            env.pop(key, None)
        run = subprocess.run([shell, str(p / name)], env=env,
                             stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        assert run.returncode != 0, name
        logs.append((name + ': rejects missing inputs PASS\n').encode() + run.stdout)
    (p / 'shell-validation.log').write_bytes(b'\n'.join(logs))
    shell_result = 'PASS: sh -n, empty-sysfs exit 2, build/DTS missing-input rejection; host shell only'
result = dict(
    static_audit='PASS', upstream_archive_and_extracted_files='PASS', official_file_count=count,
    python_syntax='PASS', shell_lf_and_shebang='PASS', dts_address_irq_disabled_checks='PASS',
    boot_fdt_parser='PASS: two 64-bit ranges; missing no-map and truncated blob rejected (synthetic)',
    shell_execution=shell_result, full_dts_compile='NOT_RUN: no full target DTS/DTB supplied',
    kernel_module_build='NOT_RUN: target kernel build/SDK not supplied',
    board_initialization='NOT_RUN: no board session',
    complete_hdmi_linux_initializer='NOT_IMPLEMENTED: existing IDT provider needs board integration/verification; custom DRM source missing')
(p / 'verification.json').write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
manifest = {str(f.relative_to(p)).replace('\\', '/'): hashlib.sha256(f.read_bytes()).hexdigest()
            for f in sorted(p.rglob('*')) if f.is_file() and f.name != 'SHA256SUMS.json' and '__pycache__' not in f.parts}
(p / 'SHA256SUMS.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
print(json.dumps(result, ensure_ascii=False))
