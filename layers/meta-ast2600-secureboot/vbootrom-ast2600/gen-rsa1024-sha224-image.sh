#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Self-signs an RSA1024/SHA224 test image + matching OTP image, closing
# the one real remaining gap in this ROM's tested algorithm coverage:
# socsec's own test suite has real A3+big reference vectors for every
# rsa-size/sha-mode combination EXCEPT rsa1024/sha224 -- both are
# implemented (otp.c's rsa_len/sha_mode dispatch already
# covers them) but were never checked against real ground truth. Same
# self-signing approach as gen-cot-image.sh (real socsec/otptool CLI,
# via the same throwaway venv), just a fresh OTP config instead of
# reusing this lab's own real one, since this needs a different
# key/algorithm than this lab's real RSA4096/SHA512 key.
#
# Uses a real 1024-bit test key already bundled in socsec's own test
# suite (tests/keys/rsa1024.pem/.pub.pem) -- not a freshly generated
# one -- and socsec's own generic BL1 test stub, same as
# gen-cot-image.sh.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT_DIR="${1:-$HERE/work/rsa1024-sha224}"
mkdir -p "$OUT_DIR"

SECUREBOOT_BUILD="$HOME/openbmc/build/evb-ast2600-secureboot"
SOCSEC_NATIVE_SRC="$SECUREBOOT_BUILD/tmp/work/x86_64-linux/socsec-native/2.0.12/sources/socsec-2.0.12"
SOCSEC_PATH="$SECUREBOOT_BUILD/tmp/sysroots-components/x86_64/socsec-native/usr/lib/python3.14/site-packages"
BL1_STUB="$SOCSEC_NATIVE_SRC/tests/data/bl1.bin"
KEY_DIR="$SOCSEC_NATIVE_SRC/tests/keys"

for f in "$SOCSEC_PATH" "$BL1_STUB" "$KEY_DIR/rsa1024.pem"; do
    if [ ! -e "$f" ]; then
        echo "ERROR: required socsec build artifact not found: $f" >&2
        echo "  Run './scripts/build-image.sh --secureboot' at least once first." >&2
        exit 1
    fi
done

VENV="$HERE/work/otpvenv"
if [ ! -x "$VENV/bin/python3" ]; then
    echo "Creating throwaway venv for socsec/otptool at $VENV..."
    python3 -m venv "$VENV"
    "$VENV/bin/pip" install -q bitarray ecdsa pycryptodome jstyleson jsonschema cryptography
fi

# Config modeled on socsec's own real A3+big reference fixtures
# (tests/otp/2600-a3_mode2-rsa*-sha*-big.json) -- same shape, just
# rsa1024.pem/RSA1024/SHA224 instead of a size socsec already ships a
# vector for. "Enable Secure Boot" deliberately left unset (matches
# every other socsec-shipped fixture used by test-vectors/): this
# script's output is only ever fed to verify_test/aes_decrypt_test,
# which call verify_image() directly regardless of the enable bit --
# see run-tests.sh.
cat > "$OUT_DIR/otp-rsa1024-sha224.json" <<'JSON'
{
    "name": "rsa1024-sha224-selfsigned",
    "version": "A3",
    "data_region": {
        "ecc_region": true,
        "rsa_key_order": "big",
        "key": [
            {
                "types": "rsa_pub_oem",
                "key_pem": "rsa1024.pem",
                "offset": "0x480",
                "number_id": 0,
                "sha_mode": "SHA224"
            }
        ]
    },
    "config_region": {
        "Secure Boot Mode": "Mode_2",
        "Secure crypto RSA length": "RSA1024",
        "Hash mode": "SHA224",
        "Enable image encryption": false
    }
}
JSON

echo "Generating rsa1024/sha224 OTP image..."
"$VENV/bin/python3" -c "
import sys
sys.path.insert(0, '$SOCSEC_PATH')
from socsec.otptool import otpTool
otpTool().run(['otptool', 'make_otp_image', '--key_folder', '$KEY_DIR',
               '--output_folder', '$OUT_DIR',
               '$OUT_DIR/otp-rsa1024-sha224.json'])
"

echo "Signing a real RSA1024/SHA224 test image..."
"$VENV/bin/python3" -c "
import sys
sys.path.insert(0, '$SOCSEC_PATH')
from socsec.socsec import secTool
secTool().run(['socsec', 'make_secure_bl1_image',
               '--soc', '2600',
               '--algorithm', 'RSA1024_SHA224',
               '--rsa_sign_key', '$KEY_DIR/rsa1024.pem',
               '--bl1_image', '$BL1_STUB',
               '--stack_intersects_verification_region=false',
               '--rsa_key_order=big',
               '--output', '$OUT_DIR/bl1.rsa1024-sha224.signed.bin'])
"

# Flat OTP image, same layout every other gen-*.sh script here uses --
# see gen-lab-otp-image.sh's own comment for why this isn't otptool's
# own otp-all.image format.
truncate -s 16384 "$OUT_DIR/otp-flat.bin"
dd if="$OUT_DIR/otp-data.bin" of="$OUT_DIR/otp-flat.bin" conv=notrunc status=none
dd if="$OUT_DIR/otp-conf.bin" of="$OUT_DIR/otp-flat.bin" bs=1 seek=8192 conv=notrunc status=none

echo "Wrote $OUT_DIR/bl1.rsa1024-sha224.signed.bin and $OUT_DIR/otp-flat.bin"
