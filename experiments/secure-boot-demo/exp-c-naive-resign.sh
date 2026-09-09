#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Experiment C: secureboot variant (real FIT signing on), same tamper +
# naive rehash (mkimage -f, no key -- the attacker doesn't have this
# lab's private signing key). Expected: rejected. Unlike B, recomputing
# the hash alone isn't enough here -- the configuration-level
# signature-1 node is never touched by an unsigned rebuild (it's simply
# absent from a fresh build, not stale), so signature verification
# fails and the image is refused.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/lib.sh"

OUT="$WORK/exp-c"
mkdir -p "$OUT"

"$HERE/tamper-ramdisk.sh" "$SB_DEPLOY/fitImage" "$OUT/tamper" >/dev/null

"$HERE/rebuild-fit.sh" "$SB_DEPLOY/fitImage" "$SB_DEPLOY/fitImage-its-evb-ast2600" \
    "$OUT/tamper/ramdisk1.tampered.cpio.xz" "$OUT/rebuild" >/dev/null

make_flash_copy secureboot "$OUT/flash.mtd"
splice "$OUT/flash.mtd" "$OUT/rebuild/fitImage.rebuilt" 1048576

qemu_boot ast2600-evb "$PATCHED_QEMU" "$OUT/flash.mtd" "$OUT/boot.log" 60

if command grep -q "Failed to verify required signature" "$OUT/boot.log" \
    && ! command grep -q "login:" "$OUT/boot.log"; then
    echo "PASS: C (naive rehash rejected, no private key) -- $OUT/boot.log"
    exit 0
else
    echo "FAIL: C -- expected signature verification failure and no login prompt, see $OUT/boot.log"
    exit 1
fi
