/***************************************************************************************
* Copyright (c) 2025, Chen Yiming, Huazhong University of Science and Technology
*
* This is my iringbuf realization
***************************************************************************************/
#ifndef _CPU_IRINGBUF_H_
#define _CPU_IRINGBUF_H_

#include <stddef.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>

typedef struct {
    char (*ringbuffer)[128];
    int size;
    size_t head;
    size_t tail;
    bool full;
} iringbuf;

iringbuf *iringbuf_init(int size);
void iringbuf_free(iringbuf *rb);
char *iringbuf_write(iringbuf *rb, const char *data);
char *iringbuf_read(iringbuf *rb, int size);

#endif
