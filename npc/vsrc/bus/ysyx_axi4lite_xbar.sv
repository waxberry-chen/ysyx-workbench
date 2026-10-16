

// Registered single-transaction router. Port order: SRAM, UART, CLINT, DECERR.
module ysyx_axi4lite_xbar #(parameter logic [31:0] SRAM_BYTES = 32'h00100000) (
    input wire clk,
    input wire rst_n,
    input  wire         s_axi_arvalid,
    output wire         s_axi_arready,
    input  wire [31:0]  s_axi_araddr,
    input  wire [2:0]   s_axi_arprot,
    output wire         s_axi_rvalid,
    input  wire         s_axi_rready,
    output wire [31:0]  s_axi_rdata,
    output wire [1:0]   s_axi_rresp,
    input  wire         s_axi_awvalid,
    output wire         s_axi_awready,
    input  wire [31:0]  s_axi_awaddr,
    input  wire [2:0]   s_axi_awprot,
    input  wire         s_axi_wvalid,
    output wire         s_axi_wready,
    input  wire [31:0]  s_axi_wdata,
    input  wire [3:0]   s_axi_wstrb,
    output wire         s_axi_bvalid,
    input  wire         s_axi_bready,
    output wire [1:0]   s_axi_bresp,
    output wire         m_axi_arvalid [0:3],
    input  wire         m_axi_arready [0:3],
    output wire [31:0]  m_axi_araddr [0:3],
    output wire [2:0]   m_axi_arprot [0:3],
    input  wire         m_axi_rvalid [0:3],
    output wire         m_axi_rready [0:3],
    input  wire [31:0]  m_axi_rdata [0:3],
    input  wire [1:0]   m_axi_rresp [0:3],
    output wire         m_axi_awvalid [0:3],
    input  wire         m_axi_awready [0:3],
    output wire [31:0]  m_axi_awaddr [0:3],
    output wire [2:0]   m_axi_awprot [0:3],
    output wire         m_axi_wvalid [0:3],
    input  wire         m_axi_wready [0:3],
    output wire [31:0]  m_axi_wdata [0:3],
    output wire [3:0]   m_axi_wstrb [0:3],
    input  wire         m_axi_bvalid [0:3],
    output wire         m_axi_bready [0:3],
    input  wire [1:0]   m_axi_bresp [0:3]
);

