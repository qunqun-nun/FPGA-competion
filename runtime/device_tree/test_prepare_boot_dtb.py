import copy
import hashlib
import importlib.util
import json
from pathlib import Path
import shutil
import struct
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('prepare', Path(__file__).with_name('prepare_boot_dtb.py'))
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)


def fixture(tree, memreserve=()):
    names = sorted({key for props in tree.values() for key in props})
    strings = b''
    offsets = {}
    for name in names:
        offsets[name] = len(strings)
        strings += name.encode() + b'\0'
    align = lambda data: data + b'\0' * (-len(data) % 4)

    def node(path):
        result = m.encode(1) + align((path.rsplit('/', 1)[-1] if path != '/' else '').encode() + b'\0')
        for key, data in tree[path].items():
            result += m.encode(3, len(data), offsets[key]) + align(data)
        for child in tree:
            if child != '/' and child.rsplit('/', 1)[0] == path.rstrip('/'):
                result += node(child)
        return result + m.encode(2)

    structure = node('/') + m.encode(9)
    reserve = b''.join(struct.pack('>QQ', *item) for item in memreserve) + b'\0' * 16
    start = 40 + len(reserve)
    return m.encode(0xd00dfeed, start + len(structure) + len(strings), start,
                    start + len(structure), 40, 17, 16, 0, len(strings), len(structure)) + reserve + structure + strings


def base(ac=2, sc=2):
    return {'/': {'#address-cells': m.encode(ac), '#size-cells': m.encode(sc), 'compatible': b'xlnx,zcu104\0'},
            '/soc': {'compatible': b'simple-bus\0', 'ranges': b''},
            '/soc/hdmi@82000000': {'reg': b'unchanged-opaque-data', 'interrupts': m.encode(0, 91, 4)}}


def reserve(tree, address=0x20000000, size=0x4b0000, **properties):
    ac = m.cells(tree['/']['#address-cells'])[0]
    sc = m.cells(tree['/']['#size-cells'])[0]
    tree.setdefault('/reserved-memory', {'#address-cells': m.encode(ac), '#size-cells': m.encode(sc), 'ranges': b''})
    tree['/reserved-memory/old@%x' % address] = {'reg': address.to_bytes(ac * 4, 'big') + size.to_bytes(sc * 4, 'big'),
                                              'no-map': b'', **properties}


