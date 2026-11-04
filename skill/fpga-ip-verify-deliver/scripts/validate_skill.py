import argparse
import ast
import datetime
import json
import re
import subprocess
import sys
from pathlib import Path
from urllib.parse import unquote


ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=False)
    checks = []
    syntax = []
    for path in ROOT.rglob('*.py'):
        try:
            ast.parse(path.read_text(encoding='utf-8-sig'))
        except SyntaxError as error:
            syntax.append(str(error))
    checks.append({'name': 'syntax', 'status': 'FAIL' if syntax else 'PASS', 'errors': syntax})
    content = (ROOT / 'SKILL.md').read_text(encoding='utf-8')
    front = re.match(r'^---\nname: ([a-z0-9-]{1,64})\ndescription: (.+)\n---', content)
    checks.append({'name': 'frontmatter', 'status': 'PASS' if front else 'FAIL'})
    broken = []
    for path in ROOT.rglob('*.md'):
        for target in re.findall(r'\]\(([^)]+)\)', path.read_text(encoding='utf-8')):
            if '://' in target or target.startswith('#'):
                continue
            if not (path.parent / unquote(target.split('#')[0])).exists():
                broken.append({'file': path.relative_to(ROOT).as_posix(), 'target': target})
    checks.append({'name': 'local_links', 'status': 'FAIL' if broken else 'PASS', 'broken': broken})
    commands = [
        ('unit_tests', [ROOT / 'scripts/test_release_check.py'], 0),
        ('cli_help', [ROOT / 'scripts/release_check.py', '--help'], 0),
        ('empty_manifest_blocked', [ROOT / 'scripts/release_check.py', 'audit', ROOT,
                                    ROOT / 'assets/release_manifest.template.json'], 2),
    ]
    for name, argv, expected in commands:
        argv = [sys.executable, '-B'] + [str(value) for value in argv]
        result = subprocess.run(argv, capture_output=True)
        (args.output / (name + '.stdout.log')).write_bytes(result.stdout)
        (args.output / (name + '.stderr.log')).write_bytes(result.stderr)
        checks.append({'name': name, 'argv': argv, 'exit_code': result.returncode,
                       'expected_exit': expected, 'status': 'PASS' if result.returncode == expected else 'FAIL'})
    report = {'status': 'PASS' if all(item['status'] == 'PASS' for item in checks) else 'FAIL',
              'date_utc': datetime.datetime.now(datetime.timezone.utc).isoformat(), 'python': sys.version,
              'scope': 'offline_skill_structure_and_synthetic_delivery_fixtures', 'checks': checks,
              'not_run': ['user_rtl_simulation', 'hardware_build', 'board_validation', 'fresh_agent_behavior_trials']}
    (args.output / 'results.json').write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding='utf-8')
    print(json.dumps({'status': report['status'], 'checks': len(checks), 'output': str(args.output)}, ensure_ascii=False))
    return 0 if report['status'] == 'PASS' else 1


if __name__ == '__main__':
    sys.exit(main())
