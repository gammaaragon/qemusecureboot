/* SPDX-License-Identifier: MIT */
/* Minimal freestanding replacements -- no libc is linked (-ffreestanding
 * -nostdlib -fno-builtin), so these have to exist somewhere. */
#ifndef LIBC_MIN_H
#define LIBC_MIN_H
#include <stddef.h>

void *memcpy(void *dst, const void *src, size_t n);
void *memset(void *dst, int c, size_t n);
int memcmp(const void *a, const void *b, size_t n);

static inline unsigned long long cpu_to_be64(unsigned long long v)
{
    return ((v & 0xffULL) << 56) | ((v & 0xff00ULL) << 40) |
           ((v & 0xff0000ULL) << 24) | ((v & 0xff000000ULL) << 8) |
           ((v >> 8) & 0xff000000ULL) | ((v >> 24) & 0xff0000ULL) |
           ((v >> 40) & 0xff00ULL) | ((v >> 56) & 0xffULL);
}

#endif
