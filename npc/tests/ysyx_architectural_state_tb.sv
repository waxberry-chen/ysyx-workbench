`timescale 1ns/1ps
module ysyx_architectural_state_tb;
    logic timer_irq=0;
    wire interrupt_pending;
    logic clk = 0, rst_n = 1;
    logic [4:0] rf_rs1 = 0, rf_rs2 = 0, rf_rd = 0;
    logic rf_we = 0;
    logic [31:0] rf_wd = 0;
    wire [31:0] rf_rd0, rf_rd1;
    logic [11:0] csr_addr = 0;
    logic [31:0] csr_wdata = 0, trap_epc = 0, trap_cause = 0;
    logic csr_we = 0, trap_valid = 0, mret_valid = 0;
    wire [31:0] csr_rdata, trap_target, mret_target;
    ysyx_regfile gpr (.*);
    ysyx_csr csr (.*);

    task automatic tick;
        #2; clk = 1; #2; clk = 0; #1;
    endtask
    task automatic check_gpr(input logic [4:0] index, input logic [31:0] expected);
        rf_rs1 = index; rf_rs2 = index; #1;
        if (rf_rd0 !== expected || rf_rd1 !== expected)
            $fatal(1, "GPR x%0d expected %h, got %h/%h", index, expected, rf_rd0, rf_rd1);
    endtask
    task automatic check_csr(input logic [11:0] addr, input logic [31:0] expected);
        csr_addr = addr; #1;
        if (csr_rdata !== expected)
            $fatal(1, "CSR %h expected %h, got %h", addr, expected, csr_rdata);
    endtask
    task automatic write_csr(input logic [11:0] addr, input logic [31:0] value);
        csr_addr = addr; csr_wdata = value; csr_we = 1; tick(); csr_we = 0;
        check_csr(addr, value);
    endtask
    task automatic check_reset;
        for (int i = 0; i < 16; i++) check_gpr(5'(i), 0);
        check_csr('h300, 'h1800); check_csr('h305, 0);
        check_csr('h341, 0); check_csr('h342, 0);
        if (trap_target !== 0 || mret_target !== 0) $fatal(1, "Reset targets");
    endtask
    initial begin
        // Assert reset without any clock edge: do not rely on time-zero values.
        #1; rst_n = 0; #1; check_reset(); tick(); rst_n = 1;
        for (int i = 1; i < 16; i++) begin
            rf_we = 1; rf_rd = 5'(i); rf_wd = 32'h12340000 + 32'(i); tick();
        end
        rf_we = 0;
        for (int i = 1; i < 16; i++) check_gpr(5'(i), 32'h12340000 + 32'(i));
        rf_rs1 = 5; rf_rs2 = 13; #1;
        if (rf_rd0 !== 32'h12340005 || rf_rd1 !== 32'h1234000d) $fatal(1, "Independent read ports");
        rf_rd = 0; rf_wd = '1; rf_we = 1; tick(); check_gpr(0, 0);
        rf_rd = 7; rf_we = 0; tick(); check_gpr(7, 32'h12340007);

        // High indices neither read nor alias the lower physical registers.
        rf_we = 1; rf_rd = 23; rf_wd = '1; tick(); rf_we = 0;
        check_gpr(23, 0); check_gpr(7, 32'h12340007);
        csr_we = 1; csr_addr = 'h300; csr_wdata = '1; tick(); csr_we = 0;
        check_csr('h300, 'h1888);
        csr_we = 1; csr_addr = 'h305; csr_wdata = 'h80000103; tick(); csr_we = 0;
        check_csr('h305, 'h80000100);
        csr_we = 1; csr_addr = 'h341; csr_wdata = 'h80000203; tick(); csr_we = 0;
        check_csr('h341, 'h80000200);
        csr_we = 1; csr_addr = 'h301; csr_wdata = '1; tick(); csr_we = 0;
        check_csr('h301, 0); check_csr('h300, 'h1888);
        write_csr('h300, 'h1808); write_csr('h305, 'h80000100);
        write_csr('h341, 'h80000200); write_csr('h342, 'h11);
        if (trap_target !== 'h80000100 || mret_target !== 'h80000200) $fatal(1, "CSR targets");
        // MTIP is hardware-owned; MTIE and MIE independently gate delivery.
        check_csr('h304, 0); check_csr('h344, 0);
        timer_irq=1; #1; check_csr('h344, 'h80);
        if(interrupt_pending) $fatal(1, "MTIE mask");
        csr_we=1; csr_addr='h344; csr_wdata=0; tick(); csr_we=0;
        check_csr('h344, 'h80);
        csr_we=1; csr_addr='h304; csr_wdata='1; tick(); csr_we=0;
        check_csr('h304, 'h80);
        if(!interrupt_pending) $fatal(1, "enabled timer pending");
        write_csr('h300, 'h1800);
        if(interrupt_pending) $fatal(1, "MIE mask");
        write_csr('h300, 'h1808); timer_irq=0; #1;
        if(interrupt_pending) $fatal(1, "cleared timer");
        // Trap wins against ordinary writes to each affected CSR.
        csr_we = 1; csr_addr = 'h341; csr_wdata = '1;
        trap_valid = 1; trap_epc = 'h80000300; trap_cause = 5; tick();
        csr_we = 0; trap_valid = 0;
        check_csr('h300, 'h1880); check_csr('h341, 'h80000300); check_csr('h342, 5);
        mret_valid = 1; csr_we = 1; csr_addr = 'h300; csr_wdata = 0; tick();
        mret_valid = 0; csr_we = 0; check_csr('h300, 'h1888);
        csr_we = 1; csr_addr = 'h342; csr_wdata = '1; trap_valid = 1; tick();
        csr_we = 0; trap_valid = 0; check_csr('h342, 5);
        write_csr('h300, 'h1808);
        csr_we = 1; csr_addr = 'h300; csr_wdata = '1; trap_valid = 1; mret_valid = 1; tick();
        csr_we = 0; trap_valid = 0; mret_valid = 0; check_csr('h300, 'h1880);

        // Dirty state must clear immediately on a later reset, despite writes/trap.
        rf_we = 1; rf_rd = 9; rf_wd = '1;
        csr_we = 1; trap_valid = 1; #1; rst_n = 0; #1; check_reset();
        tick(); check_reset();
        rf_we = 0; csr_we = 0; trap_valid = 0; rst_n = 1; tick(); check_reset();
        rf_we = 1; rf_rd = 15; rf_wd = 'habcd; tick(); rf_we = 0; check_gpr(15, 'habcd);
        write_csr('h305, 'h80000400); check_gpr(0, 0);
        $display("Architectural state test: PASS (GPR, CSR, asynchronous/repeated reset)");
        $finish;
    end
endmodule
