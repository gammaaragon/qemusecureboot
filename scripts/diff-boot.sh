#!/bin/bash
# SPDX-License-Identifier: MIT
# Boots base and lab in turn, normalizes their console logs (strips ANSI
# color codes, kernel uptime timestamps, random MAC addresses, and other
# per-boot-random IDs), and diffs the result.
#
# The diff is taken on SORTED normalized output, not raw sequential order.
# Verified empirically (two separate boots of the *same* base image) that
# Linux's async device probing and systemd's parallel unit
# startup reorder ~190 lines of boot output between any two boots,
# identical image or not — a sequential diff is mostly measuring that
# jitter, not anything meta-ast2600-lab did. Sorting cancels reordering and
# leaves only genuine content differences (added/removed lines) in the
# diff; the unsorted per-boot logs are still saved in work/diffs/ if you
# want to eyeball real ordering.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK_DIR="$REPO_ROOT/work"
DIFF_DIR="$WORK_DIR/diffs"
TIMEOUT_SECS=180

while [ $# -gt 0 ]; do
  case "$1" in
    --timeout)
      shift
      [ $# -gt 0 ] || { echo "ERROR: --timeout requires a value" >&2; exit 1; }
      TIMEOUT_SECS="$1"
      ;;
    *) echo "ERROR: unknown argument: $1 (expected --timeout N)" >&2; exit 1 ;;
  esac
  shift
done

mkdir -p "$DIFF_DIR"

boot_and_capture() {
  local variant="$1"
  local raw
  raw="$(mktemp)"
  echo "Booting $variant (timeout ${TIMEOUT_SECS}s)..." >&2
  "$REPO_ROOT/scripts/run-qemu.sh" "--$variant" --fresh --timeout "$TIMEOUT_SECS" < /dev/null > "$raw" 2>&1 || true
  local logfile
  logfile="$(grep -oE 'Console log -> .*' "$raw" | sed 's/^Console log -> //')"
  rm -f "$raw"
  if [ -z "$logfile" ] || [ ! -e "$logfile" ]; then
    echo "ERROR: could not find a console log for the $variant boot (run-qemu.sh failed before booting?)" >&2
    exit 1
  fi
  echo "$logfile"
}

normalize() {
  perl -ne '
    next if /A start job is running for/;             # systemd TTY progress spinner: redrawn N times with a live elapsed-time countdown, not boot content
    s/\x1b\[[\x30-\x3f]*[\x20-\x2f]*[\x40-\x7e]//g;   # ANSI CSI, full param/intermediate/final byte ranges (color/cursor/DECSTR/etc.)
    s/\x1b\][^\x07\x1b]*(\x07|\x1b\\)//g;             # OSC ... ST/BEL (carries start=/machineid=/bootid=/pid=/pidfdid=/invocationid=)
    s/\x1bP[^\x1b]*\x1b\\//g;                         # DCS ... ST
    s/\x1b[0-9A-Za-z]//g;                             # bare 2-byte escapes (e.g. ESC M reverse-index)
    s/\r//g;                                           # CR (terminal same-line-redraw control)
    s/^\[\s*\d+\.\d+\]/[TIMESTAMP]/;                  # kernel uptime
    s/mapped at [0-9a-fA-F]{8}/mapped at IRQHASH/g;   # kernel randomizes this per-boot debug hash
    s/systemd-journald\[\d+\]/systemd-journald[PID]/g; # journald forks at a variable point, variable pid
    s/notice: \(\d+\) jffs2_build_xattr_subsystem/notice: (N) jffs2_build_xattr_subsystem/; # jffs2 summary-node counter, varies per image build not per boot
    s/[0-9a-fA-F]{2}(:[0-9a-fA-F]{2}){5}/MACADDR/g;   # MAC addresses
    s/\b[0-9a-fA-F]{32}\b/HEXID32/g;                  # any leftover 32-hex id
    print;
  ' "$1"
}

BASE_LOG="$(boot_and_capture base)"
LAB_LOG="$(boot_and_capture lab)"

echo "base console log: $BASE_LOG" >&2
echo "lab console log:  $LAB_LOG" >&2

BASE_NORM="$DIFF_DIR/$(basename "$BASE_LOG" .log).normalized"
LAB_NORM="$DIFF_DIR/$(basename "$LAB_LOG" .log).normalized"
normalize "$BASE_LOG" > "$BASE_NORM"
normalize "$LAB_LOG" > "$LAB_NORM"

DIFF_FILE="$DIFF_DIR/$(date +%Y%m%d-%H%M%S)-base-vs-lab.diff"
if diff <(sort "$BASE_NORM") <(sort "$LAB_NORM") > "$DIFF_FILE"; then
  echo "No differences after normalization." | tee "$DIFF_FILE" >&2
else
  echo "Differences found (sorted, order-independent), written to $DIFF_FILE:" >&2
fi
echo "---"
cat "$DIFF_FILE"
