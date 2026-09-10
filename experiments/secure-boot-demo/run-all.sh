#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Runs all six secure-boot demonstration experiments (A/B/C/D1/D2/D3) and
# reports pass/fail -- same shape as
# layers/meta-ast2600-secureboot/vbootrom-ast2600/run-tests.sh's own
# record()/print_summary() pattern.
#
# Usage: ./run-all.sh [--keep-going]
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KEEP_GOING=0
[ "${1:-}" = "--keep-going" ] && KEEP_GOING=1

PASS=0
FAIL=0
SKIP=0
FAILED_NAMES=()

run_exp() {
    local name="$1" script="$2"
    echo
    echo "=== $name ==="
    "$HERE/$script"
    local rc=$?
    if [ "$rc" -eq 0 ]; then
        PASS=$((PASS + 1))
    elif [ "$rc" -eq 2 ]; then
        SKIP=$((SKIP + 1))
    else
        FAIL=$((FAIL + 1))
        FAILED_NAMES+=("$name")
        if [ "$KEEP_GOING" -ne 1 ]; then
            echo "Stopping at first failure (pass --keep-going to continue)."
            print_summary
            exit 1
        fi
    fi
}

print_summary() {
    echo
    echo "=== $PASS passed, $FAIL failed, $SKIP skipped ==="
    if [ "$FAIL" -gt 0 ]; then
        printf '  %s\n' "${FAILED_NAMES[@]}"
    fi
}

run_exp "A: stale hash (unsigned, corruption caught)"        exp-a-stale-hash.sh
run_exp "B: rehashed (unsigned, tamper undetected)"          exp-b-rehash.sh
run_exp "C: naive resign (signed, no private key -- caught)" exp-c-naive-resign.sh
run_exp "D1: key swap, stock machine (no anchor -- succeeds)" exp-d1-key-swap-stock-machine.sh
run_exp "D2: key swap, secureboot machine (anchored -- caught)" exp-d2-key-swap-secureboot-machine.sh
run_exp "D3: well-formed header, wrong key (BAD_SIGNATURE -- caught)" exp-d3-signed-header-wrong-key.sh

print_summary
[ "$FAIL" -eq 0 ]
