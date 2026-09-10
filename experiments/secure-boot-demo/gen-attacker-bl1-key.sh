#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Generates (once, cached) a fresh RSA-4096 "attacker" keypair for D3:
# a bare PEM private key, the same shape socsec's own real signing key
# (rsa_oem_dss_key.pem, checked directly under
# build/evb-ast2600-secureboot) is -- no X.509 wrapper needed, unlike
# gen-attacker-keys.sh's FIT key (that one needs a self-signed cert
# because mkimage -F -K reads the public half out of a cert, not a bare
# key). This key plays the role of "an attacker's own private key",
# used to produce a real, well-formed, internally-consistent
# ROT_HEADER -- signed correctly, just not with the key this lab's own
# OTP actually has fused.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/lib.sh"

KEYDIR="$WORK/attacker-keys"
mkdir -p "$KEYDIR"

if [ -f "$KEYDIR/attacker-bl1-key.pem" ]; then
    echo "Attacker BL1 key already cached at $KEYDIR/attacker-bl1-key.pem"
    exit 0
fi

openssl genrsa -F4 -out "$KEYDIR/attacker-bl1-key.pem" 4096
echo "Generated attacker BL1 key at $KEYDIR/attacker-bl1-key.pem"