class BootDtbTests(unittest.TestCase):
    def test_32_and_64bit_additions_preserve_hardware(self):
        for ac, sc in [(1, 1), (2, 1), (2, 2)]:
            original = m.parse_fdt(fixture(base(ac, sc)))
            edits, report = m.plan_changes(original)
            after = copy.deepcopy(original)
            for path, name, value in edits:
                after['tree'].setdefault(path, {})[name] = value
            m.verify_preservation(original, m.parse_fdt(fixture(after['tree'])), edits)
            self.assertEqual([r['action'] for r in report['regions']], ['add', 'add'])

    def test_larger_existing_region_reused_for_both(self):
        tree = base()
        reserve(tree, size=0x1200000)
        edits, report = m.plan_changes(m.parse_fdt(fixture(tree)))
        self.assertEqual(edits, [])
        self.assertEqual([r['action'] for r in report['regions']], ['reuse', 'reuse'])

    def test_partial_disabled_reusable_missing_nomap_conflicts(self):
        for props in [{'status': b'disabled\0'}, {'reusable': b''}, {'no-map': b'bad'}, {'no-map': None}]:
            tree = base()
            reserve(tree, **props)
            if props.get('no-map', 1) is None:
                del tree['/reserved-memory/old@20000000']['no-map']
            with self.assertRaises(m.PrepareError):
                m.plan_changes(m.parse_fdt(fixture(tree)))
        tree = base()
        reserve(tree, size=0x1000)
        with self.assertRaises(m.PrepareError):
            m.plan_changes(m.parse_fdt(fixture(tree)))

    def test_existing_overlap_and_dynamic_and_memreserve_rejected(self):
        tree = base()
        reserve(tree)
        reserve(tree, address=0x20001000, size=0x1000)
        with self.assertRaises(m.PrepareError):
            m.plan_changes(m.parse_fdt(fixture(tree)))
        tree = base()
        reserve(tree, address=0x30000000)
        tree['/reserved-memory/dynamic'] = {'size': m.encode(0, 0x1000)}
        with self.assertRaises(m.PrepareError):
            m.plan_changes(m.parse_fdt(fixture(tree)))
        with self.assertRaises(m.PrepareError):
            m.plan_changes(m.parse_fdt(fixture(base(), [(0x20000000, 4096)])))

    def test_bad_ranges_cells_overlay_and_truncation(self):
        for change in [lambda t: t.update({'/__fixups__': {}}),
                       lambda t: t.update({'/reserved-memory': {'ranges': m.encode(1)}}),
                       lambda t: t.update({'/reserved-memory': {'#address-cells': m.encode(1)}})]:
            tree = base()
            change(tree)
            with self.assertRaises(m.PrepareError):
                m.plan_changes(m.parse_fdt(fixture(tree)))
        with self.assertRaises(m.PrepareError):
            m.parse_fdt(fixture(base())[:-1])

    def test_unrelated_hardware_modification_rejected(self):
        original = m.parse_fdt(fixture(base()))
        edits, _ = m.plan_changes(original)
        after = copy.deepcopy(original)
        for path, name, value in edits:
            after['tree'].setdefault(path, {})[name] = value
        after['tree']['/soc/hdmi@82000000']['interrupts'] = m.encode(0, 90, 4)
        with self.assertRaises(m.PrepareError):
            m.verify_preservation(original, after, edits)

    def test_missing_tools_and_existing_output_leave_source_unchanged(self):
        with tempfile.TemporaryDirectory() as directory:
            source, output = Path(directory) / 'boot.dtb', Path(directory) / 'new.dtb'
            source.write_bytes(fixture(base()))
            original = source.read_bytes()
            with self.assertRaises(m.PrepareError):
                m.prepare(source, output, 'nonexistent-fengyan-fdtget', 'nonexistent-fengyan-fdtput')
            self.assertFalse(output.exists())
            output.write_bytes(b'existing boot file')
            with self.assertRaises(m.PrepareError):
                m.prepare(source, output)
            self.assertEqual(output.read_bytes(), b'existing boot file')
            self.assertEqual(source.read_bytes(), original)

    def test_full_orchestration_with_fixture_tool_backend(self):
        # Test double, not evidence of actual libfdt execution.
        def run(command):
            if command[0] == 'fixture-get':
                doc = m.parse_fdt(Path(command[3]).read_bytes())
                return ' '.join('%x' % v for v in m.cells(doc['tree'][command[4]][command[5]]))
            file, path, name = Path(command[4]), command[5], command[6]
            doc = m.parse_fdt(file.read_bytes())
            doc['tree'].setdefault(path, {})[name] = m.encode(*(int(v, 16) for v in command[7:]))
            file.write_bytes(fixture(doc['tree'], doc['memreserve']))
            return ''
        with tempfile.TemporaryDirectory() as directory:
            source, output = Path(directory) / 'boot.dtb', Path(directory) / 'new.dtb'
            source.write_bytes(fixture(base()))
            before = hashlib.sha256(source.read_bytes()).hexdigest()
            with patch.object(m, 'tool_path', side_effect=lambda name: name), patch.object(m, 'run_tool', side_effect=run):
                report = m.prepare(source, output, 'fixture-get', 'fixture-put')
            self.assertEqual(before, hashlib.sha256(source.read_bytes()).hexdigest())
            self.assertEqual(report['output_sha256'], hashlib.sha256(output.read_bytes()).hexdigest())
            self.assertEqual(json.loads(Path(str(output) + '.manifest.json').read_text())['input_sha256'], before)

    @unittest.skipUnless(shutil.which('fdtget') and shutil.which('fdtput'), 'actual fdtget/fdtput unavailable')
    def test_actual_libfdt_tools(self):
        with tempfile.TemporaryDirectory() as directory:
            source, output = Path(directory) / 'boot.dtb', Path(directory) / 'new.dtb'
            source.write_bytes(fixture(base()))
            m.prepare(source, output)
            self.assertEqual(m.plan_changes(m.parse_fdt(output.read_bytes()))[0], [])


if __name__ == '__main__':
    unittest.main(verbosity=2)
