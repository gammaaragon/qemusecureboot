/* SPDX-License-Identifier: GPL-2.0-or-later */
/*
 * AES encryption (block cipher only -- no decrypt, no mode wrapper),
 * generalized from U-Boot's lib/aes.c (SPDX-License-Identifier:
 * GPL-2.0+, Copyright (C) 2011 The Chromium OS Authors / NVIDIA
 * Corporation, original AES core by Karl Malbrain, public domain --
 * see aes.c's own comment) for AES-128/192/256 instead of that file's
 * hardcoded AES-128-only constants.
 *
 * That file's algorithm -- the S-box tables, shift_rows/mix_sub_columns/
 * add_round_key, and aes_expand_key()'s key-schedule logic -- is
 * already Nk/Nr-generic (it has an explicit branch for AES-256's extra
 * key-schedule S-box step, `AES_KEYCOLS > 6` in the original); only its
 * `enum` constants fixed it to AES-128 (10 rounds, 4-word key). This
 * file takes key length and round count as runtime parameters instead.
 * This lab's own AES key (OTP's `aes_oem` entry) is 32 bytes -- AES-256 --
 * confirmed against the real key size in socsec's own test fixtures,
 * not assumed from the original AES-128-only file.
 *
 * Encrypt-only: this project only ever uses AES as a CTR-mode keystream
 * generator (see aes_ctr.h), which never calls the decrypt direction --
 * so inv_sbox/inv_shift_rows/inv_mix_sub_columns/aes_decrypt (all
 * present in the original file) are deliberately not ported at all,
 * rather than carried along unused and untested.
 */
#ifndef AES_H
#define AES_H

#include <stdint.h>

#define AES_BLOCK_BYTES 16u

/* AES-256 is the largest key size this project needs (this lab's own
 * aes_oem key) -- sized generously in case that ever changes, since the
 * key schedule itself is already generic over any of the three sizes. */
#define AES_MAX_KEY_WORDS 8u                       /* AES-256 */
#define AES_MAX_ROUNDS 14u                          /* AES-256: Nk + 6 */
#define AES_MAX_EXPKEY_BYTES (4u * 4u * (AES_MAX_ROUNDS + 1u)) /* 240 */

/* Expands `key` (key_words * 4 bytes -- 4/6/8 words for AES-128/192/256)
 * into `expkey` (caller-provided, must have room for
 * AES_MAX_EXPKEY_BYTES bytes -- only 4*4*(rounds+1) of it is actually
 * used for a given key size). rounds_out receives the round count this
 * key size needs (key_words + 6, the standard AES relation -- 10/12/14
 * for 128/192/256), which the caller must pass back into
 * aes_encrypt_block(). */
void aes_expand_key(const uint8_t *key, unsigned int key_words,
                    uint8_t *expkey, unsigned int *rounds_out);

/* Encrypts one 16-byte block. rounds must be the value aes_expand_key()
 * returned for this key. */
void aes_encrypt_block(const uint8_t *in, const uint8_t *expkey,
                       unsigned int rounds, uint8_t *out);

#endif
