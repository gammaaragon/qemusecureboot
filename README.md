<!-- SPDX-License-Identifier: MIT -->

# qemusecureboot

A reproducible lab for running and instrumenting OpenBMC's dormant AST2600
secure-boot chain under QEMU, plus a small custom virtual boot ROM
(`layers/meta-ast2600-secureboot/vbootrom-ast2600/`) that makes the
otherwise-unexercisable ROM-level trust anchor (layer 1: ROM verifies SPL
against an OTP-fused key) actually runnable in emulation. Includes five
demonstration experiments proving that a hash check and a real
cryptographic signature check are not the same guarantee as authenticity
anchored to hardware.

![Boot-time trust chain: the ROM layer either performs no check (stock QEMU) or verifies SPL against an OTP-fused RSA key (this repo's vboot ROM); either way, the same SPL→U-Boot→kernel FIT-signature chain runs downstream, using a software build key rather than a hardware anchor.](docs/architecture.svg)

A real signature check two layers downstream is only as trustworthy as
whatever verifies the layer beneath it. Layers 2–3 (FIT signing) are
identical on both machines above — only layer 1's hardware anchor
decides whether that check ever gets exercised honestly. That's exactly
what experiments D1 and D2 demonstrate: the identical attacker-swapped
artifact boots unchallenged on the left, gets rejected before SPL ever
runs on the right.

## Layout

    scripts/                         build-image.sh, run-qemu.sh, diff-boot.sh,
                                      qemu-console.py, build-patched-qemu.sh
    layers/meta-ast2600-lab/         hwmon/lm75 layer (adds a sensor over D-Bus)
    layers/meta-ast2600-secureboot/  FIT/OTP secure-boot layer + the vbootrom-ast2600
                                      custom boot ROM and its own test suite
    experiments/secure-boot-demo/    A/B/C/D1/D2 tamper-demonstration experiments

Each of `layers/meta-ast2600-lab/`, `layers/meta-ast2600-secureboot/`
(and `.../vbootrom-ast2600/` within it), and `experiments/secure-boot-demo/`
has its own README with full design/implementation detail. This file is
just the clone-to-running-QEMU path.

## Prerequisites

**1. An OpenBMC source clone, built for `evb-ast2600`.** This repo is a
set of layers/scripts that sit *alongside* OpenBMC, not a fork of it —
nothing here modifies OpenBMC's own tracked layers.

```
git clone https://github.com/openbmc/openbmc.git ~/openbmc
cd ~/openbmc
. setup evb-ast2600
```

(Building `obmc-phosphor-image` from scratch is a multi-hour Yocto build.
7.7 GiB of RAM is the practical constraint, not CPU core count — if you're
similarly memory-limited, set `BB_NUMBER_THREADS` and `PARALLEL_MAKE` low
in `conf/local.conf` before building.)

**2. `qemu-system-arm`.** The stock distro package works for `--base` and
`--lab`. The `--secureboot` variant (real RSA/SHA signature verification
under QEMU) needs a locally built QEMU 11.1.x with two small local
patches (adding a new `ast2600-evb-secureboot` machine type that carries
the vboot ROM hook, and defaulting its secure-boot hardware strap on —
see `layers/meta-ast2600-secureboot/qemu-patches/`). Build it with:

```
./scripts/build-patched-qemu.sh
```

Needs `ninja-build`, `meson`, `libglib2.0-dev`, `libpixman-1-dev`,
`libfdt-dev`, `flex`, `bison`, `python3-venv`, `libslirp-dev`, and network
access to fetch QEMU's own source tarball. The built binary lives under
`work/` (gitignored); `scripts/run-qemu.sh --secureboot` finds and uses it
automatically.

**3. A cross-compiler for the vbootrom itself**, only if you want to
rebuild `vbootrom-ast2600` (the QEMU patch above embeds a prebuilt image
into the machine type, so this is only needed if you're changing the boot
ROM's own C/assembly source):

```
sudo apt install gcc-arm-linux-gnueabi
```

## Clone and place this repo

This repo expects to sit next to `~/openbmc`, not inside it:

```
git clone <this-repo-url> ~/qemusecureboot
cd ~/qemusecureboot
```

(`scripts/*.sh` all resolve paths relative to their own location and to
`$HOME/openbmc`, so the exact directory name doesn't matter as long as
`~/openbmc` exists and has been through `. setup evb-ast2600` once.)

## Build the three image variants

```
./scripts/build-image.sh --base         # stock OpenBMC, no extra layer
./scripts/build-image.sh --lab          # + meta-ast2600-lab (hwmon/lm75)
./scripts/build-image.sh --secureboot   # + meta-ast2600-secureboot (FIT/OTP signing on)
```

Each builds `obmc-phosphor-image` from its own `~/openbmc/build/evb-ast2600[-variant]`
directory (created on first run, sharing `downloads/`/`sstate-cache/` with
the base build dir so nothing is re-fetched or re-compiled per variant).
An incremental rebuild after a small recipe change is much faster than the
initial build (well under two minutes in this lab's own testing).

After building, the deploy image's checksum should be recorded in
`scripts/golden-<variant>.sha256` — `run-qemu.sh` refuses to boot a copy
that doesn't match. If you rebuild an image yourself, regenerate that file:

```
sha256sum ~/openbmc/build/evb-ast2600<variant-suffix>/tmp/deploy/images/evb-ast2600/obmc-phosphor-image-evb-ast2600-*.static.mtd \
    > scripts/golden-<variant>.sha256
```

## Boot a variant under QEMU

```
./scripts/run-qemu.sh                  # base, 180s timeout
./scripts/run-qemu.sh --lab            # lab variant
./scripts/run-qemu.sh --secureboot     # secureboot variant (needs the patched QEMU above)
./scripts/run-qemu.sh --interactive    # no timeout, auto-logs in, drops to a shell
```

Never boots the deploy image directly — always copies into `work/` first
(gitignored), so the artifact bitbake produced stays byte-identical.
Console is driven by `scripts/qemu-console.py`, which auto-sends the
stock OpenBMC login (`root` / `0penBmc`), and logs everything to
`work/logs/`. ssh is reachable at `ssh -p 2222 root@127.0.0.1` once booted.

## Diff base vs. lab boot output

```
./scripts/diff-boot.sh
```

Boots both variants, normalizes non-deterministic output (timestamps, MAC
addresses, PIDs, etc.), and diffs the sorted result — see the script's own
comments for why sorted rather than sequential.

## Run the vboot ROM's own test suite

```
cd layers/meta-ast2600-secureboot/vbootrom-ast2600
./run-tests.sh --keep-going
```

Exercises the full RSA-size × SHA-mode × AES-mode matrix against real
`socsec` reference vectors checked into `test-vectors/`, plus this lab's
own real signed SPL/OTP image if `build-image.sh --secureboot` has already
been run locally (skipped with a clear message otherwise, not a hard
failure).

## Run the tamper-demonstration experiments

```
cd experiments/secure-boot-demo
./run-all.sh --keep-going    # all five: A, B, C, D1, D2
./exp-a-stale-hash.sh        # or any single experiment directly
```

| Exp | Variant | Tamper | Machine | Result |
|---|---|---|---|---|
| A | lab | ramdisk tampered, hash left stale | `ast2600-evb` | caught (`Bad Data Hash`) |
| B | lab | same tamper, hash correctly recomputed | `ast2600-evb` | boots unchallenged — a hash proves nothing about *who* rebuilt it |
| C | secureboot | same tamper, FIT naively resigned (no private key) | `ast2600-evb` | rejected (real signature check fails) |
| D1 | secureboot | SPL + U-Boot-proper replaced, signed with a fresh attacker keypair | `ast2600-evb` (no ROM/OTP anchor) | boots unchallenged — nothing verifies SPL itself |
| D2 | secureboot | identical attacker substitution | `ast2600-evb-secureboot` (real vboot ROM + OTP-fused key) | rejected before SPL ever executes |

Needs both the `lab` and `secureboot` variants already built, the patched
QEMU for C/D1/D2, and the vboot ROM's own OTP image
(`layers/meta-ast2600-secureboot/vbootrom-ast2600/gen-lab-otp-image.sh`)
for D2 — see `experiments/secure-boot-demo/README.md` for full detail.
D1 vs. D2 is the actual payoff: identical attacker artifact, only the
anchor differs, only the anchored boot catches it.

## Ground rules carried over from this repo's development

- Never edit `~/openbmc` directly — everything here lives in this repo's
  own layers, added via generated `bblayers.conf` files per build dir.
- Never boot a golden deploy image directly — always through
  `scripts/run-qemu.sh` or the experiment scripts, which copy first.

## License

Split-licensed, file by file — see `LICENSE` for the breakdown and
`LICENSES/` for the full texts. Original work here is MIT; a handful of
files ported near-verbatim from U-Boot
(`layers/meta-ast2600-secureboot/vbootrom-ast2600/sha256.*`,
`sha512.*`, `aes.*`, `rsa_mod_exp.c`, `rsa.h`, `pkcs15.h`) and the QEMU/
U-Boot patch files stay GPL-2.0-or-later, matching their upstream
license. Every file carries its own `SPDX-License-Identifier` (inline,
or in a `.license` sidecar file), so no need to infer it from directory
alone.
