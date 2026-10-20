#ifndef NEMU_YSYXSOC_H
#define NEMU_YSYXSOC_H
#include <common.h>
bool soc_memory_span(paddr_t addr, size_t n);
bool soc_memory_writable(paddr_t addr, size_t n);
bool soc_device_access(paddr_t addr, int len, bool write);
#endif
