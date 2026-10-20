

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
    output             commit_exception,
    output     [31:0]  commit_exception_cause,
    output             commit_redirect_valid,
    output     [1:0]   commit_redirect_reason,
    output             commit_mem_valid,
    output             commit_mem_write,
    output     [31:0]  commit_mem_addr,
    output             commit_mem_error,

    output             ifu_axi_arvalid,
    input              ifu_axi_arready,
    output     [31:0]  ifu_axi_araddr,
    output     [2:0]   ifu_axi_arprot,
    output     [2:0]   ifu_axi_arsize,
    input              ifu_axi_rvalid,
    output             ifu_axi_rready,
    input      [31:0]  ifu_axi_rdata,
    input      [1:0]   ifu_axi_rresp,

    output             lsu_axi_awvalid,
    input              lsu_axi_awready,
    output     [31:0]  lsu_axi_awaddr,
    output     [2:0]   lsu_axi_awprot,
    output     [2:0]   lsu_axi_awsize,
    output             lsu_axi_wvalid,
    input              lsu_axi_wready,
    output     [31:0]  lsu_axi_wdata,
    output     [3:0]   lsu_axi_wstrb,
    input              lsu_axi_bvalid,
    output             lsu_axi_bready,
    input      [1:0]   lsu_axi_bresp,
    output             lsu_axi_arvalid,
    input              lsu_axi_arready,
    output     [31:0]  lsu_axi_araddr,
    output     [2:0]   lsu_axi_arprot,
    output     [2:0]   lsu_axi_arsize,
    input              lsu_axi_rvalid,
    output             lsu_axi_rready,
    input      [31:0]  lsu_axi_rdata,
    input      [1:0]   lsu_axi_rresp

`ifdef DEBUG
    ,
    output             putchar,
    output     [7:0]   c
`endif
);

localparam [1:0] REDIRECT_NONE      = 2'd0;
localparam [1:0] REDIRECT_CONTROL   = 2'd1;
localparam [1:0] REDIRECT_EXCEPTION = 2'd2;
localparam [1:0] REDIRECT_MRET      = 2'd3;

// Frontend instruction context.
wire        if_ctx_valid;
wire        if_ctx_ready;
wire [31:0] if_ctx_pc;
wire [31:0] if_ctx_inst;
wire        if_ctx_error;
wire        if_ctx_pred_taken;
wire [31:0] if_ctx_pred_npc;
wire        if_ctx_fire;

// IFU-local memory interface.  AXI channel state is owned by the adapter.
wire        imem_req_valid;
wire        imem_req_ready;
wire [31:0] imem_req_addr;
wire        imem_rsp_valid;
wire        imem_rsp_ready;
wire [31:0] imem_rsp_data;
wire        imem_rsp_error;

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
wire        lsu_rsp_error;

// LSU-local memory interface.  Address alignment and byte-lane conversion
// happen before the request reaches the external AXI4-Lite master ports.
wire        dmem_req_valid;
wire        dmem_req_ready;
wire        dmem_req_write;
wire [31:0] dmem_req_addr;
wire [1:0]  dmem_req_size;
wire [31:0] dmem_req_wdata;
wire        dmem_rsp_valid;
wire        dmem_rsp_ready;
wire [31:0] dmem_rsp_data;
wire        dmem_rsp_error;

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
    .imem_rsp_data    (imem_rsp_data),
    .imem_rsp_error   (imem_rsp_error)
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
    .rst_n (rst_n),
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
    .lsu_rsp_error    (lsu_rsp_error),
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
    .commit_mem_error (commit_mem_error),
    .commit_exception (commit_exception),
    .commit_exception_cause(commit_exception_cause),
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
    .rsp_error      (lsu_rsp_error),

    .dmem_req_valid (dmem_req_valid),
    .dmem_req_ready (dmem_req_ready),
    .dmem_req_write (dmem_req_write),
    .dmem_req_addr  (dmem_req_addr),
    .dmem_req_size  (dmem_req_size),
    .dmem_req_wdata (dmem_req_wdata),
    .dmem_rsp_valid (dmem_rsp_valid),
    .dmem_rsp_ready (dmem_rsp_ready),
    .dmem_rsp_data  (dmem_rsp_data),
    .dmem_rsp_error (dmem_rsp_error)
);

