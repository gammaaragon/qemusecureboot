/* SPDX-License-Identifier: MIT */
/*
 * Computes the Montgomery constants (n0inv, R^2 mod N) that
 * rsa_mod_exp_sw() needs but doesn't compute itself -- normally a host
 * tool (mkimage) precomputes these once at image-build time and embeds
 * them in the FDT alongside the key. OTP only stores the raw modulus,
 * so this boot ROM has to compute them itself, at every verify. New
 * code, not extracted from U-Boot -- every output cross-checked against
 * an independent Python computation for this lab's real key before
 * being trusted. See notes/2026-09-03-05-vbootrom-ast2600-rsa-verify.md.
 */
#ifndef BIGNUM_H
#define BIGNUM_H
#include <stdint.h>

/* Reverses word order and byteswaps each word -- converts between the
 * "MSW-first, each word needs a byteswap" layout otp_read_rsa_pub_key()
 * (and rsa_mod_exp_sw()'s own prop->modulus/prop->rr inputs) use, and
 * the canonical "LSW-first, correct native values" layout big-number
 * arithmetic is naturally done in. Self-inverse: applying it twice is
 * the identity, so it converts in both directions with the same call. */
void bignum_reverse_byteswap(uint32_t *dst, const uint32_t *src, unsigned int len);

/* n0inv = -1/n0 mod 2^32, where n0 is the modulus's canonical
 * (already-byteswapped) least significant word. */
uint32_t bignum_compute_n0inv(uint32_t canonical_n0);

/* rr_be = R^2 mod N, where R = 2^(len*32) (e.g. 2^4096 for RSA4096).
 * mod_be and rr_be are both in otp_read_rsa_pub_key()'s native format
 * (MSW-first, needs-byteswap) -- matching what rsa_mod_exp_sw()'s own
 * prop->modulus/prop->rr expect, so both can be passed straight through
 * with no extra conversion at the call site. */
void bignum_compute_rr(const uint32_t *mod_be, uint32_t *rr_be, unsigned int len_words);

#endif
