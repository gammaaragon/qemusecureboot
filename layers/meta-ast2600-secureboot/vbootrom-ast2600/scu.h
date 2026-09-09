/* SPDX-License-Identifier: MIT */
/*
 * ASPEED AST2600 SCU (System Control Unit) hardware-strap register.
 *
 * Real AST2600 gates ROM-level secure boot on TWO bits: the OTP
 * config-region "Enable Secure Boot" bit (otp.c) AND a separate
 * hardware-strap bit of the same name -- real silicon loads OTP-stored
 * strap content into this SCU register at reset. QEMU's own
 * hw/nvram/aspeed_otp.c and hw/misc/aspeed_sbc.c device models never do
 * that (confirmed: no "strap" string appears in either file) -- under
 * QEMU, hw-strap1 is only ever the machine class's own fixed default
 * (bit 0 set for ast2600-evb-secureboot specifically, see
 * qemu-patches/0002-...-default-secure-boot-strap-bit-for-ast.patch) or
 * an explicit `-global aspeed.scu-ast2600.hw-strap1=` override. Address
 * and register offset confirmed against QEMU 11.1.1's own device model
 * (hw/misc/aspeed_scu.c: AST2600_HW_STRAP1 at TO_REG(0x500), SCU base
 * 0x1E6E2000 -- hw/arm/aspeed_ast2600.c) and independently against
 * vendored U-Boot's own platform.h (ASPEED_HW_STRAP1 0x1e6e2500) --
 * both agree, not just one source.
 */
#ifndef SCU_H
#define SCU_H

/* Bit 0 of hw-strap1: "Enable secure boot" -- confirmed against
 * socsec's own otp_info schema (a1_strap.json, bit_offset 0, the schema
 * this lab's A3 config actually uses per socsec/__init__.py's SoC
 * table). */
#define SCU_HW_STRAP1_SECURE_BOOT_EN (1u << 0)

/* Returns 1 if the "Enable secure boot" hardware-strap bit is set,
 * 0 otherwise. A plain MMIO read -- NOT the SBC indirect
 * R_ADDR/R_CMD/R_STATUS/R_CAMP1 protocol otp.c uses for the OTP
 * config-region bit, since this register belongs to a different
 * peripheral (SCU) entirely. */
int scu_read_hw_strap_secure_boot(void);

#endif
