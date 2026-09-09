/* SPDX-License-Identifier: GPL-2.0-or-later */
/*
 * Trimmed from U-Boot's include/u-boot/rsa.h + include/u-boot/rsa-mod-exp.h
 * (SPDX-License-Identifier: GPL-2.0+) -- only the structs/constants
 * rsa_mod_exp.c actually needs, no FDT/driver-model/sign-side pieces
 * (this is a verify-only boot ROM, not U-Boot).
 */
#ifndef RSA_H
#define RSA_H
#include <stdint.h>

struct rsa_public_key {
    unsigned int len;   /* len of modulus[] in number of uint32_t */
    uint32_t n0inv;      /* -1 / modulus[0] mod 2^32 */
    uint32_t *modulus;   /* modulus as little endian array */
    uint32_t *rr;        /* R^2 as little endian array */
    /*
     * Exponent as a big-endian byte buffer, `exponent_len` bytes --
     * generalized from the original U-Boot file's fixed `uint64_t
     * exponent` (adequate only for the small, fixed public exponent
     * 0x10001 every RSA_OEM/RSA_SOC_PUB verify uses) to also cover
     * RSA_SOC_PRI's full-width private exponent D (up to `len` words
     * wide -- mode2aes2's RSA-unwrap step, stage 3 slice 3.7). Same
     * math either way (modular exponentiation doesn't care whether the
     * exponent is public or private) -- only how many bits of it
     * pow_mod() has to walk changes.
     */
    const uint8_t *exponent;
    unsigned int exponent_len;
};

struct key_prop {
    const void *rr;
    const void *modulus;
    const void *public_exponent; /* big-endian byte buffer, exp_len bytes long */
    uint32_t n0inv;
    int num_bits;
    uint32_t exp_len;             /* buffer length of public_exponent, in bytes */
};

/* OTP's rsa_len config code allows 1024 (code 0) -- see otp.h's own
 * comment -- so the floor here has to match, not the 2048 this file
 * started with (that was simply the only size this lab's own key ever
 * used, not a real hardware/algorithm limit). */
#define RSA_MIN_KEY_BITS 1024
#define RSA_MAX_KEY_BITS 4096
#define RSA4096_BYTES (4096 / 8)

int rsa_mod_exp_sw(const uint8_t *sig, uint32_t sig_len,
                   struct key_prop *prop, uint8_t *out);

#endif
