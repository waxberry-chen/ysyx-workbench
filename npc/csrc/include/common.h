#ifndef __COMMON_H__
#define __COMMON_H__

#include <stdio.h>
#include <stdint.h>
#include <assert.h>
#include <stdbool.h>

#include "config.h"
#include "debug.h"

#define MAX_SIM_TIME 4000000

/***************
*     TYPE     *
****************/
typedef uint32_t word_t; 
typedef int32_t sword_t; 
typedef unsigned long long duword_t;
typedef long long dsword_t;

#define FMT_WORD "0x%08x"
#define FMT_PADDR "0x%08x"

typedef word_t vaddr_t;
typedef word_t paddr_t;
typedef uint16_t ioaddr_t;

/*****************
*     GLOBAL     *
******************/
extern uint32_t *cpu_gpr;

// typedef struct {
//     word_t mepc;
//     word_t mstatus;
//     word_t mcause;
//     word_t mtvec;
// } CSR;

typedef struct {
    word_t gpr[32];
    word_t pc;
} CPU_state;

typedef struct {
    int state;
    vaddr_t halt_pc;
    uint32_t halt_ret;
} SimState;

enum {SIM_RUNNING, SIM_STOP, SIM_END, SIM_ABORT, SIM_QUIT};

extern CPU_state sim_cpu;
extern SimState sim_state;

/*********************
*     SIMULATION     *
**********************/
void single_cycle();
void reset(int n);
// halt
bool test_break();

/*****************
*     MEMORY     *
******************/
uint64_t load_img(char *img_name);
// DPI-C
extern "C" void pmem_read(bool re, paddr_t raddr, uint32_t mask, word_t *rdata);
extern "C" void pmem_write(bool we, paddr_t waddr, uint32_t mask, word_t wdata);
word_t paddr_read(paddr_t addr, int len, word_t *rdata);
void paddr_write(paddr_t addr, int len, word_t wdata);
word_t host_read(void *haddr, int len);
void host_write(void *haddr, int len, word_t wdata);

/**************
*     SBD     *
***************/
void init_sdb();
void sdb_mainloop();
void cpu_exec(unsigned int n);
void isa_reg_display();
word_t isa_reg_str2val(const char *s, bool *success);


#endif
