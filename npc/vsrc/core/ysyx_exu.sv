`default_nettype none

// In-order single-issue execution unit.
//
// Ordinary ALU/branch/CSR operations complete combinationally from the stable
// opbuf context.  A memory operation remains in opbuf while this module owns
// the request/response lifecycle through mem_wait_q.
module ysyx_exu (
    input              clk,
    input              rst_n,

    input              op_valid,
    output             op_ready,
    input      [31:0]  op_pc,
    input      [31:0]  op_inst,
    input              op_fetch_error,
    input              op_pred_taken,
    input      [31:0]  op_pred_npc,
    input      [31:0]  op_imm,
    input              op_alu_lhs_pc,
    input              op_alu_rhs_imm,
    input      [4:0]   op_alu_ctrl,
    input      [2:0]   op_branch_type,
    input              op_is_branch,
    input              op_is_jal,
    input              op_is_jalr,
    input              op_gpr_wen,
    input      [1:0]   op_wb_sel,
    input              op_is_load,
    input              op_is_store,
    input      [2:0]   op_mem_type,
    input              op_csr_wen,
    input      [11:0]  op_csr_addr,
    input              op_trap_valid,
    input      [31:0]  op_trap_cause,
    input              op_mret_valid,
    input      [4:0]   op_rd_idx,
    input      [31:0]  op_rs1_data,
    input      [31:0]  op_rs2_data,

    output     [11:0]  csr_addr,
    input      [31:0]  csr_rdata,
    output     [31:0]  csr_wdata,
    output             csr_write_valid,
    output             trap_commit,
    output     [31:0]  trap_epc,
    output     [31:0]  trap_cause,
    output             mret_commit,
    input      [31:0]  trap_target,
    input      [31:0]  mret_target,

    output             gpr_write_valid,
    output     [4:0]   gpr_write_idx,
    output     [31:0]  gpr_write_data,

    output             lsu_req_valid,
    input              lsu_req_ready,
    output             lsu_req_write,
    output     [31:0]  lsu_req_addr,
    output     [2:0]   lsu_req_type,
    output     [31:0]  lsu_req_wdata,
    input              lsu_rsp_valid,
    output             lsu_rsp_ready,
    input      [31:0]  lsu_rsp_rdata,
    input              lsu_rsp_error,

    output             commit_valid,
    output     [31:0]  commit_pc,
    output     [31:0]  commit_inst,
    output     [31:0]  commit_npc,
    output             commit_is_mmio,
    output             commit_mem_valid,
    output             commit_mem_write,
    output     [31:0]  commit_mem_addr,
    output     [31:0]  commit_mem_wdata,
    output             commit_mem_error,
    output             commit_exception,
    output     [31:0]  commit_exception_cause,

    output             redirect_valid,
    output     [31:0]  redirect_target
);

reg mem_wait_q;

wire        op_is_mem;
wire        memory_operation;
wire        lsu_req_fire;
wire        lsu_rsp_fire;
wire [31:0] alu_lhs;
wire [31:0] alu_rhs;
wire [31:0] alu_result;
wire        branch_taken;
wire [31:0] pc_plus4;
wire [31:0] branch_target;
wire [31:0] jalr_target;
wire        control_redirect;
wire        operation_complete;
wire        data_access_exception;
wire        exception_valid;
wire [31:0] exception_cause;

assign op_is_mem = op_is_load | op_is_store;
assign memory_operation = op_is_mem & (~op_fetch_error);

assign alu_lhs = op_alu_lhs_pc ? op_pc : op_rs1_data;
assign alu_rhs = op_alu_rhs_imm ? op_imm : op_rs2_data;

ysyx_alu u_alu (
    .alu_src0(alu_lhs),
    .alu_src1(alu_rhs),
    .alu_ctrl(op_alu_ctrl),
    .alu_res (alu_result)
);

ysyx_branch u_branch (
    .br_type(op_branch_type),
    .br_en  (op_is_branch),
    .rf_rd0 (op_rs1_data),
    .rf_rd1 (op_rs2_data),
    .br     (branch_taken)
);

assign pc_plus4      = op_pc + 32'd4;
assign branch_target = alu_result;
assign jalr_target   = alu_result & 32'hffff_fffe;

assign data_access_exception = memory_operation & mem_wait_q &
                               lsu_rsp_valid & lsu_rsp_error;
assign exception_valid = op_fetch_error | data_access_exception |
                         op_trap_valid;
assign exception_cause = op_fetch_error ? 32'd1 :
                         (data_access_exception ?
                          (op_is_store ? 32'd7 : 32'd5) :
                          op_trap_cause);

assign commit_npc = exception_valid ? trap_target :
                    (op_mret_valid ? mret_target :
                    ((op_is_jal | branch_taken) ? branch_target :
                    (op_is_jalr ? jalr_target : pc_plus4)));
assign control_redirect = exception_valid | op_mret_valid |
                          op_is_jal | op_is_jalr | branch_taken;

assign lsu_req_valid = op_valid & memory_operation & (~mem_wait_q);
assign lsu_req_write = op_is_store;
assign lsu_req_addr  = alu_result;
assign lsu_req_type  = op_mem_type;
assign lsu_req_wdata = op_rs2_data;
assign lsu_req_fire  = lsu_req_valid & lsu_req_ready;

assign lsu_rsp_ready = op_valid & mem_wait_q;
assign lsu_rsp_fire  = lsu_rsp_valid & lsu_rsp_ready;

assign operation_complete = op_fetch_error | (~op_is_mem) |
                            (mem_wait_q & lsu_rsp_valid);
assign commit_valid = op_valid & operation_complete;
assign op_ready     = commit_valid;
assign commit_pc    = op_pc;
assign commit_inst  = op_inst;

assign csr_addr  = op_csr_addr;
assign csr_wdata = (op_inst[6:0] == 7'h73) ?
                   ((op_inst[14:12] == 3'b010) ?
                    (op_rs1_data | csr_rdata) :
                   ((op_inst[14:12] == 3'b001) ? op_rs1_data : 32'b0)) :
                   32'b0;
assign csr_write_valid = commit_valid & op_csr_wen & (~exception_valid);
assign trap_commit     = commit_valid & exception_valid;
assign trap_epc        = op_pc;
assign trap_cause      = exception_cause;
assign mret_commit     = commit_valid & op_mret_valid & (~exception_valid);

ysyx_gnrl_data_mux #(
    .DW(32),
    .N (4)
) u_wb_mux (
    .out_data(gpr_write_data),
    .in_data ({csr_rdata, lsu_rsp_rdata, pc_plus4, alu_result}),
    .sel     (op_wb_sel)
);

assign gpr_write_valid = commit_valid & op_gpr_wen & (~exception_valid);
assign gpr_write_idx   = op_rd_idx;

assign commit_mem_valid = commit_valid & memory_operation;
assign commit_mem_write = op_is_store;
assign commit_mem_addr  = alu_result;
assign commit_mem_wdata = op_rs2_data;
assign commit_mem_error = commit_mem_valid & lsu_rsp_error;
assign commit_exception = commit_valid & exception_valid;
assign commit_exception_cause = exception_cause;
assign commit_is_mmio   = commit_mem_valid & (alu_result[31:28] == 4'ha);

assign redirect_valid  = commit_valid & control_redirect;
assign redirect_target = commit_npc;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        mem_wait_q <= 1'b0;
    end else begin
        if (lsu_rsp_fire)
            mem_wait_q <= 1'b0;
        else if (lsu_req_fire)
            mem_wait_q <= 1'b1;
    end
end

property p_memory_commit_requires_lsu_response;
    @(posedge clk) disable iff (!rst_n)
        commit_mem_valid |-> mem_wait_q && lsu_rsp_valid;
endproperty
assert property (p_memory_commit_requires_lsu_response);

property p_memory_wait_keeps_its_context;
    @(posedge clk) disable iff (!rst_n)
        mem_wait_q |-> op_valid && op_is_mem;
endproperty
assert property (p_memory_wait_keeps_its_context);

property p_request_stable_when_stalled;
    @(posedge clk) disable iff (!rst_n)
        lsu_req_valid && !lsu_req_ready
        |=> lsu_req_valid &&
            $stable({lsu_req_write, lsu_req_addr,
                     lsu_req_type, lsu_req_wdata});
endproperty
assert property (p_request_stable_when_stalled);

property p_static_prediction_metadata;
    @(posedge clk) disable iff (!rst_n)
        op_valid |-> !op_pred_taken && op_pred_npc == op_pc + 32'd4;
endproperty
assert property (p_static_prediction_metadata);

property p_exception_has_no_normal_writeback;
    @(posedge clk) disable iff (!rst_n)
        commit_exception |-> trap_commit && redirect_valid &&
                              !gpr_write_valid && !csr_write_valid &&
                              !mret_commit;
endproperty
assert property (p_exception_has_no_normal_writeback);

property p_fetch_error_does_not_issue_lsu;
    @(posedge clk) disable iff (!rst_n)
        op_valid && op_fetch_error |-> !lsu_req_valid;
endproperty
assert property (p_fetch_error_does_not_issue_lsu);

property p_memory_error_raises_access_fault;
    @(posedge clk) disable iff (!rst_n)
        commit_mem_error |-> commit_exception &&
            (commit_exception_cause ==
             (op_is_store ? 32'd7 : 32'd5));
endproperty
assert property (p_memory_error_raises_access_fault);

endmodule

`default_nettype wire
