#!/bin/bash
# SPDX-License-Identifier: MIT
# Builds qemu-system-arm from upstream source, patched, for the
# --secureboot variant and the experimental vbootrom-ast2600 work.
#
# History: QEMU 8.2.2 (the version Ubuntu 24.04 packages) had real bugs
# in its hw/misc/aspeed_hace.c device model that made it impossible to
# boot --secureboot with layer 3 (kernel-FIT signature verification)
# turned on -- as of QEMU 11.1.0 they're gone upstream, structurally
# eliminated by a rewrite, not just patched over. No patch is carried for
# them here any more.
#
# What's patched now, for a different reason: a new "ast2600-evb-secureboot"
# machine type (layers/meta-ast2600-secureboot/qemu-patches/0001-...patch),
# adding a virtual-boot-ROM hook for AST2600 that doesn't exist upstream --
# see layers/meta-ast2600-secureboot/vbootrom-ast2600/. This new machine
# type is opt-in (amc->vbootrom) and doesn't touch the existing
# "ast2600-evb" machine's own boot path at all, so this same patched
# binary still serves --secureboot exactly as an unpatched one would --
# confirmed by regression-testing --secureboot against it, not just by
# reading the diff.
#
# CONFIG_ASPEED_ACRY's register-polling hang (see layer.conf) is unrelated
# to any of this and is still not modeled in QEMU 11.1.1 -- the
# disable-aspeed-acry.cfg workaround in the u-boot-aspeed-sdk .bbappend is
# still required regardless of QEMU version.
#
# None of this touches the system qemu-system-arm package. The built
# binary lives entirely under work/ (gitignored) and is used only when
# scripts/run-qemu.sh --secureboot finds it there.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
QEMU_VERSION="11.1.1"
BUILD_ROOT="$REPO_ROOT/work/qemu-aspeed-hace-fix"
SRC_DIR="$BUILD_ROOT/qemu-$QEMU_VERSION"
PATCH_DIR="$REPO_ROOT/layers/meta-ast2600-secureboot/qemu-patches"
TARBALL="$BUILD_ROOT/qemu-$QEMU_VERSION.tar.xz"
BINARY="$SRC_DIR/build/qemu-system-arm"

if [ -x "$BINARY" ]; then
  echo "Already built: $BINARY" >&2
  echo "Delete it (or the whole $BUILD_ROOT directory) to force a rebuild." >&2
  exit 0
fi

for tool in ninja meson curl; do
  command -v "$tool" >/dev/null 2>&1 || {
    echo "ERROR: $tool not found." >&2
    echo "  sudo apt install -y ninja-build meson libglib2.0-dev libpixman-1-dev libfdt-dev flex bison python3-venv libslirp-dev" >&2
    exit 1
  }
done

mkdir -p "$BUILD_ROOT"

if [ ! -e "$TARBALL" ]; then
  echo "Downloading QEMU $QEMU_VERSION source..." >&2
  curl -fsSL "https://download.qemu.org/qemu-$QEMU_VERSION.tar.xz" -o "$TARBALL"
fi

if [ ! -d "$SRC_DIR" ]; then
  echo "Extracting..." >&2
  tar xf "$TARBALL" -C "$BUILD_ROOT"

  echo "Applying local patches..." >&2
  (cd "$SRC_DIR" && for p in "$PATCH_DIR"/*.patch; do
    echo "  $(basename "$p")" >&2
    patch -p1 < "$p"
  done)
fi

echo "Configuring (arm-softmmu only)..." >&2
mkdir -p "$SRC_DIR/build"
(cd "$SRC_DIR/build" && ../configure --target-list=arm-softmmu --disable-docs --disable-tools)

echo "Building (this takes a few minutes)..." >&2
(cd "$SRC_DIR/build" && ninja -j2 qemu-system-arm)

echo "Built: $BINARY" >&2
"$BINARY" --version
