"""Portable offline evidence checks. Python 3.8+, standard library only."""
import argparse
import hashlib
import json
import math
import statistics
import sys
from pathlib import Path


def read(path):
    return json.loads(Path(path).read_text(encoding='utf-8-sig'))


def sha(path):
    h = hashlib.sha256()
    with Path(path).open('rb') as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b''):
            h.update(chunk)
    return h.hexdigest()


def safe(root, name):
    p = Path(name)
    if p.is_absolute() or '..' in p.parts or '\\' in name or ':' in name:
        raise ValueError('Unsafe manifest path: ' + name)
    target = (root / p).resolve()
    if root != target and root not in target.parents:
        raise ValueError('Manifest escapes root: ' + name)
    return target


def manifest(root, output):
    root, output = Path(root).resolve(), Path(output).resolve()
    if not root.is_dir() or output.exists():
        raise ValueError('Root must exist; output must be new')
    files = {}
    for p in sorted(root.rglob('*')):
        if p.is_symlink():
            raise ValueError('Symlink requires explicit packaging decision: ' + str(p))
        if p.is_file() and p.resolve() != output:
            files[p.relative_to(root).as_posix()] = sha(p)
    if not files:
        raise ValueError('Empty package')
    output.write_text(json.dumps({'algorithm': 'sha256', 'files': files}, indent=2), encoding='utf8')
    return {'status': 'PASS', 'files': len(files)}


def verify(root, path):
    root = Path(root).resolve()
    m = read(path)
    if m.get('algorithm') != 'sha256' or not m.get('files'):
        raise ValueError('Expected nonempty sha256 manifest')
    failures = []
    for n, expected in m['files'].items():
        p = safe(root, n)
        if not isinstance(expected, str) or len(expected) != 64 or any(c not in '0123456789abcdef' for c in expected):
            raise ValueError('Invalid hash: ' + n)
        if not p.is_file() or sha(p) != expected:
            failures.append(n)
    return {'status': 'FAIL' if failures else 'PASS', 'checked': len(m['files']), 'failures': failures,
            'note': 'Listed files only; extra files are not certified by this check.'}


def finite(v):
    return type(v) in (int, float) and math.isfinite(v)


def compare(gold, actual, atol, rtol):
    if not finite(atol) or not finite(rtol) or min(atol, rtol) < 0:
        raise ValueError('Tolerances must be finite and nonnegative')
    errors, count, maximum = [], 0, 0.0

    def walk(g, a, path):
        nonlocal count, maximum
        if isinstance(g, list):
            if not isinstance(a, list) or len(g) != len(a):
                raise ValueError('Shape mismatch at ' + path)
            for i, (x, y) in enumerate(zip(g, a)):
                walk(x, y, path + '/' + str(i))
        else:
            if not finite(g) or not finite(a):
                raise ValueError('Nonfinite or nonnumeric value at ' + path)
            count += 1
            err = abs(a - g)
            maximum = max(maximum, err)
            if err > atol + rtol * abs(g):
                errors.append(path)
    walk(gold, actual, '')
    if count == 0:
        raise ValueError('Empty reference')
    return {'status': 'FAIL' if errors else 'PASS', 'values': count, 'mismatches': len(errors),
            'first_mismatches': errors[:20], 'max_abs_error': maximum, 'atol': atol, 'rtol': rtol}


