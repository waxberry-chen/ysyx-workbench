#include <cpu/iringbuf.h>
#include <stdio.h>
#include <string.h>
#include <stdbool.h>

iringbuf *iringbuf_init(int size) {
    iringbuf *rb = malloc(sizeof(iringbuf));
    if (rb == NULL) {
        printf("ERROR: iringbuf init failed");
        return NULL;
    }
    rb->ringbuffer = malloc(size * sizeof(char[128]));
    if(rb->ringbuffer == NULL) {
        printf("ERROR: iringbuf ringbuffer malloc failed");
        free(rb);
        return NULL;
    }
    rb->size = size;
    rb->head = 0;
    rb->tail = 0;
    rb->full = false;
    return rb;
}

void iringbuf_free(iringbuf *rb) {
    if (rb == NULL) {
        printf("ERROR: iringbuf_destroy recieve NULL");
        return;
    }
    free(rb->ringbuffer);
    free(rb);
}

char *iringbuf_write(iringbuf *rb, const char *data) {
    if (rb == NULL) {
        printf("ERROR: iringbuf_write recieve NULL");
        return NULL;
    }
    strcpy(rb->ringbuffer[rb->head], data);
    rb->head = (rb->head+1) % rb->size;
    return rb->ringbuffer[rb->head];
}

char *iringbuf_read(iringbuf *rb, int size) {
    if(size > rb->size) {
        printf("ERROR: read size overflow");
        return NULL; 
    }
    char *iringbuf_out = malloc(size*sizeof(char[128]));
    char *current_pos = iringbuf_out;
    // size_t read_ptr = (rb->head + rb->size - 1) % rb->size;
    size_t read_ptr = (rb->head + size - rb->size) % size;
    for(int i = 0; i < size; i++) {
        int len = sprintf(current_pos, "\t%s\n", rb->ringbuffer[read_ptr]); // not safe
        current_pos += len;
        read_ptr = (read_ptr+1) % rb->size;
    }
    return iringbuf_out;
}