localparam logic [32:0] SRAM_END = 33'h080000000 + {1'b0, SRAM_BYTES};
function automatic [1:0] decode(input [31:0] addr);
    if ({1'b0,addr} >= 33'h080000000 && {1'b0,addr} < SRAM_END) decode = 2'd0;
    else if (addr >= 32'ha00003f8 && addr < 32'ha0000400) decode = 2'd1;
    else if (addr >= 32'ha0000048 && addr < 32'ha0000050) decode = 2'd2;
    else decode = 2'd3;
endfunction
// Reject invalid configurations at simulation startup before any traffic.
initial begin
    if (SRAM_BYTES == 0 || SRAM_BYTES[1:0] != 0 ||
        SRAM_END > 33'h100000000 || SRAM_END > 33'h0a0000048)
        $fatal(1, "SRAM_BYTES must be positive, word aligned and not overflow/overlap MMIO");
end

typedef enum logic [3:0] { IDLE, COLLECT_R, SEND_R, WAIT_R, RESP_R,
                          COLLECT_W, SEND_W, WAIT_W, RESP_W } state_t;
state_t state_q;
reg write_q, prefer_write_q, target_valid_q;
reg [1:0] target_q, resp_q;
reg [31:0] addr_q, wdata_q, rdata_q;
reg [2:0] prot_q;
reg [3:0] strb_q;
reg aw_have_q, w_have_q, aw_sent_q, w_sent_q;
wire write_pending = s_axi_awvalid || s_axi_wvalid;
wire choose_write = write_pending && (!s_axi_arvalid || prefer_write_q);
wire up_ar = s_axi_arvalid && s_axi_arready;
wire up_aw = s_axi_awvalid && s_axi_awready;
wire up_w = s_axi_wvalid && s_axi_wready;
wire down_ar = m_axi_arvalid[target_q] && m_axi_arready[target_q];
wire down_aw = m_axi_awvalid[target_q] && m_axi_awready[target_q];
wire down_w = m_axi_wvalid[target_q] && m_axi_wready[target_q];
wire down_r = m_axi_rvalid[target_q] && m_axi_rready[target_q];
wire down_b = m_axi_bvalid[target_q] && m_axi_bready[target_q];
wire done = (s_axi_rvalid && s_axi_rready) || (s_axi_bvalid && s_axi_bready);
assign s_axi_arready = rst_n && state_q == COLLECT_R;
assign s_axi_awready = rst_n && state_q == COLLECT_W && !aw_have_q;
assign s_axi_wready = rst_n && state_q == COLLECT_W && !w_have_q;
assign s_axi_rvalid = rst_n && state_q == RESP_R;
assign s_axi_bvalid = rst_n && state_q == RESP_W;
assign s_axi_rdata = rdata_q;
assign s_axi_rresp = resp_q;
assign s_axi_bresp = resp_q;
for (genvar i=0; i<4; i=i+1) begin : ports
    wire selected = rst_n && target_valid_q && target_q == 2'(i);
    assign m_axi_arvalid[i] = selected && state_q == SEND_R;
    assign m_axi_awvalid[i] = selected && state_q == SEND_W && !aw_sent_q;
    assign m_axi_wvalid[i] = selected && state_q == SEND_W && !w_sent_q;
    assign m_axi_rready[i] = selected && state_q == WAIT_R;
    assign m_axi_bready[i] = selected && state_q == WAIT_W;
    assign m_axi_araddr[i] = addr_q;
    assign m_axi_awaddr[i] = addr_q;
    assign m_axi_arprot[i] = prot_q;
    assign m_axi_awprot[i] = prot_q;
    assign m_axi_wdata[i] = wdata_q;
    assign m_axi_wstrb[i] = strb_q;
`ifndef SYNTHESIS
    a01_ar_holding: assert property (@(posedge clk) disable iff (!rst_n)
        m_axi_arvalid[i] && !m_axi_arready[i] |=> m_axi_arvalid[i] && $stable({m_axi_araddr[i],m_axi_arprot[i]}));
    a01_aw_holding: assert property (@(posedge clk) disable iff (!rst_n)
        m_axi_awvalid[i] && !m_axi_awready[i] |=> m_axi_awvalid[i] && $stable({m_axi_awaddr[i],m_axi_awprot[i]}));
    a01_w_holding: assert property (@(posedge clk) disable iff (!rst_n)
        m_axi_wvalid[i] && !m_axi_wready[i] |=> m_axi_wvalid[i] && $stable({m_axi_wdata[i],m_axi_wstrb[i]}));
    a05_unselected_quiet: assert property (@(posedge clk) disable iff (!rst_n)
        !selected |-> !(m_axi_arvalid[i] || m_axi_awvalid[i] || m_axi_wvalid[i] || m_axi_rready[i] || m_axi_bready[i]));
`endif
end
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state_q <= IDLE;
        write_q <= 0; prefer_write_q <= 0; target_valid_q <= 0; target_q <= 0;
        aw_have_q <= 0; w_have_q <= 0; aw_sent_q <= 0; w_sent_q <= 0;
        addr_q <= 0; prot_q <= 0; wdata_q <= 0; strb_q <= 0; rdata_q <= 0; resp_q <= 0;
    end else begin
        case (state_q)
            IDLE: if (s_axi_arvalid || write_pending) begin
                write_q <= choose_write;
                state_q <= choose_write ? COLLECT_W : COLLECT_R;
            end
            COLLECT_R: if (up_ar) begin
                addr_q <= s_axi_araddr; prot_q <= s_axi_arprot;
                target_q <= decode(s_axi_araddr); target_valid_q <= 1;
                state_q <= SEND_R;
            end
            SEND_R: if (down_ar) state_q <= WAIT_R;
            WAIT_R: if (down_r) begin
                rdata_q <= m_axi_rdata[target_q]; resp_q <= m_axi_rresp[target_q];
                state_q <= RESP_R;
            end
            COLLECT_W: begin
                if (up_aw) begin
                    addr_q <= s_axi_awaddr; prot_q <= s_axi_awprot;
                    target_q <= decode(s_axi_awaddr); target_valid_q <= 1;
                    aw_have_q <= 1;
                end
                if (up_w) begin
                    wdata_q <= s_axi_wdata; strb_q <= s_axi_wstrb; w_have_q <= 1;
                end
                if ((aw_have_q || up_aw) && (w_have_q || up_w)) state_q <= SEND_W;
            end
            SEND_W: begin
                if (down_aw) aw_sent_q <= 1;
                if (down_w) w_sent_q <= 1;
                if ((aw_sent_q || down_aw) && (w_sent_q || down_w)) state_q <= WAIT_W;
            end
            WAIT_W: if (down_b) begin
                resp_q <= m_axi_bresp[target_q]; state_q <= RESP_W;
            end
            RESP_R, RESP_W: if (done) begin
                prefer_write_q <= !write_q;
                target_valid_q <= 0;
                aw_have_q <= 0; w_have_q <= 0; aw_sent_q <= 0; w_sent_q <= 0;
                state_q <= IDLE;
            end
            default: state_q <= IDLE;
        endcase
    end
end
`ifndef SYNTHESIS
a05_target_holding: assert property (@(posedge clk) disable iff (!rst_n)
    target_valid_q && !done |=> target_valid_q && $stable(target_q));
a04_type_holding: assert property (@(posedge clk) disable iff (!rst_n)
    state_q != IDLE && !done |=> $stable(write_q));
a03_send_requires_both: assert property (@(posedge clk) disable iff (!rst_n)
    state_q == SEND_W |-> target_valid_q && aw_have_q && w_have_q);
a03_response_requires_sent: assert property (@(posedge clk) disable iff (!rst_n)
    state_q == WAIT_W || state_q == RESP_W |-> aw_sent_q && w_sent_q);
a04_one_type: assert property (@(posedge clk) disable iff (!rst_n)
    !(s_axi_arready && (s_axi_awready || s_axi_wready)) && !(s_axi_rvalid && s_axi_bvalid));
a01_r_holding: assert property (@(posedge clk) disable iff (!rst_n)
    s_axi_rvalid && !s_axi_rready |=> s_axi_rvalid && $stable({s_axi_rdata,s_axi_rresp}));
a01_b_holding: assert property (@(posedge clk) disable iff (!rst_n)
    s_axi_bvalid && !s_axi_bready |=> s_axi_bvalid && $stable(s_axi_bresp));
`endif
endmodule

