/* SPDX-License-Identifier: MIT */
#include "otp.h"
#include "io.h"

#define SBC_BASE 0x1E6F2000u

#define SBC_R_CMD (SBC_BASE + 0x004u)
#define SBC_R_ADDR (SBC_BASE + 0x010u)
#define SBC_R_STATUS (SBC_BASE + 0x014u)
#define SBC_R_CAMP1 (SBC_BASE + 0x020u)
#define SBC_R_CAMP2 (SBC_BASE + 0x024u)

#define SBC_OTP_CMD_READ 0x23b1e361u

#define SBC_STATUS_OTP_IDLE (1u << 2)
#define SBC_STATUS_OTP_MEM_IDLE (1u << 1)
#define SBC_STATUS_READY (SBC_STATUS_OTP_IDLE | SBC_STATUS_OTP_MEM_IDLE)

#define OTP_DATA_DWORD_COUNT 0x800u /* data region: [0, 0x800); config: [0x800, 0x1000) */

/* config DW0 bit positions, confirmed against a real otptool-generated
 * OTP image via `otptool print` -- see the notes entry. */
#define CFG_DW0_SECURE_BOOT_EN (1u << 1)
#define CFG_DW0_IGNORE_STRAP (1u << 6)
#define CFG_DW0_MODE2 (1u << 7)
#define CFG_DW0_RSA_LEN_SHIFT 10
#define CFG_DW0_RSA_LEN_MASK 0x3u
#define CFG_DW0_SHA_MODE_SHIFT 12
#define CFG_DW0_SHA_MODE_MASK 0x3u
#define CFG_DW0_ENC_MODE (1u << 27)

/* Data-region key-list-header word layout, confirmed against socsec.py's
 * parse_data() / otptool.py's genKeyHeader_a3_big() -- see otp.h's own
 * comment for why this is the A3+big table specifically. */
#define KEY_HDR_COUNT 16u
#define KEY_HDR_TYPE_SHIFT 14
#define KEY_HDR_TYPE_MASK 0xfu
#define KEY_HDR_ID_MASK 0x7u
#define KEY_HDR_OFFSET_SHIFT 3
#define KEY_HDR_OFFSET_MASK 0x3ffu
#define KEY_HDR_PAR_SHIFT 18
#define KEY_HDR_PAR_MASK 0x3u
#define KEY_HDR_LAST (1u << 13)

unsigned int otp_read_dword(unsigned int otp_addr)
{
    unsigned int status;

    writel(SBC_R_ADDR, otp_addr);
    writel(SBC_R_CMD, SBC_OTP_CMD_READ);

    do {
        status = readl(SBC_R_STATUS);
    } while ((status & SBC_STATUS_READY) != SBC_STATUS_READY);

    return readl(SBC_R_CAMP1);
}

void otp_read_secure_boot_config(struct otp_secure_boot_config *cfg)
{
    unsigned int dw0 = otp_read_dword(OTP_DATA_DWORD_COUNT + 0);
    unsigned int dw3 = otp_read_dword(OTP_DATA_DWORD_COUNT + 3);

    cfg->enabled = (dw0 & CFG_DW0_SECURE_BOOT_EN) != 0;
    cfg->ignore_strap = (dw0 & CFG_DW0_IGNORE_STRAP) != 0;
    cfg->mode2 = (dw0 & CFG_DW0_MODE2) != 0;
    cfg->enc_mode = (dw0 & CFG_DW0_ENC_MODE) != 0;
    cfg->rsa_len = (dw0 >> CFG_DW0_RSA_LEN_SHIFT) & CFG_DW0_RSA_LEN_MASK;
    cfg->sha_mode = (dw0 >> CFG_DW0_SHA_MODE_SHIFT) & CFG_DW0_SHA_MODE_MASK;
    cfg->header_offset = dw3 & 0xffffu;
}

int otp_find_key(unsigned int type, unsigned int *byte_offset_out,
                 unsigned int *par_out)
{
    unsigned int i;

    for (i = 0; i < KEY_HDR_COUNT; i++) {
        unsigned int h = otp_read_dword(i);
        unsigned int t = (h >> KEY_HDR_TYPE_SHIFT) & KEY_HDR_TYPE_MASK;

        if (t == type) {
            *byte_offset_out = ((h >> KEY_HDR_OFFSET_SHIFT) & KEY_HDR_OFFSET_MASK)
                               << KEY_HDR_OFFSET_SHIFT;
            *par_out = (h >> KEY_HDR_PAR_SHIFT) & KEY_HDR_PAR_MASK;
            return 1;
        }
        if (h & KEY_HDR_LAST) {
            break;
        }
    }
    return 0;
}

void otp_read_rsa_pub_key(unsigned int *mod_out, unsigned int rsa_len_words,
                          unsigned int *exp_out)
{
    unsigned int byte_offset, par, dword_offset, i;

    if (!otp_find_key(OTP_KEY_TYPE_RSA_OEM, &byte_offset, &par)) {
        for (i = 0; i < rsa_len_words; i++) {
            mod_out[i] = 0;
        }
        *exp_out = 0;
        return;
    }

    /* byte_offset is always a multiple of 4 (in fact 8, by the signing
     * side's own key-placement convention) -- see otp_find_key()'s own
     * comment. */
    dword_offset = byte_offset / 4;
    for (i = 0; i < rsa_len_words; i++) {
        mod_out[i] = otp_read_dword(dword_offset + i);
    }

    /*
     * The exponent is NOT stored in OTP at all for a public key --
     * socsec's own rsa_key_to_bin() (socsec/__init__.py) validates it's
     * exactly 0x10001 and only writes the modulus. 0x10001 is the
     * universal RSA public exponent this whole signing scheme assumes.
     */
    *exp_out = 0x10001u;
}

int otp_read_rsa_priv_key(unsigned int *mod_out, unsigned int *priv_exp_out,
                          unsigned int rsa_len_words)
{
    unsigned int byte_offset, par, dword_offset, i;

    if (!otp_find_key(OTP_KEY_TYPE_RSA_SOC_PRI, &byte_offset, &par)) {
        return 0;
    }

    dword_offset = byte_offset / 4;
    for (i = 0; i < rsa_len_words; i++) {
        mod_out[i] = otp_read_dword(dword_offset + i);
    }
    /* D immediately follows M, same rsa_len_words width -- socsec.py's
     * own parse_data() layout for this key type. */
    for (i = 0; i < rsa_len_words; i++) {
        priv_exp_out[i] = otp_read_dword(dword_offset + rsa_len_words + i);
    }
    return 1;
}
