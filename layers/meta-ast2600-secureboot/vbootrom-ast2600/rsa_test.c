/* SPDX-License-Identifier: MIT */
/*
 * Diagnostic-only build: isolates the RSA modexp step alone (real
 * signature, real key, real n0inv/rr) and prints the decrypted bytes
 * over UART, to cross-check against an independent Python
 * pow(sig, e, n) computation -- narrowing down verify_test's first
 * BAD_SIGNATURE result to whichever stage is actually wrong.
 */
#include <stdint.h>
#include "bignum.h"
#include "header.h"
#include "otp.h"
#include "rsa.h"
#include "uart.h"
#include "libc_min.h"

#define FLASH_WINDOW_BASE 0x20000000u
#define RSA4096_WORDS 128
#define RSA4096_SIG_BYTES 512

void rsa_test_main(void)
{
    struct rot_header hdr;
    unsigned int mod[RSA4096_WORDS];
    unsigned int rr[RSA4096_WORDS];
    unsigned int canon_mod[RSA4096_WORDS];
    unsigned int exp_unused;
    static const unsigned char exp_be[8] = {0, 0, 0, 0, 0, 1, 0, 1};
    struct key_prop prop;
    unsigned char sig[RSA4096_SIG_BYTES];
    unsigned char decrypted[RSA4096_SIG_BYTES];
    int ret;
    unsigned int i;

    uart_init();
    uart_puts("\nrsa_test: isolating RSA modexp...\n");

    header_read(FLASH_WINDOW_BASE, ROT_HEADER_OFFSET, &hdr);
    uart_puts("signature_offset=");
    uart_put_hex32(hdr.signature_offset);
    uart_puts("\n");

    otp_read_rsa_pub_key(mod, RSA4096_WORDS, &exp_unused);
    bignum_compute_rr(mod, rr, RSA4096_WORDS);
    bignum_reverse_byteswap(canon_mod, mod, RSA4096_WORDS);

    prop.rr = rr;
    prop.modulus = mod;
    prop.public_exponent = exp_be;
    prop.n0inv = bignum_compute_n0inv(canon_mod[0]);
    prop.num_bits = 4096;
    prop.exp_len = 3;

    uart_puts("n0inv=");
    uart_put_hex32(prop.n0inv);
    uart_puts("\n");

    memcpy(sig, (const void *)(uintptr_t)(FLASH_WINDOW_BASE + hdr.signature_offset),
          RSA4096_SIG_BYTES);

    uart_puts("sig[0..3]=");
    for (i = 0; i < 4; i++) {
        uart_put_hex32(sig[i]);
        uart_puts(" ");
    }
    uart_puts("\n");

    ret = rsa_mod_exp_sw(sig, RSA4096_SIG_BYTES, &prop, decrypted);
    uart_puts("rsa_mod_exp_sw ret=");
    uart_put_hex32((unsigned int)ret);
    uart_puts("\n");

    uart_puts("decrypted[0..15]=");
    for (i = 0; i < 16; i++) {
        uart_put_hex32(decrypted[i]);
        uart_puts(" ");
    }
    uart_puts("\ndecrypted[496..511]=");
    for (i = 496; i < 512; i++) {
        uart_put_hex32(decrypted[i]);
        uart_puts(" ");
    }
    /* boundary region: end of the 0xff padding run, the 0x00 separator,
     * and the start of the DER prefix -- expected (per pkcs15.c's own
     * arithmetic, pad_len=448, ff_len=426): decrypted[427]=last 0xff,
     * decrypted[428]=0x00, decrypted[429..447]=DER prefix. */
    uart_puts("\ndecrypted[425..450]=");
    for (i = 425; i <= 450; i++) {
        uart_put_hex32(decrypted[i]);
        uart_puts(" ");
    }
    uart_puts("\n\nrsa_test: done\n");
}
