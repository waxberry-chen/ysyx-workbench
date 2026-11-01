// Single-service-slot router following the IFU/LSU arbiter. The arbiter owns
// the requester; this module owns the target until its buffered response retires.
// AW and W are buffered independently BEFORE decoding/forwarding a write, so a
// W-first transfer cannot escape to an unknown target. No AXI input -> AXI output
// combinational path. Fixed ID/LEN/BURST/LAST are provided by the upstream arbiter.
module ysyx_axi4_router (
    input clk,
    input rst_n,
    output timer_irq,
    input s_axi_arvalid,
    output s_axi_arready,
    input [31:0] s_axi_araddr,
    input [2:0] s_axi_arsize,
    input [2:0] s_axi_arprot,
    output s_axi_rvalid,
    input s_axi_rready,
    output [31:0] s_axi_rdata,
    output [1:0] s_axi_rresp,
    output [3:0] s_axi_rid,
    output s_axi_rlast,
    input s_axi_awvalid,
    output s_axi_awready,
    input [31:0] s_axi_awaddr,
    input [2:0] s_axi_awsize,
    input [2:0] s_axi_awprot,
    input s_axi_wvalid,
    output s_axi_wready,
    input [31:0] s_axi_wdata,
    input [3:0] s_axi_wstrb,
    output s_axi_bvalid,
    input s_axi_bready,
    output [1:0] s_axi_bresp,
    output [3:0] s_axi_bid,
    output m_axi_arvalid,
    input m_axi_arready,
    output [31:0] m_axi_araddr,
    output [2:0] m_axi_arsize,
    output [2:0] m_axi_arprot,
    input m_axi_rvalid,
    output m_axi_rready,
    input [31:0] m_axi_rdata,
    input [1:0] m_axi_rresp,
    input [3:0] m_axi_rid,
    input m_axi_rlast,
    output m_axi_awvalid,
    input m_axi_awready,
    output [31:0] m_axi_awaddr,
    output [2:0] m_axi_awsize,
    output [2:0] m_axi_awprot,
    output m_axi_wvalid,
    input m_axi_wready,
    output [31:0] m_axi_wdata,
    output [3:0] m_axi_wstrb,
    input m_axi_bvalid,
    output m_axi_bready,
    input [1:0] m_axi_bresp,
    input [3:0] m_axi_bid
);
typedef enum logic [3:0] {IDLE, COLLECT_W, DISPATCH_R, DISPATCH_W,
                        SEND_R, WAIT_R, SEND_W, WAIT_B, RESP_R, RESP_B} state_t;
state_t state_q;
reg [31:0] addr_q, data_q, rdata_q;
reg [2:0] size_q, prot_q;
reg [3:0] strb_q, id_q;
reg [1:0] resp_q;
reg last_q, aw_have_q, w_have_q, aw_sent_q, w_sent_q;
wire local_target = addr_q[31:16] == 16'h0200;
wire ar_fire = s_axi_arvalid && s_axi_arready;
wire aw_fire = s_axi_awvalid && s_axi_awready;
wire w_fire = s_axi_wvalid && s_axi_wready;
wire local_valid = rst_n && local_target &&
                   (state_q == DISPATCH_R || state_q == DISPATCH_W);
