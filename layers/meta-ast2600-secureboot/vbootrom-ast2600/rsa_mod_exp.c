/* SPDX-License-Identifier: GPL-2.0-or-later */
/*
 * RSA modular exponentiation, ported near-verbatim from U-Boot's
 * lib/rsa/rsa-mod-exp.c (SPDX-License-Identifier: GPL-2.0+, Copyright
 * 2013 Google Inc.) -- the exact Montgomery-ladder implementation this
 * lab's own SPL/U-Boot already use for layers 2/3's FIT verification,
 * proven correct under this QEMU. The actual math (subtract_modulus,
 * montgomery_mul*, pow_mod) is unmodified; only the FDT/host-tool
 * byteswap helpers were swapped for this project's own (this target is
 * little-endian, so fdt32/64_to_cpu here are plain byteswaps, not FDT
 * parsing) and debug()/malloc-only USE_HOSTCC branches removed (this is
 * always a target build, single fixed key size).
 */
#include "rsa.h"

static inline uint32_t fdt32_to_cpu(uint32_t x)
{
    return ((x & 0xff) << 24) | ((x & 0xff00) << 8) |
           ((x >> 8) & 0xff00) | ((x >> 24) & 0xff);
}

static inline uint64_t fdt64_to_cpu(uint64_t x)
{
    return ((uint64_t)fdt32_to_cpu((uint32_t)x) << 32) |
           fdt32_to_cpu((uint32_t)(x >> 32));
}

#define get_unaligned_be32(a) fdt32_to_cpu(*(uint32_t *)(a))
#define put_unaligned_be32(a, b) (*(uint32_t *)(b) = fdt32_to_cpu(a))

static void subtract_modulus(const struct rsa_public_key *key, uint32_t num[])
{
    int64_t acc = 0;
    unsigned int i;

    for (i = 0; i < key->len; i++) {
        acc += (uint64_t)num[i] - key->modulus[i];
        num[i] = (uint32_t)acc;
        acc >>= 32;
    }
}

static int greater_equal_modulus(const struct rsa_public_key *key, uint32_t num[])
{
    int i;

    for (i = (int)key->len - 1; i >= 0; i--) {
        if (num[i] < key->modulus[i]) {
            return 0;
        }
        if (num[i] > key->modulus[i]) {
            return 1;
        }
    }
    return 1;
}

static void montgomery_mul_add_step(const struct rsa_public_key *key,
                                    uint32_t result[], const uint32_t a,
                                    const uint32_t b[])
{
    uint64_t acc_a, acc_b;
    uint32_t d0;
    unsigned int i;

    acc_a = (uint64_t)a * b[0] + result[0];
    d0 = (uint32_t)acc_a * key->n0inv;
    acc_b = (uint64_t)d0 * key->modulus[0] + (uint32_t)acc_a;
    for (i = 1; i < key->len; i++) {
        acc_a = (acc_a >> 32) + (uint64_t)a * b[i] + result[i];
        acc_b = (acc_b >> 32) + (uint64_t)d0 * key->modulus[i] + (uint32_t)acc_a;
        result[i - 1] = (uint32_t)acc_b;
    }

    acc_a = (acc_a >> 32) + (acc_b >> 32);
    result[i - 1] = (uint32_t)acc_a;

    if (acc_a >> 32) {
        subtract_modulus(key, result);
    }
}

static void montgomery_mul(const struct rsa_public_key *key, uint32_t result[],
                           uint32_t a[], const uint32_t b[])
{
    unsigned int i;

    for (i = 0; i < key->len; ++i) {
        result[i] = 0;
    }
    for (i = 0; i < key->len; ++i) {
        montgomery_mul_add_step(key, result, a[i], b);
    }
}

/*
 * Generalized from a fixed uint64_t exponent (the original U-Boot
 * file's own version, adequate only for the small public exponent
 * 0x10001) to an arbitrary-width big-endian byte buffer -- see rsa.h's
 * own comment on struct rsa_public_key::exponent for why (mode2aes2's
 * full-width private exponent D, stage 3 slice 3.7). Finds the highest
 * set bit by skipping leading zero bytes, then scanning the first
 * nonzero byte -- same effective result as the original's u64 version
 * for a small exponent like 0x10001 (still finds bit 17 as the top
 * bit), just not limited to 64 bits.
 */
