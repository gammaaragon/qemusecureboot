<!-- SPDX-License-Identifier: MIT -->

# Security policy

## What this project is

This is an emulation lab for studying the AST2600 secure-boot chain under
QEMU. The boot ROM in
`layers/meta-ast2600-secureboot/vbootrom-ast2600/` performs real RSA/SHA
signature verification against a key held in an emulated OTP region, and
the experiments under `experiments/secure-boot-demo/` demonstrate real
attacks being caught. None of it is production firmware.

**Do not use this boot ROM as a trust anchor on real hardware.** It is
written to be read, instrumented and stepped through, not to resist an
attacker. Among other things it makes no attempt at constant-time
comparison, fault-injection resistance, glitch detection, anti-rollback,
or any of the other properties a real ROM-level root of trust needs. Its
purpose is to make an otherwise unobservable boot stage observable.

## Keys in this repository

There are no real keys here, and none are secret:

- The attacker keypairs used by experiments D1/D2/D3 are generated fresh
  at run time into gitignored `work/` directories. They exist to play the
  part of "a key the hardware does not trust" and protect nothing.
- `layers/meta-ast2600-secureboot/vbootrom-ast2600/test-vectors/` contains
  ASPEED's own published `socsec` reference fixtures, MIT-licensed. The
  `mode2aes2` variants' `otp-data.bin` includes an RSA private exponent
  by design, because that mode unwraps an RSA-wrapped AES key with a key
  held in OTP. It is upstream public test material.

If a secret scanner flags anything in this repository, that is what it
found.

## Reporting a problem

For a bug in this code — a verification path that accepts something it
should reject, an experiment that passes for the wrong reason, a build
that does not reproduce — please open an issue.

If you believe you have found something with real-world security impact
beyond this lab (for example, a claim made here about AST2600 silicon
behaviour that is wrong in a way that could mislead someone building real
firmware), please open an issue for that too. Nothing in this repository
runs on anyone's production system, so there is no embargo process and
no private disclosure channel.

Issues about ASPEED silicon or about OpenBMC itself belong with those
projects, not here.
