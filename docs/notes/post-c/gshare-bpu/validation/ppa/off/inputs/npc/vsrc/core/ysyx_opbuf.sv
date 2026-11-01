

// One-entry decoded instruction context buffer.
//
// Keeping the complete context in one ready/valid register prevents a stalled
// execution instruction from observing decode or register-file signals that
// already belong to a younger instruction.
module ysyx_opbuf #(parameter BPU_INDEX_BITS = 7) (
    input              clk,
    input              rst_n,
    input              flush,

    input              in_valid,
    output             in_ready,
    input      [31:0]  in_pc,
    input      [31:0]  in_inst,
    input              in_fetch_error,
    input              in_pred_taken,
    input      [31:0]  in_pred_npc,
    input              in_pred_branch,
    input [BPU_INDEX_BITS-1:0] in_pred_index,
    input      [31:0]  in_imm,
    input              in_alu_lhs_pc,
    input              in_alu_rhs_imm,
    input      [4:0]   in_alu_ctrl,
    input      [2:0]   in_branch_type,
    input              in_is_branch,
    input              in_is_jal,
    input              in_is_jalr,
    input              in_gpr_wen,
    input      [1:0]   in_wb_sel,
    input              in_is_load,
    input              in_is_store,
    input      [2:0]   in_mem_type,
    input              in_csr_wen,
    input      [11:0]  in_csr_addr,
    input              in_trap_valid,
    input      [31:0]  in_trap_cause,
    input              in_mret_valid,
    input      [4:0]   in_rs1_idx,
    input      [4:0]   in_rs2_idx,
    input      [4:0]   in_rd_idx,
    input      [31:0]  in_rs1_data,
    input      [31:0]  in_rs2_data,

    output             out_valid,
    input              out_ready,
    output     [31:0]  out_pc,
    output     [31:0]  out_inst,
    output             out_fetch_error,
    output             out_pred_taken,
    output     [31:0]  out_pred_npc,
    output             out_pred_branch,
    output [BPU_INDEX_BITS-1:0] out_pred_index,
    output     [31:0]  out_imm,
    output             out_alu_lhs_pc,
    output             out_alu_rhs_imm,
    output     [4:0]   out_alu_ctrl,
    output     [2:0]   out_branch_type,
    output             out_is_branch,
    output             out_is_jal,
    output             out_is_jalr,
    output             out_gpr_wen,
    output     [1:0]   out_wb_sel,
    output             out_is_load,
    output             out_is_store,
    output     [2:0]   out_mem_type,
    output             out_csr_wen,
    output     [11:0]  out_csr_addr,
    output             out_trap_valid,
    output     [31:0]  out_trap_cause,
    output             out_mret_valid,
    output     [4:0]   out_rs1_idx,
    output     [4:0]   out_rs2_idx,
    output     [4:0]   out_rd_idx,
    output     [31:0]  out_rs1_data,
    output     [31:0]  out_rs2_data
);

localparam OPBUF_DW = 278 + BPU_INDEX_BITS;

wire [OPBUF_DW-1:0] in_payload;
wire [OPBUF_DW-1:0] out_payload;

assign in_payload = {
    in_pc, in_inst, in_fetch_error, in_pred_taken, in_pred_npc,
    in_pred_branch, in_pred_index,
    in_imm, in_alu_lhs_pc, in_alu_rhs_imm, in_alu_ctrl,
    in_branch_type, in_is_branch, in_is_jal, in_is_jalr,
    in_gpr_wen, in_wb_sel, in_is_load, in_is_store, in_mem_type,
    in_csr_wen, in_csr_addr, in_trap_valid, in_trap_cause,
    in_mret_valid, in_rs1_idx, in_rs2_idx, in_rd_idx,
    in_rs1_data, in_rs2_data
};

assign {
    out_pc, out_inst, out_fetch_error, out_pred_taken, out_pred_npc,
    out_pred_branch, out_pred_index,
    out_imm, out_alu_lhs_pc, out_alu_rhs_imm, out_alu_ctrl,
    out_branch_type, out_is_branch, out_is_jal, out_is_jalr,
    out_gpr_wen, out_wb_sel, out_is_load, out_is_store, out_mem_type,
    out_csr_wen, out_csr_addr, out_trap_valid, out_trap_cause,
    out_mret_valid, out_rs1_idx, out_rs2_idx, out_rd_idx,
    out_rs1_data, out_rs2_data
} = out_payload;

ysyx_gnrl_rv_reg #(
    .DW(OPBUF_DW)
) u_context_reg (
    .in_valid (in_valid),
    .in_ready (in_ready),
    .in_data  (in_payload),
    .out_valid(out_valid),
    .out_ready(out_ready),
    .out_data (out_payload),
    .flush    (flush),
    .clk      (clk),
    .rst_n    (rst_n)
);

endmodule