def stats(rows):
    if not rows:
        raise ValueError('No samples')
    boots, prev, measured, start, stages = set(), -1, [], None, None
    for r in rows:
        boots.add(r['boot_id'])
        t = r['accepted_ns']
        if type(t) != int or t <= prev or not r['boot_id'] or type(r['warmup']) != bool:
            raise ValueError('Invalid timestamp/boot/warmup')
        prev = t
        if r['warmup']:
            if measured:
                raise ValueError('Warmup after measurement')
            start = t
            continue
        ds = r['durations_ms']
        if not ds or any(not isinstance(k, str) or not k or not finite(v) or v < 0 for k, v in ds.items()):
            raise ValueError('Invalid duration')
        if stages is None:
            stages = set(ds)
        if set(ds) != stages:
            raise ValueError('Missing/inconsistent stage fields')
        valid, source = r['valid_position'], r['position_source']
        if type(valid) != bool or source not in ('detect', 'track', 'none') or valid != (source != 'none'):
            raise ValueError('Position validity/source mismatch')
        measured.append(r)
    if len(boots) != 1 or start is None or len(measured) < 100:
        raise ValueError('Require single boot, preceding warmup and >=100 measured tasks')
    seconds = (measured[-1]['accepted_ns'] - start) / 1e9
    result = {}
    for stage in sorted(stages):
        values = sorted(r['durations_ms'][stage] for r in measured)
        result[stage] = {'n': len(values), 'mean_ms': statistics.mean(values),
                         'p95_ms': values[math.ceil(.95 * len(values)) - 1]}
    return {'status': 'PASS', 'n': len(measured), 'window_seconds': seconds,
            'detection_service_fps': len(measured) / seconds,
            'observed_position_publication_fps': sum(r['valid_position'] for r in measured) / seconds,
            'stages': result, 'note': 'Not display latency or ground-truth localization success.'}


def limits(m):
    missing, failed = [], []
    digest = m.get('source_report_sha256')
    if not isinstance(digest, str) or len(digest) != 64 or any(c not in '0123456789abcdef' for c in digest):
        missing.append('source_report_sha256')
    if not m.get('tool_version'):
        missing.append('tool_version')
    for key in ('implementation_complete', 'clock_constraints_verified'):
        if type(m.get(key)) != bool:
            missing.append(key)
        elif not m[key]:
            failed.append(key)
    for key in ('wns_ns', 'tns_ns'):
        if not finite(m.get(key)):
            missing.append(key)
        elif m[key] < 0:
            failed.append(key)
    n = m.get('unconstrained_paths')
    if type(n) != int or n < 0:
        missing.append('unconstrained_paths')
    elif n:
        failed.append('unconstrained_paths')
    resources = m.get('resources')
    if not isinstance(resources, dict) or not resources:
        missing.append('resources')
    else:
        for name, r in resources.items():
            vals = [r.get(k) for k in ('used', 'available', 'max_ratio')]
            if any(not finite(v) for v in vals) or vals[0] < 0 or vals[1] <= 0 or not 0 < vals[2] <= 1:
                missing.append(name)
            elif vals[0] / vals[1] > vals[2]:
                failed.append(name)
    return {'status': 'FAIL' if failed else 'BLOCKED' if missing else 'PASS', 'missing': missing, 'failed': failed,
            'note': 'Requires trusted extraction from a hash-identified completed report; not a board functional test.'}


def main():
    p = argparse.ArgumentParser(description=__doc__)
    sub = p.add_subparsers(dest='cmd', required=True)
    for cmd in ('manifest', 'verify'):
        c = sub.add_parser(cmd); c.add_argument('root'); c.add_argument('path')
    c = sub.add_parser('compare'); c.add_argument('gold'); c.add_argument('actual')
    c.add_argument('--atol', type=float, default=0); c.add_argument('--rtol', type=float, default=0)
    c = sub.add_parser('stats'); c.add_argument('input'); c.add_argument('output')
    c = sub.add_parser('limits'); c.add_argument('input')
    a = p.parse_args()
    try:
        if a.cmd == 'manifest': result = manifest(a.root, a.path)
        elif a.cmd == 'verify': result = verify(a.root, a.path)
        elif a.cmd == 'compare': result = compare(read(a.gold), read(a.actual), a.atol, a.rtol)
        elif a.cmd == 'limits': result = limits(read(a.input))
        else:
            if Path(a.output).exists(): raise ValueError('Output must be new')
            rows = [json.loads(l) for l in Path(a.input).read_text(encoding='utf-8-sig').splitlines() if l.strip()]
            result = stats(rows)
            Path(a.output).write_text(json.dumps(result, indent=2), encoding='utf8')
        print(json.dumps(result, ensure_ascii=False, indent=2))
        return {'PASS': 0, 'FAIL': 1, 'BLOCKED': 2}[result['status']]
    except (ValueError, KeyError, TypeError, OSError) as exc:
        print(json.dumps({'status': 'BLOCKED', 'reason': str(exc)}, ensure_ascii=False))
        return 2


if __name__ == '__main__':
    sys.exit(main())
