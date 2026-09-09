/* SPDX-License-Identifier: MIT */
#include <stdint.h>
#include "verify.h"
#include "header.h"
#include "otp.h"
#include "bignum.h"
#include "rsa.h"
#include "pkcs15.h"
#include "sha256.h"
#include "sha512.h"
#include "libc_min.h"

/* Buffers are sized for the largest key this ROM ever handles
 * (RSA4096); the actual size used per boot is a runtime value read
 * from OTP (rsa_bits/rsa_words/rsa_bytes below), not a compile-time
 * constant -- this lab's own key happens to be RSA4096, but the OTP
 * config's own rsa_len field allows 1024/2048/3072 too. */
#define RSA_MAX_WORDS (RSA_MAX_KEY_BITS / 32)
#define RSA_MAX_SIG_BYTES (RSA_MAX_KEY_BITS / 8)

/* config DW0 rsa_len code -> modulus size in bits, per otp.h's own
 * comment on struct otp_secure_boot_config::rsa_len. */
static unsigned int rsa_len_bits(unsigned int rsa_len_code)
{
    switch (rsa_len_code) {
    case 0: return 1024;
    case 1: return 2048;
    case 2: return 3072;
    default: return 4096;
    }
}

/* config DW0 sha_mode code -> digest over image[0:len], written into
 * digest_out (must have room for SHA512_SUM_LEN bytes, the largest of
 * the four). Returns the actual digest length for that mode, per
 * otp.h's own comment on struct otp_secure_boot_config::sha_mode. */
static unsigned int sha_digest(unsigned int sha_mode_code, unsigned int image_base,
                               unsigned int len, unsigned char *digest_out)
{
    switch (sha_mode_code) {
    case 0: {
        sha256_context ctx;

        sha224_starts(&ctx);
        sha256_update(&ctx, (const unsigned char *)(uintptr_t)image_base, len);
        sha224_finish(&ctx, digest_out);
        return SHA224_SUM_LEN;
    }
    case 1: {
        sha256_context ctx;

        sha256_starts(&ctx);
        sha256_update(&ctx, (const unsigned char *)(uintptr_t)image_base, len);
        sha256_finish(&ctx, digest_out);
        return SHA256_SUM_LEN;
    }
    case 2: {
        sha512_context ctx;

        sha384_starts(&ctx);
        sha512_update(&ctx, (const unsigned char *)(uintptr_t)image_base, len);
        sha384_finish(&ctx, digest_out);
        return SHA384_SUM_LEN;
    }
    default: {
        sha512_context ctx;

        sha512_starts(&ctx);
        sha512_update(&ctx, (const unsigned char *)(uintptr_t)image_base, len);
        sha512_finish(&ctx, digest_out);
        return SHA512_SUM_LEN;
    }
    }
}

enum verify_result verify_image(unsigned int image_base,
                                struct aes_decrypt_info *aes_info)
{
    struct rot_header hdr;
    struct otp_secure_boot_config cfg;
    unsigned int rsa_bits, rsa_words, rsa_bytes;
    unsigned int mod[RSA_MAX_WORDS];
    unsigned int rr[RSA_MAX_WORDS];
    unsigned int canon_mod[RSA_MAX_WORDS];
    unsigned int exp_unused;
    /* 0x10001 as a plain 8-byte big-endian blob -- rsa_mod_exp_sw()'s
     * exponent-bit helpers (stage 3 slice 3.7) index this directly as a
     * big-endian byte buffer, MSB first, no separate byteswap step. */
    static const unsigned char exp_be[8] = {0, 0, 0, 0, 0, 1, 0, 1};
    struct key_prop prop;
    unsigned char digest[SHA512_SUM_LEN];
    unsigned int digest_len;
    unsigned char sig[RSA_MAX_SIG_BYTES];
    unsigned char decrypted[RSA_MAX_SIG_BYTES];

