/* SPDX-License-Identifier: MIT */
/*
 * Diagnostic-only build: computes n0inv and RR mod N for the real OTP
 * key and prints them over UART, to cross-check against an independent
 * Python computation (e.g. `pow`/modular-inverse in a REPL) before
 * trusting bignum.c in the real verify pipeline.
 */
#include "bignum.h"
#include "otp.h"
#include "uart.h"

#define RSA4096_WORDS 128

void bignum_test_main(void)
{
    unsigned int mod[RSA4096_WORDS];
    unsigned int rr[RSA4096_WORDS];
    unsigned int exp;
    unsigned int canon_mod[RSA4096_WORDS];
    unsigned int n0inv;

    uart_init();
    uart_puts("\nbignum_test: reading real OTP key...\n");

    otp_read_rsa_pub_key(mod, RSA4096_WORDS, &exp);

    bignum_reverse_byteswap(canon_mod, mod, RSA4096_WORDS);
    n0inv = bignum_compute_n0inv(canon_mod[0]);

    uart_puts("n0inv=");
    uart_put_hex32(n0inv);
    uart_puts("\n");

    bignum_compute_rr(mod, rr, RSA4096_WORDS);

    /* RR printed as a big-endian byte stream (word 0 = MSW, matching
     * how the Python cross-check printed it) -- first and last 16
     * bytes only, enough to confirm against the independent check. */
    uart_puts("RR first 4 words (MSW-first)=");
    uart_put_hex32(rr[0]);
    uart_puts(" ");
    uart_put_hex32(rr[1]);
    uart_puts(" ");
    uart_put_hex32(rr[2]);
    uart_puts(" ");
    uart_put_hex32(rr[3]);
    uart_puts("\nRR last 4 words=");
    uart_put_hex32(rr[RSA4096_WORDS - 4]);
    uart_puts(" ");
    uart_put_hex32(rr[RSA4096_WORDS - 3]);
    uart_puts(" ");
    uart_put_hex32(rr[RSA4096_WORDS - 2]);
    uart_puts(" ");
    uart_put_hex32(rr[RSA4096_WORDS - 1]);
    uart_puts("\n\nbignum_test: done\n");
}
