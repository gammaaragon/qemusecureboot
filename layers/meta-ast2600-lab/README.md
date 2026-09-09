<!-- SPDX-License-Identifier: MIT -->

meta-ast2600-lab
================

Local sensor customization layer for the evb-ast2600 QEMU lab in this repo.
Depends on `phosphor-layer` (meta-phosphor) for the `phosphor-hwmon` recipe
it appends, and is built against the `evb-ast2600` machine from
meta-evb-ast2600 / the AST2600 SoC support in meta-aspeed.

Currently adds one lm75 temperature sensor at i2c bus@1e78a000/i2c@480,
address 0x4d, via a `phosphor-hwmon` bbappend.

Not upstream material — this is lab/tutorial-specific hardware description,
kept out of the pristine `~/openbmc` clone so that tree stays clean for
sending real patches upstream. See `../../CLAUDE.md` and
`scripts/build-image.sh` for how it's wired into a build.
