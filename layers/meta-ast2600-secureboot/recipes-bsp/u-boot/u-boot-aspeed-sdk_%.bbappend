# SPDX-License-Identifier: MIT
FILESEXTRAPATHS:prepend := "${THISDIR}/${PN}:"

# =====================================================================
# Layers 2 & 3: SPL -> U-Boot-proper, and U-Boot-proper -> kernel FIT.
# Both are software-verified FIT signatures (uboot-sign.bbclass /
# kernel-fit-image.bbclass from oe-core). ast2600_openbmc_spl_defconfig
# already ships CONFIG_SPL_FIT_SIGNATURE=y and CONFIG_FIT_SIGNATURE=y --
# this is a pure recipe-variable toggle, no U-Boot config changes needed.
#
# The actual UBOOT_SIGN_ENABLE/FIT_HASH_ALG/etc. variables live in
# ../../../conf/layer.conf, not here -- the kernel FIT is assembled by a
# different recipe than this one, and bitbake gives every recipe its own
# isolated metadata, so a bbappend scoped to u-boot-aspeed-sdk can't
# reach the kernel recipe's build. See layer.conf's own comment for the
# full story (this was found the hard way: u-boot's own FIT came out
# signed, the kernel FIT stayed plain-hash, until these moved to global
# config).
#
# One demo RSA keypair (generated at build time by uboot-sign.bbclass's
# own do_uboot_generate_rsa_keys task, nothing private committed to git)
# drives both layers -- same pattern IBM's p10bmc uses in
# meta-ibm/recipes-bsp/u-boot/u-boot-aspeed-sdk_2019.04.bbappend.
#
# disable-aspeed-acry.cfg (2026-09-02): RSA *verification* hangs forever
# under QEMU regardless of the above -- root-caused via GDB to
# CONFIG_ASPEED_ACRY's hardware-accelerator driver polling a status
# register QEMU doesn't model. This .cfg fragment gets merged into
# U-Boot's .config automatically by the existing find_cfgs()/
# merge_config.sh machinery in u-boot-configure.inc -- the same mechanism
# already merging u-boot_flash_64M.cfg, nothing new to wire up. See the
# fragment's own comment and notes/2026-09-01-01-secure-boot-fit-and-otp-signing.md
# for the full evidence chain.
# =====================================================================
DEPENDS += "openssl-native"

SRC_URI += "file://disable-aspeed-acry.cfg"

# See the patch's own commit message for the full story: QEMU's aspeed_hace
# model expects SG mode disabled for the finishing hash trigger, and this
# driver never does that. Confirmed both halves independently: a locally
# patched QEMU (fixing a real out-of-bounds read in has_padding(), also
# reported upstream and fixed in QEMU git as 534a52755b/c6aa2d0ac1, neither
# yet in a tagged release) stops the crash but still verifies the kernel
# FIT incorrectly ("Bad Data Hash") without this u-boot-side patch too.
SRC_URI += "file://0001-crypto-aspeed_hace-send-final-hash-trigger-without-.patch"

# Tried and REVERTED (2026-09-02): a disable-aspeed-hace.cfg fragment
# (# CONFIG_ASPEED_HACE / SHA_HW_ACCEL / SHA_PROG_HW_ACCEL is not set),
# same mechanism as disable-aspeed-acry.cfg above, to test whether QEMU's
# HACE hash-accelerator model is the cause of the layer-3 SIGSEGV. This
# recipe has only ONE shared .config for both SPL and full U-Boot
# (UBOOT_MACHINE = a single defconfig, no UBOOT_CONFIG multi-target
# indexing -- see evb-ast2600.conf), and find_cfgs() has no way to scope a
# fragment to only one of the two -- so disabling HACE also disabled it for
# SPL, and software SHA-512's larger code size overflowed SPL's fixed
# "flash" link region by 7016 bytes (do_compile failure, not a runtime
# result). Source-level analysis (aspeed_hace.c, both here and in QEMU's
# own hw/misc/aspeed_hace.c) instead points at the SG-descriptor length
# encoding (HACE_SG_LAST = BIT(31), tested as a single top byte == 0x80 --
# matches the crash instruction found under GDB, cmpb $0x80,(%rax,%r10,1))
# as the more likely fault, present identically regardless of
# CONFIG_SHA_PROG_HW_ACCEL since hw_sha512()'s one-shot path
# (CONFIG_SHA_HW_ACCEL alone) uses the same 2-entry SG list via
# sha_digest(). See notes/2026-09-01-01-secure-boot-fit-and-otp-signing.md
# for the full chain -- this remains an open, documented issue, not fixed.

# =====================================================================
# Layer 1: ROM -> SPL, ASPEED's real hardware root-of-trust tooling.
# Off by default on every OpenBMC board (see evb-ast2600.conf's own
# comment).
#
# evb-ast2600-secureboot-otp-{off,on}.json are adapted from
# meta-ibm/recipes-bsp/u-boot/u-boot-aspeed-sdk/p10bmc/ibm.json -- IBM
# p10bmc's real, working OTP config, the one board in this tree that
# turns SOCSEC_SIGN_ENABLE on. config_region/otp_strap are IBM's generic
# AST2600 hardware-strap values, reused as-is (except "Enable boot from
# eMMC" set false -- this board boots from SPI, not eMMC, unlike
# p10bmc); data_region.key points at this recipe's own already-bundled
# demo key instead of IBM's board-specific ones. The two files differ
# only in the "Enable Secure Boot" / "Enable secure boot" fields (off vs
# on) -- see the layer README for what that A/B comparison can and can't
# demonstrate under this QEMU version. otptool's own JSON schema is
# strict (top-level additionalProperties: false) so, unlike this
# .bbappend, these files can't carry a "why" comment field of their own.
#
# SOCSEC_SIGN_KEY is left at its recipe default
# (${UNPACKDIR}/rsa_oem_dss_key.pem, already fetched by the base recipe).
#
# Both JSON files set data_region.rsa_key_order = "big" explicitly. The
# recipe's own SOCSEC_SIGN_EXTRA_OPTS default already signs the SPL with
# --rsa_key_order=big, but otptool.py defaults rsa_key_order to "little"
# when the OTP config doesn't say -- leaving it unset here produced a
# genuinely signed SPL that then failed the recipe's own offline
# verify_spl_otp self-check ("Mode 2 verify failed"), because the OTP
# image and the signature disagreed on key byte order, not because the
# keys or the signature itself were wrong.
# =====================================================================
SOCSEC_SIGN_ENABLE = "1"

SRC_URI += " \
    file://evb-ast2600-secureboot-otp-off.json \
    file://evb-ast2600-secureboot-otp-on.json \
"

OTPTOOL_CONFIGS = "${UNPACKDIR}/evb-ast2600-secureboot-otp-off.json"
OTPTOOL_KEY_DIR = "${UNPACKDIR}"
