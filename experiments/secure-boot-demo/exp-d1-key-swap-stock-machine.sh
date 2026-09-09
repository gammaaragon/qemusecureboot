#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Experiment D1: the trust-anchor gap. secureboot variant's SPL and
# U-Boot-proper wholesale-substituted with an attacker-signed
# replacement (fresh RSA-4096 keypair, no access to this lab's real
# key), booted via the STOCK ast2600-evb machine (no ROM/OTP anchor).
# Expected: boots completely unchallenged, all the way to a login
# prompt -- even though layer 2's own FIT signature check is real and
# working, it's checking against whatever key SPL's own dtb happens to
# carry, and nothing here verifies SPL itself before it runs. Signing
# alone doesn't help if the verifier and its key aren't themselves
# anchored to something the attacker can't rewrite.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/lib.sh"

OUT="$WORK/exp-d1"
mkdir -p "$OUT"

"$HERE/gen-attacker-keys.sh" >/dev/null
"$HERE/build-attacker-uboot.sh" "$OUT/attacker-uboot" >/dev/null

make_flash_copy secureboot "$OUT/flash.mtd"
splice "$OUT/flash.mtd" "$OUT/attacker-uboot/u-boot-spl.bin.attacker" 0
splice "$OUT/flash.mtd" "$OUT/attacker-uboot/u-boot-fitImage.attacker" 65536

qemu_boot ast2600-evb "$PATCHED_QEMU" "$OUT/flash.mtd" "$OUT/boot.log" 170

if command grep -q "U-Boot 2019.04" "$OUT/boot.log" && command grep -q "login:" "$OUT/boot.log"; then
    echo "PASS: D1 (attacker-substituted trust chain boots unchallenged) -- $OUT/boot.log"
    exit 0
else
    echo "FAIL: D1 -- expected U-Boot-proper banner and login prompt, see $OUT/boot.log"
    exit 1
fi
