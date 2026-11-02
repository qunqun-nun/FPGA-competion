#!/usr/bin/env python3
"""Read-only Linux adaptation inputs. No MMIO, I2C transactions or DT overlays."""
import argparse
import hashlib
import json
from pathlib import Path
import struct

EXPECTED = [(0x20000000, 0x004b0000), (0x21000000, 0x00200000)]


def cells(data):
    if len(data) % 4:
        raise ValueError('Unaligned DT cell data')
    return list(struct.unpack('>' + 'I' * (len(data) // 4), data))


def parse_fdt(data):
    if len(data) < 40:
        raise ValueError('Short FDT header')
    header = struct.unpack('>10I', data[:40])
    magic, total, off_struct, off_strings = header[:4]
    if magic != 0xd00dfeed or total > len(data):
        raise ValueError('Invalid FDT header')
    tree, stack, pos = {}, [], off_struct
    while pos + 4 <= total:
        token = struct.unpack_from('>I', data, pos)[0]
        pos += 4
        if token == 1:
            end = data.index(b'\0', pos)
            stack.append(data[pos:end].decode())
            pos = (end + 4) & ~3
            tree['/' + '/'.join(stack[1:])] = {}
        elif token == 2:
            stack.pop()
        elif token == 3:
            length, offset = struct.unpack_from('>II', data, pos)
            pos += 8
            start = off_strings + offset
            end = data.index(b'\0', start)
            name = data[start:end].decode()
            if pos + length > total:
                raise ValueError('FDT property out of bounds')
            tree['/' + '/'.join(stack[1:])][name] = data[pos:pos + length]
            pos = (pos + length + 3) & ~3
        elif token == 4:
            continue
        elif token == 9:
            return tree
        else:
            raise ValueError('Unexpected FDT token')
    raise ValueError('Missing FDT END')


def reservations(tree):
    parent = tree.get('/reserved-memory', {})
    root = tree.get('/', {})
    ac = cells(parent.get('#address-cells', root.get('#address-cells', b'\0\0\0\2')))[0]
    sc = cells(parent.get('#size-cells', root.get('#size-cells', b'\0\0\0\1')))[0]
    result = []
    for name, props in tree.items():
        if not name.startswith('/reserved-memory/') or name.count('/') != 2:
            continue
        values = cells(props.get('reg', b''))
        for offset in range(0, len(values), ac + sc):
            chunk = values[offset:offset + ac + sc]
            if len(chunk) != ac + sc:
                raise ValueError('Invalid reserved-memory reg')
            addr = int.from_bytes(struct.pack('>' + 'I' * ac, *chunk[:ac]), 'big')
            size = int.from_bytes(struct.pack('>' + 'I' * sc, *chunk[ac:]), 'big')
            result.append(dict(node=name, address=addr, size=size, no_map='no-map' in props,
                               enabled=props.get('status', b'okay\0') in [b'okay\0', b'ok\0'],
                               reusable='reusable' in props))
    return result


def reserved_ok(items):
    return all(any(e['address'] == a and e['size'] == s and e['no_map'] and e['enabled']
                   and not e['reusable'] for e in items) for a, s in EXPECTED)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--output-dir', type=Path, default=Path(__file__).resolve().parent / 'board-inputs')
    ap.add_argument('--dt-root', type=Path, default=Path('/sys/firmware/devicetree/base'))
    ap.add_argument('--boot-fdt', type=Path, default=Path('/sys/firmware/fdt'))
    args = ap.parse_args()
    if not args.dt_root.is_dir():
        ap.error('Live Linux device tree is unavailable')
    tree = {}
    for directory in [args.dt_root] + [f for f in args.dt_root.rglob('*') if f.is_dir()]:
        name = '/' + directory.relative_to(args.dt_root).as_posix().strip('.')
        tree[name] = {f.name: f.read_bytes() for f in directory.iterdir() if f.is_file()}
    report = dict(live_reserved_memory=reservations(tree))
    try:
        blob = args.boot_fdt.read_bytes()
        report['boot_fdt_sha256'] = hashlib.sha256(blob).hexdigest()
        report['boot_reserved_memory'] = reservations(parse_fdt(blob))
        report['boot_reservations_pass'] = reserved_ok(report['boot_reserved_memory'])
    except (OSError, ValueError, struct.error, IndexError) as e:
        report['boot_reservations_pass'] = False
        report['boot_fdt_error'] = str(e)
    report['live_reservations_pass'] = reserved_ok(report['live_reserved_memory'])
    report['device_tree_properties_hex'] = {
        n: {k: v.hex() for k, v in props.items() if k in [
            'compatible', 'status', 'reg', 'interrupts', 'interrupt-parent', 'interrupt-names',
            'clocks', 'clock-names', '#clock-cells', 'clock-frequency', 'phys', 'phy-names',
            '#phy-cells', 'phandle', 'linux,phandle', 'remote-endpoint', 'dmas', 'dma-names',
            'memory-region', 'no-map', '#address-cells', '#size-cells', 'ranges']}
        for n, props in tree.items()}
    report['note'] = 'Collection only; no initialization. Runtime DT reservations alone do not pass boot reservation checks.'
    args.output_dir.mkdir(parents=True, exist_ok=True)
    for name in ['iomem', 'interrupts', 'version', 'cmdline']:
        try:
            (args.output_dir / ('proc-' + name + '.txt')).write_bytes((Path('/proc') / name).read_bytes())
        except OSError as e:
            report['proc_' + name + '_error'] = str(e)
    (args.output_dir / 'adaptation-inputs.json').write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8')
    print(json.dumps({k: report[k] for k in ['boot_reservations_pass', 'live_reservations_pass']}))
    return 0 if report['boot_reservations_pass'] and report['live_reservations_pass'] else 2


if __name__ == '__main__':
    raise SystemExit(main())
