#include "Vaxi4lite_slaves_test_top.h"
#include "verilated.h"
int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);
    Vaxi4lite_slaves_test_top dut;
    dut.clk = 0;
    dut.rst_n = 0;
    dut.eval();
    dut.final();
    return 0;
}
