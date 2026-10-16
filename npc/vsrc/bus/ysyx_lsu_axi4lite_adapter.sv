

// Fully-registered, single-outstanding load/store AXI4-Lite adapter.
//
// Read requests use AR/R.  Write address and data are independent AXI
// channels, so aw_pending_q and w_pending_q retire each payload separately
// before the adapter waits for the single B response.
module ysyx_lsu_axi4lite_adapter (
    input              clk,
    input              rst_n,

    input              dmem_req_valid,
    output             dmem_req_ready,
    input              dmem_req_write,
    input      [31:0]  dmem_req_addr,
    input      [1:0]   dmem_req_size,
    input      [31:0]  dmem_req_wdata,
    output             dmem_rsp_valid,
    input              dmem_rsp_ready,
    output     [31:0]  dmem_rsp_data,
    output             dmem_rsp_error,

    output             m_axi_awvalid,
    input              m_axi_awready,
    output     [31:0]  m_axi_awaddr,
    output     [2:0]   m_axi_awprot,
    output             m_axi_wvalid,
    input              m_axi_wready,
    output     [31:0]  m_axi_wdata,
    output     [3:0]   m_axi_wstrb,
    input              m_axi_bvalid,
    output             m_axi_bready,
    input      [1:0]   m_axi_bresp,

    output             m_axi_arvalid,
    input              m_axi_arready,
    output     [31:0]  m_axi_araddr,
    output     [2:0]   m_axi_arprot,
    input              m_axi_rvalid,
    output             m_axi_rready,
    input      [31:0]  m_axi_rdata,
    input      [1:0]   m_axi_rresp
);

localparam [2:0] IDLE       = 3'd0,
                 SEND_AR    = 3'd1,
                 WAIT_R     = 3'd2,
                 SEND_WRITE = 3'd3,
                 WAIT_B     = 3'd4,
                 HOLD_RSP   = 3'd5;

reg [2:0]  state_q;
reg [31:0] request_addr_q;
reg [1:0]  request_size_q;
reg [31:0] request_wdata_q;
reg        aw_pending_q;
reg        w_pending_q;
reg [31:0] response_data_q;
reg        response_error_q;

reg [3:0] base_strobe;

wire [4:0]  byte_shift;
wire [31:0] aligned_addr;
wire [31:0] normalized_read_data;
wire        local_request_aligned;
wire        local_req_fire;
wire        axi_ar_fire;
wire        axi_r_fire;
wire        axi_aw_fire;
wire        axi_w_fire;
wire        axi_b_fire;
wire        local_rsp_fire;

