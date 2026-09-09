/* SPDX-License-Identifier: MIT */
/*
 * AES-CTR, hand-written on top of aes.c's block-encrypt primitive.
 * Counter semantics confirmed against socsec.py's own
 * decode_bl1_mode_2_enc_image()/mode2_decrypt() (both mode2aes1 and
 * mode2aes2 use the identical CTR construction once the AES key is in
 * hand): pycryptodome's `Counter.new(128, initial_value=int.from_bytes(
 * iv, 'big'))` -- a full 128-bit big-endian counter block, incremented
 * as one big integer (not just its low 32 bits, the more common
 * "32-bit counter in the last word" CTR variant), XORed with
 * AES-encrypted counter blocks against the ciphertext/plaintext. CTR
 * mode always uses the block cipher's *encrypt* direction for both
 * encryption and decryption -- aes.c deliberately has no decrypt
 * primitive at all, see its own comment.
 */
#ifndef AES_CTR_H
#define AES_CTR_H

#include <stdint.h>

/* Decrypts (or encrypts -- CTR is symmetric) `len` bytes from `src`
 * into `dst`, AES-key `key` (key_words words: 4/6/8 for
 * AES-128/192/256), starting from the 16-byte big-endian counter
 * block `iv`. `len` need not be a multiple of 16 -- a partial final
 * block is handled by discarding the unused tail of the last keystream
 * block, same as any standard CTR implementation. src and dst may be
 * the same buffer (in-place). */
void aes_ctr_crypt(const uint8_t *key, unsigned int key_words,
                   const uint8_t iv[16], const uint8_t *src, uint8_t *dst,
                   unsigned int len);

#endif
