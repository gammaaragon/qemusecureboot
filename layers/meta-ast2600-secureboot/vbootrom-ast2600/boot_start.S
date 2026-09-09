/* SPDX-License-Identifier: MIT */
/*
 * The real boot flow's entry point -- supersedes stage1.S now that
 * verification (verify.c/boot.c) exists. Linked at 0x4000000 (see
 * link.ld), same placement discipline stage1.S used and for the same
 * reason: safely above the full-flash copy destination [0x0,
 * 0x4000000), so this code (and everything boot_main()/
 * boot_copy_and_prepare() call, all linked into this same region) is
 * never touched by the copy no matter how much of that range gets
 * overwritten. reset.S's _reset (at address 0x0, SPL's own link
 * address) jumps straight here before anything is copied.
 *
 * AST2600 is dual-core -- same MPIDR/CPU-park fix as every other
 * boot-code entry point in this project (see crt0.S's own comment for
 * how this was found).
 */
.section .text, "ax"
.global _start
_start:
	mrc	p15, 0, r0, c0, c0, 5	/* MPIDR */
	and	r0, r0, #0xff		/* Aff0: CPU ID within cluster */
	cmp	r0, #0
	bne	park

	ldr	sp, =0x04020000		/* top of the vbootrom region */
	bl	boot_main		/* r0 = 1: verified/not required, proceed
					 * r0 = 0: verification failed, halt */
	cmp	r0, #0
	beq	park

	bl	boot_copy_and_prepare
	mov	pc, #0			/* jump to the now-copied SPL at 0x0 */

park:
	wfe
	b	park