static int num_public_exponent_bits(const struct rsa_public_key *key, int *num_bits)
{
    unsigned int i;
    uint8_t b;
    int bits_in_byte;

    for (i = 0; i < key->exponent_len; i++) {
        if (key->exponent[i] != 0) {
            break;
        }
    }
    if (i == key->exponent_len) {
        *num_bits = 0;
        return 0;
    }

    b = key->exponent[i];
    bits_in_byte = 0;
    while (b) {
        bits_in_byte++;
        b >>= 1;
    }
    *num_bits = bits_in_byte + 8 * (int)(key->exponent_len - 1 - i);
    return 0;
}

/* pos counts from the LSB of the whole big-endian buffer (bit 0 is the
 * least-significant bit of the last byte), matching the original u64
 * version's (key->exponent & (1ULL << pos)) semantics exactly. */
static int is_public_exponent_bit_set(const struct rsa_public_key *key, int pos)
{
    unsigned int byte_from_end = (unsigned int)pos / 8;
    unsigned int bit_in_byte = (unsigned int)pos % 8;

    if (byte_from_end >= key->exponent_len) {
        return 0;
    }
    return (key->exponent[key->exponent_len - 1 - byte_from_end] &
           (1u << bit_in_byte)) != 0;
}

static int pow_mod(const struct rsa_public_key *key, uint32_t *inout)
{
    uint32_t *result, *ptr;
    unsigned int i;
    int j, k;

    if (key->len > RSA_MAX_KEY_BITS / 32) {
        return -1;
    }

    uint32_t val[key->len], acc[key->len], tmp[key->len];
    uint32_t a_scaled[key->len];
    result = tmp;

    for (i = 0, ptr = inout + key->len - 1; i < key->len; i++, ptr--) {
        val[i] = get_unaligned_be32(ptr);
    }

    if (num_public_exponent_bits(key, &k) != 0) {
        return -1;
    }
    if (k < 2) {
        return -1;
    }
    if (!is_public_exponent_bit_set(key, 0)) {
        return -1;
    }

    montgomery_mul(key, acc, val, key->rr);
    for (i = 0; i < key->len; i++) {
        a_scaled[i] = acc[i];
    }

    for (j = k - 2; j > 0; --j) {
        montgomery_mul(key, tmp, acc, acc);
        if (is_public_exponent_bit_set(key, j)) {
            montgomery_mul(key, acc, tmp, a_scaled);
        } else {
            for (i = 0; i < key->len; i++) {
                acc[i] = tmp[i];
            }
        }
    }

    montgomery_mul(key, tmp, acc, acc);
    montgomery_mul(key, acc, tmp, val);
    for (i = 0; i < key->len; i++) {
        result[i] = acc[i];
    }

    if (greater_equal_modulus(key, result)) {
        subtract_modulus(key, result);
    }

    for (i = key->len - 1, ptr = inout; (int)i >= 0; i--, ptr++) {
        put_unaligned_be32(result[i], ptr);
    }
    return 0;
}

static void rsa_convert_big_endian(uint32_t *dst, const uint32_t *src, int len)
{
    int i;

    for (i = 0; i < len; i++) {
        dst[i] = fdt32_to_cpu(src[len - 1 - i]);
    }
}

int rsa_mod_exp_sw(const uint8_t *sig, uint32_t sig_len, struct key_prop *prop,
                   uint8_t *out)
{
    struct rsa_public_key key;
    int ret;
    unsigned int i;

    if (!prop) {
        return -1;
    }
    key.n0inv = prop->n0inv;
    key.len = (unsigned int)prop->num_bits;

    if (!prop->public_exponent || !prop->exp_len) {
        /* Every real caller always sets both -- fail closed rather than
         * silently default to 65537 the way the original (fixed
         * public-exponent-only) version of this function did. */
        return -1;
    }
    key.exponent = (const uint8_t *)prop->public_exponent;
    key.exponent_len = prop->exp_len;

    if (!key.len || !prop->modulus || !prop->rr) {
        return -1;
    }
    if (key.len > RSA_MAX_KEY_BITS || key.len < RSA_MIN_KEY_BITS) {
        return -1;
    }
    key.len /= sizeof(uint32_t) * 8;

    uint32_t key1[key.len], key2[key.len];
    key.modulus = key1;
    key.rr = key2;
    rsa_convert_big_endian(key.modulus, (uint32_t *)prop->modulus, (int)key.len);
    rsa_convert_big_endian(key.rr, (uint32_t *)prop->rr, (int)key.len);

    uint32_t buf[sig_len / sizeof(uint32_t)];
    for (i = 0; i < sig_len; i++) {
        ((uint8_t *)buf)[i] = sig[i];
    }

    ret = pow_mod(&key, buf);
    if (ret) {
        return ret;
    }

    for (i = 0; i < sig_len; i++) {
        out[i] = ((uint8_t *)buf)[i];
    }
    return 0;
}
