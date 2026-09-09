#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Runs the full positive/negative test matrix this project's
# implementation was verified against, so it can be re-run by anyone from
# a clone. See README.md's "Layout" section for the design behind each
# piece being tested.
#
# Covers:
#   - The real 27-combination socsec reference-vector matrix in
#     test-vectors/ (mode2 x 9, mode2aes1 x 9, mode2aes2 x 9 --
#     rsa{2048,3072,4096} x sha{256,384,512}), each checked against real
#     ground truth (verify result for mode2; decrypted-region hash
#     cross-checked against the real plaintext for the AES modes).
#   - A self-generated COT-suffixed BL1 image (gen-cot-image.sh) --
#     socsec's own test suite has no A3-big COT vectors, so this signs
#     one locally instead.
#   - This lab's own real signed SPL + real OTP key, if both are
#     present locally (gen-lab-otp-image.sh for the OTP image; the
#     signed SPL needs a real `build-image.sh --secureboot` run, a
#     gitignored build artifact -- skipped with a clear message if
#     missing, not a hard failure).
#   - One corrupted-signature negative test per mode family, confirming
#     rejection.
#
# Usage: ./run-tests.sh [--keep-going]
#   --keep-going: don't stop at the first failure (default: stop, matching
#   `set -e` style so a real regression is loud, not buried in a scroll
#   of subsequent output).
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$HERE/../../.." && pwd)"
QEMU="$REPO_ROOT/work/qemu-aspeed-hace-fix/qemu-11.1.1/build/qemu-system-arm"
VECTORS="$HERE/test-vectors"
WORK="$HERE/work/run-tests"
TIMEOUT=30
KEEP_GOING=0
[ "${1:-}" = "--keep-going" ] && KEEP_GOING=1

if [ ! -x "$QEMU" ]; then
    echo "ERROR: patched qemu-system-arm not found at $QEMU" >&2
    echo "  Run '$REPO_ROOT/scripts/build-patched-qemu.sh' first." >&2
    exit 1
fi

mkdir -p "$WORK"
cd "$HERE"
echo "Building all diagnostics..."
make all otp_test.bin header_test.bin bignum_test.bin verify_test.bin \
    rsa_test.bin sha512_test.bin aes_test.bin aes_decrypt_test.bin \
    scu_test.bin boot_gate_test.bin \
    >"$WORK/build.log" 2>&1 || { echo "BUILD FAILED, see $WORK/build.log" >&2; exit 1; }

PASS=0
FAIL=0
FAILED_NAMES=()

record() {  # record <name> <ok:0|1>
    if [ "$2" -eq 0 ]; then
        PASS=$((PASS + 1))
        echo "  PASS  $1"
    else
        FAIL=$((FAIL + 1))
        FAILED_NAMES+=("$1")
        echo "  FAIL  $1"
        [ "$KEEP_GOING" -eq 1 ] || { echo "Stopping at first failure (pass --keep-going to continue). See $WORK for logs."; print_summary; exit 1; }
    fi
}

print_summary() {
    echo
    echo "=== $PASS passed, $FAIL failed ==="
    if [ "$FAIL" -gt 0 ]; then
        printf '  %s\n' "${FAILED_NAMES[@]}"
    fi
}

assemble_otp_flat() {  # assemble_otp_flat <data.bin> <conf.bin> <out.bin>
    truncate -s 16384 "$3"
    dd if="$1" of="$3" conv=notrunc status=none
    dd if="$2" of="$3" bs=1 seek=8192 conv=notrunc status=none
}

pad_image() {  # pad_image <src> <out> -- zero-pads to the w25q512jv's full 64 MiB
    cp "$1" "$2"
    truncate -s 67108864 "$2"
}

corrupt_byte() {  # corrupt_byte <file> <offset> -- overwrites with a differing byte
    local file=$1 offset=$2
    local orig new
    orig=$(od -An -tu1 -j "$offset" -N1 "$file" | tr -d ' ')
    new=$(((orig + 1) % 256))
    printf "$(printf '\\x%02x' "$new")" | dd of="$file" bs=1 seek="$offset" conv=notrunc status=none
}

