#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Experiment D3: the specific sub-case D2's own comment flags as
# untested -- an attacker who builds a real, well-formed ROT_HEADER
# (correct format, correct checksum, a genuine RSA4096/SHA512 signature
# that verifies fine against the attacker's OWN key) around the same
# wholesale-replaced SPL + U-Boot-proper as D1/D2, rather than D1/D2's
# cruder substitution (a plain SPL binary with no ROT_HEADER at all).
#
# Everything about this image is internally consistent and would pass
# any check that didn't have the real OTP-fused key to compare against:
# layer 2's signature genuinely verifies against the attacker's own
# embedded pubkey hash, and layer 1's ROT_HEADER is genuinely well-formed
# -- built with socsec's own real make_secure_bl1_image, the same tool
# and same algorithm (RSA4096_SHA512, --rsa_key_order=big,
# --stack_intersects_verification_region=false) this lab's own real
# build uses (socsec-sign.bbclass's sign_spl_helper()), just pointed at
# an attacker-generated key instead of this lab's real
# rsa_oem_dss_key.pem.
#
# Expected: the vboot ROM's header/checksum stage passes (unlike D2 --
# there IS a real ROT_HEADER this time), but the RSA signature stage
# fails once verify_image() decrypts the signature with the real
# OTP-stored public key and finds it doesn't PKCS#1v1.5-decode to the
# image's real digest -- VERIFY_BAD_SIGNATURE, not VERIFY_BAD_CHECKSUM.
# See verify.c's own header_checksum_valid()/pkcs15_verify() sequence.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/lib.sh"

OUT="$WORK/exp-d3"
mkdir -p "$OUT"

"$HERE/gen-attacker-keys.sh" >/dev/null
"$HERE/gen-attacker-bl1-key.sh" >/dev/null
"$HERE/build-attacker-uboot.sh" "$OUT/attacker-uboot" >/dev/null

# socsec's make_secure_bl1_image enforces a hard 65024-byte cap on
# --bl1_image. build-attacker-uboot.sh's u-boot-spl.bin.attacker (56360
# nodtb + 8704 dtb = 65064) is 40 bytes over it -- the dtb came out
# bigger than the real deploy's own signed dtb (8704 vs 6656) because it
# was built by re-signing an ALREADY real-signed dtb (mkimage -F had to
# grow the fdt by a fresh 2048-byte block to fit a second, differently
# keyed signature on top of one that already used up the original
# padding). The real u-boot build's own pre-signature SPL dtb, still
# sitting in its build/ dir (4608 bytes, confirmed via its own fdt
# header totalsize field), has that padding free -- signing directly
# from there needs only the one real 2048-byte growth step, landing at
# 6656 bytes exactly like this lab's own real signed SPL, comfortably
# under the cap.
SPL_BUILD_DTB="$OPENBMC_ROOT/build/evb-ast2600-secureboot/tmp/work/evb_ast2600-openbmc-linux-gnueabi/u-boot-aspeed-sdk/v2019.04+git/sources/build/spl/u-boot-spl.dtb"
if [ ! -f "$SPL_BUILD_DTB" ]; then
    echo "SKIP: D3 needs u-boot's own pre-signature SPL dtb, not found at:"
    echo "  $SPL_BUILD_DTB"
    echo "  (run ./scripts/build-image.sh --secureboot first)"
    exit 2
fi
cp "$SPL_BUILD_DTB" "$OUT/u-boot-spl.dtb.d3"
"$MKIMAGE" -F -k "$WORK/attacker-keys" -K "$OUT/u-boot-spl.dtb.d3" -r "$OUT/attacker-uboot/u-boot-fitImage.attacker"
cat "$SB_DEPLOY/u-boot-spl-nodtb.bin" "$OUT/u-boot-spl.dtb.d3" > "$OUT/u-boot-spl.bin.d3"

SECUREBOOT_BUILD="$OPENBMC_ROOT/build/evb-ast2600-secureboot"
SOCSEC_PATH="$SECUREBOOT_BUILD/tmp/sysroots-components/x86_64/socsec-native/usr/lib/python3.14/site-packages"
VENV="$VBOOTROM_DIR/work/otpvenv"
BL1_KEY="$WORK/attacker-keys/attacker-bl1-key.pem"

if [ ! -d "$SOCSEC_PATH" ]; then
    echo "SKIP: D3 needs $SECUREBOOT_BUILD's socsec-native sysroot -- run"
    echo "  ./scripts/build-image.sh --secureboot first."
    exit 2
fi
if [ ! -x "$VENV/bin/python3" ]; then
    echo "SKIP: D3 needs $VBOOTROM_DIR's own otptool venv -- run"
    echo "  ($VBOOTROM_DIR/gen-lab-otp-image.sh) first."
    exit 2
fi

echo "Wrapping the attacker SPL in a real, well-formed ROT_HEADER (attacker's own key)..."
"$VENV/bin/python3" -c "
import sys
sys.path.insert(0, '$SOCSEC_PATH')
from socsec.socsec import secTool
secTool().run(['socsec', 'make_secure_bl1_image',
               '--soc', '2600',
               '--algorithm', 'RSA4096_SHA512',
               '--rsa_sign_key', '$BL1_KEY',
               '--bl1_image', '$OUT/u-boot-spl.bin.d3',
               '--stack_intersects_verification_region=false',
               '--rsa_key_order=big',
               '--output', '$OUT/attacker-uboot/bl1.attacker-signed.bin'])
"

make_flash_copy secureboot "$OUT/flash.mtd"
splice "$OUT/flash.mtd" "$OUT/attacker-uboot/bl1.attacker-signed.bin" 0
splice "$OUT/flash.mtd" "$OUT/attacker-uboot/u-boot-fitImage.attacker" 65536

LAB_OTP="$VBOOTROM_DIR/work/otp-on/otp-flat.bin"
if [ ! -f "$LAB_OTP" ]; then
    echo "SKIP: D3 needs $VBOOTROM_DIR's real OTP image -- run"
    echo "  ($VBOOTROM_DIR/gen-lab-otp-image.sh) first"
    exit 2
fi

qemu_boot ast2600-evb-secureboot "$PATCHED_QEMU" "$OUT/flash.mtd" "$OUT/boot.log" 30 \
    -bios "$VBOOTROM_DIR/ast2600_bootrom.bin" \
    -blockdev driver=file,filename="$LAB_OTP",node-name=otp \
    -global aspeed-otp.drive=otp

if command grep -q "^ast2600 vboot:" "$OUT/boot.log" \
    && command grep -q "BAD_SIGNATURE" "$OUT/boot.log" \
    && command grep -q "halting" "$OUT/boot.log" \
    && ! command grep -q "U-Boot 2019.04" "$OUT/boot.log"; then
    echo "PASS: D3 (well-formed but wrongly-keyed ROT_HEADER rejected by the vboot ROM) -- $OUT/boot.log"
    exit 0
else
    echo "FAIL: D3 -- expected a BAD_SIGNATURE vboot rejection and no U-Boot-proper banner, see $OUT/boot.log"
    exit 1
fi
