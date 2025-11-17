#include <verilated_vcd_c.h>
#include "VCPU.h"

#include <stdio.h>
#include "./include/common.h"
#include "./include/debug.h"

// ********** Hardware **********
VCPU *dut = new VCPU;
VerilatedVcdC *m_trace = new VerilatedVcdC;

size_t sim_time = 0;
CPU_state sim_cpu;


int main(int argc, char *argv[]) {
  printf(ANSI_FG_YELLOW "Hello, ysyx!\n" ANSI_NONE);
  printf(ANSI_FG_GREEN  "Loading img: %s\n" ANSI_NONE , argv[1]);
  // ***** load img into memory *****
  uint64_t size = load_img(argv[1]); 
  

  return 0;
}
