/* SPDX-License-Identifier: MIT */
/*
 * Diagnostic-only build: checks aes.c's AES-256 block encrypt and
 * aes_ctr.c's CTR wrapper against known-answer vectors, prints
 * PASS/FAIL for each over UART, then halts. Two vectors, each
 * independently computed via pycryptodome (not from memory, not
 * derived from the code under test):
 *
 * 1. FIPS-197 Appendix C.3's own AES-256 single-block test vector
 *    (key = bytes 0x00..0x1f, plaintext = the well-known
 *    00112233...eeff pattern) -- checks aes_expand_key()/
 *    aes_encrypt_block() alone, independent of the CTR wrapper.
 * 2. A 40-byte (2 full blocks + one 8-byte partial block) CTR-mode
 *    check using the same key, with the initial counter deliberately
 *    chosen to roll over across all three blocks (0xff * 14, 0xff,
 *    0xfe -- so block 2's counter is all-0xff, and block 3's counter
 *    wraps all the way from all-0xff to all-0x00), to exercise
 *    aes_ctr_crypt()'s multi-byte carry-chain logic, not just a
 *    trivial low-byte increment. Cross-checked against pycryptodome's
 *    AES.MODE_CTR with the identical Counter.new(128, ...) semantics
 *    aes_ctr.h's own comment documents socsec.py as relying on.
 */
#include <stdint.h>
#include "aes.h"
#include "aes_ctr.h"
#include "uart.h"
#include "libc_min.h"

static void put_hex(const uint8_t *buf, unsigned int len)
{
    unsigned int i;

    for (i = 0; i < len; i++) {
        uart_put_hex32(buf[i]);
        uart_puts(" ");
    }
}

void aes_test_main(void)
{
    static const uint8_t key[32] = {
        0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07,
        0x08, 0x09, 0x0a, 0x0b, 0x0c, 0x0d, 0x0e, 0x0f,
        0x10, 0x11, 0x12, 0x13, 0x14, 0x15, 0x16, 0x17,
        0x18, 0x19, 0x1a, 0x1b, 0x1c, 0x1d, 0x1e, 0x1f,
    };
    static const uint8_t ecb_pt[16] = {
        0x00, 0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77,
        0x88, 0x99, 0xaa, 0xbb, 0xcc, 0xdd, 0xee, 0xff,
    };
    static const uint8_t ecb_expected[16] = {
        0x8e, 0xa2, 0xb7, 0xca, 0x51, 0x67, 0x45, 0xbf,
        0xea, 0xfc, 0x49, 0x90, 0x4b, 0x49, 0x60, 0x89,
    };
    static const uint8_t ctr_iv[16] = {
        0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
        0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xfe,
    };
    static const uint8_t ctr_pt[40] = {
        0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15,
        16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31,
        32, 33, 34, 35, 36, 37, 38, 39,
    };
    static const uint8_t ctr_expected[40] = {
        99, 228, 182, 1, 177, 27, 78, 218, 242, 228, 243, 213, 149, 193, 41, 75,
        249, 136, 246, 14, 88, 178, 102, 205, 75, 158, 11, 96, 65, 146, 73, 241,
        210, 177, 34, 149, 14, 108, 185, 247,
    };

    uint8_t expkey[AES_MAX_EXPKEY_BYTES];
    unsigned int rounds;
    uint8_t ecb_out[16];
    uint8_t ctr_out[40];

    uart_init();
    uart_puts("\naes_test: checking AES-256 against known-answer vectors...\n");

    aes_expand_key(key, 8, expkey, &rounds);
    aes_encrypt_block(ecb_pt, expkey, rounds, ecb_out);

    uart_puts("ecb: rounds=");
    uart_put_hex32(rounds);
    uart_puts("\n  got: ");
    put_hex(ecb_out, 16);
    uart_puts("\n  exp: ");
    put_hex(ecb_expected, 16);
    uart_puts("\n  ");
    uart_puts(memcmp(ecb_out, ecb_expected, 16) == 0 ? "PASS" : "FAIL");
    uart_puts("\n\n");

    aes_ctr_crypt(key, 8, ctr_iv, ctr_pt, ctr_out, sizeof(ctr_pt));

    uart_puts("ctr:\n  got: ");
    put_hex(ctr_out, sizeof(ctr_out));
    uart_puts("\n  exp: ");
    put_hex(ctr_expected, sizeof(ctr_expected));
    uart_puts("\n  ");
    uart_puts(memcmp(ctr_out, ctr_expected, sizeof(ctr_out)) == 0 ? "PASS" : "FAIL");
    uart_puts("\n\naes_test: done\n");
}
