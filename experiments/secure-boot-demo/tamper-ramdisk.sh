#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Extracts a fitImage's ramdisk-1 subimage, patches a visible marker into
# the initramfs's own init script, and repacks it -- the shared tamper
# payload experiments A/B/C build on. ramdisk-1 is XZ-compressed (CRC32)
# GNU cpio "newc" format, confirmed against real fitImage output this
# session -- init (the initramfs's entry point, a plain POSIX shell
# script) is the tamper target since the kernel binary itself has no
# accessible plaintext strings to patch (checked, zero hits).
#
# Usage: ./tamper-ramdisk.sh <fitImage> <out-dir> [marker-text]
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/lib.sh"

FIT="${1:?usage: tamper-ramdisk.sh <fitImage> <out-dir> [marker-text]}"
OUT="${2:?usage: tamper-ramdisk.sh <fitImage> <out-dir> [marker-text]}"
MARKER="${3:-EXPERIMENT-TAMPER-MARKER: this initramfs has been modified}"

mkdir -p "$OUT"
OUT="$(cd "$OUT" && pwd)"  # canonicalize: subshells below cd into $OUT/extracted,
                           # so a relative $OUT would stop resolving correctly
rm -rf "$OUT/extracted"
mkdir -p "$OUT/extracted"

"$DUMPIMAGE" -T flat_dt -p 2 -o "$OUT/ramdisk1.orig.cpio.xz" "$FIT" >/dev/null

xz -dc "$OUT/ramdisk1.orig.cpio.xz" > "$OUT/ramdisk1.orig.cpio"

# cpio -idm under an unprivileged user prints "Cannot mknod: Operation
# not permitted" for device nodes (e.g. dev/console) and exits nonzero
# for it -- confirmed benign (the rest of the archive still extracts
# fine around it) -- so the exit code isn't treated as the success
# signal here; "init" actually showing up afterward is (checked below).
(cd "$OUT/extracted" && cpio -idm --no-absolute-filenames < "$OUT/ramdisk1.orig.cpio" 2>"$OUT/cpio-extract.log") || true

if [ ! -f "$OUT/extracted/init" ]; then
    echo "ERROR: extracted ramdisk has no top-level 'init' -- unexpected layout" >&2
    exit 1
fi

# Insert the marker as the second line (right after the shebang), so it
# runs -- and prints to the console -- immediately on boot, before
# anything else in init.
awk -v marker="$MARKER" '
    NR == 1 { print; print "echo \"" marker "\""; next }
    { print }
' "$OUT/extracted/init" > "$OUT/extracted/init.new"
mv "$OUT/extracted/init.new" "$OUT/extracted/init"
chmod +x "$OUT/extracted/init"

(cd "$OUT/extracted" && find . | cpio -o -H newc 2>"$OUT/cpio-pack.log" > "$OUT/ramdisk1.tampered.cpio") \
    || { echo "cpio pack failed, see $OUT/cpio-pack.log" >&2; exit 1; }

xz -z -C crc32 -c "$OUT/ramdisk1.tampered.cpio" > "$OUT/ramdisk1.tampered.cpio.xz"

echo "Wrote $OUT/ramdisk1.tampered.cpio.xz (marker: \"$MARKER\")"
