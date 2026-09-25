`default_nettype none

// Single-outstanding instruction fetch unit with a small elastic queue.
//
// The IFU owns the speculative fetch PC and the complete instruction-memory
// transaction.  A redirect cannot cancel an accepted request, so an old
// response is consumed in DROP state and never enters the instruction queue.
module ysyx_ifu #(
    parameter PC_RST    = 32'h8000_0000,
    parameter IFQ_DEPTH = 2
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
wire [64:0] ifq_in_data;
wire [64:0] ifq_out_data;
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
assign ifq_in_data  = {imem_rsp_error, request_pc_q, imem_rsp_data};

ysyx_gnrl_fifo #(
    .DW   (65),
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

assign if_ctx_error      = ifq_out_data[64];
assign if_ctx_pc         = ifq_out_data[63:32];
assign if_ctx_inst       = ifq_out_data[31:0];
assign if_ctx_pred_taken = 1'b0;
assign if_ctx_pred_npc   = if_ctx_pc + 32'd4;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state_q      <= REQ;
        fetch_pc_q   <= PC_RST;
        request_pc_q <= PC_RST;
    end else if (redirect_valid) begin
        fetch_pc_q <= redirect_target;
        if ((state_q == WAIT) && !rsp_fire)
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
                if (rsp_fire)
                    state_q <= REQ;
            end

            DROP: begin
                if (rsp_fire)
                    state_q <= REQ;
            end

            default: state_q <= REQ;
        endcase
    end
end

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
                                      if_ctx_pred_npc}));
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

endmodule

`default_nettype wire
