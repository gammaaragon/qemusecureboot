/* SPDX-License-Identifier: MIT */
/*
 * Diagnostic-only build: calls boot_main() directly and prints its
 * return value, to test the OTP-enable AND hw-strap AND-gate (boot.c)
 * in isolation -- that gate decision is the whole point of this
 * diagnostic, not whether the subsequent signature check itself passes.
 * Any correctly-formatted signed image + OTP pair is enough for this
 * (even a mismatched one -- if the gate opens, boot_main() prints
 * "verifying SPL..." before attempting verification either way; if it
 * doesn't open, boot_main() stays silent and returns 1 regardless of
 * what's in flash), so this needs no real bootable SPL image the way
 * ast2600_bootrom.bin's own full boot does.
 *
 * uart_init() is called unconditionally here, BEFORE boot_main(),
 * because boot_main() itself only calls it when the gate is open (by
 * design -- matching stage 1's original silent behavior when secure
 * boot is off) -- calling it first guarantees this diagnostic's own
 * message always gets printed regardless of which path boot_main()
 * takes.
 */
#include "uart.h"

extern int boot_main(void);

void boot_gate_test_main(void)
{
    int r;

    uart_init();
    uart_puts("\nboot_gate_test: calling boot_main()...\n");
    r = boot_main();
    uart_puts("boot_gate_test: boot_main() returned ");
    uart_puts(r ? "1" : "0");
    uart_puts("\n\nboot_gate_test: done\n");
}
