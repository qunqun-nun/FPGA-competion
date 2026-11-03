#!/bin/sh
# Compile a COMPLETE system DTS that already includes the selected fragment(s).
# Optional arguments are cpp include directories (kernel include + DTG output).
set -eu
[ "$#" -ge 1 ] || { echo 'Usage: sh validate-dts.sh full-system.dts [include-dir ...]' >&2; exit 2; }
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
SOURCE=$1
shift
command -v cpp >/dev/null
command -v dtc >/dev/null
WORK=$(mktemp -d "$HERE/dts-check.XXXXXX")
set -- "$@"
# Expand include directories without eval or unquoted argument splitting.
for directory do
    [ -d "$directory" ] || { echo "Not a directory: $directory" >&2; exit 2; }
done
python3 - "$SOURCE" "$WORK/preprocessed.dts" "$HERE" "$@" <<'PY'
import subprocess, sys
source, output, here, *dirs = sys.argv[1:]
cmd = ['cpp', '-nostdinc', '-undef', '-D__DTS__', '-x', 'assembler-with-cpp']
for directory in [here] + dirs:
    cmd += ['-I', directory]
with open(output, 'wb') as f:
    subprocess.run(cmd + [source], stdout=f, check=True)
PY
dtc -I dts -O dtb -i "$HERE" -o "$WORK/system.dtb" "$WORK/preprocessed.dts" 2>"$WORK/dtc.log"
cat "$WORK/dtc.log"
printf 'Compiled %s/system.dtb; review warnings and DT against the actual kernel.\n' "$WORK"
