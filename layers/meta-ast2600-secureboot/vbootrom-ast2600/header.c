/* SPDX-License-Identifier: MIT */
#include "header.h"
#include "io.h"

void header_read(unsigned int image_base, unsigned int header_offset,
                 struct rot_header *hdr)
{
    unsigned int base = image_base + header_offset;

    hdr->aes_data_offset = readl(base + 0);
    hdr->enc_offset = readl(base + 4);
    hdr->sign_image_size = readl(base + 8);
    hdr->signature_offset = readl(base + 12);
    hdr->revision_low = readl(base + 16);
    hdr->revision_high = readl(base + 20);
    hdr->flash_patch_offset = readl(base + 24);
    hdr->checksum = readl(base + 28);
}

int header_checksum_valid(const struct rot_header *hdr)
{
    unsigned int sum = hdr->aes_data_offset + hdr->enc_offset +
                       hdr->sign_image_size + hdr->signature_offset +
                       hdr->revision_low + hdr->revision_high +
                       hdr->flash_patch_offset;
    unsigned int expected = (unsigned int)(-(int)sum);

    return expected == hdr->checksum;
}
