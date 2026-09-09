# SPDX-License-Identifier: MIT
# Shared functions for the secure-boot demonstration experiments
# (exp-a/b/c/d1/d2.sh, run-all.sh). Sourced, not executed directly.
#
# Conventions mirrored from elsewhere in this repo rather than
# reinvented: golden-image checksum verification and QEMU-binary
# selection copy scripts/run-qemu.sh's own logic; the timeout-kill QEMU
# boot pattern copies layers/meta-ast2600-secureboot/vbootrom-ast2600/
# run-tests.sh's own run_diag(). Never touch
# work/obmc-phosphor-image-evb-ast2600-<variant>.static.mtd (that's
# run-qemu.sh's own managed copy) -- every experiment gets its own flash
# copy under this directory's own work/.

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$HERE/.." && cd .. && pwd)"
OPENBMC_ROOT="$HOME/openbmc"
WORK="$HERE/work"

LAB_BUILD="$OPENBMC_ROOT/build/evb-ast2600-lab"
SB_BUILD="$OPENBMC_ROOT/build/evb-ast2600-secureboot"
LAB_DEPLOY="$LAB_BUILD/tmp/deploy/images/evb-ast2600"
SB_DEPLOY="$SB_BUILD/tmp/deploy/images/evb-ast2600"

MKIMAGE="$SB_BUILD/tmp/sysroots-components/x86_64/u-boot-tools-native/usr/bin/mkimage"
DUMPIMAGE="$SB_BUILD/tmp/sysroots-components/x86_64/u-boot-tools-native/usr/bin/dumpimage"
FDTPUT="$SB_BUILD/tmp/sysroots-components/x86_64/dtc-native/usr/bin/fdtput"

SYS_QEMU="qemu-system-arm"
PATCHED_QEMU="$REPO_ROOT/work/qemu-aspeed-hace-fix/qemu-11.1.1/build/qemu-system-arm"

VBOOTROM_DIR="$REPO_ROOT/layers/meta-ast2600-secureboot/vbootrom-ast2600"

for tool in "$MKIMAGE" "$DUMPIMAGE" "$FDTPUT"; do
    if [ ! -x "$tool" ]; then
        echo "ERROR: required tool not found or not executable: $tool" >&2
        echo "  Run './scripts/build-image.sh --secureboot' at least once first." >&2
        exit 1
    fi
done

# mkimage -f shells out to `dtc` (device tree compiler) to compile the
# .its source -- not on PATH by default, only in dtc-native's own
# sysroot alongside fdtput.
export PATH="$(dirname "$FDTPUT"):$PATH"

mkdir -p "$WORK"

# golden_image_path <variant>  (base|lab|secureboot)
golden_image_path() {
    local build_dir
    case "$1" in
        base)       build_dir="$OPENBMC_ROOT/build/evb-ast2600" ;;
        lab)        build_dir="$LAB_BUILD" ;;
        secureboot) build_dir="$SB_BUILD" ;;
        *) echo "ERROR: unknown variant '$1'" >&2; return 1 ;;
    esac
    echo "$build_dir/tmp/deploy/images/evb-ast2600/obmc-phosphor-image-evb-ast2600.static.mtd"
}

# make_flash_copy <variant> <dest-file>  -- checksum-verified copy of the
# real golden deploy image, writable, distinct from run-qemu.sh's own
# managed work/ copy.
make_flash_copy() {
    local variant="$1" dest="$2"
    local golden checksum_file expected actual

    golden="$(golden_image_path "$variant")"
    checksum_file="$REPO_ROOT/scripts/golden-$variant.sha256"

    if [ ! -e "$golden" ]; then
        echo "ERROR: golden image not found at $golden" >&2
        echo "  Build it first: ./scripts/build-image.sh --$variant" >&2
        return 1
    fi
    if [ ! -e "$checksum_file" ]; then
        echo "ERROR: no recorded checksum at $checksum_file" >&2
        return 1
    fi
    expected="$(awk '{print $1; exit}' "$checksum_file")"
    actual="$(sha256sum "$golden" | awk '{print $1}')"
    if [ "$actual" != "$expected" ]; then
        echo "ERROR: golden image checksum mismatch for $variant, refusing to use it" >&2
        echo "  expected: $expected" >&2
        echo "  actual:   $actual" >&2
        return 1
    fi

    mkdir -p "$(dirname "$dest")"
    cp "$golden" "$dest"
    chmod u+w "$dest"
}

# splice <flash-file> <region-file> <byte-offset>
splice() {
    local flash="$1" region="$2" offset="$3"
    dd if="$region" of="$flash" bs=1 seek="$offset" conv=notrunc status=none
}

# qemu_boot <machine> <qemu-binary> <flash-file> <log-file> <timeout-secs> [extra qemu args...]
#
# Same background-process-plus-sleep-killer shape as
# vbootrom-ast2600/run-tests.sh's own run_diag() -- a killed qemu can
# never be left orphaned regardless of how the diagnostic itself exits.
qemu_boot() {
    local machine="$1" qemu_bin="$2" flash="$3" log="$4" timeout_secs="$5"
    shift 5

    "$qemu_bin" -machine "$machine" -m 1G \
        -drive file="$flash",if=mtd,format=raw \
        -net nic -net user \
        -serial stdio -serial null -display none \
        "$@" \
        >"$log" 2>&1 &
    local pid=$!
    ( sleep "$timeout_secs"; kill "$pid" 2>/dev/null ) &
    local killer=$!
    wait "$pid" 2>/dev/null || true
    kill "$killer" 2>/dev/null || true
    wait "$killer" 2>/dev/null || true
}
