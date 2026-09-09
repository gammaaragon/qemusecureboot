# SPDX-License-Identifier: MIT
# ast2600 vbootrom -- see README.md for what this is and how each piece
# fits together.

CROSS_COMPILE ?= arm-linux-gnueabi-
CC       := $(CROSS_COMPILE)gcc
OBJCOPY  := $(CROSS_COMPILE)objcopy

CFLAGS := -march=armv7-a -ffreestanding -nostdlib -fno-builtin -fno-pic \
          -Wall -Wextra -O2

%.o: %.c
	$(CC) $(CFLAGS) -c -o $@ $<

%.o: %.S
	$(CC) $(CFLAGS) -c -o $@ $<

all: ast2600_bootrom.bin

# --- the real boot flow: verifies against the OTP key (if secure boot
# is fused on) before copying flash to 0x0 and jumping there; halts
# instead if verification fails. Supersedes an earlier unconditional
# copy+jump implementation with no verification at all. ---
BOOTROM_OBJS := reset.o boot_start.o boot.o verify.o header.o otp.o scu.o \
                bignum.o rsa_mod_exp.o pkcs15.o sha256.o sha512.o aes.o \
                aes_ctr.o uart.o libc_min.o

ast2600_bootrom.elf: $(BOOTROM_OBJS) link.ld
	$(CC) $(CFLAGS) -nostdlib -static -T link.ld -o $@ $(BOOTROM_OBJS)

ast2600_bootrom.bin: ast2600_bootrom.elf
	$(OBJCOPY) -O binary $< $@

# --- standalone diagnostics, not part of the boot flow -- each reads
# something real, prints it over UART, and halts, so its output can be
# cross-checked against an independent computation before the same code
# is trusted in the real verify pipeline. See each *_test.c's own
# comment for what it checks. ---
crt0_otp.o: crt0.S
	$(CC) $(CFLAGS) -DDIAG_ENTRY=otp_test_main -c -o $@ $<

otp_test.elf: crt0_otp.o otp.o uart.o otp_test.o link-test.ld
	$(CC) $(CFLAGS) -nostdlib -static -T link-test.ld -o $@ crt0_otp.o otp.o uart.o otp_test.o

crt0_header.o: crt0.S
	$(CC) $(CFLAGS) -DDIAG_ENTRY=header_test_main -c -o $@ $<

header_test.elf: crt0_header.o header.o uart.o header_test.o link-test.ld
	$(CC) $(CFLAGS) -nostdlib -static -T link-test.ld -o $@ crt0_header.o header.o uart.o header_test.o

crt0_bignum.o: crt0.S
	$(CC) $(CFLAGS) -DDIAG_ENTRY=bignum_test_main -c -o $@ $<

bignum_test.elf: crt0_bignum.o bignum.o otp.o uart.o bignum_test.o link-test.ld
	$(CC) $(CFLAGS) -nostdlib -static -T link-test.ld -o $@ crt0_bignum.o bignum.o otp.o uart.o bignum_test.o

crt0_verify.o: crt0.S
	$(CC) $(CFLAGS) -DDIAG_ENTRY=verify_test_main -c -o $@ $<

VERIFY_OBJS := crt0_verify.o verify.o header.o otp.o bignum.o rsa_mod_exp.o \
               pkcs15.o sha256.o sha512.o aes.o aes_ctr.o uart.o libc_min.o \
               verify_test.o

verify_test.elf: $(VERIFY_OBJS) link-test.ld
	$(CC) $(CFLAGS) -nostdlib -static -T link-test.ld -o $@ $(VERIFY_OBJS)

crt0_rsa.o: crt0.S
	$(CC) $(CFLAGS) -DDIAG_ENTRY=rsa_test_main -c -o $@ $<

RSA_TEST_OBJS := crt0_rsa.o rsa_test.o header.o otp.o bignum.o rsa_mod_exp.o \
                uart.o libc_min.o

rsa_test.elf: $(RSA_TEST_OBJS) link-test.ld
	$(CC) $(CFLAGS) -nostdlib -static -T link-test.ld -o $@ $(RSA_TEST_OBJS)

crt0_sha512.o: crt0.S
	$(CC) $(CFLAGS) -DDIAG_ENTRY=sha512_test_main -c -o $@ $<

sha512_test.elf: crt0_sha512.o sha512_test.o header.o sha512.o uart.o libc_min.o link-test.ld
	$(CC) $(CFLAGS) -nostdlib -static -T link-test.ld -o $@ crt0_sha512.o sha512_test.o header.o sha512.o uart.o libc_min.o

crt0_aes.o: crt0.S
	$(CC) $(CFLAGS) -DDIAG_ENTRY=aes_test_main -c -o $@ $<

aes_test.elf: crt0_aes.o aes.o aes_ctr.o aes_test.o uart.o libc_min.o link-test.ld
	$(CC) $(CFLAGS) -nostdlib -static -T link-test.ld -o $@ crt0_aes.o aes.o aes_ctr.o aes_test.o uart.o libc_min.o

crt0_aes_decrypt.o: crt0.S
	$(CC) $(CFLAGS) -DDIAG_ENTRY=aes_decrypt_test_main -c -o $@ $<

AES_DECRYPT_TEST_OBJS := crt0_aes_decrypt.o verify.o header.o otp.o bignum.o \
                        rsa_mod_exp.o pkcs15.o sha256.o sha512.o aes.o \
                        aes_ctr.o uart.o libc_min.o aes_decrypt_test.o

aes_decrypt_test.elf: $(AES_DECRYPT_TEST_OBJS) link-test.ld
	$(CC) $(CFLAGS) -nostdlib -static -T link-test.ld -o $@ $(AES_DECRYPT_TEST_OBJS)

crt0_scu.o: crt0.S
	$(CC) $(CFLAGS) -DDIAG_ENTRY=scu_test_main -c -o $@ $<

scu_test.elf: crt0_scu.o scu.o uart.o scu_test.o link-test.ld
	$(CC) $(CFLAGS) -nostdlib -static -T link-test.ld -o $@ crt0_scu.o scu.o uart.o scu_test.o

crt0_boot_gate.o: crt0.S
	$(CC) $(CFLAGS) -DDIAG_ENTRY=boot_gate_test_main -c -o $@ $<

BOOT_GATE_TEST_OBJS := crt0_boot_gate.o boot.o verify.o header.o otp.o scu.o \
                      bignum.o rsa_mod_exp.o pkcs15.o sha256.o sha512.o aes.o \
                      aes_ctr.o uart.o libc_min.o boot_gate_test.o

boot_gate_test.elf: $(BOOT_GATE_TEST_OBJS) link-test.ld
	$(CC) $(CFLAGS) -nostdlib -static -T link-test.ld -o $@ $(BOOT_GATE_TEST_OBJS)

%_test.bin: %_test.elf
	$(OBJCOPY) -O binary $< $@

clean:
	rm -f *.o *.elf *.bin

.PHONY: all clean
