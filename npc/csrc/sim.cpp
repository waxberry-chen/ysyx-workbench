#include "verilated_dpi.h"
#include "Vysyx_core.h"
#include "verilated_fst_c.h"
#include <bits/stdc++.h>
#include "include/debug.h"
#include "include/common.h"
#include "include/ram_model.h"
#include "include/commit_trace.h"
#include "include/sim_stats.h"
#include "utils/disasm.h"
#include "memory/paddr.h"

using namespace std;

extern Vysyx_core *dut;
extern uint64_t sim_time;
extern VerilatedFstC *m_trace;
extern uint8_t pmem[];

typedef struct {
  word_t pc;
  word_t inst;
  char asm_buf[128];
} inst_log;

void itrace_commit_print(inst_log *inst_log, vaddr_t commit_pc, word_t commit_inst);
// void difftest_step();

// str: a string buffer, dump disasmbled asm code. 
// size: size of str buffer. 
// pc: the pc of inst. 
// code: inst code. 
// nbyte: the length of inst code, representative value is 4. 
extern void disassemble(char *str, int size, uint64_t pc, uint8_t *code, int nbyte);

static const char *csr_names[] = {"mstatus", "mtvec", "mepc",  "mcause"};
// uint32_t *cpu_mstatus = NULL, *cpu_mtvec = NULL, *cpu_mepc = NULL, *cpu_mcause = NULL;

// load the state of your simulated cpu into sim_cpu
// called in every sim cycle
void set_state() {
  sim_cpu.pc = dut->commit_pc;
  memcpy(&sim_cpu.gpr[0], cpu_gpr, 4 * 32);
  sim_cpu.csr.mstatus = *cpu_csr[CSR_MSTATUS];
  sim_cpu.csr.mtvec   = *cpu_csr[CSR_MTVEC];
  sim_cpu.csr.mepc    = *cpu_csr[CSR_MEPC];
  sim_cpu.csr.mcause  = *cpu_csr[CSR_MCAUSE];
}

// num of executed instruction
uint64_t g_nr_guest_inst = 0;

// simulate a single cycle
void single_cycle() {
  // Drive and settle inputs while clk is low so the FST contains the values
  // sampled by the following active edge.
  dut->clk = 0;
  ram_model_drive();
  dut->eval();
  #ifdef CONFIG_FST
    m_trace->dump(sim_time++);
  #endif

  sim_stats_sample_cycle(dut->rst_n,
                         dut->ifu_axi_arvalid, dut->ifu_axi_arready,
                         dut->ifu_axi_rvalid, dut->ifu_axi_rready,
                         dut->lsu_axi_arvalid, dut->lsu_axi_arready,
                         dut->lsu_axi_rvalid, dut->lsu_axi_rready,
                         dut->lsu_axi_awvalid, dut->lsu_axi_awready,
                         dut->lsu_axi_wvalid, dut->lsu_axi_wready,
                         dut->lsu_axi_bvalid, dut->lsu_axi_bready);

  ram_model_sample();

  dut->clk = 1;
  dut->eval();
  #ifdef CONFIG_FST
    m_trace->dump(sim_time++);
  #endif
  ram_model_tick();

  dut->clk = 0;
  #ifdef AXI
  pmem_write();
  pmem_read();
  #endif
  dut->eval();
  #ifdef CONFIG_FST
    m_trace->dump(sim_time++);
  #endif
}

// simulate a reset
void reset(int n) {
  dut->clk = 0;
  dut->rst_n = 0;
  dut->eval();
  while (n-- > 0) {
    single_cycle();
  }
  dut->rst_n = 1;
  dut->eval();  // use to load first inst
  set_state();
}

// ** End simulation by software **
// check if the program should end, run to ebreak
inline bool test_break(){
  return dut->commit_inst == 0x00100073U;
}

static void statistic() {
  Log("total guest instructions = %ld", g_nr_guest_inst);
  sim_stats_report();
  ram_model_report();
}

// void device_update();
// init the running state of our simulator
SimState sim_state = { .state = SIM_STOP };


