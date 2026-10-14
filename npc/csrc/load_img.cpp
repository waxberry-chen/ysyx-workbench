#include <stdio.h>
#include "common.h"
#include "debug.h"
#include "platform.h"

extern uint8_t pmem[];

uint64_t load_img(const char *img_name) {
    if (img_name == NULL) {
        Log("No image given in npc-load_img");
        exit(1);
    }
    FILE *fp = fopen(img_name, "rb");
    Assert(fp, "ERROR: Cannot load img %s", img_name);

    fseek(fp, 0, SEEK_END);
    long size = ftell(fp);

    if (size <= 0 || (uint64_t)size > CONFIG_MSIZE) {
        fprintf(stderr, "Image size %ld exceeds capacity %u or is empty\n", size, (unsigned)CONFIG_MSIZE);
        fclose(fp);
        exit(1);
    }
    Log("The image is %s, size = %ld", img_name, size);

    fseek(fp, 0, SEEK_SET);
    int ret = fread(pmem, size, 1, fp);
    assert(ret==1);

    fclose(fp);
    platform_load(size);
    return size;
}
