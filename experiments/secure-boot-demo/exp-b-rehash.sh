#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Experiment B: same tamper as A, but the FIT hash is regenerated after
# tampering (mkimage -f, no key). Expected: boots clean with the
# tampered marker visible -- the article's central point, a hash alone
# is not a security control, just corruption detection; anyone who can
# recompute it (no key needed) can make a tampered image "verify" fine.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/lib.sh"

OUT="$WORK/exp-b"
mkdir -p "$OUT"

"$HERE/tamper-ramdisk.sh" "$LAB_DEPLOY/fitImage" "$OUT/tamper" >/dev/null

"$HERE/rebuild-fit.sh" "$LAB_DEPLOY/fitImage" "$LAB_DEPLOY/fitImage-its-evb-ast2600" \
    "$OUT/tamper/ramdisk1.tampered.cpio.xz" "$OUT/rebuild" >/dev/null

make_flash_copy lab "$OUT/flash.mtd"
splice "$OUT/flash.mtd" "$OUT/rebuild/fitImage.rebuilt" 1048576

# A full OpenBMC boot to login genuinely takes ~150s under QEMU/TCG
# (this repo's own run-qemu.sh defaults to a 180s timeout) -- shorter
# windows here reliably catch the early tamper-marker print but not the
# login prompt, which is real boot time, not a hang.
qemu_boot ast2600-evb "$SYS_QEMU" "$OUT/flash.mtd" "$OUT/boot.log" 170

if ! command grep -q "Bad Data Hash" "$OUT/boot.log" \
    && command grep -q "EXPERIMENT-TAMPER-MARKER" "$OUT/boot.log" \
    && command grep -q "login:" "$OUT/boot.log"; then
    echo "PASS: B (tampered image boots clean after rehash) -- $OUT/boot.log"
    exit 0
else
    echo "FAIL: B -- expected no hash error, marker present, login reached, see $OUT/boot.log"
    exit 1
fi
