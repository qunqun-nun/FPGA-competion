#!/bin/sh
# Observation only: no devmem, i2c scanning, modprobe, unbind or FPGA loading.
set -eu
SYS=${HDMI_SYSFS:-/sys}
printf 'HDMI audit (observation only); kernel: '
uname -r
printf '\nFPGA manager state:\n'
for f in "$SYS"/class/fpga_manager/*/state; do
    [ -r "$f" ] && { printf '%s: ' "$f"; cat "$f"; }
done
missing=0
for addr in 82000000 82020000 82030000; do
    found=0
    for p in "$SYS"/bus/platform/devices/"$addr".*; do
        [ -d "$p" ] || continue
        found=1
        printf '\n%s\n' "$p"
        if [ -L "$p/driver" ]; then readlink "$p/driver"; else
            printf 'UNBOUND (or disabled in DT)\n'; missing=1
        fi
        for f in hdmi_info vphy_info; do
            if [ -r "$p/$f" ]; then cat "$p/$f"; fi
        done
    done
    if [ "$found" = 0 ]; then printf '\n%s: no platform device\n' "$addr"; missing=1; fi
done
printf '\nI2C adapters (no bus transactions):\n'
for p in "$SYS"/class/i2c-adapter/i2c-*; do
    [ -d "$p" ] || continue
    printf '%s: ' "$p"
    cat "$p/name"
    readlink -f "$p/device" || true
done
printf '\nHDMI connectors:\n'
connector=0
for p in "$SYS"/class/drm/card*-HDMI-A-*; do
    [ -d "$p" ] || continue
    connector=1
    printf '%s\n' "$p"
    for f in status enabled modes; do
        [ ! -r "$p/$f" ] || { printf '%s: ' "$f"; cat "$p/$f"; }
    done
done
printf '\nRelevant kernel log (permissions may restrict access):\n'
dmesg 2>/dev/null | grep -Ei 'hdmi|vphy|dp159|8t49|820[0-3]0000|defer' || true
if [ "$missing" != 0 ] || [ "$connector" = 0 ]; then
    printf '\nINCOMPLETE: platform binding/DRM connector missing. This is not an initialization success.\n'
    exit 2
fi
printf '\nOBSERVED: drivers and connector exist. Verify 720p60 stream/PLL/monitor separately.\n'
