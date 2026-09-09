#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Rebuilds a fitImage from its own real .its + dumpimage-extracted
# kernel/fdt + a (possibly tampered) ramdisk, via `mkimage -f`. Shared
# mechanic experiments B and C both build on: unsigned (no keydir) is a
# "naive rehash" -- every per-image hash-N gets correctly recomputed
# against whatever data is actually there, but a configuration-level
# signature-1 node (if any) is never touched by an unsigned rebuild, so
# a signed source .its rebuilt this way still carries its original,
# now-stale signature -- which is exactly what makes it fail
# verification (Experiment C). Passing a keydir signs for real instead
# (not currently exercised by any driver, kept for completeness/
# possible extension).
#
# The source .its's kernel-1/fdt-* /incbin paths are relative filenames
# (resolved via dumpimage extraction below, since their own standalone
# build-dir copies no longer exist); ramdisk-1's /incbin path is
# absolute, into ~/openbmc's build tree -- rewritten to point at our own
# tampered copy instead, since we never write into ~/openbmc (this
# repo's own ground rule).
#
# Usage: ./rebuild-fit.sh <source-fitImage> <its-file> <ramdisk-xz> <out-dir> [keydir]
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/lib.sh"

SRC_FIT="${1:?usage: rebuild-fit.sh <source-fitImage> <its-file> <ramdisk-xz> <out-dir> [keydir]}"
ITS="${2:?usage: rebuild-fit.sh <source-fitImage> <its-file> <ramdisk-xz> <out-dir> [keydir]}"
RAMDISK="${3:?usage: rebuild-fit.sh <source-fitImage> <its-file> <ramdisk-xz> <out-dir> [keydir]}"
OUT="${4:?usage: rebuild-fit.sh <source-fitImage> <its-file> <ramdisk-xz> <out-dir> [keydir]}"
KEYDIR="${5:-}"

mkdir -p "$OUT"
OUT="$(cd "$OUT" && pwd)"  # mkimage runs with $OUT as cwd below; relative
                           # /incbin paths in the .its resolve against it

"$DUMPIMAGE" -T flat_dt -p 0 -o "$OUT/linux.bin" "$SRC_FIT" >/dev/null
"$DUMPIMAGE" -T flat_dt -p 1 -o "$OUT/aspeed-ast2600-evb.dtb" "$SRC_FIT" >/dev/null
cp "$RAMDISK" "$OUT/ramdisk.cpio.xz"

sed -E 's#data = /incbin/\("[^"]*obmc-phosphor-initramfs[^"]*"\);#data = /incbin/("ramdisk.cpio.xz");#' \
    "$ITS" > "$OUT/fit.its"

if ! command grep -q 'ramdisk.cpio.xz' "$OUT/fit.its"; then
    echo "ERROR: failed to rewrite ramdisk /incbin path in $OUT/fit.its -- .its format may have changed" >&2
    exit 1
fi

if [ -n "$KEYDIR" ]; then
    (cd "$OUT" && "$MKIMAGE" -f fit.its -k "$KEYDIR" -r fitImage.rebuilt)
else
    (cd "$OUT" && "$MKIMAGE" -f fit.its fitImage.rebuilt)
fi

echo "Wrote $OUT/fitImage.rebuilt"
