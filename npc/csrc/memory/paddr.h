#ifndef __PADDR_H__
#define __PADDR_H__

#include "common.h"

#define PMEM_LEFT  ((paddr_t)CONFIG_MBASE)
#define PMEM_RIGHT ((paddr_t)CONFIG_MBASE + CONFIG_MSIZE - 1)
#define RESET_VECTOR (PMEM_LEFT + CONFIG_PC_RESET_OFFSET)

// used both in paddr and mmio
static inline bool in_pmem(paddr_t addr) {
    return (addr >= CONFIG_MBASE) && (addr < (paddr_t)CONFIG_MBASE + CONFIG_MSIZE);
}

void pmem_read();
void pmem_write();

#endif
