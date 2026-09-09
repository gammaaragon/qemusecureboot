<!-- SPDX-License-Identifier: MIT -->

# ast2600 vbootrom

A virtual boot ROM for QEMU's `ast2600-evb-secureboot` machine (added by
`layers/meta-ast2600-secureboot/qemu-patches/`), emulating layer 1 of
this lab's secure-boot chain (ROM verifies SPL against an OTP-stored RSA
public key) — the one layer that used to be only a build-time artifact,
never exercised at runtime under QEMU. Built in stages: a single-mode
implementation first (RSA-4096/SHA-512 only), then broadened to the full
RSA-size × SHA-mode matrix plus both AES-encrypted key-storage modes,
then two follow-up gap closures (OTP hardware-strap fidelity,
`rsa1024`/`sha224` ground truth) — see "Layout" and "Testing" below for
what each piece actually does.

**Current status: real RSA/SHA verification across the full
1024/2048/3072/4096-bit × SHA-224/256/384/512 matrix, both AES-encrypted
key-storage modes, and real OTP-enable/hardware-strap AND-gate fidelity,
all wired into the boot flow, working, and checked against real ground
truth.** Real silicon's own gate is two bits, ANDed: the OTP
config-region "Enable Secure Boot" bit and a separate hardware-strap bit
of the same name (unless OTP's "Ignore Secure Boot hardware strap" bit
says not to consult the strap) — `boot.c` now implements that AND, not
just the config bit alone. This needed two separate QEMU machine types,
`ast2600-evb-secureboot` and `ast2600-evb-secureboot-strapoff`, rather
than a runtime flag, because QEMU's own `aspeed_otp`/`aspeed_sbc` device
models never load OTP strap content into the SCU's `hw-strap1` register
the way real silicon does — that register can only be set per-machine-class
default or via an explicit `-global` override at startup, not toggled
from OTP content at runtime. If the effective result is disabled, this boots
unverified (matching real fused-off silicon). If enabled, verifies SPL's
signature against the OTP-stored key (RSA key size, SHA mode, and header
offset all read from OTP's own config fields, not hardcoded) before
copying flash to address `0x0` and jumping there — decrypting first, if
the image is AES-encrypted (`mode2aes1`: plain key in OTP; `mode2aes2`:
RSA-wrapped key, unwrapped with an OTP-stored private exponent) —
halting instead, with a UART message, if verification fails or the
image is encrypted in a mode this ROM doesn't recognize. Tested against
this lab's real signed SPL and real OTP key (a valid image boots all the
way through SPL, U-Boot proper, and into OpenBMC userspace with all
three trust layers verifying live; a corrupted image is rejected and
halts before SPL ever runs; a real "secure boot disabled" OTP config, or
strap-off machine, boots silently unverified) and against the real
`socsec` reference vector matrix — plus, for the two combinations
`socsec`'s own test suite has no A3+big vector for (`rsa1024`/`sha224`
and COT-suffixed BL1), a self-signed equivalent generating real ground
truth locally instead.

AES-GCM, ECDSA, and the BL2/BL3 chain-of-trust mechanism are explicitly
out of scope: this lab's real key config never uses AES-GCM or ECDSA,
and layers 2/3 of this lab's own boot chain already use a structurally
different mechanism (FIT/mkimage) than BL2/BL3's own separate
chain-of-trust, so implementing BL2/BL3 wouldn't exercise anything this
lab's real boot flow depends on.

## Building

```
make                              # arm-linux-gnueabi-gcc by default
make CROSS_COMPILE=arm-linux-gnueabihf-gcc-   # or another cross toolchain
```

Produces `ast2600_bootrom.bin` (the real boot ROM) plus one `*_test.bin`
per standalone diagnostic (see "Layout" below). Nothing built is checked
into git (see `.gitignore`) — rebuild locally.

## Running