wire [31:0] local_data;
wire local_error;
ysyx_clint clint (
    .clk(clk), .rst_n(rst_n), .req_valid(local_valid),
    .req_write(state_q == DISPATCH_W), .req_addr(addr_q), .req_size(size_q),
    .req_wdata(data_q), .req_wstrb(strb_q),
    .rsp_data(local_data), .rsp_error(local_error), .timer_irq(timer_irq)
);
// IDLE observes which transaction is being offered, then reserves a channel.
// A read can be accepted directly; write ready is raised only in COLLECT_W.
assign s_axi_arready = rst_n && state_q == IDLE;
assign s_axi_awready = rst_n && state_q == COLLECT_W && !aw_have_q;
assign s_axi_wready = rst_n && state_q == COLLECT_W && !w_have_q;
assign s_axi_rvalid = rst_n && state_q == RESP_R;
assign s_axi_rdata = rdata_q;
assign s_axi_rresp = resp_q;
assign s_axi_rid = id_q;
assign s_axi_rlast = last_q;
assign s_axi_bvalid = rst_n && state_q == RESP_B;
assign s_axi_bresp = resp_q;
assign s_axi_bid = id_q;
assign m_axi_arvalid = rst_n && state_q == SEND_R;
assign m_axi_araddr = addr_q;
assign m_axi_arsize = size_q;
assign m_axi_arprot = prot_q;
assign m_axi_rready = rst_n && state_q == WAIT_R;
assign m_axi_awvalid = rst_n && state_q == SEND_W && !aw_sent_q;
assign m_axi_awaddr = addr_q;
assign m_axi_awsize = size_q;
assign m_axi_awprot = prot_q;
assign m_axi_wvalid = rst_n && state_q == SEND_W && !w_sent_q;
assign m_axi_wdata = data_q;
assign m_axi_wstrb = strb_q;
assign m_axi_bready = rst_n && state_q == WAIT_B;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state_q <= IDLE;
        addr_q <= 0; data_q <= 0; rdata_q <= 0;
        size_q <= 0; prot_q <= 0; strb_q <= 0; id_q <= 0; resp_q <= 0;
        last_q <= 1; aw_have_q <= 0; w_have_q <= 0; aw_sent_q <= 0; w_sent_q <= 0;
    end else case (state_q)
        IDLE: begin
            if (ar_fire) begin
                addr_q <= s_axi_araddr; size_q <= s_axi_arsize; prot_q <= s_axi_arprot;
                state_q <= DISPATCH_R;
            end else if (s_axi_awvalid || s_axi_wvalid) state_q <= COLLECT_W;
        end
        COLLECT_W: begin
            if (aw_fire) begin
                addr_q <= s_axi_awaddr; size_q <= s_axi_awsize; prot_q <= s_axi_awprot;
                aw_have_q <= 1;
            end
            if (w_fire) begin
                data_q <= s_axi_wdata; strb_q <= s_axi_wstrb; w_have_q <= 1;
            end
            if ((aw_have_q || aw_fire) && (w_have_q || w_fire)) state_q <= DISPATCH_W;
        end
        DISPATCH_R: begin
            if (local_target) begin
                rdata_q <= local_data; resp_q <= local_error ? 2'b10 : 2'b00;
                id_q <= 0; last_q <= 1; state_q <= RESP_R;
            end else state_q <= SEND_R;
        end
        DISPATCH_W: begin
            if (local_target) begin
                resp_q <= local_error ? 2'b10 : 2'b00; id_q <= 0; state_q <= RESP_B;
            end else state_q <= SEND_W;
        end
        SEND_R: if (m_axi_arready) state_q <= WAIT_R;
        WAIT_R: if (m_axi_rvalid) begin
            rdata_q <= m_axi_rdata; resp_q <= m_axi_rresp;
            id_q <= m_axi_rid; last_q <= m_axi_rlast; state_q <= RESP_R;
        end
        SEND_W: begin
            if (m_axi_awvalid && m_axi_awready) aw_sent_q <= 1;
            if (m_axi_wvalid && m_axi_wready) w_sent_q <= 1;
            if ((aw_sent_q || m_axi_awready) && (w_sent_q || m_axi_wready)) state_q <= WAIT_B;
        end
        WAIT_B: if (m_axi_bvalid) begin
            resp_q <= m_axi_bresp; id_q <= m_axi_bid; state_q <= RESP_B;
        end
        RESP_R, RESP_B: if ((s_axi_rvalid && s_axi_rready) || (s_axi_bvalid && s_axi_bready)) begin
            aw_have_q <= 0; w_have_q <= 0; aw_sent_q <= 0; w_sent_q <= 0;
            state_q <= IDLE;
        end
        default: state_q <= IDLE;
    endcase
end
`ifndef SYNTHESIS
// The single-outstanding upstream contract is guaranteed by the arbiter.
a_no_read_write_overlap: assert property (@(posedge clk) disable iff (!rst_n)
    !(s_axi_arvalid && (s_axi_awvalid || s_axi_wvalid)));
a_local_isolation: assert property (@(posedge clk) disable iff (!rst_n)
    local_valid |-> !(m_axi_arvalid || m_axi_awvalid || m_axi_wvalid));
a_r_expected: assert property (@(posedge clk) disable iff (!rst_n)
    m_axi_rvalid |-> state_q == WAIT_R || state_q == SEND_R);
a_b_expected: assert property (@(posedge clk) disable iff (!rst_n)
    m_axi_bvalid |-> state_q == WAIT_B || state_q == SEND_W);
a_ar_hold: assert property (@(posedge clk) disable iff (!rst_n)
    m_axi_arvalid && !m_axi_arready |=> m_axi_arvalid && $stable({m_axi_araddr,m_axi_arsize,m_axi_arprot}));
a_aw_hold: assert property (@(posedge clk) disable iff (!rst_n)
    m_axi_awvalid && !m_axi_awready |=> m_axi_awvalid && $stable({m_axi_awaddr,m_axi_awsize,m_axi_awprot}));
a_w_hold: assert property (@(posedge clk) disable iff (!rst_n)
    m_axi_wvalid && !m_axi_wready |=> m_axi_wvalid && $stable({m_axi_wdata,m_axi_wstrb}));
a_r_hold: assert property (@(posedge clk) disable iff (!rst_n)
    s_axi_rvalid && !s_axi_rready |=> s_axi_rvalid && $stable({s_axi_rdata,s_axi_rresp,s_axi_rid,s_axi_rlast}));
a_b_hold: assert property (@(posedge clk) disable iff (!rst_n)
    s_axi_bvalid && !s_axi_bready |=> s_axi_bvalid && $stable({s_axi_bresp,s_axi_bid}));
`endif
endmodule
