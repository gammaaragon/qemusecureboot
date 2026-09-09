<!-- SPDX-License-Identifier: MIT -->

# secure-boot-demo

Five demonstration experiments proving what this lab's boot chain
actually protects: **integrity** (accidental corruption is caught) is
not the same guarantee as **authenticity anchored to a hardware root of
trust** (a deliberate, signed substitution is caught only where a real
root of trust exists to check it against). Built after this repo's own vboot ROM
(`layers/meta-ast2600-secureboot/vbootrom-ast2600/`, see its own README)
made layer 1 (ROM verifies SPL against an OTP-fused key) exercisable at
runtime under QEMU — the precondition that used to make "D" (the
trust-anchor limit) something this lab could only state, not
demonstrate.

**Current status: all five experiments pass against real QEMU boot
output, `./run-all.sh --keep-going` reports `5 passed, 0 failed`.**

## What each experiment proves

| Exp | Variant | What's tampered | Machine | Result | What it proves |
|---|---|---|---|---|---|
| A | lab | ramdisk `init`, hash left **stale** | `ast2600-evb` | `Bad Data Hash`, boot refused | The FIT hash node catches accidental corruption. |
| B | lab | ramdisk `init`, **rehashed** correctly | `ast2600-evb` | boots clean, tamper marker present, reaches `login:` | A correct hash alone proves nothing about *who* made the change — the lab variant has no signature to check. |
| C | secureboot | same tamper, FIT **naively resigned** (no private key) | `ast2600-evb` | `Failed to verify required signature 'key-rsa_oem_fitimage_key'`, boot refused | Real signature verification (layer 2/3, FIT signing) rejects a rebuild the attacker can't actually sign correctly. |
| D1 | secureboot | SPL + U-Boot-proper wholesale-replaced, signed with a **fresh attacker keypair** | `ast2600-evb` (stock, no ROM/OTP anchor) | boots completely unchallenged to `login:` | Signing is only as good as the anchor checking it — nothing here verifies SPL itself before it runs, so the attacker's own key is trusted as if it were real. |
| D2 | secureboot | same attacker substitution as D1 | `ast2600-evb-secureboot` (real vboot ROM + OTP-fused key) | `ast2600 vboot: BAD_CHECKSUM -- header corrupted, halting.` | With layer 1 actually anchored to OTP, the same attack is caught before SPL ever executes — closing exactly the gap D1 exposes. |

D1/D2 is the real payoff: identical attacker artifact, only the
anchor differs, only the anchored boot rejects it.

**D2's real rejection reason** (`BAD_CHECKSUM`, not `BAD_SIGNATURE`) is
because the vboot ROM's verification (`socsec`'s own `ROT_HEADER`
format) is a structurally separate mechanism from FIT signing — the
attacker's plain U-Boot SPL binary has no `ROT_HEADER` at all, so it
fails the header/checksum check before ever reaching RSA signature
verification. The outcome that matters is unchanged: the gate opens,
inspects what's actually in flash, and halts before SPL runs. `exp-d2`'s
pass condition checks this generically (gate message + halt + absence of
D1's success banner) rather than one hardcoded failure string, since a
more sophisticated attacker payload (a well-formed but wrongly-signed
`ROT_HEADER`) would hit `BAD_SIGNATURE` instead and the point would still
hold.

## Running

```
./run-all.sh                # stop at first failure
./run-all.sh --keep-going   # run all five, summarize
./exp-a-stale-hash.sh       # or run any single experiment directly
```

Each experiment builds its own scratch flash image under
`work/<exp>/flash.mtd` (a checksum-verified copy of the real golden
deploy image — `make_flash_copy()` in `lib.sh`, never
`work/obmc-phosphor-image-evb-ast2600-<variant>.static.mtd`, which is
`../../scripts/run-qemu.sh`'s own managed copy) and boots it directly
with a background QEMU process plus a timeout-kill, mirroring
`vbootrom-ast2600/run-tests.sh`'s own `run_diag()` pattern. `work/` is
gitignored; nothing here mutates the real deploy images or
`run-qemu.sh`'s own copies (confirmed after every run:
`scripts/golden-{lab,secureboot}.sha256` still match the real deploy
images byte-for-byte).

Needs both the `lab` and `secureboot` build variants already built
(`../../scripts/build-image.sh --lab`/`--secureboot`), the locally
patched QEMU 11.1.1 (`../../scripts/build-patched-qemu.sh`) for C/D1/D2,
and `vbootrom-ast2600`'s own OTP image
(`layers/meta-ast2600-secureboot/vbootrom-ast2600/gen-lab-otp-image.sh`)
for D2 — `exp-d2` exits 2 (skip) rather than failing if that image
doesn't exist yet.

## Layout

    lib.sh                       shared functions: golden-copy verification,
                                  flash splicing, QEMU boot-with-timeout
    tamper-ramdisk.sh             fitImage -> tampered ramdisk1.cpio.xz
                                  (extracts, decompresses, unpacks cpio,
                                  inserts a marker line into init, repacks)
    rebuild-fit.sh                rebuilds a fitImage around a tampered
                                  ramdisk, optionally re-signed (-k keydir)
    gen-attacker-keys.sh           fresh RSA-4096 keypair for D1/D2, cached
                                  under work/attacker-keys/ (must be named
                                  rsa_oem_fitimage_key.key/.crt -- mkimage
                                  resolves signing keys by name hint, not
                                  by who generated them)
    build-attacker-uboot.sh       real u-boot.its/u-boot-spl.dtb rebuilt
                                  and signed against the attacker keypair
    exp-a-stale-hash.sh
    exp-b-rehash.sh
    exp-c-naive-resign.sh
    exp-d1-key-swap-stock-machine.sh
    exp-d2-key-swap-secureboot-machine.sh
    run-all.sh                    runs all five, pass/fail summary
    work/                         gitignored: per-experiment flash images,
                                  boot logs, cached attacker keys

## A real bug this caught

`lib.sh`'s `qemu_boot()` originally had `kill "$killer" 2>/dev/null`
(and `wait`) with no `|| true` under `set -euo pipefail`. Once the
timeout-killer subshell had already exited (the normal case — it exits
right after killing qemu), that `kill` returns non-zero; `2>/dev/null`
silences the message but not the exit status, so `set -e` killed the
whole driver script right there, silently, before the PASS/FAIL check
ever ran. Every experiment's actual boot behavior was already correct
(confirmed by inspecting the raw `boot.log` files by hand) but
`run-all.sh` reported `0 passed, 5 failed` on a from-scratch run because
none of the five scripts ever reached their own `exit 0`/`exit 1`. Fixed
by adding `|| true` to the three cleanup lines in `qemu_boot()` — a
reminder that `set -e` plus "best-effort cleanup that's allowed to fail"
needs an explicit `|| true`, every time, not just where it seemed
load-bearing.
