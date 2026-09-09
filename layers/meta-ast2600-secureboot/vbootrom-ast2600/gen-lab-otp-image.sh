#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Generates this lab's own real otp-on flat OTP image: the one
# `run-tests.sh` uses for the "this lab's own real key" checks (as
# opposed to the 27 socsec reference-vector combos in test-vectors/,
# which ship their own OTP components already).
#
# This lab's build only ever deploys otp-off (OTPTOOL_CONFIGS in
# u-boot-aspeed-sdk_%.bbappend); otp-on.json exists in the recipe but
# bitbake never builds it. Needed a real otp-on image to test
# verification against, so this generates one directly with the real
# `otptool` (its own #!/usr/bin/env nativepython3 shebang only works
# inside a bitbake-sourced environment, so this uses a throwaway venv
# instead -- same approach as notes/2026-09-03-03-vbootrom-ast2600-stage2.md,
# now scripted instead of redone by hand every session).
#
# Needs the evb-ast2600-secureboot build's socsec-native sysroot and
# u-boot-aspeed-sdk sources to already exist (i.e. `build-image.sh
# --secureboot` has been run at least once) -- this script only signs/
# packages, it doesn't build the toolchain itself.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT_DIR="${1:-$HERE/work/otp-on}"
mkdir -p "$OUT_DIR"

SECUREBOOT_BUILD="$HOME/openbmc/build/evb-ast2600-secureboot"
SOCSEC_PATH="$SECUREBOOT_BUILD/tmp/sysroots-components/x86_64/socsec-native/usr/lib/python3.14/site-packages"
SOCSEC_SRC="$SECUREBOOT_BUILD/tmp/work/evb_ast2600-openbmc-linux-gnueabi/u-boot-aspeed-sdk/v2019.04+git/sources"
OTP_ON_JSON="$SOCSEC_SRC/evb-ast2600-secureboot-otp-on.json"

if [ ! -d "$SOCSEC_PATH" ] || [ ! -f "$OTP_ON_JSON" ]; then
    echo "ERROR: evb-ast2600-secureboot build artifacts not found." >&2
    echo "  Expected: $SOCSEC_PATH" >&2
    echo "  Expected: $OTP_ON_JSON" >&2
    echo "  Run './scripts/build-image.sh --secureboot' at least once first." >&2
    exit 1
fi

VENV="$HERE/work/otpvenv"
if [ ! -x "$VENV/bin/python3" ]; then
    echo "Creating throwaway venv for otptool at $VENV..."
    python3 -m venv "$VENV"
    "$VENV/bin/pip" install -q bitarray ecdsa pycryptodome jstyleson jsonschema cryptography
fi

echo "Generating otp-on image via otptool (real ASPEED tooling, MIT-licensed)..."
"$VENV/bin/python3" -c "
import sys
sys.path.insert(0, '$SOCSEC_PATH')
from socsec.otptool import otpTool
otpTool().run(['otptool', 'make_otp_image', '--key_folder', '$SOCSEC_SRC',
               '--output_folder', '$OUT_DIR',
               '$OTP_ON_JSON'])
"

# QEMU's aspeed_otp device (hw/nvram/aspeed_otp.c) does one flat
# blk_pread() into a buffer sized OTP_MEMORY_SIZE (0x4000 bytes):
#   data region   [0x0000, 0x2000)  <- otp-data.bin verbatim
#   config region starting 0x2000   <- otp-conf.bin verbatim
#   rest zero
# otptool's own otp-all.image is a different, header-prefixed,
# tool-internal format -- not what QEMU's loader expects directly. See
# notes/2026-09-03-03-vbootrom-ast2600-stage2.md for how this was found
# (comparing byte offsets of the known modulus bytes between the two).
FLAT="$OUT_DIR/otp-flat.bin"
truncate -s 16384 "$FLAT"
dd if="$OUT_DIR/otp-data.bin" of="$FLAT" conv=notrunc status=none
dd if="$OUT_DIR/otp-conf.bin" of="$FLAT" bs=1 seek=8192 conv=notrunc status=none

echo "Wrote $FLAT"
