#!/bin/sh
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(dirname "$HERE")
PIDFILE="$ROOT/state/pipeline.pid"
if [ ! -f "$PIDFILE" ]; then echo 'No recorded pipeline'; exit 0; fi
PID=$(cat "$PIDFILE")
case "$PID" in ''|*[!0-9]*) echo 'Invalid pid file' >&2; exit 1;; esac
# Do not signal an unrelated process if a stale PID has been reused.
if [ ! -f "/proc/$PID/cmdline" ]; then rm -f "$PIDFILE"; exit 0; fi
if tr '\000' '\n' < "/proc/$PID/cmdline" | grep -Fqx "$HERE/run_pipeline.py"; then
    kill -TERM "$PID"
    echo 'Stop requested; wait for PL_PIPELINE_STOPPED. Firmware config is retained until rollback/reboot.'
else
    echo 'PID belongs to another command; no signal sent. Inspect state/pipeline.pid.' >&2
    exit 1
fi
