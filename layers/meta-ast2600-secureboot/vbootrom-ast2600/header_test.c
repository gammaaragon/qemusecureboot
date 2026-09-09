/* SPDX-License-Identifier: MIT */
/*
 * Diagnostic-only build: reads the ROT_HEADER straight out of the real
 * signed SPL sitting in flash (at its real address, flash_window_base
 * = 0x20000000 -- SPL is the first thing in the flash layout, so no
 * additional offset needed), prints every field and the checksum
 * verdict over UART, then halts. Cross-check target: this lab's real
 * deployed signed SPL, independently parsed offline (e.g. with a small
 * Python struct-unpack script against the same ROT_HEADER layout) before
 * trusting this code's own parse of it.
 */
#include "header.h"
#include "uart.h"

#define FLASH_WINDOW_BASE 0x20000000u

void header_test_main(void)
{
    struct rot_header hdr;

    uart_init();
    uart_puts("\nheader_test: reading ROT_HEADER at flash+0x20...\n");

    header_read(FLASH_WINDOW_BASE, ROT_HEADER_OFFSET, &hdr);

    uart_puts("aes_data_offset=");
    uart_put_hex32(hdr.aes_data_offset);
    uart_puts(" enc_offset=");
    uart_put_hex32(hdr.enc_offset);
    uart_puts("\nsign_image_size=");
    uart_put_hex32(hdr.sign_image_size);
    uart_puts(" signature_offset=");
    uart_put_hex32(hdr.signature_offset);
    uart_puts("\nrevision_low=");
    uart_put_hex32(hdr.revision_low);
    uart_puts(" revision_high=");
    uart_put_hex32(hdr.revision_high);
    uart_puts("\nflash_patch_offset=");
    uart_put_hex32(hdr.flash_patch_offset);
    uart_puts(" checksum=");
    uart_put_hex32(hdr.checksum);
    uart_puts("\nchecksum_valid=");
    uart_puts(header_checksum_valid(&hdr) ? "1" : "0");
    uart_puts("\n\nheader_test: done\n");
}
