`default_nettype none

module ysyx_core #(
    parameter PC_RST    = 32'h8000_0000,
    parameter IFQ_DEPTH = 2
) (
    input              clk,
    input              rst_n,
    output     [31:0]  commit_pc,
    output     [31:0]  commit_inst,
    output             commit_valid,
    output             commit_is_mmio,

    output             imem_req_valid,
    input              imem_req_ready,
    output     [31:0]  imem_req_addr,
    input              imem_rsp_valid,
    output             imem_rsp_ready,
    input      [31:0]  imem_rsp_data,

    output             dmem_req_valid,
    input              dmem_req_ready,
    output             dmem_req_write,
    output     [31:0]  dmem_req_addr,
    output     [1:0]   dmem_req_size,
    output     [31:0]  dmem_req_wdata,
    input              dmem_rsp_valid,
    output             dmem_rsp_ready,
    input      [31:0]  dmem_rsp_data

`ifdef DEBUG
    ,
    output             putchar,
    output     [7:0]   c
`endif
);

// Frontend instruction context.
wire        if_ctx_valid;
wire        if_ctx_ready;
wire [31:0] if_ctx_pc;
wire [31:0] if_ctx_inst;
wire        if_ctx_error;
wire        if_ctx_pred_taken;
wire [31:0] if_ctx_pred_npc;
wire        if_ctx_fire;

// Decode and register-read context entering opbuf.
wire [2:0]  dec_imm_type;
wire [31:0] dec_imm;
wire        dec_alu_lhs_pc;
wire        dec_alu_rhs_imm;
wire [4:0]  dec_alu_ctrl;
wire [2:0]  dec_branch_type;
wire        dec_is_branch;
wire        dec_is_jal;
wire        dec_is_jalr;
wire        dec_gpr_wen;
wire [1:0]  dec_wb_sel;
wire [2:0]  dec_mem_type;
wire        dec_is_store;
wire        dec_is_load;
wire        dec_csr_wen;
wire [11:0] dec_csr_addr;
wire        dec_trap_valid;
wire [31:0] dec_trap_cause;
wire        dec_mret_valid;
wire [4:0]  dec_rs1_idx;
wire [4:0]  dec_rs2_idx;
wire [4:0]  dec_rd_idx;
wire [31:0] gpr_rs1_data_raw;
wire [31:0] gpr_rs2_data_raw;
wire [31:0] dec_rs1_data;
wire [31:0] dec_rs2_data;

// Stable opbuf context consumed by EXU.
wire        op_valid;
wire        op_ready;
wire [31:0] op_pc;
wire [31:0] op_inst;
wire        op_fetch_error;
wire        op_pred_taken;
wire [31:0] op_pred_npc;
wire [31:0] op_imm;
wire        op_alu_lhs_pc;
wire        op_alu_rhs_imm;
wire [4:0]  op_alu_ctrl;
wire [2:0]  op_branch_type;
wire        op_is_branch;
wire        op_is_jal;
wire        op_is_jalr;
wire        op_gpr_wen;
wire [1:0]  op_wb_sel;
wire        op_is_load;
wire        op_is_store;
wire [2:0]  op_mem_type;
wire        op_csr_wen;
wire [11:0] op_csr_addr;
wire        op_trap_valid;
wire [31:0] op_trap_cause;
wire        op_mret_valid;
wire [4:0]  op_rs1_idx;
wire [4:0]  op_rs2_idx;
wire [4:0]  op_rd_idx;
wire [31:0] op_rs1_data;
wire [31:0] op_rs2_data;

// Architectural writeback and control-flow recovery.
wire        gpr_write_valid;
wire [4:0]  gpr_write_idx;
wire [31:0] gpr_write_data;
wire [31:0] exu_commit_pc;
wire [31:0] exu_commit_inst;
wire [31:0] commit_npc;
wire        redirect_valid;
wire [31:0] redirect_target;
wire        commit_mem_valid;
wire        commit_mem_write;
wire [31:0] commit_mem_addr;
wire [31:0] commit_mem_wdata;

// CSR architectural interface.
wire [11:0] exu_csr_addr;
wire [31:0] csr_rdata;
wire [31:0] exu_csr_wdata;
wire        exu_csr_write_valid;
wire        exu_trap_commit;
wire [31:0] exu_trap_epc;
wire [31:0] exu_trap_cause;
wire        exu_mret_commit;
wire [31:0] trap_target;
wire [31:0] mret_target;

// Backend-to-LSU interface.
wire        lsu_req_valid;
wire        lsu_req_ready;
wire        lsu_req_write;
wire [31:0] lsu_req_addr;
wire [2:0]  lsu_req_type;
wire [31:0] lsu_req_wdata;
wire        lsu_rsp_valid;
wire        lsu_rsp_ready;
wire [31:0] lsu_rsp_rdata;

ysyx_gnrl_dfflrs #(
    .DW (32),
    .RST(PC_RST)
) u_arch_pc (
    .lden (commit_valid),
    .dnxt (commit_npc),
    .qout (commit_pc),
    .clk  (clk),
    .rst_n(rst_n)
);

ysyx_ifu #(
    .PC_RST   (PC_RST),
    .IFQ_DEPTH(IFQ_DEPTH)
) u_ifu (
    .clk              (clk),
    .rst_n            (rst_n),

    .redirect_valid   (redirect_valid),
    .redirect_target  (redirect_target),
    // if_ctx_* (rv + inst payload: pc, inst, error, reserved pred sigs) 
    .if_ctx_valid     (if_ctx_valid),
    .if_ctx_ready     (if_ctx_ready),
    .if_ctx_pc        (if_ctx_pc),
    .if_ctx_inst      (if_ctx_inst),
    .if_ctx_error     (if_ctx_error),
    .if_ctx_pred_taken(if_ctx_pred_taken),
    .if_ctx_pred_npc  (if_ctx_pred_npc),
    // mem interface, 2 channel
    .imem_req_valid   (imem_req_valid),
    .imem_req_ready   (imem_req_ready),
    .imem_req_addr    (imem_req_addr),
    .imem_rsp_valid   (imem_rsp_valid),
    .imem_rsp_ready   (imem_rsp_ready),
    .imem_rsp_data    (imem_rsp_data)
);

ysyx_idu u_decoder (
    .inst        (if_ctx_inst),

    .imm_type    (dec_imm_type),
    .alu_src0_sel(dec_alu_lhs_pc),
    .alu_src1_sel(dec_alu_rhs_imm),
    .alu_ctrl    (dec_alu_ctrl),
    .br_type     (dec_branch_type),
    .br_en       (dec_is_branch),
    .jal         (dec_is_jal),
    .jalr        (dec_is_jalr),
    .rf_we       (dec_gpr_wen),
    .rf_wd_sel   (dec_wb_sel),
    .dm_type     (dec_mem_type),
    .dm_we_raw   (dec_is_store),
    .dm_re_raw   (dec_is_load),
    .csr_we      (dec_csr_wen),
    .csr_addr    (dec_csr_addr),
    .trap_valid  (dec_trap_valid),
    .trap_cause  (dec_trap_cause),
    .mret_valid  (dec_mret_valid)
);

ysyx_gen_imm u_decode_imm (
    .inst    (if_ctx_inst),
    .imm_type(dec_imm_type),
    .imm     (dec_imm)
);

assign dec_rs1_idx = if_ctx_inst[19:15];
assign dec_rs2_idx = if_ctx_inst[24:20];
assign dec_rd_idx  = if_ctx_inst[11:7];

ysyx_regfile u_gpr (
    .clk   (clk),
    .rf_rs1(dec_rs1_idx),
    .rf_rs2(dec_rs2_idx),
    .rf_rd (gpr_write_idx),
    .rf_we (gpr_write_valid),
    .rf_wd (gpr_write_data),
    .rf_rd0(gpr_rs1_data_raw),
    .rf_rd1(gpr_rs2_data_raw)
);

// Data hazard: 
// Decode reads and the previous instruction's writeback meet at the same
// edge.  Forward the committing value so opbuf never captures stale operands.
assign dec_rs1_data = (dec_rs1_idx == 5'd0) ? 32'b0 :
                      ((gpr_write_valid &&
                        (gpr_write_idx == dec_rs1_idx)) ?
                       gpr_write_data : gpr_rs1_data_raw);
assign dec_rs2_data = (dec_rs2_idx == 5'd0) ? 32'b0 :
                      ((gpr_write_valid &&
                        (gpr_write_idx == dec_rs2_idx)) ?
                       gpr_write_data : gpr_rs2_data_raw);

ysyx_opbuf u_opbuf (
    .clk             (clk),
    .rst_n           (rst_n),
    .flush           (1'b0),
    // ifu output if_ctx_* 
    .in_valid        (if_ctx_valid),
    .in_ready        (if_ctx_ready),
    .in_pc           (if_ctx_pc),
    .in_inst         (if_ctx_inst),
    .in_fetch_error  (if_ctx_error),
    .in_pred_taken   (if_ctx_pred_taken),
    .in_pred_npc     (if_ctx_pred_npc),
    // idu out 17 sigs + rs1, rs2 data & idx + rd idx
    .in_imm          (dec_imm),
    .in_alu_lhs_pc   (dec_alu_lhs_pc),
    .in_alu_rhs_imm  (dec_alu_rhs_imm),
    .in_alu_ctrl     (dec_alu_ctrl),
    .in_branch_type  (dec_branch_type),
    .in_is_branch    (dec_is_branch),
    .in_is_jal       (dec_is_jal),
    .in_is_jalr      (dec_is_jalr),
    .in_gpr_wen      (dec_gpr_wen),
    .in_wb_sel       (dec_wb_sel),
    .in_is_load      (dec_is_load),
    .in_is_store     (dec_is_store),
    .in_mem_type     (dec_mem_type),
    .in_csr_wen      (dec_csr_wen),
    .in_csr_addr     (dec_csr_addr),
    .in_trap_valid   (dec_trap_valid),
    .in_trap_cause   (dec_trap_cause),
    .in_mret_valid   (dec_mret_valid),
    .in_rs1_idx      (dec_rs1_idx),
    .in_rs2_idx      (dec_rs2_idx),
    .in_rd_idx       (dec_rd_idx),
    .in_rs1_data     (dec_rs1_data),
    .in_rs2_data     (dec_rs2_data),
    // rv_reg out 
    .out_valid       (op_valid),
    .out_ready       (op_ready),
    .out_pc          (op_pc),
    .out_inst        (op_inst),
    .out_fetch_error (op_fetch_error),
    .out_pred_taken  (op_pred_taken),
    .out_pred_npc    (op_pred_npc),
    .out_imm         (op_imm),
    .out_alu_lhs_pc  (op_alu_lhs_pc),
    .out_alu_rhs_imm (op_alu_rhs_imm),
    .out_alu_ctrl    (op_alu_ctrl),
    .out_branch_type (op_branch_type),
    .out_is_branch   (op_is_branch),
    .out_is_jal      (op_is_jal),
    .out_is_jalr     (op_is_jalr),
    .out_gpr_wen     (op_gpr_wen),
    .out_wb_sel      (op_wb_sel),
    .out_is_load     (op_is_load),
    .out_is_store    (op_is_store),
    .out_mem_type    (op_mem_type),
    .out_csr_wen     (op_csr_wen),
    .out_csr_addr    (op_csr_addr),
    .out_trap_valid  (op_trap_valid),
    .out_trap_cause  (op_trap_cause),
    .out_mret_valid  (op_mret_valid),
    .out_rs1_idx     (op_rs1_idx),
    .out_rs2_idx     (op_rs2_idx),
    .out_rd_idx      (op_rd_idx),
    .out_rs1_data    (op_rs1_data),
    .out_rs2_data    (op_rs2_data)
);

ysyx_exu u_exu (
    .clk              (clk),
    .rst_n            (rst_n),
    // opbuf out without rs1, rs2 idx
    .op_valid         (op_valid),
    .op_ready         (op_ready),
    .op_pc            (op_pc),
    .op_inst          (op_inst),
    .op_fetch_error   (op_fetch_error),
    .op_pred_taken    (op_pred_taken),
    .op_pred_npc      (op_pred_npc),
    .op_imm           (op_imm),
    .op_alu_lhs_pc    (op_alu_lhs_pc),
    .op_alu_rhs_imm   (op_alu_rhs_imm),
    .op_alu_ctrl      (op_alu_ctrl),
    .op_branch_type   (op_branch_type),
    .op_is_branch     (op_is_branch),
    .op_is_jal        (op_is_jal),
    .op_is_jalr       (op_is_jalr),
    .op_gpr_wen       (op_gpr_wen),
    .op_wb_sel        (op_wb_sel),
    .op_is_load       (op_is_load),
    .op_is_store      (op_is_store),
    .op_mem_type      (op_mem_type),
    .op_csr_wen       (op_csr_wen),
    .op_csr_addr      (op_csr_addr),
    .op_trap_valid    (op_trap_valid),
    .op_trap_cause    (op_trap_cause),
    .op_mret_valid    (op_mret_valid),
    .op_rd_idx        (op_rd_idx),
    .op_rs1_data      (op_rs1_data),
    .op_rs2_data      (op_rs2_data),
    // csr
    .csr_addr         (exu_csr_addr),
    .csr_rdata        (csr_rdata),
    .csr_wdata        (exu_csr_wdata),
    .csr_write_valid  (exu_csr_write_valid),
    .trap_commit      (exu_trap_commit),
    .trap_epc         (exu_trap_epc),
    .trap_cause       (exu_trap_cause),
    .mret_commit      (exu_mret_commit),
    .trap_target      (trap_target),
    .mret_target      (mret_target),
    // gpr write
    .gpr_write_valid  (gpr_write_valid),
    .gpr_write_idx    (gpr_write_idx),
    .gpr_write_data   (gpr_write_data),
    // to lsu
    .lsu_req_valid    (lsu_req_valid),
    .lsu_req_ready    (lsu_req_ready),
    .lsu_req_write    (lsu_req_write),
    .lsu_req_addr     (lsu_req_addr),
    .lsu_req_type     (lsu_req_type),
    .lsu_req_wdata    (lsu_req_wdata),
    .lsu_rsp_valid    (lsu_rsp_valid),
    .lsu_rsp_ready    (lsu_rsp_ready),
    .lsu_rsp_rdata    (lsu_rsp_rdata),
    // commit pack
    .commit_valid     (commit_valid),
    .commit_pc        (exu_commit_pc),
    .commit_inst      (exu_commit_inst),
    .commit_npc       (commit_npc),
    .commit_is_mmio   (commit_is_mmio),
    .commit_mem_valid (commit_mem_valid),
    .commit_mem_write (commit_mem_write),
    .commit_mem_addr  (commit_mem_addr),
    .commit_mem_wdata (commit_mem_wdata),
    // redirect channel 
    .redirect_valid   (redirect_valid),
    .redirect_target  (redirect_target)
);

assign commit_inst = exu_commit_inst;

ysyx_csr u_csr (
    .clk        (clk),
    .rst_n      (rst_n),

    .csr_addr   (exu_csr_addr),
    .csr_wdata  (exu_csr_wdata),
    .csr_we     (exu_csr_write_valid),
    .csr_rdata  (csr_rdata),
    .trap_valid (exu_trap_commit),
    .trap_epc   (exu_trap_epc),
    .trap_cause (exu_trap_cause),
    .mret_valid (exu_mret_commit),
    .trap_target(trap_target),
    .mret_target(mret_target)
);

ysyx_lsu u_lsu (
    .clk            (clk),
    .rst_n          (rst_n),
    
    .req_valid      (lsu_req_valid),
    .req_ready      (lsu_req_ready),
    .req_write      (lsu_req_write),
    .req_addr       (lsu_req_addr),
    .req_type       (lsu_req_type),
    .req_wdata      (lsu_req_wdata),
    .rsp_valid      (lsu_rsp_valid),
    .rsp_ready      (lsu_rsp_ready),
    .rsp_rdata      (lsu_rsp_rdata),

    .dmem_req_valid (dmem_req_valid),
    .dmem_req_ready (dmem_req_ready),
    .dmem_req_write (dmem_req_write),
    .dmem_req_addr  (dmem_req_addr),
    .dmem_req_size  (dmem_req_size),
    .dmem_req_wdata (dmem_req_wdata),
    .dmem_rsp_valid (dmem_rsp_valid),
    .dmem_rsp_ready (dmem_rsp_ready),
    .dmem_rsp_data  (dmem_rsp_data)
);

assign if_ctx_fire = if_ctx_valid & if_ctx_ready;

`ifdef DEBUG
assign putchar = commit_valid && commit_mem_write && (&commit_mem_addr);
assign c       = commit_mem_wdata[7:0];
`endif

property p_commit_context_matches_architectural_pc;
    @(posedge clk) disable iff (!rst_n)
        commit_valid |-> exu_commit_pc == commit_pc;
endproperty
assert property (p_commit_context_matches_architectural_pc);

property p_incoming_context_matches_next_architectural_pc;
    @(posedge clk) disable iff (!rst_n)
        if_ctx_fire |->
            if_ctx_pc == (commit_valid ? commit_npc : commit_pc);
endproperty
assert property (p_incoming_context_matches_next_architectural_pc);

property p_opbuf_stable_when_stalled;
    @(posedge clk) disable iff (!rst_n)
        op_valid && !op_ready
        |=> op_valid &&
            $stable({op_pc, op_inst, op_fetch_error,
                     op_pred_taken, op_pred_npc, op_imm,
                     op_alu_lhs_pc, op_alu_rhs_imm, op_alu_ctrl,
                     op_branch_type, op_is_branch, op_is_jal, op_is_jalr,
                     op_gpr_wen, op_wb_sel, op_is_load, op_is_store,
                     op_mem_type, op_csr_wen, op_csr_addr,
                     op_trap_valid, op_trap_cause, op_mret_valid,
                     op_rs1_idx, op_rs2_idx, op_rd_idx,
                     op_rs1_data, op_rs2_data});
endproperty
assert property (p_opbuf_stable_when_stalled);

property p_rs1_writeback_bypass;
    @(posedge clk) disable iff (!rst_n)
        if_ctx_fire && gpr_write_valid && (gpr_write_idx != 5'd0) &&
        (dec_rs1_idx == gpr_write_idx)
        |=> op_valid && op_rs1_data == $past(gpr_write_data);
endproperty
assert property (p_rs1_writeback_bypass);

property p_rs2_writeback_bypass;
    @(posedge clk) disable iff (!rst_n)
        if_ctx_fire && gpr_write_valid && (gpr_write_idx != 5'd0) &&
        (dec_rs2_idx == gpr_write_idx)
        |=> op_valid && op_rs2_data == $past(gpr_write_data);
endproperty
assert property (p_rs2_writeback_bypass);

property p_commit_memory_metadata;
    @(posedge clk) disable iff (!rst_n)
        commit_mem_valid |->
            commit_valid && (commit_mem_write == op_is_store) &&
            (commit_mem_addr == lsu_req_addr) &&
            (commit_mem_wdata == op_rs2_data);
endproperty
assert property (p_commit_memory_metadata);

endmodule

`default_nettype wire
