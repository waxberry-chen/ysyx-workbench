

// Fully-registered, single-outstanding instruction AXI4-Lite adapter.
//
// The local request is captured before ARVALID is asserted.  Likewise, an AXI
// read response is captured before it is exposed on the local response
// channel.  This keeps AXI inputs out of combinational paths to AXI outputs and
// gives both sides independent backpressure.
module ysyx_ifu_axi4lite_adapter (
    input              clk,
    input              rst_n,

    input              imem_req_valid,
    output             imem_req_ready,
    input      [31:0]  imem_req_addr,
    output             imem_rsp_valid,
    input              imem_rsp_ready,
    output     [31:0]  imem_rsp_data,
    output             imem_rsp_error,

    output             m_axi_arvalid,
    input              m_axi_arready,
    output     [31:0]  m_axi_araddr,
    output     [2:0]   m_axi_arprot,
    input              m_axi_rvalid,
    output             m_axi_rready,
    input      [31:0]  m_axi_rdata,
    input      [1:0]   m_axi_rresp
);

localparam [1:0] IDLE     = 2'd0,
                 SEND_AR  = 2'd1,
                 WAIT_R   = 2'd2,
                 HOLD_RSP = 2'd3;

reg [1:0]  state_q;
reg [31:0] request_addr_q;
reg [31:0] response_data_q;
reg        response_error_q;

wire local_req_fire;
wire axi_ar_fire;
wire axi_r_fire;
wire local_rsp_fire;

assign imem_req_ready = rst_n && (state_q == IDLE);
assign local_req_fire = imem_req_valid && imem_req_ready;

assign m_axi_arvalid = rst_n && (state_q == SEND_AR);
assign m_axi_araddr  = request_addr_q;
assign m_axi_arprot  = 3'b101;
assign axi_ar_fire   = m_axi_arvalid && m_axi_arready;

// The registered response buffer is empty throughout WAIT_R, so the adapter
// can accept the response independently of local response backpressure.
assign m_axi_rready = rst_n && (state_q == WAIT_R);
assign axi_r_fire   = m_axi_rvalid && m_axi_rready;

assign imem_rsp_valid = rst_n && (state_q == HOLD_RSP);
assign imem_rsp_data  = response_data_q;
assign imem_rsp_error = response_error_q;
assign local_rsp_fire = imem_rsp_valid && imem_rsp_ready;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state_q          <= IDLE;
        request_addr_q   <= 32'b0;
        response_data_q  <= 32'b0;
        response_error_q <= 1'b0;
    end else begin
        case (state_q)
            IDLE: begin
                if (local_req_fire) begin
                    request_addr_q <= imem_req_addr;
                    state_q        <= SEND_AR;
                end
            end

            SEND_AR: begin
                if (axi_ar_fire)
                    state_q <= WAIT_R;
            end

            WAIT_R: begin
                if (axi_r_fire) begin
                    response_data_q  <= m_axi_rdata;
                    response_error_q <= m_axi_rresp != 2'b00;
                    state_q          <= HOLD_RSP;
                end
            end

            HOLD_RSP: begin
                if (local_rsp_fire)
                    state_q <= IDLE;
            end

            default: state_q <= IDLE;
        endcase
    end
end

`ifndef SYNTHESIS
property p_aligned_local_request;
    @(posedge clk) disable iff (!rst_n)
        imem_req_valid |-> imem_req_addr[1:0] == 2'b00;
endproperty
assert property (p_aligned_local_request);

property p_ar_payload_stable_when_stalled;
    @(posedge clk) disable iff (!rst_n)
        m_axi_arvalid && !m_axi_arready
        |=> m_axi_arvalid &&
            $stable({m_axi_araddr, m_axi_arprot});
endproperty
assert property (p_ar_payload_stable_when_stalled);

property p_local_response_stable_when_stalled;
    @(posedge clk) disable iff (!rst_n)
        imem_rsp_valid && !imem_rsp_ready
        |=> imem_rsp_valid &&
            $stable({imem_rsp_data, imem_rsp_error});
endproperty
assert property (p_local_response_stable_when_stalled);

property p_axi_response_requires_outstanding_read;
    @(posedge clk) disable iff (!rst_n)
        m_axi_rvalid |-> state_q == WAIT_R;
endproperty
assert property (p_axi_response_requires_outstanding_read);

property p_single_outstanding_blocks_local_request;
    @(posedge clk) disable iff (!rst_n)
        state_q != IDLE |-> !imem_req_ready;
endproperty
assert property (p_single_outstanding_blocks_local_request);

`endif

endmodule


