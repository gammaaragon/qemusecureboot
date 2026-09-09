/* SPDX-License-Identifier: MIT */
/*
 * PKCS#1 v1.5 signature padding check.
 *
 * NOT the same padding U-Boot's own lib/rsa/rsa-verify.c checks (that
 * version expects a DER-encoded DigestInfo prefix ahead of the digest
 * -- 0x00 0x01 0xFF..0xFF 0x00 <DER prefix> <digest> -- matching how
 * mkimage signs FIT images, which this lab's own layers 2/3 use).
 * socsec's own signing (socsec.py's rsa_pkcs15_sign(), which calls raw
 * `openssl rsautl -sign` on nothing but the digest bytes -- no DigestInfo
 * wrapper) produces the simpler classic PKCS#1 v1.5 block instead:
 * 0x00 0x01 0xFF..0xFF 0x00 <digest>, no DER prefix at all.
 *
 * Found the hard way: an earlier version of this file, ported from
 * rsa-verify.c's DER-prefixed logic on the reasonable-looking
 * assumption that "PKCS1.5 SHA-512" meant the same thing in both
 * signing schemes, correctly decrypted the real signature (confirmed
 * via rsa_test.c against an independent Python computation) and still
 * failed verification -- because it was checking for 19 bytes of DER
 * prefix that socsec never wrote. Diagnosed by printing the decrypted
 * block's boundary bytes and comparing against Python's own
 * pow(sig, e, n): the digest started right after a single 0x00, with
 * no DER prefix in between at all.
 */
#include "pkcs15.h"
#include "libc_min.h"

int pkcs15_verify(const uint8_t *msg, unsigned int msg_len,
                  const uint8_t *hash, unsigned int hash_len)
{
    unsigned int pad_len = msg_len - hash_len;
    unsigned int ff_len;
    const uint8_t *p = msg;

    if (msg_len <= hash_len + 3) {
        return 0;
    }

    if (*p++ != 0x00) {
        return 0;
    }
    if (*p++ != 0x01) {
        return 0;
    }

    ff_len = pad_len - 3;
    if (*p != 0xff) {
        return 0;
    }
    if (memcmp(p, p + 1, ff_len - 1) != 0) {
        return 0;
    }
    p += ff_len;

    if (*p++ != 0x00) {
        return 0;
    }

    if (memcmp(p, hash, hash_len) != 0) {
        return 0;
    }

    return 1;
}
