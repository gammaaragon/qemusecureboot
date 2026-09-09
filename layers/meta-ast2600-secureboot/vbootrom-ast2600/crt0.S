/* SPDX-License-Identifier: MIT */
/*
 * Generic C runtime entry, linked at 0x0 (see link-test.ld). Sets up a
 * stack and calls into C. Shared by every standalone diagnostic build
 * (otp_test, header_test, bignum_test, ...) -- none of them copy or
 * jump anywhere, they just read something real, print it over UART,
 * and halt, so there's no self-overwrite hazard to design around here
 * (unlike stage1.S). Which C function to call is set per-target via
 * -DDIAG_ENTRY=<function> (see Makefile).
 *
 * AST2600 is dual-core: without the MPIDR check below, both CPUs ran
 * this same code from address 0x0 simultaneously and raced on the same
 * UART -- confirmed the hard way, as visibly interleaved/duplicated
 * output, before this was added. Only Aff0==0 (the primary CPU)
 * proceeds; the secondary CPU parks immediately.
 */
#ifndef DIAG_ENTRY
#define DIAG_ENTRY otp_test_main
#endif

.section .text, "ax"
.global _start
_start:
	mrc	p15, 0, r0, c0, c0, 5	/* MPIDR */
	and	r0, r0, #0xff		/* Aff0: CPU ID within cluster */
	cmp	r0, #0
	bne	park

	ldr	sp, =0x20000
	bl	DIAG_ENTRY
park:
	wfe
	b	park