ysyx_ifu_axi4_adapter u_ifu_axi4_adapter (
    .clk           (clk),
    .rst_n         (rst_n),
    .imem_req_valid(imem_req_valid),
    .imem_req_ready(imem_req_ready),
    .imem_req_addr (imem_req_addr),
    .imem_rsp_valid(imem_rsp_valid),
    .imem_rsp_ready(imem_rsp_ready),
    .imem_rsp_data (imem_rsp_data),
    .imem_rsp_error(imem_rsp_error),
    .m_axi_arvalid (ifu_axi_arvalid),
    .m_axi_arready (ifu_axi_arready),
    .m_axi_araddr  (ifu_axi_araddr),
    .m_axi_arprot  (ifu_axi_arprot),
    .m_axi_arsize  (ifu_axi_arsize),
    .m_axi_rvalid  (ifu_axi_rvalid),
    .m_axi_rready  (ifu_axi_rready),
    .m_axi_rdata   (ifu_axi_rdata),
    .m_axi_rresp   (ifu_axi_rresp)
);

ysyx_lsu_axi4_adapter u_lsu_axi4_adapter (
    .clk           (clk),
    .rst_n         (rst_n),
    .dmem_req_valid(dmem_req_valid),
    .dmem_req_ready(dmem_req_ready),
    .dmem_req_write(dmem_req_write),
    .dmem_req_addr (dmem_req_addr),
    .dmem_req_size (dmem_req_size),
    .dmem_req_wdata(dmem_req_wdata),
    .dmem_rsp_valid(dmem_rsp_valid),
    .dmem_rsp_ready(dmem_rsp_ready),
    .dmem_rsp_data (dmem_rsp_data),
    .dmem_rsp_error(dmem_rsp_error),
    .m_axi_awvalid (lsu_axi_awvalid),
    .m_axi_awready (lsu_axi_awready),
    .m_axi_awaddr  (lsu_axi_awaddr),
    .m_axi_awprot  (lsu_axi_awprot),
    .m_axi_awsize  (lsu_axi_awsize),
    .m_axi_wvalid  (lsu_axi_wvalid),
    .m_axi_wready  (lsu_axi_wready),
    .m_axi_wdata   (lsu_axi_wdata),
    .m_axi_wstrb   (lsu_axi_wstrb),
    .m_axi_bvalid  (lsu_axi_bvalid),
    .m_axi_bready  (lsu_axi_bready),
    .m_axi_bresp   (lsu_axi_bresp),
    .m_axi_arvalid (lsu_axi_arvalid),
    .m_axi_arready (lsu_axi_arready),
    .m_axi_araddr  (lsu_axi_araddr),
    .m_axi_arprot  (lsu_axi_arprot),
    .m_axi_arsize  (lsu_axi_arsize),
    .m_axi_rvalid  (lsu_axi_rvalid),
    .m_axi_rready  (lsu_axi_rready),
    .m_axi_rdata   (lsu_axi_rdata),
    .m_axi_rresp   (lsu_axi_rresp)
);

assign if_ctx_fire = if_ctx_valid & if_ctx_ready;
assign commit_redirect_valid = redirect_valid;
assign commit_redirect_reason = commit_exception ? REDIRECT_EXCEPTION :
                                (exu_mret_commit ? REDIRECT_MRET :
                                (redirect_valid ? REDIRECT_CONTROL :
                                                  REDIRECT_NONE));

`ifdef DEBUG
assign putchar = commit_valid && commit_mem_write && !commit_mem_error &&
                 (&commit_mem_addr);
assign c       = commit_mem_wdata[7:0];
`endif

`ifndef SYNTHESIS
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

property p_exception_redirects_without_normal_writeback;
    @(posedge clk) disable iff (!rst_n)
        commit_exception |-> redirect_valid && exu_trap_commit &&
                              !gpr_write_valid && !exu_csr_write_valid &&
                              !exu_mret_commit;
endproperty
assert property (p_exception_redirects_without_normal_writeback);

`endif

endmodule


