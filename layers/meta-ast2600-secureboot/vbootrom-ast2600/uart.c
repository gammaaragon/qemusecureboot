/* SPDX-License-Identifier: MIT */
#include "uart.h"
#include "io.h"

#define UART5_BASE 0x1E784000u

/* regshift=2: each register is 4 bytes apart */
#define UART_THR (UART5_BASE + (0 << 2)) /* transmit holding register */
#define UART_LSR (UART5_BASE + (5 << 2)) /* line status register */
#define UART_LSR_THRE 0x20u              /* transmit holding register empty */

void uart_init(void)
{
    /*
     * Deliberately no baud/LCR setup: QEMU's serial_mm model transmits
     * characters written to THR to its backing chardev regardless of
     * divisor/LCR configuration, and SPL/U-Boot (running right after us)
     * do their own real UART init anyway. If this is ever run against
     * real silicon, this needs actual divisor-latch/LCR programming
     * first -- not done here, this is QEMU-only debug output.
     */
}

void uart_putc(char c)
{
    while (!(readl(UART_LSR) & UART_LSR_THRE)) {
    }
    writel(UART_THR, (unsigned int)(unsigned char)c);
}

void uart_puts(const char *s)
{
    while (*s) {
        if (*s == '\n') {
            uart_putc('\r');
        }
        uart_putc(*s++);
    }
}

void uart_put_hex32(unsigned int v)
{
    static const char hex[] = "0123456789abcdef";
    int i;

    uart_puts("0x");
    for (i = 28; i >= 0; i -= 4) {
        uart_putc(hex[(v >> i) & 0xf]);
    }
}
