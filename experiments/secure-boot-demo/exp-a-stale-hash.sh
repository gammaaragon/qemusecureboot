#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Experiment A: unsigned kernel FIT (lab variant), ramdisk tampered with
# a benign visible marker, hash left STALE (still the original,
# pre-tamper value). Expected: U-Boot's own hash check catches the
# mismatch and refuses to boot -- proves the hash node alone is doing
# its job for accidental corruption.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/lib.sh"

OUT="$WORK/exp-a"
mkdir -p "$OUT"

"$HERE/tamper-ramdisk.sh" "$LAB_DEPLOY/fitImage" "$OUT/tamper" >/dev/null

"$HERE/rebuild-fit.sh" "$LAB_DEPLOY/fitImage" "$LAB_DEPLOY/fitImage-its-evb-ast2600" \
    "$OUT/tamper/ramdisk1.tampered.cpio.xz" "$OUT/rebuild" >/dev/null

ORIG_HASH="$("$DUMPIMAGE" -l "$LAB_DEPLOY/fitImage" | awk '/Image 2 \(ramdisk-1\)/{f=1} f && /Hash value/{print $3; exit}')"
cp "$OUT/rebuild/fitImage.rebuilt" "$OUT/rebuild/fitImage.stale-hash.itb"
"$FDTPUT" -t bx "$OUT/rebuild/fitImage.stale-hash.itb" /images/ramdisk-1/hash-1 value \
    $(echo "$ORIG_HASH" | fold -w2 | tr '\n' ' ') >/dev/null

make_flash_copy lab "$OUT/flash.mtd"
splice "$OUT/flash.mtd" "$OUT/rebuild/fitImage.stale-hash.itb" 1048576

qemu_boot ast2600-evb "$SYS_QEMU" "$OUT/flash.mtd" "$OUT/boot.log" 60

if command grep -q "Bad Data Hash" "$OUT/boot.log" && ! command grep -q "login:" "$OUT/boot.log"; then
    echo "PASS: A (hash mismatch caught, boot refused) -- $OUT/boot.log"
    exit 0
else
    echo "FAIL: A -- expected 'Bad Data Hash' and no login prompt, see $OUT/boot.log"
    exit 1
fi
