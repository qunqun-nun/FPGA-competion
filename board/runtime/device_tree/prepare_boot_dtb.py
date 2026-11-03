#!/usr/bin/env python3
"""Prepare a NEW boot DTB using fdtget/fdtput; never install or apply it.

Python 3.8+, standard library. Existing DT properties are compared byte-for-byte
after editing. fdtput only receives a private temporary copy, never the input.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import struct
import subprocess
import sys
import tempfile

REGIONS = [('fengyan_frames', 0x20000000, 0x004B0000),
           ('fengyan_input', 0x21000000, 0x00200000)]


class PrepareError(Exception):
    pass


def cells(raw):
    if len(raw) % 4:
        raise PrepareError('DT property has an invalid cell length')
    return list(struct.unpack('>' + 'I' * (len(raw) // 4), raw))


def encode(*values):
    return struct.pack('>' + 'I' * len(values), *values)


def parse_fdt(data):
    """Read ordinary boot FDT structure and header memreserve entries."""
    if len(data) < 40:
        raise PrepareError('Truncated DTB header')
    h = struct.unpack_from('>10I', data)
    magic, total, off, strings, reserve, version, compatible, cpu, strsize, size = h
    if magic != 0xD00DFEED or not 40 <= total <= len(data):
        raise PrepareError('Invalid DTB magic/totalsize')
    if version < 17 or compatible > 17:
        raise PrepareError('Requires FDT version 17 compatible input')
    if off % 4 or reserve % 8 or not (40 <= off <= off + size <= total) or not (40 <= strings <= strings + strsize <= total):
        raise PrepareError('Invalid DTB block offsets')
    if max(off, strings) < min(off + size, strings + strsize):
        raise PrepareError('Overlapping DTB structure/string blocks')
    reservations, pos = [], reserve
    while True:
        if pos < 40 or pos + 16 > total or any(max(pos, start) < min(pos + 16, end) for start, end in [(off, off + size), (strings, strings + strsize)]):
            raise PrepareError('Invalid/unterminated DTB memreserve block')
        address, length = struct.unpack_from('>QQ', data, pos)
        pos += 16
        if not address and not length:
            break
        if not length or address + length > 1 << 64:
            raise PrepareError('Invalid memreserve address/size')
        reservations.append((address, length))
    tree, stack, pos, root_seen = {}, [], off, False
    limit = off + size
    while pos + 4 <= limit:
        token = struct.unpack_from('>I', data, pos)[0]
        pos += 4
        if token == 1:
            end = data.find(b'\0', pos, limit)
            if end < 0:
                raise PrepareError('Unterminated DT node name')
            try:
                name = data[pos:end].decode('ascii')
            except UnicodeDecodeError:
                raise PrepareError('Non-ASCII DT node name')
            if '/' in name or (not stack and (name or root_seen)) or (stack and not name):
                raise PrepareError('Invalid DT node hierarchy')
            root_seen = True
            stack.append(name)
            path = '/' + '/'.join(stack[1:])
            if path in tree:
                raise PrepareError('Duplicate DT node: ' + path)
            tree[path] = {}
            pos = (end + 4) & ~3
        elif token == 2:
            if not stack:
                raise PrepareError('Unbalanced END_NODE')
            stack.pop()
        elif token == 3:
            if not stack or pos + 8 > limit:
                raise PrepareError('Invalid DT property position')
            length, nameoff = struct.unpack_from('>II', data, pos)
            pos += 8
            end = data.find(b'\0', strings + nameoff, strings + strsize)
            if nameoff >= strsize or end < 0 or pos + length > limit:
                raise PrepareError('Invalid DT property bounds')
            name = data[strings + nameoff:end].decode('ascii')
            props = tree['/' + '/'.join(stack[1:])]
            if name in props:
                raise PrepareError('Duplicate DT property: ' + name)
            props[name] = data[pos:pos + length]
            pos = (pos + length + 3) & ~3
        elif token == 4:
            continue
        elif token == 9:
            if stack or '/' not in tree:
                raise PrepareError('Unbalanced/incomplete DTB')
            if any(n in tree for n in ['/__fixups__', '/__local_fixups__']) or any(n.startswith('/fragment@') for n in tree):
                raise PrepareError('An overlay DTBO is not a complete boot DTB')
            return {'tree': tree, 'memreserve': reservations, 'boot_cpuid': cpu}
        else:
            raise PrepareError('Unknown FDT token: ' + str(token))
    raise PrepareError('Missing FDT END token')


def cell_count(props, key, default):
    values = cells(props.get(key, encode(default)))
    if len(values) != 1 or values[0] not in [1, 2]:
        raise PrepareError(key + ' must contain one cell with value 1 or 2')
    return values[0]


def ranges(raw, ac, sc):
    values = cells(raw)
    if not values or len(values) % (ac + sc):
        raise PrepareError('Empty or malformed reg/alloc-ranges property')
    result = []
    for pos in range(0, len(values), ac + sc):
        chunk = values[pos:pos + ac + sc]
        address = int.from_bytes(encode(*chunk[:ac]), 'big')
        length = int.from_bytes(encode(*chunk[ac:]), 'big')
        if not length or address + length > 1 << (32 * ac):
            raise PrepareError('Invalid/overflowing reserved-memory range')
        result.append((address, length))
    return result


def overlap(a, size, b, length):
    return a < b + length and b < a + size


def enabled(props):
    return props.get('status', b'okay\0') in [b'okay\0', b'ok\0']


def plan_changes(document):
    tree = document['tree']
    root = tree['/']
    ac = cell_count(root, '#address-cells', 2)
    sc = cell_count(root, '#size-cells', 1)
    parent = '/reserved-memory'
    props = tree.get(parent, {})
    if not enabled(props):
        raise PrepareError('/reserved-memory is not enabled')
    if cell_count(props, '#address-cells', ac) != ac or cell_count(props, '#size-cells', sc) != sc:
        raise PrepareError('/reserved-memory cell counts differ from root')
    if props.get('ranges', b''):
        raise PrepareError('Non-empty /reserved-memory ranges cannot be safely merged')
    changes = []
    for name, value in [('#address-cells', encode(ac)), ('#size-cells', encode(sc)), ('ranges', b'')]:
        if name not in props:
            changes.append((parent, name, value))
    fixed = []
    for path, item in tree.items():
        if not path.startswith(parent + '/') or path.count('/') != 2:
            continue
        if 'reg' in item:
            fixed += [(path, a, s, item) for a, s in ranges(item['reg'], ac, sc)]
        elif 'size' in item and enabled(item):
            if 'alloc-ranges' not in item or any(overlap(a, s, b, n) for a, s in ranges(item['alloc-ranges'], ac, sc) for _, b, n in REGIONS):
                raise PrepareError('Dynamic reservation may allocate target memory: ' + path)
        elif enabled(item):
            raise PrepareError('Enabled reservation has neither reg nor size: ' + path)
    for i, (path, a, s, _) in enumerate(fixed):
        for other, b, n, _ in fixed[i + 1:]:
            if overlap(a, s, b, n):
                raise PrepareError('Existing reserved-memory ranges overlap: ' + path + ' and ' + other)
    decisions = []
    for name, address, size in REGIONS:
        if address + size > 1 << (32 * ac) or size >= 1 << (32 * sc):
            raise PrepareError('Target range cannot fit root address/size cells')
        if any(overlap(address, size, a, n) for a, n in document['memreserve']):
            raise PrepareError('Target overlaps header /memreserve/: 0x%x' % address)
        matches = [(p, a, n, item) for p, a, n, item in fixed if overlap(address, size, a, n)]
        if matches:
            path, start, length, item = matches[0]
            if len(matches) != 1 or start > address or start + length < address + size or not enabled(item) or item.get('no-map') != b'' or 'reusable' in item:
                raise PrepareError('Conflicting reservation for 0x%x: %s' % (address, path))
            decisions.append(dict(region=name, address=address, size=size, action='reuse', node=path))
            continue
        path = parent + '/%s@%x' % (name, address)
        if path in tree:
            raise PrepareError('New reservation node name already exists: ' + path)
        reg = address.to_bytes(ac * 4, 'big') + size.to_bytes(sc * 4, 'big')
        changes += [(path, 'reg', reg), (path, 'no-map', b'')]
        decisions.append(dict(region=name, address=address, size=size, action='add', node=path))
    return changes, dict(address_cells=ac, size_cells=sc,
                         root_defaults_used=[k for k in ['#address-cells', '#size-cells'] if k not in root],
                         regions=decisions)


def verify_preservation(before, after, changes):
    expected = {p: dict(v) for p, v in before['tree'].items()}
    for path, name, value in changes:
        expected.setdefault(path, {})[name] = value
    if after['tree'] != expected or after['memreserve'] != before['memreserve'] or after['boot_cpuid'] != before['boot_cpuid']:
        raise PrepareError('Edited DTB changed properties outside the approved additions')
    remaining, _ = plan_changes(after)
    if remaining:
        raise PrepareError('Output still requires reservation changes')


def run_tool(command):
    try:
        result = subprocess.run(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=60)
    except (OSError, subprocess.TimeoutExpired) as e:
        raise PrepareError('Cannot run %s: %s' % (command[0], e))
    if result.returncode:
        raise PrepareError('%s failed (%s): %s' % (command[0], result.returncode, result.stderr.decode(errors='replace').strip()))
    return result.stdout.decode('ascii').strip()


def tool_path(name):
    found = shutil.which(name)
    if not found:
        raise PrepareError('Missing dependency: %s. Install the device-tree-compiler package (fdtget/fdtput); no output generated.' % name)
    return found


def prepare(source, output, fdtget='fdtget', fdtput='fdtput'):
    source = Path(source).resolve(strict=True)
    requested = Path(output).absolute()
    if requested.exists() or requested.is_symlink():
        raise PrepareError('Output already exists; refusing to overwrite: ' + str(requested))
    output = requested.resolve()
    manifest = Path(str(output) + '.manifest.json')
    if output == source or manifest.exists() or manifest.is_symlink():
        raise PrepareError('Input/output collision or existing manifest; choose a fresh output filename')
    if not output.parent.is_dir():
        raise PrepareError('Output directory must already exist: ' + str(output.parent))
    original = source.read_bytes()
    original_hash = hashlib.sha256(original).hexdigest()
    before = parse_fdt(original)
    changes, report = plan_changes(before)
    getter, putter = tool_path(fdtget), tool_path(fdtput)
    with tempfile.TemporaryDirectory(prefix='.prepare-boot-dtb-', dir=str(output.parent)) as directory:
        working = Path(directory) / 'working.dtb'
        working.write_bytes(original)
        for key in ['#address-cells', '#size-cells']:
            if key in before['tree']['/']:
                actual = run_tool([getter, '-t', 'x', str(working), '/', key])
                if [int(v, 16) for v in actual.split()] != cells(before['tree']['/'][key]):
                    raise PrepareError('fdtget disagrees with original DTB parser')
        for path, name, value in changes:
            run_tool([putter, '-p', '-t', 'x', str(working), path, name] + ['%x' % v for v in cells(value)])
        result = working.read_bytes()
        after = parse_fdt(result)
        verify_preservation(before, after, changes)
        for entry in report['regions']:
            path = entry['node']
            if run_tool([getter, '-t', 'x', str(working), path, 'no-map']):
                raise PrepareError('Output no-map property is not empty')
            observed = run_tool([getter, '-t', 'x', str(working), path, 'reg'])
            if [int(v, 16) for v in observed.split()] != cells(after['tree'][path]['reg']):
                raise PrepareError('fdtget disagrees with output DTB parser')
        if source.read_bytes() != original:
            raise PrepareError('Original DTB changed during generation; no output published')
        report.update(input=str(source), input_sha256=original_hash, output=str(output),
                      output_sha256=hashlib.sha256(result).hexdigest(), input_unchanged=True,
                      existing_nodes_and_properties_preserved=True, fdtget=getter, fdtput=putter,
                      installed=False, runtime_overlay_applied=False)
        # Exclusive creation protects existing files, including a concurrent creator.
        created = []
        try:
            with output.open('xb') as stream:
                created.append(output)
                stream.write(result)
            with manifest.open('x', encoding='utf-8') as stream:
                created.append(manifest)
                json.dump(report, stream, ensure_ascii=False, indent=2)
                stream.write('\n')
        except BaseException:
            for file in created:
                file.unlink()
            raise
    return report


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('boot_dtb', type=Path, help='Actual current complete boot DTB; read only')
    ap.add_argument('-o', '--output', type=Path, required=True, help='Fresh DTB filename; never overwritten')
    ap.add_argument('--fdtget', default='fdtget', help='fdtget executable path/name')
    ap.add_argument('--fdtput', default='fdtput', help='fdtput executable path/name')
    args = ap.parse_args()
    try:
        report = prepare(args.boot_dtb, args.output, args.fdtget, args.fdtput)
    except (PrepareError, OSError, ValueError, UnicodeError, struct.error) as e:
        print('ERROR: ' + str(e), file=sys.stderr)
        return 2
    print(json.dumps(report, ensure_ascii=False, indent=2))
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
