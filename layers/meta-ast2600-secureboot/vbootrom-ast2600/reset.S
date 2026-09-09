/* SPDX-License-Identifier: MIT */
/*
 * ast2600 vbootrom: reset stub.
 *
 * The linker places this at address 0x0 -- the AST2600 CPU's reset PC,
 * and also where SPL itself is linked to run (CONFIG_SPL_TEXT_BASE=0 in
 * u-boot-aspeed-sdk). Stage 2+ will overwrite this address with a
 * verified copy of the real SPL image, so this stub does the one thing
 * it needs to do -- jump into the real program, linked well above SPL's
 * landing zone (see link.ld, stage1.S) -- and nothing else. It must
 * never be re-entered or referenced again after that jump.
 */
.section .reset, "ax"
.global _reset
_reset:
	ldr	pc, =_start
