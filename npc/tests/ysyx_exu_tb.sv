`timescale 1ns/1ps
`default_nettype none

module ysyx_exu_tb;

reg         clk = 1'b0;
reg         rst_n = 1'b0;
reg         op_valid = 1'b0;
wire        op_ready;
reg  [31:0] op_pc = 32'h8000_0000;
reg  [31:0] op_inst = 32'h0000_0013;
reg         op_fetch_error = 1'b0;
reg         op_pred_taken = 1'b0;
reg  [31:0] op_pred_npc = 32'h8000_0004;
reg  [31:0] op_imm = 32'b0;
reg         op_alu_lhs_pc = 1'b0;
reg         op_alu_rhs_imm = 1'b0;
reg  [4:0]  op_alu_ctrl = 5'b0;
reg  [2:0]  op_branch_type = 3'b0;
reg         op_is_branch = 1'b0;
reg         op_is_jal = 1'b0;
reg         op_is_jalr = 1'b0;
reg         op_gpr_wen = 1'b0;
reg  [1:0]  op_wb_sel = 2'b0;
reg         op_is_load = 1'b0;
reg         op_is_store = 1'b0;
reg  [2:0]  op_mem_type = 3'b0;
reg         op_csr_wen = 1'b0;
reg  [11:0] op_csr_addr = 12'b0;
reg         op_trap_valid = 1'b0;
reg  [31:0] op_trap_cause = 32'b0;
reg         op_mret_valid = 1'b0;
reg  [4:0]  op_rd_idx = 5'b0;
reg  [31:0] op_rs1_data = 32'b0;
reg  [31:0] op_rs2_data = 32'b0;
wire [11:0] csr_addr;
reg  [31:0] csr_rdata = 32'b0;
wire [31:0] csr_wdata;
wire        csr_write_valid;
wire        trap_commit;
wire [31:0] trap_epc;
wire [31:0] trap_cause;
wire        mret_commit;
reg  [31:0] trap_target = 32'h8000_1000;
reg  [31:0] mret_target = 32'h8000_2000;
wire        gpr_write_valid;
wire [4:0]  gpr_write_idx;
wire [31:0] gpr_write_data;
wire        lsu_req_valid;
reg         lsu_req_ready = 1'b0;
wire        lsu_req_write;
wire [31:0] lsu_req_addr;
wire [2:0]  lsu_req_type;
wire [31:0] lsu_req_wdata;
reg         lsu_rsp_valid = 1'b0;
wire        lsu_rsp_ready;
reg  [31:0] lsu_rsp_rdata = 32'b0;
wire        commit_valid;
wire [31:0] commit_pc;
wire [31:0] commit_inst;
wire [31:0] commit_npc;
wire        commit_is_mmio;
wire        commit_mem_valid;
wire        commit_mem_write;
wire [31:0] commit_mem_addr;
wire [31:0] commit_mem_wdata;
wire        redirect_valid;
wire [31:0] redirect_target;

always #5 clk = ~clk;

// SV auto connect by names
ysyx_exu u_exu (.*);

task tick;
begin
    @(posedge clk);
    #1;
end
endtask

task settle;
begin
    #1;
end
endtask

task check;
    input condition;
    input [8*96-1:0] message;
begin
    if (!condition) begin
        $display("EXU test failed: %0s", message);
        $fatal;
    end
end
endtask

task clear_op;
begin
    op_valid = 1'b0;
    op_inst = 32'h0000_0013;
    op_imm = 32'b0;
    op_alu_lhs_pc = 1'b0;
    op_alu_rhs_imm = 1'b0;
    op_alu_ctrl = 5'b0;
    op_branch_type = 3'b0;
    op_is_branch = 1'b0;
    op_is_jal = 1'b0;
    op_is_jalr = 1'b0;
    op_gpr_wen = 1'b0;
    op_wb_sel = 2'b0;
    op_is_load = 1'b0;
    op_is_store = 1'b0;
    op_mem_type = 3'b0;
    op_csr_wen = 1'b0;
    op_csr_addr = 12'b0;
    op_trap_valid = 1'b0;
    op_trap_cause = 32'b0;
    op_mret_valid = 1'b0;
    op_rd_idx = 5'b0;
    op_rs1_data = 32'b0;
    op_rs2_data = 32'b0;
end
endtask

task set_pc;
    input [31:0] pc;
begin
    op_pc = pc;
    op_pred_npc = pc + 32'd4;
end
endtask

