"""Verify a relative-path -> SHA-256 JSON manifest; file identity only."""
import argparse
import hashlib
import json
import re
from pathlib import Path, PureWindowsPath


def sha256(path):
    digest = hashlib.sha256()
    with path.open('rb') as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b''):
            digest.update(block)
    return digest.hexdigest()


def verify(root, manifest):
    root = Path(root).resolve()
    mapping = json.loads(Path(manifest).read_text(encoding='utf-8-sig'))
    if not isinstance(mapping, dict) or not mapping:
        raise ValueError('Expected non-empty relative-path -> SHA-256 mapping')
    results = []
    for name, expected in mapping.items():
        path = (root / name).resolve()
        try:
            path.relative_to(root)
            inside = True
        except ValueError:
            inside = False
        if Path(name).is_absolute() or PureWindowsPath(name).drive or not inside:
            raise ValueError('Path escapes package: ' + name)
        if not isinstance(expected, str) or not re.fullmatch('[a-fA-F0-9]{64}', expected):
            raise ValueError('Invalid SHA-256: ' + name)
        actual = sha256(path) if path.is_file() else None
        results.append({'file': name, 'expected': expected.lower(), 'actual': actual,
                        'status': 'PASS' if actual == expected.lower() else 'FAIL'})
    return {'scope': 'manifest file identity only', 'files': results,
            'status': 'PASS' if all(r['status'] == 'PASS' for r in results) else 'FAIL',
            'runtime_compatibility': 'NOT_TESTED'}


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--root', type=Path, required=True)
    p.add_argument('--manifest', type=Path, required=True)
    p.add_argument('--out', type=Path)
    args = p.parse_args()
    try:
        result = verify(args.root, args.manifest)
    except (OSError, ValueError, TypeError) as exc:
        print('ERROR:', exc)
        return 2
    data = json.dumps(result, ensure_ascii=False, indent=2)
    if args.out:
        args.out.write_text(data, encoding='utf-8')
    print(data)
    return 0 if result['status'] == 'PASS' else 1


if __name__ == '__main__':
    raise SystemExit(main())

