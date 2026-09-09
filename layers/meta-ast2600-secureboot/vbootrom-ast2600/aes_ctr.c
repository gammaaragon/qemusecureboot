/* SPDX-License-Identifier: MIT */
#include "aes_ctr.h"
#include "aes.h"
#include "libc_min.h"

/* Increments a 16-byte big-endian counter block by one, as one big
 * integer (carrying across the whole 128 bits, not just a 32-bit
 * low word) -- matches pycryptodome's Counter.new(128, ...) semantics,
 * which socsec.py relies on. */
static void counter_increment(uint8_t counter[16])
{
    int i;

    for (i = 15; i >= 0; i--) {
        if (++counter[i] != 0) {
            break;
        }
    }
}

void aes_ctr_crypt(const uint8_t *key, unsigned int key_words,
                   const uint8_t iv[16], const uint8_t *src, uint8_t *dst,
                   unsigned int len)
{
    uint8_t expkey[AES_MAX_EXPKEY_BYTES];
    unsigned int rounds;
    uint8_t counter[16];
    uint8_t keystream[16];
    unsigned int i, block_len;

    aes_expand_key(key, key_words, expkey, &rounds);
    memcpy(counter, iv, 16);

    while (len > 0) {
        block_len = len < 16 ? len : 16;

        aes_encrypt_block(counter, expkey, rounds, keystream);
        for (i = 0; i < block_len; i++) {
            dst[i] = src[i] ^ keystream[i];
        }

        counter_increment(counter);
        src += block_len;
        dst += block_len;
        len -= block_len;
    }
}
