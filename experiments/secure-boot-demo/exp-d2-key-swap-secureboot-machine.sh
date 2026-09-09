#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Experiment D2: the same attacker substitution as D1, but booted via
# ast2600-evb-secureboot -- the machine with the real vboot ROM (this
# lab's own layer 1: ROM verifies SPL against an OTP-fused key before
# ever running it). Expected: rejected before SPL ever executes,
# closing exactly the gap D1 exposes.
#
# Real captured result: the vboot ROM's own verification is a
# completely separate mechanism from FIT signing (socsec's ROT_HEADER
# format, not a FIT at all) -- an attacker who just substitutes a plain
# U-Boot SPL binary (as D1 does) has no ROT_HEADER at all, so the
# rejection reason is "BAD_CHECKSUM -- header corrupted" rather than
# "BAD_SIGNATURE" (which would need a well-formed-but-wrongly-signed
# ROT_HEADER, a more sophisticated attack this experiment doesn't build).
# Either way the outcome is the same and is what actually matters here:
# the gate opens, inspects what's actually in flash, and halts before
# SPL ever runs -- checked generically below (any real vboot rejection
# message, not one specific wording) rather than assuming which failure
# path a given attacker payload happens to hit.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/lib.sh"

OUT="$WORK/exp-d2"
mkdir -p "$OUT"

"$HERE/gen-attacker-keys.sh" >/dev/null
"$HERE/build-attacker-uboot.sh" "$OUT/attacker-uboot" >/dev/null

make_flash_copy secureboot "$OUT/flash.mtd"
splice "$OUT/flash.mtd" "$OUT/attacker-uboot/u-boot-spl.bin.attacker" 0
splice "$OUT/flash.mtd" "$OUT/attacker-uboot/u-boot-fitImage.attacker" 65536

LAB_OTP="$VBOOTROM_DIR/work/otp-on/otp-flat.bin"
if [ ! -f "$LAB_OTP" ]; then
    echo "SKIP: D2 needs $VBOOTROM_DIR's real OTP image -- run"
    echo "  ($VBOOTROM_DIR/gen-lab-otp-image.sh) first"
    exit 2
fi

qemu_boot ast2600-evb-secureboot "$PATCHED_QEMU" "$OUT/flash.mtd" "$OUT/boot.log" 30 \
    -bios "$VBOOTROM_DIR/ast2600_bootrom.bin" \
    -blockdev driver=file,filename="$LAB_OTP",node-name=otp \
    -global aspeed-otp.drive=otp

if command grep -q "^ast2600 vboot:" "$OUT/boot.log" \
    && command grep -q "halting" "$OUT/boot.log" \
    && ! command grep -q "U-Boot 2019.04" "$OUT/boot.log"; then
    echo "PASS: D2 (attacker-substituted trust chain rejected by the vboot ROM) -- $OUT/boot.log"
    exit 0
else
    echo "FAIL: D2 -- expected a vboot rejection and no U-Boot-proper banner, see $OUT/boot.log"
    exit 1
fi
