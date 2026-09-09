/* SPDX-License-Identifier: MIT */
#include "bignum.h"

static inline uint32_t byteswap32(uint32_t x)
{
    return ((x & 0xffu) << 24) | ((x & 0xff00u) << 8) |
           ((x >> 8) & 0xff00u) | ((x >> 24) & 0xffu);
}

void bignum_reverse_byteswap(uint32_t *dst, const uint32_t *src, unsigned int len)
{
    unsigned int i;

    for (i = 0; i < len; i++) {
        dst[i] = byteswap32(src[len - 1 - i]);
    }
}

uint32_t bignum_compute_n0inv(uint32_t canonical_n0)
{
    /*
     * Newton's iteration for the inverse of an odd number mod 2^32.
     * For any odd x, x*x = 1 (mod 8) -- so x itself is already correct
     * to 3 bits. Each iteration of inv = inv*(2 - x*inv) doubles the
     * number of correct bits (all arithmetic mod 2^32 via natural
     * uint32_t wraparound): 3 -> 6 -> 12 -> 24 -> 48 (>=32, so exact in
     * 32-bit arithmetic after 4 iterations).
     */
    uint32_t inv = canonical_n0;
    int i;

    for (i = 0; i < 4; i++) {
        inv = inv * (2u - canonical_n0 * inv);
    }
    return (uint32_t)(0u - inv);
}

static int ge(const uint32_t *a, const uint32_t *mod, unsigned int len)
{
    int i;

    for (i = (int)len - 1; i >= 0; i--) {
        if (a[i] < mod[i]) {
            return 0;
        }
        if (a[i] > mod[i]) {
            return 1;
        }
    }
    return 1; /* equal */
}

void bignum_compute_rr(const uint32_t *mod_be, uint32_t *rr_be, unsigned int len_words)
{
    uint32_t canon_mod[len_words];
    uint32_t val[len_words + 1]; /* one extra word: doubling a value < N
                                   * can produce up to 2N-1, which needs
                                   * at most 1 more bit than N's own
                                   * len_words*32 bits -- see the notes
                                   * entry for why an earlier
                                   * carry-flag-only version of this
                                   * was wrong and got replaced with
                                   * this simpler, safe extra-word
                                   * approach instead. */
    unsigned int i, bit, total_bits = len_words * 32;

    bignum_reverse_byteswap(canon_mod, mod_be, len_words);

    for (i = 0; i <= len_words; i++) {
        val[i] = 0;
    }
    val[0] = 1; /* start at 2^0 */

    for (bit = 0; bit < 2 * total_bits; bit++) {
        uint32_t carry = 0;

        for (i = 0; i <= len_words; i++) {
            uint32_t next_carry = val[i] >> 31;

            val[i] = (val[i] << 1) | carry;
            carry = next_carry;
        }

        if (val[len_words] != 0 || ge(val, canon_mod, len_words)) {
            int64_t acc = 0;

            for (i = 0; i < len_words; i++) {
                acc += (int64_t)val[i] - canon_mod[i];
                val[i] = (uint32_t)acc;
                acc >>= 32;
            }
            acc += val[len_words];
            val[len_words] = (uint32_t)acc;
        }
    }

    /* val[len_words] must be back to 0 here -- val was always < N
     * (< 2^total_bits) going into each iteration, so after one doubling
     * and at most one subtraction it's < N again. */
    bignum_reverse_byteswap(rr_be, val, len_words);
}
