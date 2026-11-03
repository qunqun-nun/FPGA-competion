"""Compare FP32/INT8 mAP; values in [0,1], tolerance in percentage points."""
import argparse
import json
import math
from pathlib import Path


def compare(data, max_drop_pp):
    if not math.isfinite(max_drop_pp) or max_drop_pp < 0:
        raise ValueError('max-drop-pp must be finite and nonnegative')
    rows = []
    for key in ('metrics/mAP50(B)', 'metrics/mAP50-95(B)'):
        f, q = float(data['fp32'][key]), float(data['int8_cpu'][key])
        if not all(math.isfinite(x) and 0 <= x <= 1 for x in (f, q)):
            raise ValueError('Expected finite mAP fractions within [0,1]')
        drop = 100 * (f - q)
        rows.append({'metric': key, 'fp32': f, 'int8_cpu': q, 'drop_pp': drop,
                     'status': 'PASS' if drop <= max_drop_pp + 1e-10 else 'FAIL'})
    return {'status': 'PASS' if all(r['status'] == 'PASS' for r in rows) else 'FAIL',
            'max_drop_pp': max_drop_pp, 'metrics': rows,
            'same_dataset_and_postprocess': 'MUST_BE_VERIFIED_SEPARATELY', 'board_accuracy': 'NOT_TESTED'}


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--input', type=Path, required=True)
    p.add_argument('--max-drop-pp', type=float, required=True)
    p.add_argument('--out', type=Path)
    args = p.parse_args()
    try:
        report = compare(json.loads(args.input.read_text(encoding='utf-8-sig')), args.max_drop_pp)
    except (OSError, ValueError, KeyError, TypeError) as exc:
        print('ERROR:', exc)
        return 2
    text = json.dumps(report, ensure_ascii=False, indent=2)
    if args.out:
        args.out.write_text(text, encoding='utf-8')
    print(text)
    return 0 if report['status'] == 'PASS' else 1


if __name__ == '__main__':
    raise SystemExit(main())

