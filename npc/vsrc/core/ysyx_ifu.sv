

// Single-outstanding instruction fetch unit with a small elastic queue.
//
// The IFU owns the speculative fetch PC and the complete instruction-memory
// transaction.  A redirect cannot cancel an accepted request, so an old
// response is consumed in DROP state and never enters the instruction queue.
module ysyx_ifu #(
    parameter PC_RST    = 32'h8000_0000,
    parameter IFQ_DEPTH = 2,
    parameter BPU_MODE = 2, // 0: legacy OFF, 1: JAL_ONLY, 2: GSHARE
    parameter BPU_INDEX_BITS = 7
) (
    input              clk,
    input              rst_n,

    input              redirect_valid,
    input      [31:0]  redirect_target,

    output             if_ctx_valid,
    input              if_ctx_ready,
    output     [31:0]  if_ctx_pc,
    output     [31:0]  if_ctx_inst,
    output             if_ctx_error,
    output             if_ctx_pred_taken,
    output     [31:0]  if_ctx_pred_npc,
    output             if_ctx_pred_branch,
    output [BPU_INDEX_BITS-1:0] if_ctx_pred_index,
    input              bpu_train_valid,
    input [BPU_INDEX_BITS-1:0] bpu_train_index,
    input              bpu_train_taken,

    output             imem_req_valid,
    input              imem_req_ready,
    output     [31:0]  imem_req_addr,
    input              imem_rsp_valid,
    output             imem_rsp_ready,
    input      [31:0]  imem_rsp_data,
    input              imem_rsp_error
);

localparam [1:0] REQ  = 2'd0,
                 WAIT = 2'd1,
                 DROP = 2'd2;

reg [1:0]  state_q;
reg [31:0] fetch_pc_q;
reg [31:0] request_pc_q;

wire        ifq_in_valid;
wire        ifq_in_ready;
localparam IFQ_DW = 99 + BPU_INDEX_BITS;
wire [IFQ_DW-1:0] ifq_in_data;
wire [IFQ_DW-1:0] ifq_out_data;
wire        req_fire;
wire        rsp_fire;

assign imem_req_valid = (state_q == REQ) & ifq_in_ready & (~redirect_valid);
assign imem_req_addr  = fetch_pc_q;
assign req_fire       = imem_req_valid & imem_req_ready;

// A fresh request reserves one IFQ entry before it is accepted.  Therefore a
// normal response can always be consumed.  During redirect, an old response
// is also consumed even though the queue is being flushed.
assign imem_rsp_ready = (state_q == DROP) |
                        ((state_q == WAIT) & (redirect_valid | ifq_in_ready));
assign rsp_fire       = imem_rsp_valid & imem_rsp_ready;

assign ifq_in_valid = (state_q == WAIT) & imem_rsp_valid & (~redirect_valid);
wire pre_branch, pre_jal;
wire [31:0] pre_target;
wire [BPU_INDEX_BITS-1:0] query_index;
wire query_taken;
ysyx_predecode u_predecode (
    .pc(request_pc_q), .inst(imem_rsp_data), .error(imem_rsp_error),
    .is_branch(pre_branch), .is_jal(pre_jal), .target(pre_target)
);
generate if (BPU_MODE == 2) begin : g_predictor
    ysyx_gshare #(.INDEX_BITS(BPU_INDEX_BITS)) u_gshare (
        .clk(clk), .rst_n(rst_n), .query_pc(request_pc_q),
        .query_index(query_index), .query_taken(query_taken),
        .train_valid(bpu_train_valid), .train_index(bpu_train_index),
        .train_taken(bpu_train_taken)
    );
end else begin : g_no_predictor
    assign query_index = '0;
    assign query_taken = 1'b0;
end endgenerate
// IALIGN=32. Do not introduce a speculative halfword-aligned bus request.
// Architectural handling of taken misaligned targets is unchanged from M5.
wire pred_taken = (BPU_MODE != 0) && (pre_target[1:0] == 2'b00) &&
                  (pre_jal || (BPU_MODE == 2 && pre_branch && query_taken));
wire [31:0] pred_npc = pred_taken ? pre_target : request_pc_q + 32'd4;
wire pred_branch = (BPU_MODE == 2) && pre_branch;
assign ifq_in_data = {pred_branch, query_index, pred_taken, pred_npc,
                     imem_rsp_error, request_pc_q, imem_rsp_data};

ysyx_gnrl_fifo #(
    .DW   (IFQ_DW),
    .DEPTH(IFQ_DEPTH)
) u_ifq (
    .in_valid (ifq_in_valid),
    .in_ready (ifq_in_ready),
    .in_data  (ifq_in_data),
    .out_valid(if_ctx_valid),
    .out_ready(if_ctx_ready),
    .out_data (ifq_out_data),
    .flush    (redirect_valid),
    .clk      (clk),
    .rst_n    (rst_n)
);

assign {if_ctx_pred_branch, if_ctx_pred_index, if_ctx_pred_taken, if_ctx_pred_npc,
        if_ctx_error, if_ctx_pc, if_ctx_inst} = ifq_out_data;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state_q      <= REQ;
        fetch_pc_q   <= PC_RST;
        request_pc_q <= PC_RST;
    end else if (redirect_valid) begin
        fetch_pc_q <= redirect_target;
        // A second redirect (e.g. MRET immediately followed by pending IRQ)
        // changes the destination but does not cancel the outstanding read.
        if (((state_q == WAIT) || (state_q == DROP)) && !rsp_fire)
            state_q <= DROP;
        else
            state_q <= REQ;
    end else begin
        case (state_q)
            REQ: begin
                if (req_fire) begin
                    request_pc_q <= fetch_pc_q;
                    fetch_pc_q   <= fetch_pc_q + 32'd4;
                    state_q      <= WAIT;
                end
            end

            WAIT: begin
                if (rsp_fire) begin
                    // Prediction changes only the NEXT request; it must not
                    // flush this instruction or older queued instructions.
                    fetch_pc_q <= pred_npc;
                    state_q <= REQ;
                end
            end

            DROP: begin
                if (rsp_fire)
                    state_q <= REQ;
            end

            default: state_q <= REQ;
        endcase
    end
end

`ifndef SYNTHESIS
initial assert (BPU_MODE >= 0 && BPU_MODE <= 2);
property p_request_stable_when_stalled;
    @(posedge clk) disable iff (!rst_n)
        imem_req_valid && !imem_req_ready
        |=> redirect_valid ||
            (imem_req_valid && $stable(imem_req_addr));
endproperty
assert property (p_request_stable_when_stalled);

property p_context_stable_when_stalled;
    @(posedge clk) disable iff (!rst_n)
        if_ctx_valid && !if_ctx_ready
        |=> redirect_valid ||
            (if_ctx_valid && $stable({if_ctx_pc, if_ctx_inst,
                                      if_ctx_error, if_ctx_pred_taken,
                                      if_ctx_pred_npc, if_ctx_pred_branch, if_ctx_pred_index}));
endproperty
assert property (p_context_stable_when_stalled);

property p_fresh_response_has_credit;
    @(posedge clk) disable iff (!rst_n)
        state_q == WAIT && imem_rsp_valid && !redirect_valid
        |-> ifq_in_ready;
endproperty
assert property (p_fresh_response_has_credit);

property p_dropped_response_never_enters_ifq;
    @(posedge clk) disable iff (!rst_n)
        state_q == DROP && imem_rsp_valid |-> !ifq_in_valid;
endproperty
assert property (p_dropped_response_never_enters_ifq);

`endif

endmodule


