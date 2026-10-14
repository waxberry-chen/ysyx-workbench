#include "Vaxi4lite_xbar_test_top.h"
#include "verilated.h"
int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);
    Vaxi4lite_xbar_test_top dut;
    dut.clk = 0;
    dut.rst_n = 0;
    dut.eval(); // Invalid configuration must fail here, before any transaction.
    dut.final();
    return 0;
}