run_diag() {  # run_diag <bios.bin> <drive-file> <otp-flat> <log-out> [machine]
    local machine="${5:-ast2600-evb-secureboot}"
    "$QEMU" -machine "$machine" -m 1G \
        -bios "$1" \
        -drive file="$2",if=mtd,format=raw \
        -blockdev driver=file,filename="$3",node-name=otp \
        -global aspeed-otp.drive=otp \
        -net nic -net user -serial stdio -serial null -display none \
        >"$4" 2>&1 &
    local pid=$!
    ( sleep "$TIMEOUT"; kill "$pid" 2>/dev/null ) &
    local killer=$!
    wait "$pid" 2>/dev/null
    kill "$killer" 2>/dev/null
    wait "$killer" 2>/dev/null
}

hex_bytes_to_hex() {  # normalizes uart_put_hex32's "0x000000aa 0x000000bb
    # ..." (stdin, one zero-extended 32-bit word per byte) to "aabb..." --
    # the byte value is the LAST 2 hex digits of each 8-digit word, not
    # the first 2 (a real bug here once printed "00" for every byte,
    # since a naive `0x[0-9a-f]{2}` pattern matches the leading zeros).
    tr -s ' ' '\n' | command grep -oE '0x[0-9a-f]{8}' | sed -E 's/^0x[0-9a-f]{6}//' | tr -d '\n'
}

# --- 1. socsec reference-vector matrix: mode2 (no AES) ---
echo
echo "=== mode2 (RSA+SHA, no AES): $VECTORS/2600-a3_mode2-*-big ==="
for d in "$VECTORS"/2600-a3_mode2-*-big; do
    [ -d "$d" ] || continue
    name=$(basename "$d")
    out="$WORK/$name"
    mkdir -p "$out"
    assemble_otp_flat "$d/otp-data.bin" "$d/otp-conf.bin" "$out/otp-flat.bin"
    pad_image "$d/bl1.signed.bin" "$out/bl1.padded.bin"
    run_diag verify_test.bin "$out/bl1.padded.bin" "$out/otp-flat.bin" "$out/verify.log"
    if command grep -q "^result=OK" "$out/verify.log"; then
        record "$name (positive)" 0
    else
        record "$name (positive)" 1
    fi
done

# One negative test for this family: corrupt a copy, expect BAD_SIGNATURE.
neg_src="$VECTORS/2600-a3_mode2-rsa2048-sha256-big"
if [ -d "$neg_src" ]; then
    out="$WORK/2600-a3_mode2-rsa2048-sha256-big-neg"
    mkdir -p "$out"
    assemble_otp_flat "$neg_src/otp-data.bin" "$neg_src/otp-conf.bin" "$out/otp-flat.bin"
    pad_image "$neg_src/bl1.signed.bin" "$out/bl1.padded.bin"
    corrupt_byte "$out/bl1.padded.bin" 1024
    run_diag verify_test.bin "$out/bl1.padded.bin" "$out/otp-flat.bin" "$out/verify.log"
    if command grep -q "^result=BAD_SIGNATURE" "$out/verify.log"; then
        record "mode2 negative (corrupted signature rejected)" 0
    else
        record "mode2 negative (corrupted signature rejected)" 1
    fi
fi

