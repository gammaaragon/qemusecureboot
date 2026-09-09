#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Signs a COT-suffixed BL1 test image with this lab's own real signing
# key, via the real socsec CLI. socsec's own test suite has no A3-big
# COT reference vector (only A0, which uses incompatible OTP key-type
# codes for this ROM -- see notes/2026-09-03-07-vbootrom-ast2600-stage3-
# slice1-otp-keylist.md), so this generates ground truth locally instead
# of relying on a pre-built fixture -- same approach as
# notes/2026-09-03-11-vbootrom-ast2600-stage3-slice5-cot-regression.md,
# now scripted instead of redone by hand.
#
# Uses socsec's own generic BL1 test stub as the plaintext image (this
# lab's real deployed SPL is already signed in place by the time a build
# completes -- no unsigned original survives to re-sign), signed with
# this lab's real key against a real --cot_algorithm/--cot_verify_key
# pair. Output verifies with this lab's own real otp-on image
# (gen-lab-otp-image.sh), not any test-vectors/ OTP.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT_DIR="${1:-$HERE/work/cot}"
mkdir -p "$OUT_DIR"

SECUREBOOT_BUILD="$HOME/openbmc/build/evb-ast2600-secureboot"
SOCSEC_NATIVE_SRC="$SECUREBOOT_BUILD/tmp/work/x86_64-linux/socsec-native/2.0.12/sources/socsec-2.0.12"
SOCSEC_PATH="$SECUREBOOT_BUILD/tmp/sysroots-components/x86_64/socsec-native/usr/lib/python3.14/site-packages"
SOCSEC_SRC="$SECUREBOOT_BUILD/tmp/work/evb_ast2600-openbmc-linux-gnueabi/u-boot-aspeed-sdk/v2019.04+git/sources"
BL1_STUB="$SOCSEC_NATIVE_SRC/tests/data/bl1.bin"
SIGN_KEY="$SOCSEC_SRC/rsa_oem_dss_key.pem"
VERIFY_KEY="$SOCSEC_SRC/rsa_pub_oem_dss_key.pem"

for f in "$SOCSEC_PATH" "$BL1_STUB" "$SIGN_KEY" "$VERIFY_KEY"; do
    if [ ! -e "$f" ]; then
        echo "ERROR: required socsec build artifact not found: $f" >&2
        echo "  Run './scripts/build-image.sh --secureboot' at least once first." >&2
        exit 1
    fi
done

VENV="$HERE/work/otpvenv"
if [ ! -x "$VENV/bin/python3" ]; then
    echo "Creating throwaway venv for socsec at $VENV..."
    python3 -m venv "$VENV"
    "$VENV/bin/pip" install -q bitarray ecdsa pycryptodome jstyleson jsonschema cryptography
fi

echo "Signing a COT-suffixed BL1 test image with this lab's real key..."
"$VENV/bin/python3" -c "
import sys
sys.path.insert(0, '$SOCSEC_PATH')
from socsec.socsec import secTool
secTool().run(['socsec', 'make_secure_bl1_image',
               '--soc', '2600',
               '--algorithm', 'RSA4096_SHA512',
               '--rsa_sign_key', '$SIGN_KEY',
               '--bl1_image', '$BL1_STUB',
               '--stack_intersects_verification_region=false',
               '--rsa_key_order=big',
               '--cot_algorithm', 'RSA4096_SHA512',
               '--cot_verify_key', '$VERIFY_KEY',
               '--output', '$OUT_DIR/bl1.cot.signed.bin'])
"

echo "Wrote $OUT_DIR/bl1.cot.signed.bin"
