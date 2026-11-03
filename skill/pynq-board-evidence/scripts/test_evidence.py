"""Synthetic fixtures verify tools, not FPGA/model accuracy."""
import copy
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
import evidence as e


class EvidenceTests(unittest.TestCase):
    def test_manifest_changed_missing(self):
        with tempfile.TemporaryDirectory() as d:
            r = Path(d) / 'pkg'; r.mkdir(); p = r / 'a'; p.write_text('one')
            m = Path(d) / 'manifest.json'
            e.manifest(r, m)
            self.assertEqual(e.verify(r, m)['status'], 'PASS')
            p.write_text('two'); self.assertEqual(e.verify(r, m)['status'], 'FAIL')
            p.unlink(); self.assertEqual(e.verify(r, m)['status'], 'FAIL')

    def test_manifest_escape(self):
        with tempfile.TemporaryDirectory() as d:
            for n in ('../secret', '/absolute', 'C:/secret', 'a\\secret'):
                with self.assertRaises(ValueError): e.safe(Path(d).resolve(), n)

    def test_gold(self):
        self.assertEqual(e.compare([[1, 2]], [[1.001, 2]], .002, 0)['status'], 'PASS')
        self.assertEqual(e.compare([1], [2], 0, 0)['status'], 'FAIL')
        for g, a in (([1], [[1]]), ([1], [float('nan')]), ([], [])):
            with self.assertRaises(ValueError): e.compare(g, a, 0, 0)

    def rows(self):
        return [dict(boot_id='a', accepted_ns=i * 1000000000, warmup=(i == 0),
                     durations_ms={'dpu': i}, valid_position=(i % 2 == 1),
                     position_source='detect' if i % 2 == 1 else 'none') for i in range(101)]

    def test_stats_p95_window(self):
        s = e.stats(self.rows())
        self.assertEqual(s['stages']['dpu'], {'n': 100, 'mean_ms': 50.5, 'p95_ms': 95})
        self.assertEqual(s['detection_service_fps'], 1)
        self.assertEqual(s['observed_position_publication_fps'], .5)

    def test_stats_reject_invalid(self):
        for kind in ('boot', 'time', 'negative', 'missing', 'source', 'warmup'):
            rows = self.rows()
            if kind == 'boot': rows[-1]['boot_id'] = 'b'
            if kind == 'time': rows[-1]['accepted_ns'] = 0
            if kind == 'negative': rows[-1]['durations_ms']['dpu'] = -1
            if kind == 'missing': rows[-1]['durations_ms'] = {'other': 1}
            if kind == 'source': rows[-1]['position_source'] = 'track'
            if kind == 'warmup': rows[-1]['warmup'] = True
            with self.assertRaises(ValueError): e.stats(rows)
        with self.assertRaises(ValueError): e.stats(self.rows()[:99])

    def test_limits(self):
        m = dict(source_report_sha256='a' * 64, tool_version='fixture', implementation_complete=True,
                 clock_constraints_verified=True, wns_ns=0, tns_ns=0, unconstrained_paths=0,
                 resources={'LUT': dict(used=5, available=10, max_ratio=.9)})
        self.assertEqual(e.limits(m)['status'], 'PASS')
        for key, val in (('wns_ns', -1), ('unconstrained_paths', 1)):
            n = dict(m); n[key] = val; self.assertEqual(e.limits(n)['status'], 'FAIL')
        n = copy.deepcopy(m); n['resources']['LUT']['used'] = 10
        self.assertEqual(e.limits(n)['status'], 'FAIL')
        del m['wns_ns']; self.assertEqual(e.limits(m)['status'], 'BLOCKED')

    def test_true_exitcode(self):
        with tempfile.TemporaryDirectory() as d:
            out = Path(d) / 'run'
            rc = subprocess.run([sys.executable, str(Path(__file__).with_name('run_logged.py')), str(out), '--',
                                 sys.executable, '-c', 'import sys;print("out");print("err",file=sys.stderr);sys.exit(7)']).returncode
            self.assertEqual(rc, 7)
            self.assertEqual(e.read(out / 'command.json')['exitcode'], 7)
            self.assertIn('err', (out / 'stderr.log').read_text())


if __name__ == '__main__': unittest.main()
