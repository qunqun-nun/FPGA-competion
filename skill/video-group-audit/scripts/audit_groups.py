"""Audit explicit source-video IDs and exact file duplicates without mutation."""
import argparse
import csv
import hashlib
import json
from pathlib import Path, PureWindowsPath


def audit(root, manifest):
    root = Path(root).resolve()
    groups, hashes, counts, issues, seen = {}, {}, {}, [], set()
    with Path(manifest).open(encoding='utf-8-sig', newline='') as stream:
        reader = csv.DictReader(stream)
        if not {'path', 'split', 'group'} <= set(reader.fieldnames or []):
            raise ValueError('CSV requires path,split,group')
        rows = list(reader)
    if not rows:
        raise ValueError('Empty dataset')
    for row in rows:
        if any(not isinstance(row.get(k), str) for k in ('path', 'split', 'group')):
            raise ValueError('Incomplete CSV row: ' + str(row))
        name, split, group = (row[k].strip() for k in ('path', 'split', 'group'))
        if not name or not group or split not in {'train', 'valid', 'test'}:
            raise ValueError('Invalid row: ' + str(row))
        path = (root / name).resolve()
        try:
            path.relative_to(root)
            inside = True
        except ValueError:
            inside = False
        if Path(name).is_absolute() or PureWindowsPath(name).drive or not inside:
            raise ValueError('Path escapes dataset: ' + name)
        if str(path) in seen:
            issues.append({'type': 'duplicate_record', 'path': name})
        seen.add(str(path))
        counts[split] = counts.get(split, 0) + 1
        groups.setdefault(group, set()).add(split)
        if not path.is_file():
            issues.append({'type': 'missing_file', 'path': name})
            continue
        digest = hashlib.sha256()
        with path.open('rb') as data:
            for block in iter(lambda: data.read(1024 * 1024), b''):
                digest.update(block)
        hashes.setdefault(digest.hexdigest(), set()).add(split)
    for group, splits in groups.items():
        if len(splits) > 1:
            issues.append({'type': 'source_group_overlap', 'group': group, 'splits': sorted(splits)})
    for digest, splits in hashes.items():
        if len(splits) > 1:
            issues.append({'type': 'exact_file_overlap', 'sha256': digest, 'splits': sorted(splits)})
    return {'status': 'FAIL' if issues else 'PASS', 'counts': counts, 'issues': issues,
            'scope': 'declared source IDs and exact file bytes only; scene independence NOT_TESTED'}


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--root', type=Path, required=True)
    p.add_argument('--manifest', type=Path, required=True)
    p.add_argument('--out', type=Path, default=Path('split_audit.json'))
    args = p.parse_args()
    try:
        report = audit(args.root, args.manifest)
        args.out.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding='utf-8')
        print(report['status'], str(args.out.resolve()))
        return 0 if report['status'] == 'PASS' else 1
    except (OSError, ValueError, TypeError) as exc:
        print('ERROR:', exc)
        return 2


if __name__ == '__main__':
    raise SystemExit(main())

