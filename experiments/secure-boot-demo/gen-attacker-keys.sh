#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Generates (once, cached) a fresh RSA-4096 "attacker" keypair for D1/D2:
# an attacker with no access to this lab's real rsa_oem_fitimage_key can
# still generate their OWN keypair and sign a replacement U-Boot-proper
# FIT with it -- the whole point of D1/D2 is showing whether anything
# catches that substitution. Key MUST be named exactly
# rsa_oem_fitimage_key.key/.crt -- that's the key-name-hint every FIT in
# this lab's chain looks for (layer.conf's UBOOT_SIGN_KEYNAME/
# SPL_SIGN_KEYNAME/FIT_KERNEL_SIGN_KEYNAME all match), and mkimage's own
# signing code resolves a key purely by that hint, regardless of whose
# key it actually is.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/lib.sh"

KEYDIR="$WORK/attacker-keys"

if [ -f "$KEYDIR/rsa_oem_fitimage_key.key" ] && [ -f "$KEYDIR/rsa_oem_fitimage_key.crt" ]; then
    echo "Attacker keypair already cached at $KEYDIR"
    exit 0
fi

mkdir -p "$KEYDIR"
openssl genrsa -F4 -out "$KEYDIR/rsa_oem_fitimage_key.key" 4096
openssl req -batch -new -x509 -key "$KEYDIR/rsa_oem_fitimage_key.key" \
    -out "$KEYDIR/rsa_oem_fitimage_key.crt" \
    -subj "/CN=attacker-demo-key (NOT the real lab key)"

echo "Generated attacker keypair at $KEYDIR"
