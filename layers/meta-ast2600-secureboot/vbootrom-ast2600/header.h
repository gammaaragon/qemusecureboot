/* SPDX-License-Identifier: MIT */
/*
 * socsec ROT_HEADER (`<8I>` in socsec.py, 32 bytes) -- the header
 * socsec's make_secure_bl1_image() embeds into the signed SPL image at
 * a fixed offset (0x20 for AST2600/2605 -- socsec.py's own default,
 * never overridden by this lab's recipe; the OTP config's "Secure boot
 * header offset" field is a *different*, unrelated value that turns out
 * not to be consulted for this at all -- see the notes entry).
 *
 * Field order, meaning, and the header's exact placement all confirmed
 * empirically against this lab's real deployed signed SPL binary, not
 * just read from socsec.py's signing code -- both agree exactly,
 * including a self-consistent checksum. See
 * notes/2026-09-03-04-vbootrom-ast2600-header-parsing.md.
 */
#ifndef HEADER_H
#define HEADER_H

#define ROT_HEADER_OFFSET 0x20u
#define ROT_HEADER_SIZE 32u

struct rot_header {
    unsigned int aes_data_offset;
    unsigned int enc_offset;
    unsigned int sign_image_size;   /* image (incl. header), padded to 512B */
    unsigned int signature_offset;  /* == sign_image_size for RSA_SHA, no AES */
    unsigned int revision_low;
    unsigned int revision_high;
    unsigned int flash_patch_offset;
    unsigned int checksum;          /* -(sum of the other 7 fields) mod 2^32 */
};

/* Reads and byte-swaps (flash is a plain byte stream; this struct is
 * little-endian on the wire, matching struct.pack('<8I', ...) on the
 * signing side) the header from `image_base + header_offset`.
 * header_offset is the caller's responsibility to resolve -- real
 * firmware's own fallback (socsec.py's parse_config(), confirmed
 * against source) is "OTP config's header_offset field if nonzero,
 * else ROT_HEADER_OFFSET" (see otp.h's struct
 * otp_secure_boot_config::header_offset). Kept as an explicit parameter
 * rather than baked in here, since header.c has no OTP dependency of
 * its own. */
void header_read(unsigned int image_base, unsigned int header_offset,
                 struct rot_header *hdr);

/* Recomputes the checksum the same way socsec.py does and compares it
 * against hdr->checksum -- a cheap, no-crypto integrity check catching
 * gross corruption before RSA/SHA verification even starts. */
int header_checksum_valid(const struct rot_header *hdr);

#endif
