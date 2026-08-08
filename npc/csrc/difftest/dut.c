/*******************************************
*   Difftest related functions on NPC side *
*******************************************/
#include "common.h"
#include "debug.h"
#include <dlfcn.h>

enum { DIFFTEST_TO_DUT, DIFFTEST_TO_REF };

/* Function pointers of NEMU's API funcitons */
void (*difftest_memcpy)(paddr_t addr, void *buf, size_t n, bool direction) = NULL;
void (*difftest_regcpy)(void *dut, bool direction) = NULL;
void (*difftest_exec)(uint64_t n) = NULL;
void (*difftest_raise_intr)(word_t NO) = NULL;
void (*difftest_init)(int port) = NULL;

/* predefined units */
extern uint8_t pmem[];
static uint8_t ref_pmem[CONFIG_MSIZE];

static const char *regs[] = {
  "$0", "ra", "sp", "gp", "tp", "t0", "t1", "t2",
  "s0", "s1", "a0", "a1", "a2", "a3", "a4", "a5",
  "a6", "a7", "s2", "s3", "s4", "s5", "s6", "s7",
  "s8", "s9", "s10", "s11", "t3", "t4", "t5", "t6"
};  // reg table

/* Skip */
static bool is_skip_ref = false;
static int skip_dut_nr_inst = 0;

void difftest_skip_ref() {
    is_skip_ref = true;
    skip_dut_nr_inst = 0;
}

void difftest_skip_dut(int nr_ref, int nr_dut) {
    skip_dut_nr_inst += nr_dut;
    while (nr_ref-- > 0) {
        difftest_exec(1);   // n steps ahead for ref
    }
}

// difftest_init 
void difftest_init_npc(const char *ref_so_file, long img_size, int port) {
    assert(ref_so_file != NULL);
    Log("open dynamic lib: %s", ref_so_file);
    
    void *handle; 
    handle = dlopen(ref_so_file, RTLD_LAZY); 
    // Resolve symbols only as the code that references them is executed. 
    assert(handle);

    // find symbols
    difftest_memcpy = (void (*)(paddr_t, void *, size_t, bool))dlsym(handle, "difftest_memcpy");
    assert(difftest_memcpy);
    difftest_regcpy = (void (*)(void *, bool))dlsym(handle, "difftest_regcpy");
    assert(difftest_regcpy);
    difftest_exec = (void (*)(uint64_t))dlsym(handle, "difftest_exec");
    assert(difftest_exec);
    difftest_init = (void (*)(int))dlsym(handle, "difftest_init");
    assert(difftest_init);

    Log("Differential testing: %s", ANSI_FMT("ON", ANSI_FG_GREEN));

    difftest_init(port);
    // init the state to NEMU
    difftest_memcpy(CONFIG_MBASE, guest_to_host(CONFIG_MBASE), CONFIG_MSIZE, DIFFTEST_TO_REF);
    sim_cpu.pc = CONFIG_MBASE;
    difftest_regcpy(&sim_cpu, DIFFTEST_TO_REF); // CPU_state type contains pc
}

// specific isa-related regs check
bool isa_difftest_checkregs(CPU_state *ref_r, vaddr_t pc) {
    // check gpr first
    for (int i=0; i<32; i++) {
        if(sim_cpu.gpr[i] != ref_r->gpr[i]) {
            printf(ANSI_BG_RED "DIFFTEST: gpr[%d] (%s) = 0x" FMT_WORD " (dut); 0x" 
            FMT_WORD " (nemu)" ANSI_NONE "\n", i, regs[i], sim_cpu.gpr[i], ref_r->gpr[i]);
            return false;
        }
    }
    // pc 
    if (sim_cpu.pc != ref_r->pc) {
        printf(ANSI_BG_RED "DIFFTEST: pc = 0x" FMT_WORD " (dut.pc); 0x" FMT_WORD " (nemu.pc)" ANSI_NONE "\n", sim_cpu.pc, ref_r->pc);
        return false;
    }
    return true;
}

// check mem
bool isa_difftest_checkmem(uint8_t *ref_pmem, vaddr_t pc) {
  for (int i = 0; i < CONFIG_MSIZE; i++){
    if (ref_pmem[i] != pmem[i]) {
      printf(ANSI_BG_RED "memory of NPC is different before executing instruction at pc = " FMT_WORD
        ", mem[%x] right = " FMT_WORD ", wrong = " FMT_WORD ", diff = " FMT_WORD ANSI_NONE "\n",
        sim_cpu.pc, i, ref_pmem[i], pmem[i], ref_pmem[i] ^ pmem[i]); 
      return false;
    }
  }
  return true;
}

static void checkregs(CPU_state *ref, vaddr_t pc) {
  if (!isa_difftest_checkregs(ref, pc)) {
    sim_state.state = SIM_ABORT;
    sim_state.halt_pc = pc;
    isa_reg_display();
  }
}

static void checkmem(uint8_t *ref_pmem, vaddr_t pc) {
  if (!isa_difftest_checkmem(ref_pmem, pc)) {
    sim_state.state = SIM_ABORT;
    sim_state.halt_pc = pc;
  }
}

void difftest_step() {
    CPU_state ref_r;
    difftest_regcpy(&ref_r, DIFFTEST_TO_DUT);   // ref_r maintained in harness, dut side
    difftest_exec(1);
    checkregs(&ref_r, sim_cpu.pc);
}

// copy our registers to nemu
void difftest_sync(){
  difftest_regcpy(&sim_cpu, DIFFTEST_TO_REF);
}