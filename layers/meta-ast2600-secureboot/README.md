<!-- SPDX-License-Identifier: MIT -->

meta-ast2600-secureboot
=======================

Turns on the AST2600's dormant secure-boot capability for the evb-ast2600
QEMU lab. Kept as its own layer/build variant (`--secureboot`) rather than
folded into `meta-ast2600-lab`, so the existing base-vs-lab hwmon comparison
stays untouched — see `../../CLAUDE.md`.

## The three trust layers

The real AST2600/OpenBMC boot chain has three independent signature checks
that can each be on or off. All three are **compiled into the firmware
already built for this board** — enabling them is a Yocto recipe-variable
change, not a rebuild-from-scratch:

1. **ROM → SPL** (hardware root of trust). ASPEED's own `socsec`/`otptool`
   tools sign the raw SPL binary and burn an OTP fuse image with the
   verification key. Gated by `SOCSEC_SIGN_ENABLE` (off by default on every
   OpenBMC board except IBM's `p10bmc` — see `evb-ast2600.conf`'s own
   comment, and `meta-ibm/recipes-bsp/u-boot/u-boot-aspeed-sdk/p10bmc/` for
   the one working reference this layer's OTP configs are adapted from).
   **This layer cannot be exercised at runtime under QEMU**: QEMU 8.2.2 has
   no boot-ROM emulation at all (`hw/arm/aspeed.c`'s `write_boot_rom` just
   copies flash offset 0 into memory and jumps there) and exposes no
   OTP device or property on the `ast2600-evb` machine whatsoever
   (`qemu-system-arm -machine ast2600-evb,help` lists none). The signed SPL
   and OTP image are real, verifiable build artifacts; there is simply
   nowhere in this emulator to plug them in.
2. **SPL → U-Boot proper**. U-Boot's own FIT-based verified boot
   (`uboot-sign.bbclass`, `SPL_SIGN_ENABLE` + `UBOOT_FITIMAGE_ENABLE`).
   `ast2600_openbmc_spl_defconfig` already ships `CONFIG_SPL_FIT_SIGNATURE=y`
   and `CONFIG_SPL_LOAD_FIT=y`. **Live and working under QEMU**: SPL's own
   RSA-4096/SHA-512 checks of the "uboot" and "fdt" FIT nodes really pass
   (`+ OK`) at boot.
3. **U-Boot proper → kernel/ramdisk/dtb**. The same FIT-signature mechanism
   one level up (`kernel-fit-image.bbclass`, `FIT_KERNEL_SIGN_ENABLE`,
   defaults to `UBOOT_SIGN_ENABLE`). `ast2600_openbmc_spl_defconfig` already
   ships `CONFIG_FIT_SIGNATURE=y`. This is the layer article 1 showed as
   hash-only (`Verifying Hash Integrity ... sha256+ OK`) — now a real
   signature check (`sha512,rsa4096:rsa_oem_fitimage_key+ OK`), also live
   and working under QEMU, kernel boots all the way to a login prompt.

Layers 2 and 3 are both driven by one `UBOOT_SIGN_ENABLE = "1"` plus a
generated-at-build-time RSA keypair (`do_generate_fit_signing_key`, never
committed to git). Layer 1 is driven separately by `SOCSEC_SIGN_ENABLE = "1"`
plus an OTP config JSON.

**Layers 2 and 3 need a locally patched `qemu-system-arm`**, not the
system package. QEMU 8.2.2 has real bugs in its `hw/misc/aspeed_hace.c`
device model (a genuine out-of-bounds read that crashes QEMU itself, plus
two further accumulate-mode reconstruction bugs that silently compute the
wrong hash once the crash is fixed) — none of this is specific to this
lab's config, just to real driver behavior this QEMU version was never
tested against. Fixes are in `qemu-patches/`; `scripts/build-patched-qemu.sh`
builds them into a QEMU kept entirely under `work/` (gitignored, never
touches the system package), and `scripts/run-qemu.sh --secureboot` uses
it automatically once built. See
`notes/2026-09-01-01-secure-boot-fit-and-otp-signing.md` for the full
evidence chain.

## Not upstream material

Same rationale as `meta-ast2600-lab`: lab/demo-specific configuration (a
throwaway signing key, an OTP config adapted for this board rather than a
real product), kept out of the pristine `~/openbmc` clone.
