#!/bin/bash
# SPDX-License-Identifier: MIT
# Builds obmc-phosphor-image for evb-ast2600: stock (--base), with
# meta-ast2600-lab added (--lab, hwmon/lm75), or with
# meta-ast2600-secureboot added (--secureboot, dormant FIT/OTP signing
# turned on). Never edits ~/openbmc's tracked layer tree: each non-base
# variant gets its own build directory (build/evb-ast2600-<variant>),
# sharing downloads/sstate-cache with the base build dir instead of
# duplicating them.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OPENBMC_ROOT="$HOME/openbmc"
LAB_LAYER="$REPO_ROOT/layers/meta-ast2600-lab"
SECUREBOOT_LAYER="$REPO_ROOT/layers/meta-ast2600-secureboot"
BASE_BUILD_DIR="$OPENBMC_ROOT/build/evb-ast2600"
LAB_BUILD_DIR="$OPENBMC_ROOT/build/evb-ast2600-lab"
SECUREBOOT_BUILD_DIR="$OPENBMC_ROOT/build/evb-ast2600-secureboot"
TARGET="obmc-phosphor-image"

VARIANT=""
for arg in "$@"; do
  case "$arg" in
    --base) VARIANT="base" ;;
    --lab) VARIANT="lab" ;;
    --secureboot) VARIANT="secureboot" ;;
    *) echo "ERROR: unknown argument: $arg (expected --base, --lab, or --secureboot)" >&2; exit 1 ;;
  esac
done
if [ -z "$VARIANT" ]; then
  echo "ERROR: pass --base, --lab, or --secureboot" >&2
  exit 1
fi

if [ ! -d "$BASE_BUILD_DIR/conf" ]; then
  echo "ERROR: base build dir not found at $BASE_BUILD_DIR" >&2
  echo "Set it up first: cd ~/openbmc && . setup evb-ast2600" >&2
  exit 1
fi

case "$VARIANT" in
  base) BUILD_DIR="$BASE_BUILD_DIR" ;;
  lab) BUILD_DIR="$LAB_BUILD_DIR" ;;
  secureboot) BUILD_DIR="$SECUREBOOT_BUILD_DIR" ;;
esac

if [ "$VARIANT" != "base" ] && [ ! -d "$BUILD_DIR/conf" ]; then
  echo "Creating $VARIANT build dir at $BUILD_DIR" >&2
  mkdir -p "$BUILD_DIR/conf"
  cp "$BASE_BUILD_DIR/conf/local.conf" "$BUILD_DIR/conf/local.conf"
  cp "$BASE_BUILD_DIR/conf/bblayers.conf" "$BUILD_DIR/conf/bblayers.conf"
  cat >> "$BUILD_DIR/conf/local.conf" <<EOF

# Share downloads/sstate with the base build dir instead of duplicating them
DL_DIR = "$BASE_BUILD_DIR/downloads"
SSTATE_DIR = "$BASE_BUILD_DIR/sstate-cache"
EOF
fi

echo "Build dir: $BUILD_DIR" >&2
cd "$OPENBMC_ROOT"
set +u
source oe-init-build-env "$BUILD_DIR" >/dev/null
set -u

if [ "$VARIANT" = "lab" ]; then
  if ! bitbake-layers show-layers | grep -qF "$LAB_LAYER"; then
    echo "Adding $LAB_LAYER to $BUILD_DIR/conf/bblayers.conf" >&2
    bitbake-layers add-layer "$LAB_LAYER"
  fi
elif [ "$VARIANT" = "secureboot" ]; then
  if ! bitbake-layers show-layers | grep -qF "$SECUREBOOT_LAYER"; then
    echo "Adding $SECUREBOOT_LAYER to $BUILD_DIR/conf/bblayers.conf" >&2
    bitbake-layers add-layer "$SECUREBOOT_LAYER"
  fi
fi

bitbake "$TARGET"

DEPLOY_DIR="$BUILD_DIR/tmp/deploy/images/evb-ast2600"
IMAGE="$DEPLOY_DIR/obmc-phosphor-image-evb-ast2600.static.mtd"
echo "Built: $(readlink -f "$IMAGE")" >&2
sha256sum "$IMAGE" >&2
