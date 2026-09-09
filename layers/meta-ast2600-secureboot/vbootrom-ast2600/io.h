/* SPDX-License-Identifier: MIT */
/* Minimal memory-mapped I/O accessors for a freestanding ARM32 target. */
#ifndef IO_H
#define IO_H

static inline unsigned int readl(unsigned int addr)
{
    return *(volatile unsigned int *)addr;
}

static inline void writel(unsigned int addr, unsigned int val)
{
    *(volatile unsigned int *)addr = val;
}

#endif
