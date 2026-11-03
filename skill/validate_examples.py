"""Validate meaningful successful/failing CLI paths using temporary fixtures."""
import ast
import csv
import hashlib
import json
import platform
import re
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent


def main():
    results = []

    def run(name, script, args, expected):
        p = subprocess.run([sys.executable, str(ROOT / script)] + list(map(str, args)),
                           capture_output=True, text=True, errors='replace', timeout=90)
        results.append({'case': name, 'expected_exit': expected, 'actual_exit': p.returncode,
                        'status': 'PASS' if p.returncode == expected else 'FAIL'})
        if p.returncode != expected:
            print(name, p.stdout, p.stderr)

    for path in ROOT.rglob('*.py'):
        ast.parse(path.read_text(encoding='utf-8'))
    broken = []
    for path in ROOT.rglob('*.md'):
        for link in re.findall(r'\]\(([^)]+)\)', path.read_text(encoding='utf-8')):
            if '://' not in link and not link.startswith('#') and not (path.parent / link.split('#')[0]).exists():
                broken.append(str(path.relative_to(ROOT)) + ':' + link)
    results.append({'case': 'python_syntax_and_relative_document_links', 'status': 'FAIL' if broken else 'PASS', 'broken_links': broken})

    with tempfile.TemporaryDirectory(prefix='reusable_skill_') as temp:
        t = Path(temp)
        (t / 'a.bin').write_bytes(b'golden-reference')
        manifest = t / 'hashes.json'
        manifest.write_text(json.dumps({'a.bin': hashlib.sha256(b'golden-reference').hexdigest()}))
        script = 'pynq-artifact-audit/scripts/verify_manifest.py'
        args = ['--root', t, '--manifest', manifest]
        run('manifest_valid', script, args, 0)
        (t / 'a.bin').write_bytes(b'changed')
        run('manifest_tamper_detected', script, args, 1)
        (t / 'a.bin').unlink()
        run('manifest_missing_detected', script, args, 1)
        manifest.write_text(json.dumps({'../outside': '0' * 64}))
        run('manifest_escape_rejected', script, args, 2)
        manifest.write_text('{}')
        run('manifest_empty_rejected', script, args, 2)

        for name in ('a', 'b', 'c'):
            (t / name).write_bytes(name.encode())
        samples = t / 'samples.csv'

        def samples_write(groups):
            with samples.open('w', newline='') as stream:
                writer = csv.writer(stream)
                writer.writerow(['path', 'split', 'group'])
                writer.writerows(zip(('a', 'b', 'c'), ('train', 'valid', 'test'), groups))

        script = 'video-group-audit/scripts/audit_groups.py'
        args = ['--root', t, '--manifest', samples, '--out', t / 'audit.json']
        samples_write(('video-a', 'video-b', 'video-c'))
        run('groups_disjoint', script, args, 0)
        samples_write(('video-a', 'video-a', 'video-c'))
        run('source_overlap_detected', script, args, 1)
        samples_write(('video-a', 'video-b', 'video-c'))
        (t / 'c').write_bytes(b'a')
        run('exact_cross_split_duplicate_detected', script, args, 1)

        script = 'vitis-ptq-review/scripts/compare_map.py'
        run('real_quant_metrics_pass_3pp', script, ['--input', ROOT / 'evidence/latest_case.json', '--max-drop-pp', 3], 0)
        run('real_quant_metrics_fail_1pp', script, ['--input', ROOT / 'evidence/latest_case.json', '--max-drop-pp', 1], 1)
        invalid = t / 'invalid.json'
        data = json.loads((ROOT / 'evidence/latest_case.json').read_text(encoding='utf-8'))
        data['int8_cpu']['metrics/mAP50(B)'] = float('nan')
        invalid.write_text(json.dumps(data))
        run('nonfinite_metrics_rejected', script, ['--input', invalid, '--max-drop-pp', 3], 2)
        script = 'pynq-environment/scripts/probe_environment.py'
        run('environment_stdlib_import', script, ['--modules', 'json', '--out', t / 'env.json'], 0)
        run('environment_missing_module_recorded', script, ['--modules', '__skill_package_missing_module__', '--out', t / 'env.json'], 1)

    report = {'python_version': platform.python_version(), 'platform': platform.system(),
              'validation_scope': 'PC CLI fixtures, document links and packaged real metric example; no board revalidation',
              'status': 'PASS' if all(r['status'] == 'PASS' for r in results) else 'FAIL', 'cases': results}
    (ROOT / 'validation_results.json').write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding='utf-8')
    print(report['status'], len(results), 'cases')
    return 0 if report['status'] == 'PASS' else 1


if __name__ == '__main__':
    raise SystemExit(main())
