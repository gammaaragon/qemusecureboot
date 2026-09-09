/* SPDX-License-Identifier: MIT */
/*
 * Diagnostic-only build: computes SHA-512 over the real signed SPL's
 * image[0:sign_image_size] and prints the digest over UART, to
 * cross-check against an independent Python hashlib.sha512()
 * computation over the same real file -- isolating sha512.c from the
 * rest of verify_test's pipeline (already confirmed correct via
 * rsa_test.c and bignum_test.c).
 */
#include <stdint.h>
#include "header.h"
#include "sha512.h"
#include "uart.h"

#define FLASH_WINDOW_BASE 0x20000000u

void sha512_test_main(void)
{
    struct rot_header hdr;
    sha512_context sha;
    unsigned char digest[SHA512_SUM_LEN];
    unsigned int i;

    uart_init();
    uart_puts("\nsha512_test: hashing real image[0:sign_image_size]...\n");

    header_read(FLASH_WINDOW_BASE, ROT_HEADER_OFFSET, &hdr);
    uart_puts("sign_image_size=");
    uart_put_hex32(hdr.sign_image_size);
    uart_puts("\n");

    sha512_starts(&sha);
    sha512_update(&sha, (const unsigned char *)(uintptr_t)FLASH_WINDOW_BASE,
                  hdr.sign_image_size);
    sha512_finish(&sha, digest);

    uart_puts("digest=");
    for (i = 0; i < SHA512_SUM_LEN; i++) {
        uart_put_hex32(digest[i]);
        uart_puts(" ");
    }
    uart_puts("\n\nsha512_test: done\n");
}