initial begin
    tick;
    tick;
    rst_n = 1'b1;
    settle;

    // Ordinary ALU instruction completes immediately.
    clear_op;
    set_pc(32'h8000_0000);
    op_valid = 1'b1;
    op_gpr_wen = 1'b1;
    op_rd_idx = 5'd5;
    op_rs1_data = 32'd3;
    op_rs2_data = 32'd4;
    settle;
    check(commit_valid && op_ready && commit_npc == 32'h8000_0004,
          "ALU operation did not complete immediately");
    check(commit_pc == 32'h8000_0000 && commit_inst == 32'h0000_0013,
          "ALU commit context is incorrect");
    check(gpr_write_valid && gpr_write_idx == 5'd5 &&
          gpr_write_data == 32'd7,
          "ALU writeback is incorrect");
    check(!redirect_valid && !commit_mem_valid,
          "ALU operation produced an unexpected side effect");
    tick;

    // A taken branch commits and redirects to PC + immediate.
    clear_op;
    set_pc(32'h8000_0010);
    op_valid = 1'b1;
    op_imm = 32'h20;
    op_alu_lhs_pc = 1'b1;
    op_alu_rhs_imm = 1'b1;
    op_is_branch = 1'b1;
    op_branch_type = 3'b000;
    op_rs1_data = 32'h55;
    op_rs2_data = 32'h55;
    settle;
    check(commit_valid && redirect_valid &&
          redirect_target == 32'h8000_0030,
          "taken branch redirect is incorrect");
    tick;

    // CSRRS returns the old CSR value and writes old | rs1.
    clear_op;
    set_pc(32'h8000_0040);
    op_valid = 1'b1;
    op_inst = 32'h3000_22f3;
    op_csr_wen = 1'b1;
    op_csr_addr = 12'h300;
    op_gpr_wen = 1'b1;
    op_wb_sel = 2'd3;
    op_rd_idx = 5'd5;
    op_rs1_data = 32'h0000_0004;
    csr_rdata = 32'h0000_0080;
    settle;
    check(commit_valid && csr_write_valid && csr_addr == 12'h300 &&
          csr_wdata == 32'h0000_0084,
          "CSR write data is incorrect");
    check(gpr_write_valid && gpr_write_data == 32'h0000_0080,
          "CSR readback writeback is incorrect");
    tick;

    // Load request holds while LSU is stalled, then waits for its response.
    clear_op;
    set_pc(32'h8000_0080);
    op_valid = 1'b1;
    op_is_load = 1'b1;
    op_mem_type = 3'd2;
    op_alu_rhs_imm = 1'b1;
    op_imm = 32'd4;
    op_rs1_data = 32'h8000_1000;
    op_gpr_wen = 1'b1;
    op_wb_sel = 2'd2;
    op_rd_idx = 5'd6;
    settle;
    check(lsu_req_valid && !commit_valid && !lsu_req_write &&
          lsu_req_addr == 32'h8000_1004 && lsu_req_type == 3'd2 &&
          lsu_req_wdata == 32'b0,
          "load request is incorrect");
    tick;
    check(lsu_req_valid && lsu_req_addr == 32'h8000_1004,
          "load request changed under backpressure");
    lsu_req_ready = 1'b1;
    tick;
    lsu_req_ready = 1'b0;
    settle;
    check(!lsu_req_valid && lsu_rsp_ready && !commit_valid,
          "EXU did not enter load response wait");
    tick;
    lsu_rsp_rdata = 32'h1234_5678;
    lsu_rsp_valid = 1'b1;
    settle;
    check(commit_valid && op_ready && gpr_write_valid &&
          gpr_write_data == 32'h1234_5678,
          "load response did not produce one commit");
    check(commit_mem_valid && !commit_mem_write && !commit_is_mmio &&
          commit_mem_addr == 32'h8000_1004 && commit_mem_wdata == 32'b0,
          "load commit metadata is incorrect");
    tick;
    lsu_rsp_valid = 1'b0;

    // Trap completion updates CSR state and redirects to mtvec.
    clear_op;
    set_pc(32'h8000_00c0);
    op_valid = 1'b1;
    op_trap_valid = 1'b1;
    op_trap_cause = 32'd11;
    settle;
    check(commit_valid && trap_commit && trap_epc == 32'h8000_00c0 &&
          trap_cause == 32'd11,
          "trap commit metadata is incorrect");
    check(redirect_valid && redirect_target == trap_target,
          "trap did not redirect to mtvec");
    tick;

    // MRET follows the same precise commit boundary and redirects to mepc.
    clear_op;
    set_pc(32'h8000_00e0);
    op_valid = 1'b1;
    op_mret_valid = 1'b1;
    settle;
    check(commit_valid && mret_commit && redirect_valid &&
          redirect_target == mret_target,
          "mret commit or redirect is incorrect");
    tick;

    clear_op;
    settle;
    check(!commit_valid && !gpr_write_valid && !csr_write_valid,
          "empty EXU produced an architectural side effect");

    $display("ysyx_exu directed test: PASS");
    $finish;
end

endmodule

`default_nettype wire
