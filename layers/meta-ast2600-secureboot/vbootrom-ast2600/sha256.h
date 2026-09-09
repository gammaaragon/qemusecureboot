/* SPDX-License-Identifier: GPL-2.0-or-later */
/*
 * SHA-256/SHA-224 context/API, ported near-verbatim from U-Boot's
 * include/u-boot/sha256.h (same u-boot-aspeed-sdk tree sha512.h was
 * already ported from). SPDX-License-Identifier: GPL-2.0+ (source
 * file's own license, preserved).
 *
 * SHA-224 shares SHA-256's context shape and compression function
 * (sha256_update()) -- only the initial digest values and the
 * truncated 28-byte output differ, per FIPS 180-4. The 2019.04
 * u-boot-aspeed-sdk tree this lab already builds from has no SHA-224
 * support at all (unlike SHA-384, which its sha512.c already carries
 * behind a #if) -- sha224_starts()/sha224_finish() below are added by
 * hand, with the initial digest values cross-checked against an
 * independent implementation (ipxe's crypto/sha224.c, vendored in this
 * lab's own QEMU source tree at work/qemu-aspeed-hace-fix/qemu-11.1.1/
 * roms/ipxe/src/crypto/sha224.c), not just recalled from memory.
 */
#ifndef SHA256_H
#define SHA256_H

#include <stdint.h>

#define SHA256_SUM_LEN 32
#define SHA224_SUM_LEN 28
#define SHA256_BLOCK_SIZE 64

typedef struct {
    uint32_t total[2];
    uint32_t state[8];
    uint8_t buffer[SHA256_BLOCK_SIZE];
} sha256_context;

void sha256_starts(sha256_context *ctx);
void sha256_update(sha256_context *ctx, const uint8_t *input, uint32_t length);
void sha256_finish(sha256_context *ctx, uint8_t digest[SHA256_SUM_LEN]);

void sha224_starts(sha256_context *ctx);
/* sha224_update() is sha256_update() -- same block processing, only the
 * initial state and final truncation differ. */
void sha224_finish(sha256_context *ctx, uint8_t digest[SHA224_SUM_LEN]);

#endif
