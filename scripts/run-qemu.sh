#!/bin/bash
# SPDX-License-Identifier: MIT
# Boots the golden evb-ast2600 image (base, lab, or secureboot variant)
# under qemu-system-arm from a disposable copy in work/, so the deploy
# artifact under ~/openbmc never gets mutated.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OPENBMC_ROOT="$HOME/openbmc"
WORK_DIR="$REPO_ROOT/work"
LOG_DIR="$WORK_DIR/logs"

VARIANT="base"
FRESH=0
INTERACTIVE=0
TIMEOUT_SECS=180
AUTOLOGIN=1

while [ $# -gt 0 ]; do
  case "$1" in
    --base) VARIANT="base" ;;
    --lab) VARIANT="lab" ;;
    --secureboot) VARIANT="secureboot" ;;
    --fresh) FRESH=1 ;;
    --interactive) INTERACTIVE=1 ;;
    --no-login) AUTOLOGIN=0 ;;
    --timeout)
      shift
      [ $# -gt 0 ] || { echo "ERROR: --timeout requires a value" >&2; exit 1; }
      TIMEOUT_SECS="$1"
      ;;
    *) echo "ERROR: unknown argument: $1 (expected --base, --lab, --secureboot, --fresh, --interactive, --no-login, --timeout N)" >&2; exit 1 ;;
  esac
  shift
done

case "$VARIANT" in
  base)       BUILD_DIR="$OPENBMC_ROOT/build/evb-ast2600" ;;
  lab)        BUILD_DIR="$OPENBMC_ROOT/build/evb-ast2600-lab" ;;
  secureboot) BUILD_DIR="$OPENBMC_ROOT/build/evb-ast2600-secureboot" ;;
esac
GOLDEN="$BUILD_DIR/tmp/deploy/images/evb-ast2600/obmc-phosphor-image-evb-ast2600.static.mtd"
CHECKSUM_FILE="$REPO_ROOT/scripts/golden-$VARIANT.sha256"
COPY="$WORK_DIR/obmc-phosphor-image-evb-ast2600-$VARIANT.static.mtd"

if [ ! -e "$GOLDEN" ]; then
  echo "ERROR: golden image not found at $GOLDEN" >&2
  echo "Build it first: ./scripts/build-image.sh --$VARIANT" >&2
  exit 1
fi

mkdir -p "$WORK_DIR" "$LOG_DIR"

if [ "$FRESH" -eq 1 ] || [ ! -e "$COPY" ] || [ "$GOLDEN" -nt "$COPY" ]; then
  if [ ! -e "$CHECKSUM_FILE" ]; then
    echo "ERROR: no recorded checksum at $CHECKSUM_FILE" >&2
    exit 1
  fi
  EXPECTED_SHA="$(awk '{print $1; exit}' "$CHECKSUM_FILE")"
  ACTUAL_SHA="$(sha256sum "$GOLDEN" | awk '{print $1}')"
  if [ "$ACTUAL_SHA" != "$EXPECTED_SHA" ]; then
    echo "ERROR: golden image checksum mismatch, refusing to boot it" >&2
    echo "  variant:  $VARIANT" >&2
    echo "  golden:   $GOLDEN" >&2
    echo "  expected: $EXPECTED_SHA" >&2
    echo "  actual:   $ACTUAL_SHA" >&2
    exit 1
  fi
  echo "Checksum OK ($ACTUAL_SHA)" >&2
  echo "Copying golden image -> $COPY" >&2
  cp "$GOLDEN" "$COPY"
  # cp inherits the golden file's mode (444) when creating a new destination
  # file; qemu needs to open the copy read-write, so force that back on.
  chmod u+w "$COPY"
fi

LOG_FILE="$LOG_DIR/$(date +%Y%m%d-%H%M%S)-$VARIANT.log"
echo "Console log -> $LOG_FILE" >&2

QEMU_BIN="qemu-system-arm"
if [ "$VARIANT" = "secureboot" ]; then
  # The system qemu-system-arm (8.2.2) has real bugs in its aspeed_hace
  # device model that make layer 3 (kernel-FIT signature verification)
  # either crash QEMU or silently compute the wrong hash -- see
  # scripts/build-patched-qemu.sh. Those bugs are gone as of upstream
  # QEMU 11.1.0, so build-patched-qemu.sh now builds plain upstream
  # 11.1.x instead of patching 8.2.2. Use that local build if it's
  # there; tell the user how to get it if not.
  PATCHED_QEMU="$WORK_DIR/qemu-aspeed-hace-fix/qemu-11.1.1/build/qemu-system-arm"
  if [ -x "$PATCHED_QEMU" ]; then
    QEMU_BIN="$PATCHED_QEMU"
  else
    echo "ERROR: secureboot variant needs a locally built qemu-system-arm >= 11.1.0" >&2
    echo "  (the system package crashes or mis-verifies the signed kernel FIT)." >&2
    echo "  Not found at: $PATCHED_QEMU" >&2
    echo "  Build it first: ./scripts/build-patched-qemu.sh" >&2
    exit 1
  fi
fi

QEMU_CMD=("$QEMU_BIN"
  -machine ast2600-evb -m 1G
  -drive file="$COPY",if=mtd,format=raw
  -net nic -net user,hostfwd=tcp:127.0.0.1:2222-:22,hostfwd=tcp:127.0.0.1:2443-:443
  -serial mon:stdio -serial null
)

# qemu-console.py owns the pty, the timeout, and the log file unconditionally
# (interactive or not) -- see its docstring for why the timeout can't just be
# the external `timeout` command wrapping this. Every byte the console
# produces, including anything typed by hand in --interactive mode and the
# BMC's echo of it, lands in LOG_FILE. AUTOLOGIN sends root/0penBmc the first
# time OpenBMC's login/password prompts appear; --no-login disables that.
LOGIN_NOTE="auto-login root/0penBmc"
[ "$AUTOLOGIN" -eq 1 ] || LOGIN_NOTE="auto-login disabled (--no-login)"

if [ "$INTERACTIVE" -eq 1 ]; then
  echo "Booting $COPY (interactive, no timeout; Ctrl-A X to quit; $LOGIN_NOTE)" >&2
  python3 "$REPO_ROOT/scripts/qemu-console.py" "$LOG_FILE" 1 0 "$AUTOLOGIN" "${QEMU_CMD[@]}"
else
  echo "Booting $COPY (timeout ${TIMEOUT_SECS}s; use --interactive to disable; $LOGIN_NOTE)" >&2
  python3 "$REPO_ROOT/scripts/qemu-console.py" "$LOG_FILE" 0 "$TIMEOUT_SECS" "$AUTOLOGIN" "${QEMU_CMD[@]}"
fi
