<!-- SPDX-License-Identifier: MIT -->

# Test vectors

Real, pre-built golden test fixtures from ASPEED Technology's `socsec`
2.0.12 (MIT-licensed — see `LICENSE-socsec.txt`), copied here so this
project's positive/negative test matrix is reproducible from a clone
alone, not dependent on regenerating them by hand or on a full OpenBMC
build tree existing locally.

Each `2600-a3_<mode>-<rsa>-<sha>-big/` directory holds the 4 files
`run-tests.sh` actually needs, out of `socsec`'s own larger set (the rest
— `otp-all.image`, `.hex`, `.image`, `_mask.bin` variants — are other
representations of the same two files, not used here):

- `bl1.signed.bin` — a real, validly signed BL1 test image (`socsec`'s
  own generic small stub, not this lab's real SPL — see the stage-3
  slice-5 notes entry for why: this lab's own signed SPL is already
  overwritten in place by the time a build completes, so no unsigned
  original survives to re-sign against every mode).
- `bl1.bin` — the plaintext before signing (and, for the `mode2aes*`
  encrypted variants, before encryption too) — used as the correctness
  oracle for AES decryption: `run-tests.sh` decrypts `bl1.signed.bin`'s
  ciphertext with the real OTP-derived key and byte-compares (well, hash-
  compares) the result against this file's corresponding region.
- `otp-data.bin` / `otp-conf.bin` — the raw OTP data-region and
  config-region contents for that mode/key-size/hash combination —
  `run-tests.sh` assembles these into the flat image format QEMU's
  `-blockdev`/`aspeed-otp` expects (see `otp.c`'s own comment for why
  `otptool`'s own `otp-all.image` output isn't that format directly).

**Naming**: `2600` = AST2600, `a3` = silicon revision A3 (this lab's own
real OTP key-list encoding — A0's encoding, which most of `socsec`'s own
test suite defaults to, uses different key-type *values* than A3, see
`otp.h`'s own header comment), `big` =
`rsa_key_order` (this lab's own real convention). `mode2` = RSA+SHA,
no AES; `mode2aes1` = AES key stored plainly in OTP; `mode2aes2` = AES
key RSA-wrapped, unwrapped with an OTP-stored private exponent.

**Coverage**: `rsa{2048,3072,4096}` × `sha{256,384,512}`, all three
modes — 27 combinations, all real ground truth. **Not included**:
`rsa1024`/`sha224` (no A3-big vectors exist in `socsec`'s own test suite
for these — see the stage-3 notes entries) and any COT-suffixed variant
(also A0-only in `socsec`'s test suite — slice 5's own COT test image is
self-generated instead, at test time, not a static fixture; see
`gen-cot-image.sh`).

To refresh or extend this set from a fresh `socsec` checkout (e.g. a
newer version that adds A3 rsa1024/sha224 vectors): the source layout is
`socsec/tests/data/reference/2600-a3_<mode>-<rsa>-<sha>-big/`, same 4
filenames as above.
