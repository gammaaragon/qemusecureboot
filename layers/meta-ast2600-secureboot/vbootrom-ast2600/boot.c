/* SPDX-License-Identifier: MIT */
/*
 * The real boot flow, superseding stage1.S's unconditional copy+jump
 * now that real verification (verify.c, proven correct against the
 * real signed SPL and a corrupted negative case) exists.
 *
 * Mirrors real AST2600 silicon's own semantics: secure boot is opt-in
 * via an OTP fuse ("Enable Secure Boot", config DW0 bit 1 -- otp.c),
 * ANDed with a separate hardware-strap bit of the same name (scu.c)
 * unless OTP's "Ignore Secure Boot hardware strap" bit says not to
 * consult it -- both real silicon's actual semantics (see otp.h's own
 * comment on ignore_strap) and confirmed empirically under QEMU. If the
 * effective result is disabled, this behaves exactly like stage 1 did -- copy
 * flash to address 0x0 and boot, unverified. If enabled, SPL must
 * verify against the OTP-stored key or this halts, UART message and
 * all, before ever copying anything to 0x0 -- a corrupted or unsigned
 * image never runs.
 */
#include <stdint.h>
#include "otp.h"
#include "scu.h"
#include "verify.h"
#include "aes_ctr.h"
#include "uart.h"

#define FLASH_WINDOW_BASE 0x20000000u
#define BOOT_DEST 0x00000000u
#define FLASH_SIZE 0x04000000u /* w25q512jv, this lab's boot flash */

/* Populated by boot_main(), consumed by boot_copy_and_prepare() -- the
 * two are separate calls from boot_start.S sharing one continuously
 * growing/shrinking stack (see boot_start.S: sp is set once, not reset
 * between the two `bl`s), so a plain local in boot_main() wouldn't
 * reliably survive until boot_copy_and_prepare() runs the way this
 * comment used to assume "the stack frame has already been popped"
 * made safe. File-scope static instead -- fine since this ROM only
 * ever boots once per power-on, no re-entrancy to worry about. */
static struct aes_decrypt_info g_aes_info;

/* Returns 1 if the caller should copy flash to 0x0 and jump there, 0 if
 * it should halt instead (this function itself never halts -- the copy
 * and the final jump both have to happen from boot_start.S, since a
 * jump to 0x0 can't be an ordinary C return). */
int boot_main(void)
{
    struct otp_secure_boot_config cfg;
    enum verify_result r;
    int strap_ok;

    otp_read_secure_boot_config(&cfg);
    /* Real silicon's actual gate is enabled AND (strap OR ignore_strap)
     * -- the hardware-strap bit only matters at all when OTP doesn't
     * say to ignore it. Read unconditionally (cheap, a single MMIO
     * load) rather than short-circuiting on cfg.ignore_strap, so the
     * scu.c read path is always exercised the same way regardless of
     * config -- simpler to reason about than two different code paths
     * depending on ignore_strap's value. */
    strap_ok = cfg.ignore_strap || scu_read_hw_strap_secure_boot();

    if (!cfg.enabled || !strap_ok) {
        /* Secure boot fused off (by either bit, per the AND above):
         * real silicon boots unverified in this case too. Silent,
         * matching stage 1's own original behavior (no UART output at
         * all) -- this is the expected, unremarkable path for a chip
         * that was never fused for secure boot. */
        return 1;
    }

    uart_init();
    uart_puts("\nast2600 vboot: secure boot enabled, verifying SPL...\n");

    r = verify_image(FLASH_WINDOW_BASE, &g_aes_info);
    if (r != VERIFY_OK) {
        const char *msg;

        switch (r) {
        case VERIFY_BAD_CHECKSUM:
            msg = "ast2600 vboot: BAD_CHECKSUM -- header corrupted, halting.\n";
            break;
        case VERIFY_UNSUPPORTED_ENC:
            msg = "ast2600 vboot: UNSUPPORTED_ENC -- encrypted image, no usable key, halting.\n";
            break;
        default:
            msg = "ast2600 vboot: BAD_SIGNATURE -- verification failed, halting.\n";
            break;
        }
        uart_puts(msg);
        return 0;
    }

    uart_puts("ast2600 vboot: signature valid, booting.\n");
    return 1;
}

/* Called by boot_start.S only after boot_main() returned 1 -- performs
 * the actual copy (and, for an encrypted image, decryption). Kept
 * separate (not folded into boot_main) so the caller can do the copy
 * from well above the destination range, same placement discipline
 * stage1.S used. */
void boot_copy_and_prepare(void)
{
    /*
     * Word copy, not libc_min.h's byte-wise memcpy() -- this moves the
     * full 64 MiB flash (stage1.S's own reasoning for why the whole
     * flash, not just SPL, still applies here unchanged), and a 4x
     * larger byte-at-a-time loop would meaningfully slow down every
     * boot under TCG for no benefit; both addresses and the length are
     * word-aligned by construction (FLASH_SIZE is the whole chip size).
     * For an encrypted image this copies the ciphertext verbatim first
     * -- decryption happens as a second, separate pass below, in place
     * at the destination, not the flash source (which stays untouched
     * on every path here, encrypted or not).
     */
    volatile uint32_t *dst = (volatile uint32_t *)(uintptr_t)BOOT_DEST;
    const volatile uint32_t *src = (const volatile uint32_t *)(uintptr_t)FLASH_WINDOW_BASE;
    uint32_t words = FLASH_SIZE / sizeof(uint32_t);
    uint32_t i;

    for (i = 0; i < words; i++) {
        dst[i] = src[i];
    }

    if (g_aes_info.needed) {
        /*
         * Only [enc_offset, sign_image_size) was ever encrypted -- the
         * ROT_HEADER prologue before it and anything past the signed
         * region are already correct as copied verbatim above.
         */
        uint8_t *dec_dst = (uint8_t *)(uintptr_t)(BOOT_DEST + g_aes_info.enc_offset);
        unsigned int dec_len = g_aes_info.sign_image_size - g_aes_info.enc_offset;

        aes_ctr_crypt(g_aes_info.key, g_aes_info.key_words, g_aes_info.iv,
                     dec_dst, dec_dst, dec_len);
    }
}
