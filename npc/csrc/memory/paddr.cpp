#include "Vysyx_core.h"

#include <assert.h>
#include "common.h"

extern Vysyx_core *dut;

uint8_t pmem[CONFIG_MSIZE];

static inline bool in_pmem(paddr_t addr) {
    return (addr >= CONFIG_MBASE) && (addr < (paddr_t)CONFIG_MBASE + CONFIG_MSIZE);
}

static void out_of_bound(paddr_t addr) {
    Log("ERROR: address " FMT_PADDR " is out of bound of pmem[" FMT_PADDR ", " FMT_PADDR ")\n",
    addr, CONFIG_MBASE, CONFIG_MBASE+CONFIG_MSIZE);
}

// Address mapping between riscv code and PC
uint8_t *guest_to_host(paddr_t paddr) {
    return pmem + paddr - CONFIG_MBASE;
}

paddr_t host_to_guest(uint8_t *haddr) {
    return CONFIG_MBASE + haddr - pmem;
}

// here host addr use void*
word_t host_read(void *haddr, int size){
    switch (size) {
        case 1: return *(uint8_t  *)haddr;
        case 2: return *(uint16_t *)haddr;
        case 4: return *(uint32_t *)haddr;
        case 8: return *(uint64_t *)haddr;
        default: assert(0);
    }
}

void host_write(void *haddr, int size, word_t wdata){
    switch (size) {
        case 1: *(uint8_t *)haddr = wdata; return;
        case 2: *(uint16_t *)haddr = wdata; return;
        case 4: *(uint32_t *)haddr = wdata; return;
        case 8: *(uint64_t *)haddr = wdata; return;
        default: assert(0);
    }
}

// size: 1 2 4 8 (Byte)
word_t paddr_read(paddr_t paddr, int size) {
    if (in_pmem(paddr)) return host_read(guest_to_host(paddr), size);
    out_of_bound(paddr);
    return 0;
}

void paddr_write(paddr_t paddr, int size, word_t wdata) {
    if(in_pmem(paddr)) {
        host_write(guest_to_host(paddr), size, wdata);
        return;
    }
    out_of_bound(paddr);
}

#ifndef AXI
extern "C" void pmem_read(bool re, paddr_t paddr, uint32_t size, word_t *rdata) {
    if(!re) return;
    if(in_pmem(paddr)) {
        *rdata = host_read(guest_to_host(paddr), size);
        // printf("addr: %08x\tinst: %08x\n", paddr, *rdata); // debug
        return;
    }
    // mmio
}

extern "C" void pmem_write(bool we, paddr_t paddr, uint32_t size, word_t wdata) {
    if(!we) return;
    if(in_pmem(paddr)) {
        host_write(guest_to_host(paddr), size, wdata);
        return;
    }
    // mmio
}

#else
// bus access memory
#endif