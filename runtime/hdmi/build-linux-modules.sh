#!/bin/sh
# Run in a Linux SDK shell. Builds official source only; does not install/load.
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
: "${KERNEL_SRC:?Set KERNEL_SRC to the matching configured linux-xlnx 2022.2 source}"
: "${KERNEL_OUT:?Set KERNEL_OUT to its prepared output including Module.symvers}"
: "${CROSS_COMPILE:?Source the target AArch64 SDK environment first}"
command -v "${CROSS_COMPILE}gcc" >/dev/null
[ -r "$KERNEL_SRC/drivers/gpu/drm/xlnx/xlnx_drv.h" ] || {
    echo 'Matching Xilinx DRM source headers are required' >&2; exit 2;
}
[ -s "$KERNEL_OUT/Module.symvers" ] || {
    echo 'Need the actual target kernel build/Module.symvers, not modules_prepare alone' >&2; exit 2;
}
[ -r "$KERNEL_OUT/include/generated/autoconf.h" ] || exit 2
# Build in a fresh package-local directory; preserve the official snapshot.
WORK=$(mktemp -d "$HERE/module-build.XXXXXX")
cp -R "$HERE/official-2022.2/." "$WORK/"
make -C "$KERNEL_SRC" O="$KERNEL_OUT" M="$WORK" ARCH=arm64 \
    CROSS_COMPILE="$CROSS_COMPILE" modules
printf '\nBuilt modules (not loaded):\n'
find "$WORK" -name '*.ko' -type f -print
printf 'Build alone does not initialize the custom HDMI pipeline. See README.md.\n'
