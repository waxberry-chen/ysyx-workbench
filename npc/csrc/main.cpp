#include <verilated_fst_c.h>
#include "Vysyx_core.h"

#include <stdio.h>
#include "./include/common.h"
#include "./include/debug.h"
#include "./utils/disasm.h"

// ********** Hardware **********
Vysyx_core *dut = new Vysyx_core;
VerilatedFstC *m_trace = new VerilatedFstC;

size_t sim_time = 0;
CPU_state sim_cpu;

uint32_t *cpu_gpr = NULL;
// uint32_t *cpu_csr[NR_CSR];

extern SimState sim_state;

int main(int argc, char *argv[]) {
  printf(ANSI_FG_YELLOW "Hello, ysyx!\n" ANSI_NONE);
  printf(ANSI_FG_GREEN  "Loading img: %s\n" ANSI_NONE , argv[1]);
  // ***** load img into memory *****
  uint64_t size = load_img(argv[1]); 
  // no difftest temporarily
  init_disasm("riscv32");

  init_sdb(argv[2]);
  // wave tracer
  Verilated::traceEverOn(true);
  dut->trace(m_trace, 5);
  m_trace->open("waveform.fst");
  reset(1);

  sdb_mainloop();

  printf(ANSI_FG_GREEN "Testcase end!\n" ANSI_NONE);

  m_trace->close();
  delete dut;
  return sim_state.state == SIM_ABORT;
}
