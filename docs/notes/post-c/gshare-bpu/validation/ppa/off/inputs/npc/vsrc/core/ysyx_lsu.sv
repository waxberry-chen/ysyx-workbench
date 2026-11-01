

// Single-outstanding load/store unit.
//
// The backend submits one decoded memory operation through req_valid/req_ready.
// The LSU then owns the operation until the external response has been
// buffered and accepted by the backend through rsp_valid/rsp_ready.
module ysyx_lsu (
    input              clk,
    input              rst_n,

    input              req_valid,
    output             req_ready,
    input              req_write,
    input      [31:0]  req_addr,
    input      [2:0]   req_type,
    input      [31:0]  req_wdata,

    output             rsp_valid,
    input              rsp_ready,
    output     [31:0]  rsp_rdata,
    output             rsp_error,

    output             dmem_req_valid,
    input              dmem_req_ready,
    output             dmem_req_write,
    output     [31:0]  dmem_req_addr,
    output     [1:0]   dmem_req_size,
    output     [31:0]  dmem_req_wdata,
    input              dmem_rsp_valid,
    output             dmem_rsp_ready,
    input      [31:0]  dmem_rsp_data,
    input              dmem_rsp_error
);

localparam [1:0] IDLE = 2'd0,
                 REQ  = 2'd1,
                 WAIT = 2'd2,
                 RESP = 2'd3;

reg [1:0]  state;
reg        req_write_q;
reg [31:0] req_addr_q;
reg [2:0]  req_type_q;
reg [31:0] req_wdata_q;
reg [31:0] response_data;
reg        response_error;

wire req_fire;
wire dmem_req_fire;
wire dmem_rsp_fire;
wire rsp_fire;

assign req_ready = state == IDLE;
assign req_fire  = req_valid & req_ready;

assign dmem_req_valid = state == REQ;
assign dmem_req_write = req_write_q;
assign dmem_req_addr  = req_addr_q;
assign dmem_req_size  = req_type_q[1:0];
assign dmem_req_wdata = req_wdata_q;
assign dmem_req_fire  = dmem_req_valid & dmem_req_ready;

assign dmem_rsp_ready = state == WAIT;
assign dmem_rsp_fire  = dmem_rsp_valid & dmem_rsp_ready;

assign rsp_valid = state == RESP;
assign rsp_rdata = response_data;
assign rsp_error = response_error;
assign rsp_fire  = rsp_valid & rsp_ready;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state         <= IDLE;
        req_write_q   <= 1'b0;
        req_addr_q    <= 32'b0;
        req_type_q    <= 3'b0;
        req_wdata_q   <= 32'b0;
        response_data <= 32'b0;
        response_error <= 1'b0;
    end else begin
        case (state)
            IDLE: begin
                if (req_fire) begin
                    req_write_q <= req_write;
                    req_addr_q  <= req_addr;
                    req_type_q  <= req_type;
                    req_wdata_q <= req_wdata;
                    state     <= REQ;
                end
            end

            REQ: begin
                if (dmem_req_fire) begin
                    state <= WAIT;
                end
            end

            WAIT: begin
                if (dmem_rsp_fire) begin
                    response_error <= dmem_rsp_error;
                    if (dmem_rsp_error || req_write_q) begin
                        response_data <= 32'b0;
                    end else begin
                        case (req_type_q)
                            3'h0: response_data <= {{24{dmem_rsp_data[7]}}, dmem_rsp_data[7:0]};
                            3'h1: response_data <= {{16{dmem_rsp_data[15]}}, dmem_rsp_data[15:0]};
                            3'h2: response_data <= dmem_rsp_data;
                            3'h4: response_data <= {24'b0, dmem_rsp_data[7:0]};
                            3'h5: response_data <= {16'b0, dmem_rsp_data[15:0]};
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
`ifndef SYNTHESIS
property p_request_stable_when_stalled;
    @(posedge clk) disable iff (!rst_n)
        dmem_req_valid && !dmem_req_ready
        |=> dmem_req_valid && $stable({dmem_req_write, dmem_req_addr,
                                       dmem_req_size, dmem_req_wdata});
endproperty
assert property (p_request_stable_when_stalled);

property p_response_stable_when_stalled;
    @(posedge clk) disable iff (!rst_n)
        rsp_valid && !rsp_ready
        |=> rsp_valid && $stable({rsp_rdata, rsp_error});
endproperty
assert property (p_response_stable_when_stalled);

property p_external_response_requires_outstanding;
    @(posedge clk) disable iff (!rst_n)
        dmem_rsp_valid |-> state == WAIT;
endproperty
assert property (p_external_response_requires_outstanding);

`endif

endmodule


