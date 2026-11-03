"""Usage: python run_logged.py NEW_OUT -- COMMAND ARGS. No shell or retry."""
import datetime
import json
import subprocess
import sys
from pathlib import Path


def main():
    if len(sys.argv) < 4 or sys.argv[2] != '--':
        print(__doc__, file=sys.stderr)
        return 2
    out = Path(sys.argv[1])
    out.mkdir(parents=True, exist_ok=False)
    record = {'argv': sys.argv[3:], 'cwd': str(Path.cwd()),
              'started_at': datetime.datetime.now(datetime.timezone.utc).isoformat()}
    try:
        with (out / 'stdout.log').open('wb') as stdout, (out / 'stderr.log').open('wb') as stderr:
            rc = subprocess.run(sys.argv[3:], stdout=stdout, stderr=stderr, shell=False).returncode
        record['exitcode'] = rc
    except OSError as exc:
        rc = 2
        record.update(exitcode=None, launch_error=str(exc))
    record['ended_at'] = datetime.datetime.now(datetime.timezone.utc).isoformat()
    (out / 'command.json').write_text(json.dumps(record, ensure_ascii=False, indent=2), encoding='utf8')
    return rc if 0 <= rc <= 255 else 1


if __name__ == '__main__':
    sys.exit(main())
