#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Builds an attacker-substituted layer 2 (SPL -> U-Boot-proper): a
# freshly attacker-signed U-Boot-proper FIT, plus a matching SPL whose
# appended dtb carries the attacker's own public key instead of this
# lab's real one -- exactly what uboot-sign.bbclass's own real build
# does (mkimage -f, then mkimage -F -k <keydir> -K <dtb> -r <fit>),
# just against a keypair the attacker generated themselves
# (gen-attacker-keys.sh). Shared by D1 (stock ast2600-evb -- should
# succeed unchallenged, no OTP/ROM anchor to catch it) and D2
# (ast2600-evb-secureboot -- the vboot ROM should reject the
# substituted SPL before it ever runs).
#
# u-boot.its's uboot/fdt image nodes reference u-boot-nodtb.bin/
# u-boot.dtb as relative /incbin paths -- both real, standalone files
# still in the deploy dir (unlike the kernel FIT's kernel/fdt, no
# dumpimage extraction needed here).
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/lib.sh"

OUT="${1:-$WORK/attacker-uboot}"
KEYDIR="$WORK/attacker-keys"

if [ ! -f "$KEYDIR/rsa_oem_fitimage_key.key" ]; then
    echo "ERROR: no attacker keypair at $KEYDIR -- run ./gen-attacker-keys.sh first" >&2
    exit 1
fi

mkdir -p "$OUT"
OUT="$(cd "$OUT" && pwd)"

cp "$SB_DEPLOY/u-boot.its" "$SB_DEPLOY/u-boot-nodtb.bin" "$SB_DEPLOY/u-boot.dtb" "$OUT/"
(cd "$OUT" && "$MKIMAGE" -f u-boot.its u-boot-fitImage.attacker)

cp "$SB_DEPLOY/u-boot-spl.dtb" "$OUT/u-boot-spl.dtb.attacker"
"$MKIMAGE" -F -k "$KEYDIR" -K "$OUT/u-boot-spl.dtb.attacker" -r "$OUT/u-boot-fitImage.attacker"

cat "$SB_DEPLOY/u-boot-spl-nodtb.bin" "$OUT/u-boot-spl.dtb.attacker" > "$OUT/u-boot-spl.bin.attacker"

echo "Wrote $OUT/u-boot-fitImage.attacker and $OUT/u-boot-spl.bin.attacker"
