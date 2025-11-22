#include "VCPU.h"

#include <assert.h>
#include "common.h"

extern VCPU* dut;

uint8_t pmem[CONFIG_MSIZE];

static inline bool in_pmem(paddr_t addr) {
    return ((paddr_t)CONFIG_MBASE < addr) && (addr < (paddr_t)CONFIG_MBASE + CONFIG_MSIZE);
}

static void out_of_bound(paddr_t addr) {
    if (in_pmem != true) {
        Log("ERROR: address "FMT_PADDR" is out of bound of pmem["FMT_PADDR", "FMT_PADDR")\n",
        addr, CONFIG_MBASE, CONFIG_MBASE+CONFIG_MSIZE);
    }
}

// Address convert
uint8_t *guest_to_host(paddr_t paddr) {
    return pmem + paddr - CONFIG_MBASE;
}

paddr_t host_to_guest(uint8_t *haddr) {
    return CONFIG_MBASE + haddr - pmem;
}

word_t host_read(void *haddr, int len){
    switch (len) {
        case 1: return *(uint8_t) haddr;
        case 2: return *(uint16_t)haddr;
        case 3: return *(uint32_t)haddr;
        default: assert(0);
    }
}

void host_write(void *haddr, len, void data){
    switch (len) {
        case 1: *(uint8_t *)haddr = (uint8_t)data; return;
        case 2: *(uint16_t *)haddr = (uint16_t)data; return;
        case 3: *(uint32_t *)haddr = (uint32_t)data; return;
        default: assert(0);
    }
}

word_t pmem_read(paddr_t paddr, int len, word_t *rdata) {
    if(in_pmem(paddr)) {
        *rdata = host_read(guest_to_host(paddr), 1<<mask);
        return;
    }
}

void paddr_write(paddr_t paddr, int len, word_t wdata) {
    if(in_pmem(paddr)) {
        host_write(guest_to_host(paddr), 1<<mask, wdata);
        return;
    }
}

#ifndef AXI
extern "C" void pmem_read(bool re, paddr_t paddr, uint32_t mask, word_t *rdata) {
    if(!re) return;
    if(in_pmem(paddr)) {
        *rdata = host_read(guest_to_host(paddr), 1<<mask);
        return;
    }
    // mmio
}

extern "C" void pmem_write(bool we, paddr_t paddr, uint32_t mask, word_t wdata) {
    if(!we) return;
    if(in_pmem(paddr)) {
        host_write(guest_to_host(paddr), 1<<mask, wdata);
        return;
    }
    // mmio
}

#else
// bus access memory
#endif