# --- 2/3. socsec reference-vector matrix: mode2aes1 and mode2aes2 (AES) ---
for aesmode in mode2aes1 mode2aes2; do
    echo
    echo "=== $aesmode: $VECTORS/2600-a3_${aesmode}-*-big ==="
    for d in "$VECTORS"/2600-a3_${aesmode}-*-big; do
        [ -d "$d" ] || continue
        name=$(basename "$d")
        out="$WORK/$name"
        mkdir -p "$out"
        assemble_otp_flat "$d/otp-data.bin" "$d/otp-conf.bin" "$out/otp-flat.bin"
        pad_image "$d/bl1.signed.bin" "$out/bl1.padded.bin"
        run_diag aes_decrypt_test.bin "$out/bl1.padded.bin" "$out/otp-flat.bin" "$out/decrypt.log"

        line=$(command grep "^enc_offset=" "$out/decrypt.log" || true)
        if [ -z "$line" ]; then
            record "$name (decrypt)" 1
            continue
        fi
        enc_offset=$((16#$(echo "$line" | command grep -oE 'enc_offset=0x[0-9a-f]+' | cut -d'x' -f2)))
        dec_len=$((16#$(echo "$line" | command grep -oE 'dec_len=0x[0-9a-f]+' | cut -d'x' -f2)))
        got=$(command grep "^decrypted_sha512=" "$out/decrypt.log" | hex_bytes_to_hex)
        expected=$(dd if="$d/bl1.bin" bs=1 skip="$enc_offset" count="$dec_len" status=none | sha512sum | cut -d' ' -f1)

        if [ "$got" = "$expected" ]; then
            record "$name (decrypt matches real plaintext)" 0
        else
            record "$name (decrypt matches real plaintext)" 1
        fi
    done

    # One negative test per AES mode: corrupt a copy, expect BAD_SIGNATURE
    # (rejected before the -- for mode2aes2, heavier -- decrypt is ever attempted).
    neg_src="$VECTORS/2600-a3_${aesmode}-rsa2048-sha256-big"
    if [ -d "$neg_src" ]; then
        out="$WORK/2600-a3_${aesmode}-rsa2048-sha256-big-neg"
        mkdir -p "$out"
        assemble_otp_flat "$neg_src/otp-data.bin" "$neg_src/otp-conf.bin" "$out/otp-flat.bin"
        pad_image "$neg_src/bl1.signed.bin" "$out/bl1.padded.bin"
        corrupt_byte "$out/bl1.padded.bin" 1536
        run_diag aes_decrypt_test.bin "$out/bl1.padded.bin" "$out/otp-flat.bin" "$out/decrypt.log"
        if command grep -q "verify FAILED, result=0x00000002" "$out/decrypt.log"; then
            record "$aesmode negative (corrupted signature rejected)" 0
        else
            record "$aesmode negative (corrupted signature rejected)" 1
        fi
    fi
done

# --- 4. Self-generated COT-suffixed BL1 image ---
echo
echo "=== COT-suffixed BL1 (self-generated, no A3-big vector exists) ==="
if [ -x "$HERE/gen-cot-image.sh" ]; then
    cot_out="$WORK/cot"
    mkdir -p "$cot_out"
    if "$HERE/gen-cot-image.sh" "$cot_out" >"$cot_out/gen.log" 2>&1; then
        pad_image "$cot_out/bl1.cot.signed.bin" "$cot_out/bl1.padded.bin"
        # gen-cot-image.sh signs with THIS LAB's own real key, so it
        # needs this lab's own real otp-on image (gen-lab-otp-image.sh),
        # not a test-vectors/ OTP -- skip gracefully if that hasn't been
        # generated in this checkout yet.
        lab_otp="$HERE/work/otp-on/otp-flat.bin"
        if [ -f "$lab_otp" ]; then
            run_diag verify_test.bin "$cot_out/bl1.padded.bin" "$lab_otp" "$cot_out/verify.log"
            if command grep -q "^result=OK" "$cot_out/verify.log"; then
                record "COT-suffixed BL1 (positive)" 0
            else
                record "COT-suffixed BL1 (positive)" 1
            fi
        else
            echo "  SKIP  COT-suffixed BL1 (run gen-lab-otp-image.sh first)"
        fi
    else
        echo "  SKIP  COT-suffixed BL1 (gen-cot-image.sh failed, see $cot_out/gen.log)"
    fi
else
    echo "  SKIP  gen-cot-image.sh not found or not executable"
fi

# --- 5. Self-generated rsa1024/sha224 image (no A3-big vector exists for
# either) ---
echo
echo "=== rsa1024/sha224 (self-generated, no A3-big vector exists) ==="
if [ -x "$HERE/gen-rsa1024-sha224-image.sh" ]; then
    r1024_out="$WORK/rsa1024-sha224"
    mkdir -p "$r1024_out"
    if "$HERE/gen-rsa1024-sha224-image.sh" "$r1024_out" >"$r1024_out/gen.log" 2>&1; then
        pad_image "$r1024_out/bl1.rsa1024-sha224.signed.bin" "$r1024_out/bl1.padded.bin"
        run_diag verify_test.bin "$r1024_out/bl1.padded.bin" "$r1024_out/otp-flat.bin" "$r1024_out/verify.log"
        if command grep -q "^result=OK" "$r1024_out/verify.log"; then
            record "rsa1024/sha224 (positive)" 0
        else
            record "rsa1024/sha224 (positive)" 1
        fi

        cp "$r1024_out/bl1.padded.bin" "$r1024_out/bl1.corrupt.bin"
        corrupt_byte "$r1024_out/bl1.corrupt.bin" 768
        run_diag verify_test.bin "$r1024_out/bl1.corrupt.bin" "$r1024_out/otp-flat.bin" "$r1024_out/verify_neg.log"
        if command grep -q "^result=BAD_SIGNATURE" "$r1024_out/verify_neg.log"; then
            record "rsa1024/sha224 negative (corrupted signature rejected)" 0
        else
            record "rsa1024/sha224 negative (corrupted signature rejected)" 1
        fi
    else
        echo "  SKIP  rsa1024/sha224 (gen-rsa1024-sha224-image.sh failed, see $r1024_out/gen.log)"
    fi
else
    echo "  SKIP  gen-rsa1024-sha224-image.sh not found or not executable"
fi

# --- 6. OTP-enable AND hw-strap gate (boot.c) -- both bits must agree to
# enable verification, per real silicon's own AND-of-both-bits semantics.
# Needs this lab's own real OTP image (gen-lab-otp-image.sh -- the only
# config here with "Enable Secure Boot" actually set; none of the
# socsec-shipped test-vectors/ fixtures set it, they rely on otp_strap
# instead, which QEMU never loads automatically -- see otp.c's own
# comment). Uses boot_gate_test.bin (calls boot_main() directly) against
# BOTH machine types (ast2600-evb-secureboot: strap on by default;
# ast2600-evb-secureboot-strapoff: strap off) -- no real bootable SPL
# image needed, just whether the gate opens at all (boot_gate_test.c's
# own comment explains why a mismatched image is fine for this). ---
echo
echo "=== OTP-enable AND hw-strap gate (boot.c) ==="
lab_otp="$HERE/work/otp-on/otp-flat.bin"
gate_image="$WORK/rsa1024-sha224/bl1.padded.bin"
if [ ! -f "$lab_otp" ]; then
    echo "  SKIP  (run ./gen-lab-otp-image.sh first)"
elif [ ! -f "$gate_image" ]; then
    echo "  SKIP  (run ./gen-rsa1024-sha224-image.sh first -- reused here only as"
    echo "         *some* signed image for boot_main() to look at; it doesn't need"
    echo "         to match the OTP key, see boot_gate_test.c's own comment)"
else
    out="$WORK/strap-gate"
    mkdir -p "$out"

    run_diag boot_gate_test.bin "$gate_image" "$lab_otp" "$out/on.log" ast2600-evb-secureboot
    if command grep -q "ast2600 vboot: secure boot enabled, verifying SPL" "$out/on.log"; then
        record "strap gate: strap on + config on -> gate opens" 0
    else
        record "strap gate: strap on + config on -> gate opens" 1
    fi

    run_diag boot_gate_test.bin "$gate_image" "$lab_otp" "$out/off.log" ast2600-evb-secureboot-strapoff
    if command grep -q "ast2600 vboot" "$out/off.log"; then
        record "strap gate: strap off + config on -> gate stays closed" 1
    else
        record "strap gate: strap off + config on -> gate stays closed" 0
    fi
fi

# --- 7. This lab's own real signed SPL + real OTP key ---
echo
echo "=== This lab's own real signed SPL + real OTP key ==="
LAB_MTD="$REPO_ROOT/work/obmc-phosphor-image-evb-ast2600-secureboot.static.mtd"
LAB_OTP="$HERE/work/otp-on/otp-flat.bin"
if [ ! -f "$LAB_OTP" ]; then
    echo "  SKIP  (run ./gen-lab-otp-image.sh first)"
elif [ ! -f "$LAB_MTD" ]; then
    echo "  SKIP  (need work/obmc-phosphor-image-evb-ast2600-secureboot.static.mtd --"
    echo "         run './scripts/build-image.sh --secureboot' and boot it once via"
    echo "         run-qemu.sh to populate work/, or copy it in by hand)"
else
    out="$WORK/lab-own-key"
    mkdir -p "$out"
    run_diag verify_test.bin "$LAB_MTD" "$LAB_OTP" "$out/verify.log"
    if command grep -q "^result=OK" "$out/verify.log"; then
        record "this lab's own key (positive)" 0
    else
        record "this lab's own key (positive)" 1
    fi

    cp "$LAB_MTD" "$out/corrupt.mtd"
    corrupt_byte "$out/corrupt.mtd" 4096
    run_diag verify_test.bin "$out/corrupt.mtd" "$LAB_OTP" "$out/verify_neg.log"
    if command grep -q "^result=BAD_SIGNATURE" "$out/verify_neg.log"; then
        record "this lab's own key negative (corrupted signature rejected)" 0
    else
        record "this lab's own key negative (corrupted signature rejected)" 1
    fi
fi

print_summary
[ "$FAIL" -eq 0 ]
