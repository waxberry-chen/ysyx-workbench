// Passive events only: never enters the synthesis filelist or CPU ABI.
module npc_bpu_monitor (
    input clk, rst_n,
    input [31:0] mode,
    input commit, exception, irq, mret, branch, jal, jalr,
    input pred_valid, pred_taken, actual_taken, train,
    input [31:0] pred_npc, actual_npc,
    input redirect, request, discarded, delivered,
    input [31:0] queued
);
import "DPI-C" function void npc_bpu_event(
    input int mode, flags, redirect_kind, flushed);
wire normal = commit && !exception;
wire [31:0] kind = !redirect ? 0 : irq ? 5 : exception ? 4 :
                    mret ? 6 : jalr ? 3 : jal ? 2 : branch ? 1 : 7;
always @(posedge clk) if (rst_n)
    npc_bpu_event(int'(mode),
        int'({train, delivered, discarded, request,
              normal && (branch || jal) && pred_npc != actual_npc,
              actual_taken, pred_taken, normal && branch && pred_valid,
              normal && branch}), int'(kind), redirect ? int'(queued) : 0);
endmodule
bind ysyx_core npc_bpu_monitor bpu_monitor (
    .clk(clk), .rst_n(rst_n), .mode(32'(BPU_MODE)),
    .commit(commit_valid), .exception(commit_exception), .irq(interrupt_taken),
    .mret(op_mret_valid), .branch(op_is_branch), .jal(op_is_jal), .jalr(op_is_jalr),
    .pred_valid(op_pred_branch), .pred_taken(op_pred_taken),
    .actual_taken(bpu_actual_taken), .train(bpu_train_valid),
    .pred_npc(op_pred_npc), .actual_npc(commit_npc), .redirect(redirect_valid),
    .request(imem_req_valid && imem_req_ready),
    .discarded(imem_rsp_valid && imem_rsp_ready && (redirect_valid || u_ifu.state_q == 2)),
    .delivered(if_ctx_fire), .queued(32'(u_ifu.u_ifq.count_q))
);
