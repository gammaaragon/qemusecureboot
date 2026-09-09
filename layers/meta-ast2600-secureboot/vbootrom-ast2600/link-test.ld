/* SPDX-License-Identifier: MIT */
/*
 * Linker script for the otp_test diagnostic build only. Unlike link.ld
 * (used by the real stage-1/2 boot flow), this program never copies
 * anything over itself and never jumps away -- it just reads the OTP
 * and prints, then halts -- so there's no self-overwrite hazard and no
 * need to split .reset from the rest: everything can live at 0x0.
 */
ENTRY(_start)

SECTIONS
{
	. = 0x00000000;
	.text : { *(.text) }
	.rodata : { *(.rodata*) }
	.data : { *(.data*) }
	.bss : { *(.bss*) }

	/DISCARD/ : {
		*(.comment)
		*(.note.*)
		*(.ARM.attributes)
	}
}
