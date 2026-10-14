#ifndef NPC_PLATFORM_H
#define NPC_PLATFORM_H
#include <stddef.h>
#include <stdint.h>
void platform_init();
void platform_sample();
void platform_tick();
void platform_report();
void platform_load(size_t size);
uint32_t platform_read(uint32_t addr, int size);
void platform_write(uint32_t addr, int size, uint32_t data);
#endif