    /* header_offset needs cfg (its own real fallback -- see header.h's
     * comment on header_read()) -- read OTP config before the header,
     * not after as earlier slices did (nothing else here depended on
     * ordering). */
    otp_read_secure_boot_config(&cfg);
    if (!cfg.mode2) {
        /* Only Secure Boot Mode "Mode_2" (RSA+SHA, PKCS#1v1.5 -- this
         * ROM's only supported family) is handled. Mode_GCM and any
         * ECDSA mode are a structurally different scheme this ROM
         * doesn't implement -- fail closed rather than silently
         * misinterpret the key/header as if they were Mode_2's. */
        return VERIFY_BAD_SIGNATURE;
    }

    header_read(image_base,
               cfg.header_offset != 0 ? cfg.header_offset : ROT_HEADER_OFFSET,
               &hdr);
    if (!header_checksum_valid(&hdr)) {
        return VERIFY_BAD_CHECKSUM;
    }

    rsa_bits = rsa_len_bits(cfg.rsa_len);
    rsa_words = rsa_bits / 32;
    rsa_bytes = rsa_bits / 8;

    otp_read_rsa_pub_key(mod, rsa_words, &exp_unused);
    bignum_compute_rr(mod, rr, rsa_words);
    bignum_reverse_byteswap(canon_mod, mod, rsa_words);

    prop.rr = rr;
    prop.modulus = mod;
    prop.public_exponent = exp_be;
    prop.n0inv = bignum_compute_n0inv(canon_mod[0]);
    prop.num_bits = (int)rsa_bits;
    /* exp_len is the exp_be *buffer* length (8 bytes) now, not "how many
     * significant bytes 0x10001 needs" -- rsa_mod_exp.c's generalized
     * exponent-bit helpers (stage 3 slice 3.7) scan for leading zero
     * bytes themselves, so this just has to match sizeof(exp_be). */
    prop.exp_len = sizeof(exp_be);

    digest_len = sha_digest(cfg.sha_mode, image_base, hdr.sign_image_size, digest);

    memcpy(sig, (const void *)(uintptr_t)(image_base + hdr.signature_offset),
          rsa_bytes);

    if (rsa_mod_exp_sw(sig, rsa_bytes, &prop, decrypted) != 0) {
        return VERIFY_BAD_SIGNATURE;
    }

    if (!pkcs15_verify(decrypted, rsa_bytes, digest, digest_len)) {
        return VERIFY_BAD_SIGNATURE;
    }

