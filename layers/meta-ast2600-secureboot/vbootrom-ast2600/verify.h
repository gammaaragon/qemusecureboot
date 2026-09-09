/* SPDX-License-Identifier: MIT */
#ifndef VERIFY_H
#define VERIFY_H

enum verify_result {
    VERIFY_OK = 0,
    VERIFY_BAD_CHECKSUM,   /* header checksum didn't match */
    VERIFY_BAD_SIGNATURE,  /* RSA/SHA verification failed */
    /* config's "Enable image encryption" bit is set, but no key this
     * ROM knows how to use was found in the OTP key list -- e.g.
     * mode2aes2 (RSA-wrapped AES key), not implemented yet (stage 3
     * slice 3.7). Deliberately distinct from VERIFY_BAD_SIGNATURE: the
     * signature itself may be perfectly valid (it's computed over the
     * still-encrypted bytes, checked before this point) -- this is "I
     * can't decrypt it", not "it's forged". Still fails closed either
     * way: boot.c halts on anything but VERIFY_OK, so an image this
     * ROM can't fully handle never gets copied/jumped to as if it were
     * plain code. */
    VERIFY_UNSUPPORTED_ENC,
};

/* AES key/IV material verify_image() discovered for a still-encrypted
 * image, for the caller (boot.c) to decrypt with while copying --
 * verify_image() itself never decrypts (see verify.c's own comment on
 * why: the signature check happens over the encrypted bytes, before
 * decryption is even attempted). Only meaningful when verify_image()
 * returns VERIFY_OK and needed != 0; untouched otherwise. */
struct aes_decrypt_info {
    int needed;                    /* 1 if the image is encrypted and a usable key was found */
    unsigned int key_words;        /* 4/6/8 for AES-128/192/256 */
    unsigned char key[32];         /* up to AES-256; only key_words*4 bytes meaningful */
    unsigned char iv[16];          /* initial 128-bit big-endian CTR counter */
    unsigned int enc_offset;       /* start of the encrypted region (ROT_HEADER's own field) */
    unsigned int sign_image_size;  /* end of the encrypted region (ditto) */
};

/* Verifies the signed image at image_base (flash's real address,
 * 0x20000000) against the OTP-stored RSA public key: reads and
 * checksum-checks the ROT_HEADER, computes a digest over
 * image[0:sign_image_size], RSA-verifies the signature at
 * signature_offset against the OTP key (computing the Montgomery
 * constants at runtime -- see bignum.c), and checks the PKCS#1 v1.5
 * padding + digest match. RSA key size (1024/2048/3072/4096) and SHA
 * mode (224/256/384/512) are both read from OTP's own rsa_len/sha_mode
 * config fields -- see notes/2026-09-03-05-vbootrom-ast2600-rsa-verify.md
 * for the original RSA4096/SHA512-only version and
 * notes/2026-09-03-07-vbootrom-ast2600-stage3-slice1-otp-keylist.md
 * onward for stage 3's broader coverage. If OTP's "Enable image
 * encryption" bit is set, also locates the AES key/IV and fills
 * *aes_info (pass NULL if the caller doesn't care) -- mode2aes1 (plain
 * AES_OEM key in OTP) only; mode2aes2 (RSA-wrapped key) returns
 * VERIFY_UNSUPPORTED_ENC, not implemented yet (slice 3.7). */
enum verify_result verify_image(unsigned int image_base,
                                struct aes_decrypt_info *aes_info);

#endif
