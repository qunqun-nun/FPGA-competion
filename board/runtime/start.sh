#!/bin/sh
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(dirname "$HERE")
PYTHON=${FY_PYTHON:-python3}
if [ "$(id -u)" != 0 ]; then
    echo 'Use sudo -E sh runtime/start.sh [pipeline arguments]' >&2
    exit 1
fi
mkdir -p "$ROOT/state"
exec 9>"$ROOT/state/pipeline.lock"
flock -n 9 || { echo 'Another package pipeline is running' >&2; exit 1; }
if [ -f "$ROOT/state/pipeline.pid" ]; then
    echo 'Check stale state/pipeline.pid using runtime/stop.sh first' >&2
    exit 1
fi
cleanup() { rm -f "$ROOT/state/pipeline.pid"; }
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
"$PYTHON" "$HERE/verify_package.py"
"$PYTHON" -c 'import sys, platform; assert sys.version_info >= (3,8); assert platform.machine()=="aarch64"; import numpy,cv2,pynq,pynq_dpu,xir,vart'
if command -v cc >/dev/null 2>&1; then
    cc -std=c11 -O2 -Wall -Wextra -Werror -fPIC -shared "$HERE/native/memio.c" -o "$HERE/native/libmemio.so"
else
    cp "$HERE/native/libmemio_aarch64.so" "$HERE/native/libmemio.so"
fi
if [ "${FY_SKIP_HDMI:-0}" = 1 ]; then
    echo 'Explicit PL-only diagnostic mode: HDMI initialization skipped.' >&2
    "$PYTHON" "$HERE/run_pipeline.py" --load "$@" &
else
    echo 'Starting USB/PL/DPU with real HDMI TX/PHY initialization (board acceptance still required).' >&2
    "$PYTHON" "$HERE/run_pipeline.py" --load --hdmi "$@" &
fi
CHILD=$!
printf '%s\n' "$CHILD" > "$ROOT/state/pipeline.pid"
trap 'kill -TERM "$CHILD" 2>/dev/null || true; wait "$CHILD" || true; cleanup' INT TERM
wait "$CHILD"
