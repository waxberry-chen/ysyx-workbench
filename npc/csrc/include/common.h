#ifndef __COMMON_H__
#define __COMMON_H__

#include <stdio.h>
#include <stdint.h>
#include <assert.h>
#include <stdbool.h>
#include <string.h>
#include <stdlib.h> // malloc

#include "config.h"
#include "debug.h"
#include "macro.h"

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

// Harness maintain states for RTL and simulation process
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
uint64_t load_img(const char *img_name);
// DPI-C
extern "C" void pmem_read(bool re, paddr_t raddr, uint32_t mask, word_t *rdata);
extern "C" void pmem_write(bool we, paddr_t waddr, uint32_t mask, word_t wdata);

word_t paddr_read(paddr_t addr, int len);
void paddr_write(paddr_t addr, int len, word_t wdata);
word_t host_read(void *haddr, int len);
void host_write(void *haddr, int len, word_t wdata);

uint8_t* guest_to_host(paddr_t paddr);
paddr_t host_to_guest(uint8_t *haddr);

/**************
*     SDB     *
***************/
void init_sdb(int argc, char **argv);
void sdb_mainloop();
void cpu_exec(unsigned int n);
// isa.h in nemu
// define in sim.c
void isa_reg_display();
word_t isa_reg_str2val(const char *s, bool *success);

typedef struct {
    int difftest_port;
    const char *log_file;
    const char *diff_so_file;
    const char *elf_file;
    const char *img_file;
} Sdb_args;

extern Sdb_args sdb_args;

/***************
*   Difftest   *
****************/

void difftest_skip_ref();
void difftest_init_npc(const char *ref_so_file, long img_size, int port);
void difftest_sync();
void difftest_step(vaddr_t pc, word_t inst, bool skip_ref, uint64_t nr_inst);

/***********
*   MMIO   *
***********/
void init_device();

word_t mmio_read(paddr_t addr, int len);
void mmio_write(paddr_t addr, int len, word_t data);

/* get time */
uint64_t get_time();      // relative time (us-level)
struct tm *get_time_tm(); // real time

#endif
