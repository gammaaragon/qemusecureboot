/* SPDX-License-Identifier: MIT */
/*
 * Diagnostic-only build: runs the full verify pipeline against the real
 * signed SPL in flash and the real OTP key, prints the result over
 * UART, then halts. The decisive test for this whole stage -- every
 * other diagnostic checked one piece in isolation against an
 * independent computation; this one checks whether they compose into a
 * correct accept/reject decision. See
 * notes/2026-09-03-05-vbootrom-ast2600-rsa-verify.md.
 */
#include "verify.h"
#include "uart.h"

#define FLASH_WINDOW_BASE 0x20000000u

void verify_test_main(void)
{
    enum verify_result r;
    struct aes_decrypt_info aes_info;

    uart_init();
    uart_puts("\nverify_test: verifying real SPL against OTP key...\n");

    r = verify_image(FLASH_WINDOW_BASE, &aes_info);

    switch (r) {
    case VERIFY_OK:
        uart_puts("result=OK (signature valid)\n");
        uart_puts("encrypted=");
        uart_puts(aes_info.needed ? "1" : "0");
        uart_puts("\n");
        break;
    case VERIFY_BAD_CHECKSUM:
        uart_puts("result=BAD_CHECKSUM (header corrupted)\n");
        break;
    case VERIFY_BAD_SIGNATURE:
        /* Not necessarily SHA-512 specifically -- since stage 3's SHA
         * mode dispatch, this covers any of the RSA/SHA{224,256,384,512}
         * combinations verify_image() supports; the label stays generic
         * rather than naming one mode. */
        uart_puts("result=BAD_SIGNATURE (RSA/SHA check failed)\n");
        break;
    case VERIFY_UNSUPPORTED_ENC:
        uart_puts("result=UNSUPPORTED_ENC (encrypted, no usable key found)\n");
        break;
    default:
        uart_puts("result=UNKNOWN\n");
        break;
    }

    uart_puts("\nverify_test: done\n");
}
