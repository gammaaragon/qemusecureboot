# SPDX-License-Identifier: MIT
FILESEXTRAPATHS:prepend := "${THISDIR}/${PN}:"

SRC_URI += " \
    file://obmc/hwmon/ahb/apb/bus@1e78a000/i2c@480/lm75@4d.conf \
"

do_install:append() {
    install -d ${D}${sysconfdir}/default/obmc/hwmon/ahb/apb/bus@1e78a000/i2c@480
    install -m 0644 ${UNPACKDIR}/obmc/hwmon/ahb/apb/bus@1e78a000/i2c@480/lm75@4d.conf \
        ${D}${sysconfdir}/default/obmc/hwmon/ahb/apb/bus@1e78a000/i2c@480/lm75@4d.conf
}
