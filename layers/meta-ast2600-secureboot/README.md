<!-- SPDX-License-Identifier: MIT -->

meta-ast2600-secureboot
=======================

Turns on the AST2600's dormant secure-boot capability for the evb-ast2600
QEMU lab. Kept as its own layer/build variant (`--secureboot`) rather than
folded into `meta-ast2600-lab`, so the existing base-vs-lab hwmon comparison
stays untouched — see the repo root `README.md`.

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
   **Exercisable at runtime under QEMU**: stock QEMU has no boot-ROM
   emulation for this SoC at all (`hw/arm/aspeed.c`'s `write_boot_rom` just
   copies flash offset 0 into memory and jumps there, and no AST2600
   machine exposes an OTP device), so this layer built its own —
   `vbootrom-ast2600/` (real RSA/SHA verification against an OTP-stored
   key, see that directory's own README) plus a new QEMU machine type,
   `ast2600-evb-secureboot` (added by `qemu-patches/`, below). A validly
   signed SPL boots through; a corrupted or wrongly-signed one halts
   before SPL ever runs.
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

**This variant needs a locally built `qemu-system-arm` (11.1.x)**, not
the distro package. The distro-packaged QEMU (8.2.2 on Ubuntu 24.04) had
real bugs in its `hw/misc/aspeed_hace.c` device model — a genuine
out-of-bounds read that crashed QEMU outright, plus two further
accumulate-mode reconstruction bugs that silently computed the wrong hash
once the crash was fixed — that made layer 3 (kernel-FIT verification)
unusable. Those bugs are **gone upstream as of QEMU 11.1.0/11.1.1**
(eliminated by a rewrite of that code, not patched around), so building
current upstream QEMU is enough on its own for layers 2/3; no patch is
carried for them any more.

`qemu-patches/` now carries two patches for a different, unrelated
reason: adding the `ast2600-evb-secureboot` machine type itself (layer 1's
vboot ROM hook, above) doesn't exist upstream at all. `0001-*.patch` adds
the machine type; `0002-*.patch` makes its secure-boot hardware strap
default on, matching this lab's OTP configuration, and adds a
`-strapoff` variant for the negative test case. Confirmed these two don't
touch layers 2/3's own boot path at all — regression-tested, not just
reasoned about.

`scripts/build-patched-qemu.sh` builds QEMU 11.1.x with these two patches
into a binary kept entirely under `work/` (gitignored, never touches the
system package); `scripts/run-qemu.sh --secureboot` uses it automatically
once built.

## Not upstream material

Same rationale as `meta-ast2600-lab`: lab/demo-specific configuration (a
throwaway signing key, an OTP config adapted for this board rather than a
real product), kept out of a pristine OpenBMC clone.
