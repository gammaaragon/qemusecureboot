/* SPDX-License-Identifier: MIT */
/*
 * Diagnostic-only build: reads the raw SCU hw-strap1 register and the
 * decoded "Enable secure boot" bit, prints both over UART, then halts.
 * Cross-check target: boot with no override and confirm bit 0 is set
 * (this lab's own patched default, qemu-patches/0002-...patch) and
 * boot with `-global aspeed.scu-ast2600.hw-strap1=0` and confirm it
 * reads 0 -- proving the override path works too, before this is
 * trusted in the real boot_main() gate.
 */
#include "scu.h"
#include "io.h"
#include "uart.h"

#define SCU_HW_STRAP1 0x1E6E2500u

void scu_test_main(void)
{
    unsigned int raw = readl(SCU_HW_STRAP1);

    uart_init();
    uart_puts("\nscu_test: reading hw-strap1...\n");
    uart_puts("raw=");
    uart_put_hex32(raw);
    uart_puts(" secure_boot_strap=");
    uart_puts(scu_read_hw_strap_secure_boot() ? "1" : "0");
    uart_puts("\n\nscu_test: done\n");
}
