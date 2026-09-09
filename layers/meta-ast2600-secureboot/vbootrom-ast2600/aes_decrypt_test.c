/* SPDX-License-Identifier: MIT */
/*
 * Diagnostic-only build: runs the real verify_image() against the
 * image in flash, and if it reports an encrypted image (aes_info.needed),
 * decrypts image[enc_offset:sign_image_size] with the discovered
 * AES key/IV and prints enc_offset/sign_image_size plus a SHA-512
 * digest of the decrypted bytes over UART -- a hash, not the raw bytes
 * (thousands of bytes over a 115200 UART), for cross-checking against
 * an independently computed hash of the real plaintext image's
 * corresponding byte range on the host. This is the actual proof that
 * decryption is byte-correct, not just "the code runs" -- boot.c's own
 * decrypt-while-copying path exercises the identical aes_ctr_crypt()
 * call but has no way to report its result other than "did the next
 * boot stage run", which a generic (non-bootable) BL1 test stub can't
 * demonstrate either way.
 */
#include <stdint.h>
#include "verify.h"
#include "aes_ctr.h"
#include "sha512.h"
#include "uart.h"

#define FLASH_WINDOW_BASE 0x20000000u
#define DEC_BUF_BYTES (64u * 1024u) /* generous for this lab's/socsec's small test images */

void aes_decrypt_test_main(void)
{
    enum verify_result r;
    struct aes_decrypt_info aes_info;
    static unsigned char dec_buf[DEC_BUF_BYTES];
    unsigned int dec_len;
    sha512_context sha;
    unsigned char digest[SHA512_SUM_LEN];
    unsigned int i;

    uart_init();
    uart_puts("\naes_decrypt_test: verifying + decrypting real image...\n");

    r = verify_image(FLASH_WINDOW_BASE, &aes_info);
    if (r != VERIFY_OK) {
        uart_puts("verify FAILED, result=");
        uart_put_hex32((unsigned int)r);
        uart_puts("\n\naes_decrypt_test: done\n");
        return;
    }

    if (!aes_info.needed) {
        uart_puts("image is not encrypted (aes_info.needed == 0)\n");
        uart_puts("\naes_decrypt_test: done\n");
        return;
    }

    dec_len = aes_info.sign_image_size - aes_info.enc_offset;
    uart_puts("enc_offset=");
    uart_put_hex32(aes_info.enc_offset);
    uart_puts(" sign_image_size=");
    uart_put_hex32(aes_info.sign_image_size);
    uart_puts(" dec_len=");
    uart_put_hex32(dec_len);
    uart_puts(" key_words=");
    uart_put_hex32(aes_info.key_words);
    uart_puts("\n");

    if (dec_len > DEC_BUF_BYTES) {
        uart_puts("dec_len exceeds DEC_BUF_BYTES, aborting\n");
        uart_puts("\naes_decrypt_test: done\n");
        return;
    }

    aes_ctr_crypt(aes_info.key, aes_info.key_words, aes_info.iv,
                 (const unsigned char *)(uintptr_t)(FLASH_WINDOW_BASE + aes_info.enc_offset),
                 dec_buf, dec_len);

    sha512_starts(&sha);
    sha512_update(&sha, dec_buf, dec_len);
    sha512_finish(&sha, digest);

    uart_puts("decrypted_sha512=");
    for (i = 0; i < SHA512_SUM_LEN; i++) {
        uart_put_hex32(digest[i]);
        uart_puts(" ");
    }
    uart_puts("\n\naes_decrypt_test: done\n");
}