    /*
     * Signature verified -- only now is it safe to even look at
     * aes_data_offset/enc_offset as meaningful (an attacker-controlled,
     * not-yet-verified image could put anything there). This mirrors
     * socsec.py's own ordering (verify_bl1_image() calls
     * decode_bl1_mode_2_enc_image() only after verify_bl1_mode_2_image()
     * already passed) -- decryption itself is deferred to the caller
     * (boot.c), which does it while copying, not here.
     */
    if (aes_info) {
        aes_info->needed = 0;
    }
    if (cfg.enc_mode) {
        unsigned int byte_offset, par;

        if (otp_find_key(OTP_KEY_TYPE_AES_OEM, &byte_offset, &par)) {
            /* mode2aes1: plain AES key stored directly in OTP. */
            if (aes_info) {
                unsigned int key_dwords[8];
                unsigned int i;

                /*
                 * AES_OEM keys are always 32 bytes (AES-256) in this
                 * lab's real key layout (confirmed against socsec's
                 * own tests/keys/aes-oem.bin size, see the slice 6a
                 * notes entry) -- `par` (the RSA-length-style size
                 * code) isn't meaningful for an AES key type and isn't
                 * consulted here. Read as raw dwords, not byteswapped:
                 * otp_read_dword()'s return value already reconstructs
                 * each 4-byte group in its true OTP-storage order once
                 * written out via this target's native (little-endian)
                 * memory layout -- same reasoning already established
                 * for the RSA modulus reads in otp_read_rsa_pub_key(),
                 * which byteswap only for the Montgomery math's own
                 * word-order needs, not because the raw dword reads
                 * are byte-reversed.
                 */
                for (i = 0; i < 8; i++) {
                    key_dwords[i] = otp_read_dword(byte_offset / 4 + i);
                }
                memcpy(aes_info->key, key_dwords, 32);
                aes_info->key_words = 8;

                memcpy(aes_info->iv,
                      (const void *)(uintptr_t)(image_base + hdr.aes_data_offset),
                      16);

                aes_info->enc_offset = hdr.enc_offset;
                aes_info->sign_image_size = hdr.sign_image_size;
                aes_info->needed = 1;
            }
        } else {
            /*
             * mode2aes2: no plain AES_OEM key -- try RSA_SOC_PRI's
             * key-unwrap instead (socsec.py's mode2_decrypt() "option
             * 2" path). The AES key+IV are wrapped in an
             * rsa_bytes-long RSA-encrypted blob at aes_data_offset;
             * unwrap it with the OTP-stored private exponent D --
             * same Montgomery machinery as the signature verify above,
             * just with a private (arbitrary-width) exponent instead
             * of the fixed small public one (rsa_mod_exp.c's
             * generalized exponent-bit helpers, stage 3 slice 3.7).
             */
            unsigned int priv_mod[RSA_MAX_WORDS];
            unsigned int priv_exp_dwords[RSA_MAX_WORDS];
            unsigned char priv_exp_bytes[RSA_MAX_SIG_BYTES];
            unsigned int priv_rr[RSA_MAX_WORDS];
            unsigned int priv_canon_mod[RSA_MAX_WORDS];
            struct key_prop priv_prop;
            unsigned char wrapped[RSA_MAX_SIG_BYTES];
            unsigned char unwrapped[RSA_MAX_SIG_BYTES];

            if (!otp_read_rsa_priv_key(priv_mod, priv_exp_dwords, rsa_words)) {
                /* No key this ROM knows how to use for an encrypted
                 * image -- fail closed rather than boot ciphertext as
                 * if it were code. */
                return VERIFY_UNSUPPORTED_ENC;
            }

            /* D, like the AES key above, is a plain big-endian byte
             * stream once its raw dwords are written out on this
             * little-endian target -- no rsa_convert_big_endian()
             * needed (that conversion is for the *modulus*, which
             * feeds the Montgomery limb math directly; the exponent is
             * only ever bit-tested, byte by byte, by
             * rsa_mod_exp.c's helpers). */
            memcpy(priv_exp_bytes, priv_exp_dwords, rsa_bytes);

            bignum_compute_rr(priv_mod, priv_rr, rsa_words);
            bignum_reverse_byteswap(priv_canon_mod, priv_mod, rsa_words);

            priv_prop.rr = priv_rr;
            priv_prop.modulus = priv_mod;
            priv_prop.public_exponent = priv_exp_bytes;
            priv_prop.exp_len = rsa_bytes;
            priv_prop.n0inv = bignum_compute_n0inv(priv_canon_mod[0]);
            priv_prop.num_bits = (int)rsa_bits;

            memcpy(wrapped,
                  (const void *)(uintptr_t)(image_base + hdr.aes_data_offset),
                  rsa_bytes);

            if (rsa_mod_exp_sw(wrapped, rsa_bytes, &priv_prop, unwrapped) != 0) {
                return VERIFY_UNSUPPORTED_ENC;
            }

            if (aes_info) {
                /*
                 * socsec.py's mode2_decrypt(), rsa_key_order == 'big'
                 * branch (this lab's own real convention): aes_key =
                 * aes_object[-0x40:-0x20], aes_iv =
                 * aes_object[-0x20:-0x10], both counted from the END
                 * of the rsa_bytes-long unwrapped block -- unlike
                 * mode2aes1's IV, which sits at a fixed offset from
                 * the start.
                 */
                memcpy(aes_info->key, unwrapped + rsa_bytes - 0x40, 32);
                memcpy(aes_info->iv, unwrapped + rsa_bytes - 0x20, 16);
                aes_info->key_words = 8;
                aes_info->enc_offset = hdr.enc_offset;
                aes_info->sign_image_size = hdr.sign_image_size;
                aes_info->needed = 1;
            }
        }
    }

    return VERIFY_OK;
}
