#include <stdio.h>
#include "common.h"
#include "debug.h"

extern uint8_t pmem[];

uint64_t load_img(char *img_name) {
    if (img_name == NULL) {
        Log("No image given in npc-load_img");
        return 4096;
    }
    FILE *fp = fopen(img_name, "rb");
    Assert(fp, "ERROR: Cannot load img %s", img_name);

    fseek(fp, 0, SEEK_END);
    long size = ftell(fp);

    Log("The image is %s, size = %ld", img_name, size);

    fseek(fp, 0, SEEK_SET);
    int ret = fread(pmem, size, 1, fp);
    assert(ret==1);

    fclose(fp);
    return size;
}