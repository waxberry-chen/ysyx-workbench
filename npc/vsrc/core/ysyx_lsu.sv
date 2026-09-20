`default_nettype none

// Single-outstanding load/store unit.
//
// The backend submits one decoded memory operation through op_valid/op_ready.
// The LSU then owns the operation until the external response has been
// buffered and accepted by the backend through rsp_valid/rsp_ready.
module ysyx_lsu (
    input              clk,
    input              rst_n,

    input              op_valid,
    output             op_ready,
    input              op_write,
    input      [31:0]  op_addr,
    input      [2:0]   op_type,
    input      [31:0]  op_wdata,

    output             rsp_valid,
    input              rsp_ready,
    output     [31:0]  rsp_rdata,

    output             d_req_valid,
    input              d_req_ready,
    output             d_req_write,
    output     [31:0]  d_req_addr,
    output     [1:0]   d_req_size,
    output     [31:0]  d_req_wdata,
    input              d_rsp_valid,
    output             d_rsp_ready,
    input      [31:0]  d_rsp_data
);

localparam [1:0] IDLE = 2'd0,
                 REQ  = 2'd1,
                 WAIT = 2'd2,
                 RESP = 2'd3;

reg [1:0]  state;
reg        req_write;
reg [31:0] req_addr;
reg [2:0]  req_type;
reg [31:0] req_wdata;
reg [31:0] response_data;

wire op_fire;
wire d_req_fire;
wire d_rsp_fire;
wire rsp_fire;

assign op_ready   = state == IDLE;
assign op_fire    = op_valid & op_ready;

assign d_req_valid = state == REQ;
assign d_req_write = req_write;
assign d_req_addr  = req_addr;
assign d_req_size  = req_type[1:0];
assign d_req_wdata = req_wdata;
assign d_req_fire  = d_req_valid & d_req_ready;

assign d_rsp_ready = state == WAIT;
assign d_rsp_fire  = d_rsp_valid & d_rsp_ready;

assign rsp_valid = state == RESP;
assign rsp_rdata = response_data;
assign rsp_fire  = rsp_valid & rsp_ready;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state         <= IDLE;
        req_write     <= 1'b0;
        req_addr      <= 32'b0;
        req_type      <= 3'b0;
        req_wdata     <= 32'b0;
        response_data <= 32'b0;
    end else begin
        case (state)
            IDLE: begin
                if (op_fire) begin
                    req_write <= op_write;
                    req_addr  <= op_addr;
                    req_type  <= op_type;
                    req_wdata <= op_wdata;
                    state     <= REQ;
                end
            end

            REQ: begin
                if (d_req_fire) begin
                    state <= WAIT;
                end
            end

            WAIT: begin
                if (d_rsp_fire) begin
                    if (req_write) begin
                        response_data <= 32'b0;
                    end else begin
                        case (req_type)
                            3'h0: response_data <= {{24{d_rsp_data[7]}}, d_rsp_data[7:0]};
                            3'h1: response_data <= {{16{d_rsp_data[15]}}, d_rsp_data[15:0]};
                            3'h2: response_data <= d_rsp_data;
                            3'h4: response_data <= {24'b0, d_rsp_data[7:0]};
                            3'h5: response_data <= {16'b0, d_rsp_data[15:0]};
                            default: response_data <= 32'b0;
                        endcase
                    end
                    state <= RESP;
                end
            end

            RESP: begin
                if (rsp_fire) begin
                    state <= IDLE;
                end
            end

            default: state <= IDLE;
        endcase
    end
end

// Interface invariants. NPC and the standalone LSU test enable them with
// --assert; they also remain useful to other simulators.
property p_request_stable_when_stalled;
    @(posedge clk) disable iff (!rst_n)
        d_req_valid && !d_req_ready
        |=> d_req_valid && $stable({d_req_write, d_req_addr,
                                    d_req_size, d_req_wdata});
endproperty
assert property (p_request_stable_when_stalled);

property p_response_stable_when_stalled;
    @(posedge clk) disable iff (!rst_n)
        rsp_valid && !rsp_ready
        |=> rsp_valid && $stable(rsp_rdata);
endproperty
assert property (p_response_stable_when_stalled);

property p_external_response_requires_outstanding;
    @(posedge clk) disable iff (!rst_n)
        d_rsp_valid |-> state == WAIT;
endproperty
assert property (p_external_response_requires_outstanding);

endmodule

`default_nettype wire
