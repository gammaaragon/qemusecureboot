/* SPDX-License-Identifier: MIT */
/*
 * ASPEED AST2600 Secure Boot Controller (SBC) + OTP register interface.
 *
 * Register map and command values confirmed against QEMU 11.1.1's own
 * device model (hw/misc/aspeed_sbc.c) -- not guessed. Bit positions in
 * the config-region layout below are confirmed against a real OTP image
 * this lab generated with the actual `otptool` from this same repo's
 * u-boot-aspeed-sdk build (`otptool print <image>` decodes them with
 * the same names used here), for
 * evb-ast2600-secureboot-otp-on.json's config.
 *
 * Key-list-header layout (data-region dwords 0x0-0xF, one entry per key,
 * scanned until the "last entry" bit) and the type-code values below are
 * confirmed against socsec 2.0.12's own read side (socsec.py's
 * parse_data()) and write side (otptool.py's genKeyHeader_a3_big()) --
 * this lab's real OTP config is chip revision A3 with rsa_key_order
 * "big" (evb-ast2600-secureboot-otp-on.json), which uses different type
 * *values* than revision A0 at the same bit position (bits 17:14). This
 * ROM only ever targets this lab's real chip config, not a generic
 * multi-revision decoder -- cross-check any change here against
 * `otptool print`'s own decode of a real OTP image.
 */
#ifndef OTP_H
#define OTP_H

struct otp_secure_boot_config {
    int enabled;         /* config DW0 bit 1: "Enable Secure Boot" */
    int mode2;           /* config DW0 bit 7: "Secure Boot Mode: Mode_2" */
    int enc_mode;         /* config DW0 bit 27: "Enable image encryption" */
    /* config DW0 bit 6: "Ignore Secure Boot hardware strap" -- real
     * silicon ANDs `enabled` with the SCU hw-strap1 "Enable secure
     * boot" bit (scu.h) unless this is set, in which case the strap is
     * not consulted at all. Confirmed against socsec's own
     * otp_info/a3_config.json (dw_offset 0, bit_offset 6) -- boolean
     * semantics there list index 0 = "Do not ignore", index 1 =
     * "Ignore", i.e. bit *set* means ignore. */
    int ignore_strap;
    unsigned int rsa_len; /* config DW0 bits 11:10: 0=1024 1=2048 2=3072 3=4096 */
    unsigned int sha_mode; /* config DW0 bits 13:12: 0=224 1=256 2=384 3=512 */
    unsigned int header_offset; /* config DW3 bits 15:0 */
};

/* A3+big key-list-header type codes (data-region key entries, bits
 * 17:14 of the header word) -- NOT the same values as revision A0. */
#define OTP_KEY_TYPE_AES_VAULT 0x1u
#define OTP_KEY_TYPE_AES_OEM 0x2u
#define OTP_KEY_TYPE_RSA_OEM 0x9u    /* signature-verify public key */
#define OTP_KEY_TYPE_RSA_SOC_PUB 0xbu
#define OTP_KEY_TYPE_RSA_SOC_PRI 0xdu /* full keypair, incl. private exponent */

/* Scans the data-region key-list header (dwords 0x0-0xF) for the first
 * entry matching `type`, stopping early at the "last entry" bit (bit
 * 13) the same way socsec.py's own parse_data() does. On a match,
 * returns 1 and fills *byte_offset_out (byte offset into the data
 * region -- always a multiple of 4, so dividing by 4 gives a dword
 * address usable with otp_read_dword()) and *par_out (the key's RSA
 * length code, same encoding as struct otp_secure_boot_config's
 * rsa_len, meaningful only for RSA key types). Returns 0 if no entry of
 * that type is found before the last-entry bit (or after all 16 words,
 * if that bit is never set -- matches parse_data()'s own tolerance for
 * a missing last-entry bit, logged there but not fatal). */
int otp_find_key(unsigned int type, unsigned int *byte_offset_out,
                 unsigned int *par_out);

/* Reads one 32-bit OTP word (data region: addr < 0x800; config region:
 * addr in [0x800, 0x1000)) via the SBC's register protocol. */
unsigned int otp_read_dword(unsigned int otp_addr);

/* Reads and decodes the secure-boot-relevant config-region bits. */
void otp_read_secure_boot_config(struct otp_secure_boot_config *cfg);

/* Reads the OTP-stored RSA public key (modulus + exponent) for the
 * RSA_OEM (signature-verify) key, located via otp_find_key() rather
 * than a fixed offset -- this lab's own key happens to sit at data
 * region byte offset 0x40 (dword 0x10), but that's this lab's own key
 * config, not a fixed layout (see otp_find_key()'s own comment).
 * rsa_len_words is the modulus length in 32-bit words (128 for
 * RSA4096). mod_out must have room for rsa_len_words words; exp_out for
 * 1 word (this key's exponent, 0x10001, fits in one dword -- confirmed
 * against real `otptool print` output). If no RSA_OEM key is
 * found in the key list, mod_out is zeroed (fails closed -- a
 * zero-modulus RSA verify can never succeed) and exp_out set to 0. */
void otp_read_rsa_pub_key(unsigned int *mod_out, unsigned int rsa_len_words,
                          unsigned int *exp_out);

/* Reads the OTP-stored RSA_SOC_PRI key (mode2aes2's key-unwrap step,
 * stage 3 slice 3.7): modulus M and full private exponent D, stored
 * back-to-back at the key's data-region offset (M first, then D --
 * socsec.py's own parse_data() layout: `kl['E'] = data_region[
 * key_offset+rsa_len : key_offset+rsa_len*2]` for this key type).
 * mod_out/priv_exp_out must each have room for rsa_len_words words, in
 * the same raw dword-read representation otp_read_rsa_pub_key() uses
 * for the public modulus (i.e. NOT yet converted for the Montgomery
 * math -- that happens in verify.c, same as the public-key path).
 * Returns 1 if an RSA_SOC_PRI key was found, 0 otherwise (outputs
 * untouched). */
int otp_read_rsa_priv_key(unsigned int *mod_out, unsigned int *priv_exp_out,
                          unsigned int rsa_len_words);

#endif
