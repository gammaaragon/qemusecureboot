/* SPDX-License-Identifier: GPL-2.0-or-later */
/*
 * PKCS#1 v1.5 signature padding check, trimmed from U-Boot's
 * lib/rsa/rsa-verify.c (SPDX-License-Identifier: GPL-2.0+) --
 * rsa_verify_padding()/padding_pkcs_15_verify() with the
 * struct checksum_algo/struct image_sign_info indirection removed. The
 * padding-byte logic itself (0x00 0x01 0xFF...0xFF 0x00 <digest>, no
 * DER prefix -- see pkcs15.c's own comment for why not) is unchanged;
 * generalized from a fixed SHA-512-only digest length to any length,
 * for stage 3's broader SHA-mode coverage (224/256/384/512) -- the
 * padding shape itself doesn't depend on which hash produced the
 * digest, only its length, so this is a parameterization, not a scheme
 * change.
 */
#ifndef PKCS15_H
#define PKCS15_H
#include <stdint.h>

/* msg is the RSA-decrypted signature block (sig_len bytes, e.g. 512 for
 * RSA4096). hash is the digest to check it against, hash_len bytes
 * (28/32/48/64 for SHA-224/256/384/512). Returns 1 if the padding and
 * digest both check out, 0 otherwise. */
int pkcs15_verify(const uint8_t *msg, unsigned int msg_len,
                  const uint8_t *hash, unsigned int hash_len);

#endif
