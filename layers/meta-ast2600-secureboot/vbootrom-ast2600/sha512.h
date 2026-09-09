/* SPDX-License-Identifier: GPL-2.0-or-later */
/*
 * SHA-512 context/API, ported near-verbatim from U-Boot's
 * include/u-boot/sha512.h (same u-boot-aspeed-sdk tree this lab already
 * builds SPL/U-Boot from -- the exact code already proven correct for
 * layers 2/3's own FIT verification under this QEMU). SPDX-License-
 * Identifier: GPL-2.0+ (source file's own license, preserved).
 */
#ifndef SHA512_H
#define SHA512_H

#include <stdint.h>

#define SHA512_SUM_LEN 64
#define SHA384_SUM_LEN 48
#define SHA512_DER_LEN 19
#define SHA512_BLOCK_SIZE 128

typedef struct {
    uint64_t state[SHA512_SUM_LEN / 8];
    uint64_t count[2];
    uint8_t buf[SHA512_BLOCK_SIZE];
} sha512_context;

extern const uint8_t sha512_der_prefix[SHA512_DER_LEN];

void sha512_starts(sha512_context *ctx);
void sha512_update(sha512_context *ctx, const uint8_t *input, uint32_t length);
void sha512_finish(sha512_context *ctx, uint8_t digest[SHA512_SUM_LEN]);

void sha384_starts(sha512_context *ctx);
/* sha384_update() is sha512_update() -- same block processing, only the
 * initial state and final truncation differ. */
void sha384_finish(sha512_context *ctx, uint8_t digest[SHA384_SUM_LEN]);

#endif
