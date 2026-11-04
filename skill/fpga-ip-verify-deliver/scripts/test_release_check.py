import copy
import json
import tempfile
import unittest
import zipfile
from pathlib import Path
import release_check as release


class DeliveryTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name) / 'delivery'; self.root.mkdir()
        self.manifest = self.root / 'release_manifest.json'
        self.data = {'profile': 'pynq_xrt', 'stage': 'board_retest', 'build_id': 'SYNTHETIC-NO-HARDWARE',
                     'features': {key: False for key in release.FEATURE_ROLES}, 'files': [],
                     'verification': {key: {'status': 'PASS', 'evidence': ['simulation_log.txt']}
                                      for key in release.GATES}}
        self.data['verification']['board'] = {'status': 'NOT_RUN', 'reason': 'Fixture, no board'}
        for role in sorted(release.BASE_ROLES | {'xclbin'}):
            if role == 'build_record':
                continue
            name = 'hardware/system.' + role if role in release.HARDWARE else role + '.txt'
            self.add(role, name)
        record = {'build_id': self.data['build_id'], 'tools': {'tool': 'SYNTHETIC'},
                  'target_part': 'SYNTHETIC', 'source_revision': 'SYNTHETIC',
                  'commands_log': 'simulation_log.txt',
                  'artifacts': {item['role']: {'path': item['path'], 'sha256': item['sha256']}
                                for item in self.data['files'] if item['role'] in release.HARDWARE}}
        self.add('build_record', 'build_record.json', json.dumps(record))
        self.save()

    def add(self, role, name, content='SYNTHETIC TEXT, NOT A REAL FPGA ARTIFACT'):
        path = self.root / name; path.parent.mkdir(parents=True, exist_ok=True); path.write_text(content)
        item = {'role': role, 'path': name, 'sha256': release.sha256(path)}
        if role in release.HARDWARE:
            item['build_id'] = self.data['build_id']
        self.data['files'].append(item)

    def save(self):
        self.manifest.write_text(json.dumps(self.data))

    def result(self):
        self.save()
        return release.audit(self.root, self.manifest)

    def test_complete_retest(self):
        self.assertEqual(self.result()['status'], 'PASS')

    def test_each_required_role(self):
        original = copy.deepcopy(self.data)
        for role in release.BASE_ROLES | {'xclbin'}:
            with self.subTest(role=role):
                self.data = copy.deepcopy(original)
                self.data['files'] = [item for item in self.data['files'] if item['role'] != role]
                self.assertEqual(self.result()['status'], 'BLOCKED')

    def test_tampered_file(self):
        (self.root / self.data['files'][0]['path']).write_text('changed')
        self.assertEqual(self.result()['status'], 'FAIL')

    def test_missing_file(self):
        (self.root / self.data['files'][0]['path']).unlink()
        self.assertEqual(self.result()['status'], 'BLOCKED')

    def test_build_mismatch(self):
        next(item for item in self.data['files'] if item['role'] == 'bit')['build_id'] = 'OLD'
        self.assertEqual(self.result()['status'], 'FAIL')

    def test_build_artifact_mismatch(self):
        path = self.root / 'build_record.json'; record = release.read(path)
        record['artifacts']['bit']['sha256'] = '0' * 64
        path.write_text(json.dumps(record))
        next(item for item in self.data['files'] if item['role'] == 'build_record')['sha256'] = release.sha256(path)
        self.assertEqual(self.result()['status'], 'FAIL')

    def test_acceptance_requires_board(self):
        self.data['stage'] = 'accepted'; self.assertEqual(self.result()['status'], 'BLOCKED')
        self.data['verification']['board'] = {'status': 'PASS', 'evidence': ['simulation_log.txt']}
        self.assertEqual(self.result()['status'], 'PASS')

    def test_failed_gate(self):
        self.data['verification']['board'] = {'status': 'FAIL', 'reason': 'deliberate fixture failure'}
        self.assertEqual(self.result()['status'], 'FAIL')

    def test_missing_gate_evidence(self):
        self.data['verification']['module_simulation']['evidence'] = ['missing.log']
        self.assertEqual(self.result()['status'], 'BLOCKED')

    def test_unknown_feature(self):
        del self.data['features']['hdmi']
        with self.assertRaises(ValueError): self.result()

    def test_all_feature_requirements(self):
        for feature, roles in release.FEATURE_ROLES.items():
            self.data['features'][feature] = True
            self.assertEqual(self.result()['status'], 'BLOCKED')
            for role in roles:
                self.add(role, role + '.txt')
            self.assertEqual(self.result()['status'], 'PASS')

    def test_pynq_without_xclbin(self):
        self.data['profile'] = 'pynq'
        self.data['files'] = [item for item in self.data['files'] if item['role'] != 'xclbin']
        self.assertEqual(self.result()['status'], 'PASS')

    def test_duplicate_file(self):
        self.data['files'].append(copy.deepcopy(self.data['files'][0]))
        with self.assertRaises(ValueError): self.result()

    def test_duplicate_hardware_role(self):
        self.add('bit', 'hardware/old.bit')
        self.assertEqual(self.result()['status'], 'FAIL')

    def test_unsafe_paths(self):
        for name in ('../secret', '/secret', 'C:/secret', 'a\\b', '.', '//server/file'):
            with self.subTest(name=name), self.assertRaises(ValueError): release.relative_file(self.root, name)

    def test_reserved_manifest_path(self):
        self.data['files'][0]['path'] = 'release_manifest.json'
        with self.assertRaises(ValueError): self.result()

    def test_exact_pack(self):
        (self.root / 'unlisted.txt').write_text('not a dependency')
        output = self.root.parent / 'package.zip'
        result = release.pack(self.root, self.manifest, output)
        self.assertEqual(result['status'], 'PASS')
        with zipfile.ZipFile(output) as archive:
            self.assertNotIn('unlisted.txt', archive.namelist())
            self.assertIsNone(archive.testzip())
            new_root = self.root.parent / 'relocated'; archive.extractall(new_root)
        self.assertEqual(release.audit(new_root, new_root / 'release_manifest.json')['status'], 'PASS')

    def test_no_overwrite(self):
        output = self.root.parent / 'package.zip'; output.write_text('old')
        with self.assertRaises(ValueError): release.pack(self.root, self.manifest, output)
        self.assertEqual(output.read_text(), 'old')

    def test_failed_pack_no_output(self):
        self.data['verification']['timing'] = {'status': 'NOT_RUN', 'reason': 'not built'}; self.save()
        output = self.root.parent / 'package.zip'
        self.assertEqual(release.pack(self.root, self.manifest, output)['status'], 'BLOCKED')
        self.assertFalse(output.exists())

    def test_pack_outside_root(self):
        with self.assertRaises(ValueError): release.pack(self.root, self.manifest, self.root / 'package.zip')


if __name__ == '__main__':
    unittest.main(verbosity=2)
