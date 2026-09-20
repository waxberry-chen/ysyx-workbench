`default_nettype none

// Transitional backend controller used until Phase 2B introduces an opbuf.
// Instruction fetch ownership lives entirely in ysyx_ifu; this FSM only
// accepts instruction contexts, executes one instruction, and waits for LSU
// completion when necessary.
module ysyx_main_fsm (
    input  clk,
    input  rst_n,

    input       if_ctx_valid,
    output      if_ctx_ready,
    input       control_redirect,

    input       lsu_access,
    output      lsu_req_valid,
    input       lsu_req_ready,
    input       lsu_rsp_valid,
    output      lsu_rsp_ready,

    output      commit_valid
);

localparam [1:0] WAIT_CTX = 2'd0,
                 EXEC     = 2'd1,
                 LSU_WAIT = 2'd2;

reg [1:0] state_q;
reg [1:0] state_d;

assign lsu_req_valid = (state_q == EXEC) & lsu_access;
assign lsu_rsp_ready = state_q == LSU_WAIT;
assign commit_valid  = ((state_q == EXEC) & (~lsu_access)) |
                       ((state_q == LSU_WAIT) & lsu_rsp_valid);
assign if_ctx_ready  = (state_q == WAIT_CTX) |
                       (commit_valid & (~control_redirect));

always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        state_q <= WAIT_CTX;
    else
        state_q <= state_d;
end

always @(*) begin
    state_d = state_q;

    case (state_q)
        WAIT_CTX: begin
            if (if_ctx_valid)
                state_d = EXEC;
        end

        EXEC: begin
            if (lsu_access) begin
                if (lsu_req_ready)
                    state_d = LSU_WAIT;
            end else begin
                if (control_redirect) begin
                    state_d = WAIT_CTX;
                end else begin
                    if (if_ctx_valid)
                        state_d = EXEC;
                    else
                        state_d = WAIT_CTX;
                end
            end
        end

        LSU_WAIT: begin
            if (lsu_rsp_valid) begin
                if (control_redirect) begin
                    state_d = WAIT_CTX;
                end else begin
                    if (if_ctx_valid)
                        state_d = EXEC;
                    else
                        state_d = WAIT_CTX;
                end
            end
        end

        default: state_d = WAIT_CTX;
    endcase
end

property p_memory_commit_requires_lsu_response;
    @(posedge clk) disable iff (!rst_n)
        commit_valid && lsu_access |-> lsu_rsp_valid;
endproperty
assert property (p_memory_commit_requires_lsu_response);

property p_redirect_does_not_accept_old_context;
    @(posedge clk) disable iff (!rst_n)
        commit_valid && control_redirect |-> !if_ctx_ready;
endproperty
assert property (p_redirect_does_not_accept_old_context);

endmodule

`default_nettype wire
