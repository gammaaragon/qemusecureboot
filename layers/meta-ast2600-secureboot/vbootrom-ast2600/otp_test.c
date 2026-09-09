/* SPDX-License-Identifier: MIT */
/*
 * Diagnostic-only build: reads the OTP secure-boot config and the first
 * few words of the RSA public key modulus, prints everything over
 * UART5, then halts. No flash copying, no jump to SPL -- purely to
 * verify otp.c's register-level reads produce the correct values
 * against a real, tool-generated OTP image, before wiring this into
 * the actual boot flow. See notes/2026-09-03-03-vbootrom-ast2600-stage2.md
 * for the expected values this output should be checked against.
 */
#include "otp.h"
#include "uart.h"

void otp_test_main(void)
{
    struct otp_secure_boot_config cfg;
    unsigned int mod[4];
    unsigned int exp;
    int i;

    uart_init();
    uart_puts("\notp_test: reading secure boot config...\n");

    otp_read_secure_boot_config(&cfg);

    uart_puts("enabled=");
    uart_puts(cfg.enabled ? "1" : "0");
    uart_puts(" mode2=");
    uart_puts(cfg.mode2 ? "1" : "0");
    uart_puts(" rsa_len=");
    uart_put_hex32(cfg.rsa_len);
    uart_puts(" sha_mode=");
    uart_put_hex32(cfg.sha_mode);
    uart_puts(" header_offset=");
    uart_put_hex32(cfg.header_offset);
    uart_puts("\n");

    otp_read_rsa_pub_key(mod, 4, &exp);
    uart_puts("modulus[0..3]=");
    for (i = 0; i < 4; i++) {
        uart_put_hex32(mod[i]);
        uart_puts(" ");
    }
    uart_puts("\nexponent=");
    uart_put_hex32(exp);
    uart_puts("\n\notp_test: done\n");
}
