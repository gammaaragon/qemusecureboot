/* SPDX-License-Identifier: MIT */
#include "scu.h"
#include "io.h"

#define SCU_HW_STRAP1 0x1E6E2500u

int scu_read_hw_strap_secure_boot(void)
{
    return (readl(SCU_HW_STRAP1) & SCU_HW_STRAP1_SECURE_BOOT_EN) != 0;
}