assign byte_shift = {request_addr_q[1:0], 3'b000};
assign aligned_addr = {request_addr_q[31:2], 2'b00};
assign normalized_read_data = m_axi_rdata >> byte_shift;

always @(*) begin
    case (request_size_q)
        2'd0: base_strobe = 4'b0001;
        2'd1: base_strobe = 4'b0011;
        2'd2: base_strobe = 4'b1111;
        default: base_strobe = 4'b0000;
    endcase
end

assign local_request_aligned =
    (dmem_req_size == 2'd0) |
    ((dmem_req_size == 2'd1) && !dmem_req_addr[0]) |
    ((dmem_req_size == 2'd2) && (dmem_req_addr[1:0] == 2'b00));

assign dmem_req_ready = rst_n && (state_q == IDLE);
assign local_req_fire = dmem_req_valid && dmem_req_ready;

assign m_axi_arvalid = rst_n && (state_q == SEND_AR);
assign m_axi_araddr  = aligned_addr;
assign m_axi_arprot  = 3'b001;
assign axi_ar_fire   = m_axi_arvalid && m_axi_arready;

assign m_axi_rready = rst_n && (state_q == WAIT_R);
assign axi_r_fire   = m_axi_rvalid && m_axi_rready;

assign m_axi_awvalid = rst_n && (state_q == SEND_WRITE) && aw_pending_q;
assign m_axi_awaddr  = aligned_addr;
assign m_axi_awprot  = 3'b001;
assign axi_aw_fire   = m_axi_awvalid && m_axi_awready;

assign m_axi_wvalid = rst_n && (state_q == SEND_WRITE) && w_pending_q;
assign m_axi_wdata  = request_wdata_q << byte_shift;
assign m_axi_wstrb  = base_strobe << request_addr_q[1:0];
assign axi_w_fire   = m_axi_wvalid && m_axi_wready;

assign m_axi_bready = rst_n && (state_q == WAIT_B);
assign axi_b_fire   = m_axi_bvalid && m_axi_bready;

assign dmem_rsp_valid = rst_n && (state_q == HOLD_RSP);
assign dmem_rsp_data  = response_data_q;
assign dmem_rsp_error = response_error_q;
assign local_rsp_fire = dmem_rsp_valid && dmem_rsp_ready;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state_q          <= IDLE;
        request_addr_q   <= 32'b0;
        request_size_q   <= 2'b0;
        request_wdata_q  <= 32'b0;
        aw_pending_q     <= 1'b0;
        w_pending_q      <= 1'b0;
        response_data_q  <= 32'b0;
        response_error_q <= 1'b0;
    end else begin
        case (state_q)
            IDLE: begin
                if (local_req_fire) begin
                    request_addr_q  <= dmem_req_addr;
                    request_size_q  <= dmem_req_size;
                    request_wdata_q <= dmem_req_wdata;
                    if (dmem_req_write) begin
                        aw_pending_q <= 1'b1;
                        w_pending_q  <= 1'b1;
                        state_q      <= SEND_WRITE;
                    end else begin
                        aw_pending_q <= 1'b0;
                        w_pending_q  <= 1'b0;
                        state_q      <= SEND_AR;
                    end
                end
            end

            SEND_AR: begin
                if (axi_ar_fire)
                    state_q <= WAIT_R;
            end

            WAIT_R: begin
                if (axi_r_fire) begin
                    response_data_q  <= normalized_read_data;
                    response_error_q <= m_axi_rresp != 2'b00;
                    state_q          <= HOLD_RSP;
                end
            end

            SEND_WRITE: begin
                if (axi_aw_fire)
                    aw_pending_q <= 1'b0;
                if (axi_w_fire)
                    w_pending_q <= 1'b0;
                if ((!aw_pending_q || axi_aw_fire) &&
                    (!w_pending_q || axi_w_fire))
                    state_q <= WAIT_B;
            end

            WAIT_B: begin
                if (axi_b_fire) begin
                    response_data_q  <= 32'b0;
                    response_error_q <= m_axi_bresp != 2'b00;
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
        dmem_req_valid |-> local_request_aligned;
endproperty
assert property (p_aligned_local_request);

property p_ar_payload_stable_when_stalled;
    @(posedge clk) disable iff (!rst_n)
        m_axi_arvalid && !m_axi_arready
        |=> m_axi_arvalid &&
            $stable({m_axi_araddr, m_axi_arprot});
endproperty
assert property (p_ar_payload_stable_when_stalled);

property p_aw_payload_stable_when_stalled;
    @(posedge clk) disable iff (!rst_n)
        m_axi_awvalid && !m_axi_awready
        |=> m_axi_awvalid &&
            $stable({m_axi_awaddr, m_axi_awprot});
endproperty
assert property (p_aw_payload_stable_when_stalled);

property p_w_payload_stable_when_stalled;
    @(posedge clk) disable iff (!rst_n)
        m_axi_wvalid && !m_axi_wready
        |=> m_axi_wvalid &&
            $stable({m_axi_wdata, m_axi_wstrb});
endproperty
assert property (p_w_payload_stable_when_stalled);

property p_local_response_stable_when_stalled;
    @(posedge clk) disable iff (!rst_n)
        dmem_rsp_valid && !dmem_rsp_ready
        |=> dmem_rsp_valid &&
            $stable({dmem_rsp_data, dmem_rsp_error});
endproperty
assert property (p_local_response_stable_when_stalled);

property p_axi_read_response_requires_outstanding;
    @(posedge clk) disable iff (!rst_n)
        m_axi_rvalid |-> state_q == WAIT_R;
endproperty
assert property (p_axi_read_response_requires_outstanding);

property p_axi_write_response_requires_completed_request;
    @(posedge clk) disable iff (!rst_n)
        m_axi_bvalid |-> state_q == WAIT_B;
endproperty
assert property (p_axi_write_response_requires_completed_request);

property p_wait_b_requires_both_write_channels;
    @(posedge clk) disable iff (!rst_n)
        state_q == WAIT_B |-> !aw_pending_q && !w_pending_q;
endproperty
assert property (p_wait_b_requires_both_write_channels);

property p_single_outstanding_blocks_local_request;
    @(posedge clk) disable iff (!rst_n)
        state_q != IDLE |-> !dmem_req_ready;
endproperty
assert property (p_single_outstanding_blocks_local_request);

`endif

endmodule