Needs the patched QEMU build (`./scripts/build-patched-qemu.sh` from the
repo root — the patches in `../qemu-patches/` add the
`ast2600-evb-secureboot` machine type this depends on, and a second
`ast2600-evb-secureboot-strapoff` variant with the hardware-strap
"Enable secure boot" bit off, for testing the negative side of the
OTP-enable/strap AND-gate), a copy of this lab's `--secureboot` deploy
image, and (to exercise real verification, not just the "secure boot
disabled" passthrough) a flat OTP image attached via
`-blockdev`/`-global aspeed-otp.drive=`. There's no `run-qemu.sh`
integration yet; boot it directly:

```
../../../work/qemu-aspeed-hace-fix/qemu-11.1.1/build/qemu-system-arm \
  -machine ast2600-evb-secureboot -m 1G \
  -bios ast2600_bootrom.bin \
  -drive file=<copy of work/obmc-phosphor-image-evb-ast2600-secureboot.static.mtd>,if=mtd,format=raw \
  -blockdev driver=file,filename=<flat otp image>,node-name=otp \
  -global aspeed-otp.drive=otp \
  -net nic -net user \
  -serial stdio -serial null -display none
```

A flat OTP image isn't something `otptool` produces directly (its own
`otp-all.image` is a different, header-prefixed format) — it's built
here by concatenating `otptool`'s separate `otp-data.bin`/`otp-conf.bin`
components at the offsets QEMU's `aspeed-otp` device expects. Use
`gen-lab-otp-image.sh` below, which does this for you.

## Testing

```
./run-tests.sh              # stop at first failure
./run-tests.sh --keep-going # run everything, report all failures at the end
```

Runs the full positive/negative test matrix this project's implementation
was verified against — not a description of testing that was once done
by hand, an actual re-runnable suite. Builds every diagnostic, then:

Every test below goes through `run_diag()`, the script's shared QEMU
driver: `qemu-system-arm -machine ast2600-evb-secureboot -bios
<diagnostic>.bin -drive file=<image>,if=mtd,format=raw -blockdev
driver=file,filename=<otp-flat.bin>,node-name=otp -global
aspeed-otp.drive=otp -serial stdio ...`, run in the background with its
own timeout-kill, output captured to a log file. That puts a
diagnostic binary (see "Layout" below — a real function from the boot
ROM's own source, linked with a throwaway `crt0.S` entry point instead
of the real boot flow) at the CPU's reset address, a real signed test
image at the real flash address, and real OTP fuse content behind
QEMU's real `aspeed_sbc` MMIO registers — then greps the captured UART
output for the exact result string (`result=OK`, `result=BAD_SIGNATURE`,
etc.) the diagnostic printed before it halted. Nothing here is mocked;
only the entry point and the surrounding harness differ from a real
boot.

- The real 27-combination `socsec` reference-vector matrix in
  `test-vectors/` (`mode2` × 9, `mode2aes1` × 9, `mode2aes2` × 9 —
  `rsa{2048,3072,4096}` × `sha{256,384,512}`), each checked against real
  ground truth (verify result for `mode2`; decrypted-region hash
  cross-checked against the real plaintext for the AES modes) — see
  `test-vectors/README.md` for what these are and where they came from.
