/* SPDX-License-Identifier: MIT */
/*
 * Minimal ns16550-compatible UART driver for AST2600 UART5
 * (0x1E784000 -- matches "serial@1e784000" in this lab's own boot logs,
 * the same UART SPL/U-Boot use). AST2600 UARTs are register-shift-2
 * (each register 4 bytes apart, not the classic 1-byte PC-16550 layout)
 * -- confirmed from QEMU's own device model
 * (hw/arm/aspeed_soc_common.c's aspeed_soc_uart_realize(),
 * qdev_prop_set_uint8(DEVICE(smm), "regshift", 2)), not assumed.
 */
#ifndef UART_H
#define UART_H

void uart_init(void);
void uart_putc(char c);
void uart_puts(const char *s);
void uart_put_hex32(unsigned int v);

#endif
