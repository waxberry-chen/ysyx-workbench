#ifndef __COMMON_H__
#define __COMMON_H__

#include <stdio.h>
#include <stdint.h>
#include <assert.h>

#define MAX_SIM_TIME 4000000

typedef uint32_t word_t; 
typedef int32_t sword_t; 
typedef unsigned long long duword_t;
typedef long long dsword_t;

#define FMT_WORD "0x%08x"

typedef word_t vaddr_t;
typedef word_t paddr_t;
typedef uint16_t ioaddr_t;

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

extern CPU_state sim_cpu;

uint64_t load_img(char *img_name);

#endif