- A self-generated COT-suffixed BL1 image (`gen-cot-image.sh` — no
  A3-big COT vector exists in `socsec`'s own test suite, so this signs
  one locally with this lab's real key instead).
- A self-generated `rsa1024`/`sha224` image (`gen-rsa1024-sha224-image.sh`
  — the one RSA-size/SHA-mode combination `socsec`'s own test suite has
  no A3+big vector for either, using a real 1024-bit test key `socsec`
  already bundles).
- The OTP-enable/hardware-strap AND-gate (`boot_gate_test.bin`, which
  calls `boot_main()` directly), against both
  `ast2600-evb-secureboot` (strap on) and `ast2600-evb-secureboot-strapoff`
  (strap off) — confirms the gate opens only when both bits agree, using
  this lab's own real OTP image (the only config here with "Enable
  Secure Boot" actually set).
- This lab's own real signed SPL + real OTP key, if both are present
  locally (`gen-lab-otp-image.sh` for the OTP image; the signed SPL
  needs a real `build-image.sh --secureboot` run, a gitignored build
  artifact — skipped with a clear message if missing, not a hard
  failure, so the rest of the suite still runs from a bare clone).
- One corrupted-signature negative test per mode family, confirming
  rejection.

`gen-lab-otp-image.sh`, `gen-cot-image.sh`, and
`gen-rsa1024-sha224-image.sh` (each takes an optional `[output_dir]`;
all used internally by `run-tests.sh`, but also runnable standalone)
need this lab's own `evb-ast2600-secureboot` build artifacts to already
exist (`./scripts/build-image.sh --secureboot`, at least once) — they
sign/package against real key material from that build, they don't
build the toolchain themselves. All three create a throwaway Python venv
at `work/otpvenv/` the first time (real `otptool`/`socsec` CLI tooling,
whose own shebang only works inside a bitbake-sourced environment) and
reuse it on later runs.

## Layout

- `reset.S` — the one instruction that must sit at address `0x0` (the
  CPU's reset PC, and also SPL's own link address) before anything is
  copied there. Just branches to `boot_start.S`'s `_start`.
- `boot_start.S` / `boot.c` — the real boot flow: reads the OTP
  secure-boot-enable bit, verifies (if enabled) or skips straight to
  copying flash to `0x0` and jumping there (if not) — see `boot.c`'s
  own comment for the full decision logic.
- `verify.c` — orchestrates the actual verification: `header.c` (parses
  the signed image's `ROT_HEADER`), `otp.c` (reads the OTP-stored key(s)
  and secure-boot config, including the key-list-header scan
  `otp_find_key()` broader mode coverage needs — see its own comment),
  `bignum.c` (computes the Montgomery constants the RSA math needs,
  since OTP only stores the raw key), `rsa_mod_exp.c` (the RSA math
  itself, ported from U-Boot then generalized for arbitrary-width
  exponents — see its own comment on `struct rsa_public_key::exponent`),
  `sha256.c`/`sha512.c` (SHA-224/256/384/512, likewise ported then
  generalized), `pkcs15.c` (the PKCS#1 v1.5 padding check, generalized
  to any digest length — note this is *not* the same padding U-Boot's
  own FIT verification uses; see `pkcs15.c`'s own comment for why),
  `aes.c`/`aes_ctr.c` (AES-128/192/256 block cipher + CTR mode, for
  AES-encrypted images — see `aes.h`'s own comment for why this is a
  generalization of a vendored AES-128-only file, not a from-scratch
  implementation), `scu.c` (the OTP-enable/hardware-strap AND-gate's
  strap half — a plain MMIO read of the SCU's `hw-strap1` register, a
  different peripheral/protocol than `otp.c`'s SBC-indirect one; see
  `scu.h`'s own comment).
- `*_test.c` (`otp_test`, `header_test`, `bignum_test`, `rsa_test`,
  `sha512_test`, `verify_test`, `aes_test`, `aes_decrypt_test`,
  `scu_test`, `boot_gate_test`) — standalone diagnostics, not part of
  the real boot flow. Each isolates
  one piece, prints what it computed (or a hash of it, for anything too
  large to print byte-by-byte over UART) over UART, and halts, so it can
  be cross-checked against an independent computation before the same
  code is trusted in the real pipeline — see each file's own comment.
- `crt0.S` — shared entry point for all the diagnostics above
  (parameterized via `-DDIAG_ENTRY=<function>`, see Makefile).
- `link.ld` / `link-test.ld` — the real boot ROM's and the diagnostics'
  linker scripts, respectively. Notable gotcha documented inline in
  `link.ld`: mixing a `MEMORY` region (`> REGION`) with explicit
  `. = ADDR` reassignment doesn't do what it looks like — a region's own
  fill pointer advances independently of `.`, silently misplacing a
  later section. Avoided by not using named regions at all.
- `io.h` / `libc_min.h`+`.c` — minimal freestanding memory-mapped I/O
  accessors and `memcpy`/`memset`/`memcmp`/`cpu_to_be64`, since nothing
  else provides them in this environment (`-ffreestanding -nostdlib`).
- `run-tests.sh` / `gen-lab-otp-image.sh` / `gen-cot-image.sh` /
  `gen-rsa1024-sha224-image.sh` — the test suite, see "Testing" above.
  `test-vectors/` — the real `socsec` reference fixtures `run-tests.sh`
  checks against (see its own README.md for provenance/licensing).
  `work/` — gitignored scratch for all four scripts (generated OTP
  images, the throwaway venv, per-test logs).