// execute n instructions
void cpu_exec(unsigned int n){
  switch (sim_state.state) {
    case SIM_END: case SIM_ABORT: case SIM_QUIT:
      printf("Program execution has ended. To restart the program, exit NPC and run again.\n");
      return;
    default: sim_state.state = SIM_RUNNING;
  }
  inst_log inst_log;

  // do not print to much insts in sdb
  #ifdef CONFIG_ITRACE
  bool itrace_print = false; 
  if (n < CONFIG_ITRACE_MAX_INST) itrace_print = true;
  #endif

  while (n > 0) {    
    // Capture the instruction and its commit metadata before the active edge.
    // They describe the instruction or precise exception event that the
    // following single_cycle() will commit.
    bool will_commit = dut->commit_valid;
    vaddr_t commit_pc = dut->commit_pc;
    word_t commit_inst = dut->commit_inst;
    bool skip_ref = dut->commit_is_mmio;
    CommitInfo commit_info = {
      .exception = (bool)dut->commit_exception,
      .exception_cause = dut->commit_exception_cause,
      .redirect = (bool)dut->commit_redirect_valid,
      .redirect_reason = dut->commit_redirect_reason,
      .mem_valid = (bool)dut->commit_mem_valid,
      .mem_write = (bool)dut->commit_mem_write,
      .mem_addr = dut->commit_mem_addr,
      .mem_error = (bool)dut->commit_mem_error,
      .cycles_since_commit = 0,
      .stall_mask = 0,
    };

    if(will_commit && !commit_info.exception && test_break()) {
      // set the end state
      sim_state.halt_pc = dut->commit_pc;
      sim_state.halt_ret = cpu_gpr[10];
      sim_state.state = SIM_END;
      break;
    }

    // your cpu step a cycle
    single_cycle();

    // A DPI-C memory access may terminate the simulation during eval().  Stop
    // before committing or running DiffTest with the placeholder read value.
    if (sim_state.state != SIM_RUNNING) break;

    if (will_commit) {
      set_state();
      const CommitCycleObservation cycle_observation =
          sim_stats_take_commit_observation();
      commit_info.cycles_since_commit = cycle_observation.cycles;
      commit_info.stall_mask = cycle_observation.stall_mask;
      g_nr_guest_inst++;
      sim_stats_record_commit(commit_pc, sim_cpu.pc);
      commit_trace_record(g_nr_guest_inst, commit_pc, commit_inst, &sim_cpu,
                          &commit_info);
      n--;
      #ifdef CONFIG_ITRACE
      if(itrace_print){
        itrace_commit_print(&inst_log, commit_pc, commit_inst);
      }
      #endif
      difftest_step(commit_pc, commit_inst, skip_ref, g_nr_guest_inst,
                    &commit_info);
    }


  #ifdef DEVICE
      // device_update();
  #endif
    if(sim_state.state != SIM_RUNNING) break;
  }

  switch (sim_state.state) {
    case SIM_RUNNING: sim_state.state = SIM_STOP; break;
    case SIM_END: case SIM_ABORT:
      Log("sim: %s at pc = " FMT_WORD,
          (sim_state.state == SIM_ABORT ? ANSI_FMT("ABORT", ANSI_FG_RED) :
           (sim_state.halt_ret == 0 ? ANSI_FMT("HIT GOOD TRAP", ANSI_FG_GREEN) :
            ANSI_FMT("HIT BAD TRAP", ANSI_FG_RED))),
          sim_state.halt_pc);
      // fall through
    case SIM_QUIT: statistic();
  }
}

static const char *regs[] = {
  "$0", "ra", "sp", "gp", "tp", "t0", "t1", "t2",
  "s0", "s1", "a0", "a1", "a2", "a3", "a4", "a5",
  "a6", "a7", "s2", "s3", "s4", "s5", "s6", "s7",
  "s8", "s9", "s10", "s11", "t3", "t4", "t5", "t6"
};

// map the name of reg to its value
word_t isa_reg_str2val(const char *s, bool *success) {;
  if(!strcmp(s, "pc")){
    *success = true;
    return dut->commit_pc;
  }
  for(int i = 0; i < 32; i++){
    if(!strcmp(s, regs[i])){
      *success = true;
      return cpu_gpr[i];
    }
  }
  *success = false;
  return 0;
}

/********** RTL Registers' Interface **********/
// set cpu_gpr point to your cpu's gpr
extern "C" void set_gpr_ptr(const svOpenArrayHandle r) {
  cpu_gpr = (uint32_t *)(((VerilatedDpiOpenVar*)r)->datap());
}
// set the pointers pint to you cpu's csr
extern "C" void set_csr_ptr(const svOpenArrayHandle mstatus, const svOpenArrayHandle mtvec, const svOpenArrayHandle mepc, const svOpenArrayHandle mcause) {
  cpu_csr[CSR_MSTATUS] = (uint32_t *)(((VerilatedDpiOpenVar*)mstatus)->datap());
  cpu_csr[CSR_MTVEC] = (uint32_t *)(((VerilatedDpiOpenVar*)mtvec)->datap());
  cpu_csr[CSR_MEPC] = (uint32_t *)(((VerilatedDpiOpenVar*)mepc)->datap());
  cpu_csr[CSR_MCAUSE] = (uint32_t *)(((VerilatedDpiOpenVar*)mcause)->datap());
}
/**********************************************/

void isa_reg_display() {
  for (int i = 0; i < 32; i++) {
    printf("gpr[%d](%s) = 0x%x\n", i, regs[i], cpu_gpr[i]);
  }
  for (int i = 0; i < NR_CSR; i++) {
    printf("csr(%s) = 0x%08x\n", csr_names[i], *cpu_csr[i]);
  }
}

void itrace_commit_print(inst_log *inst_log, vaddr_t commit_pc, word_t commit_inst) {
  // disassemble and print based on commit_pc and commit_inst
  inst_log->pc = commit_pc;
  inst_log->inst = commit_inst;
  disassemble(inst_log->asm_buf, sizeof(inst_log->asm_buf), inst_log->pc, (uint8_t *)&inst_log->inst, 4);
  printf("0x%08x: %08x\t%s\n", inst_log->pc, inst_log->inst, inst_log->asm_buf);
}
