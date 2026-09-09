/* SPDX-License-Identifier: MIT */
/*
 * ast2600 vbootrom linker script.
 *
 * The vbootrom memory region added by ast2600-lab's QEMU patch (see
 * layers/meta-ast2600-secureboot/qemu-patches/) is 0x4020000 (64 MiB +
 * 128 KiB) of plain RAM overlaid at address 0x0 -- sized to hold a full
 * copy of this lab's 64 MiB (w25q512jv) boot flash (not just SPL --
 * see the matching comment in the QEMU patch, hw/arm/aspeed.c, for why)
 * plus headroom for the real verify pipeline's code and stack (its call
 * chain needs several KiB of stack; RSA modexp's pow_mod() alone uses
 * ~2 KiB for its 128-word arrays at RSA4096). .reset (the one
 * instruction that must run at 0x0 before anything is copied) is kept
 * there; everything else -- boot_start.S's entry point and every C
 * file's normal .text/.rodata/.data/.bss -- starts at 0x4000000, right
 * after the full 64 MiB copy destination ends, so nothing here is ever
 * touched by the copy loop no matter how much of that range gets
 * overwritten. Stack pointer is set (in boot_start.S) to the very top
 * of the region, 0x4020000.
 */
ENTRY(_reset)

/*
 * No MEMORY/region ("> VBOOTROM") placement here deliberately: mixing
 * named memory regions with explicit ". = ADDR" reassignment does not
 * do what it looks like -- a region's own fill pointer advances
 * independently of ".", so a later section silently landed right after
 * an earlier one instead of where "." pointed the first time this was
 * tried, even though the map file showed the "." assignment being
 * evaluated correctly just before it. Plain "." assignments avoid that
 * trap.
 */
SECTIONS
{
	. = 0x00000000;
	.reset : {
		*(.reset)
	}

	. = 0x04000000;
	.text : {
		*(.text)
		*(.text.*)
	}
	.rodata : {
		*(.rodata)
		*(.rodata.*)
	}
	.data : {
		*(.data)
		*(.data.*)
	}
	.bss : {
		*(.bss)
		*(.bss.*)
		*(COMMON)
	}

	/DISCARD/ : {
		*(.comment)
		*(.note.*)
		*(.ARM.attributes)
	}
}
