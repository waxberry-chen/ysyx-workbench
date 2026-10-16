

// IFU read-only + LSU read/write -> one AXI4-Lite master.
// One service slot, including the buffered upstream response. A grant is
// reserved before asserting READY; AW and W are then captured independently.
// All interface outputs depend only on registers (and reset), never READY.
module ysyx_axi4lite_arbiter (
    input              clk,
    input              rst_n,
    input              ifu_axi_arvalid,
    output             ifu_axi_arready,
    input      [31:0]  ifu_axi_araddr,
    input      [2:0]   ifu_axi_arprot,
    output             ifu_axi_rvalid,
    input              ifu_axi_rready,
    output     [31:0]  ifu_axi_rdata,
    output     [1:0]   ifu_axi_rresp,
    input              lsu_axi_arvalid,
    output             lsu_axi_arready,
    input      [31:0]  lsu_axi_araddr,
    input      [2:0]   lsu_axi_arprot,
    output             lsu_axi_rvalid,
    input              lsu_axi_rready,
    output     [31:0]  lsu_axi_rdata,
    output     [1:0]   lsu_axi_rresp,
    input              lsu_axi_awvalid,
    output             lsu_axi_awready,
    input      [31:0]  lsu_axi_awaddr,
    input      [2:0]   lsu_axi_awprot,
    input              lsu_axi_wvalid,
    output             lsu_axi_wready,
    input      [31:0]  lsu_axi_wdata,
    input      [3:0]   lsu_axi_wstrb,
    output             lsu_axi_bvalid,
    input              lsu_axi_bready,
    output     [1:0]   lsu_axi_bresp,
    output             m_axi_arvalid,
    input              m_axi_arready,
    output     [31:0]  m_axi_araddr,
    output     [2:0]   m_axi_arprot,
    input              m_axi_rvalid,
    output             m_axi_rready,
    input      [31:0]  m_axi_rdata,
    input      [1:0]   m_axi_rresp,
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
    input      [1:0]   m_axi_bresp
);

typedef enum logic [3:0] {
    IDLE, COLLECT_R, SEND_R, WAIT_R, RESP_R,
    COLLECT_W, SEND_W, WAIT_W, RESP_W
} state_t;
state_t state_q;
reg owner_q;                 // 0: IFU, 1: LSU
reg write_q;
reg prefer_lsu_q;            // priority on the next contention
reg [31:0] addr_q, wdata_q, rdata_q;
reg [2:0] prot_q;
reg [3:0] strb_q;
reg [1:0] resp_q;
reg aw_have_q, w_have_q, aw_sent_q, w_sent_q;

wire lsu_pending = lsu_axi_arvalid | lsu_axi_awvalid | lsu_axi_wvalid;
wire choose_lsu = lsu_pending && (!ifu_axi_arvalid || prefer_lsu_q);
wire up_ar_fire = (ifu_axi_arvalid && ifu_axi_arready) |
                  (lsu_axi_arvalid && lsu_axi_arready);
wire up_aw_fire = lsu_axi_awvalid && lsu_axi_awready;
wire up_w_fire = lsu_axi_wvalid && lsu_axi_wready;
wire ar_fire = m_axi_arvalid && m_axi_arready;
wire aw_fire = m_axi_awvalid && m_axi_awready;
wire w_fire = m_axi_wvalid && m_axi_wready;
wire r_fire = m_axi_rvalid && m_axi_rready;
wire b_fire = m_axi_bvalid && m_axi_bready;
wire done = (ifu_axi_rvalid && ifu_axi_rready) |
            (lsu_axi_rvalid && lsu_axi_rready) |
            (lsu_axi_bvalid && lsu_axi_bready);

assign ifu_axi_arready = rst_n && state_q == COLLECT_R && !owner_q;
assign lsu_axi_arready = rst_n && state_q == COLLECT_R && owner_q;
assign lsu_axi_awready = rst_n && state_q == COLLECT_W && !aw_have_q;
assign lsu_axi_wready  = rst_n && state_q == COLLECT_W && !w_have_q;
assign ifu_axi_rvalid  = rst_n && state_q == RESP_R && !owner_q;
assign lsu_axi_rvalid  = rst_n && state_q == RESP_R && owner_q;
assign lsu_axi_bvalid  = rst_n && state_q == RESP_W && owner_q && write_q;
assign ifu_axi_rdata = rdata_q;
assign lsu_axi_rdata = rdata_q;
assign ifu_axi_rresp = resp_q;
assign lsu_axi_rresp = resp_q;
assign lsu_axi_bresp = resp_q;

assign m_axi_arvalid = rst_n && state_q == SEND_R;
assign m_axi_araddr = addr_q;
assign m_axi_arprot = prot_q;
assign m_axi_awvalid = rst_n && state_q == SEND_W && !aw_sent_q;
assign m_axi_awaddr = addr_q;
assign m_axi_awprot = prot_q;
assign m_axi_wvalid = rst_n && state_q == SEND_W && !w_sent_q;
assign m_axi_wdata = wdata_q;
assign m_axi_wstrb = strb_q;
assign m_axi_rready = rst_n && state_q == WAIT_R;
assign m_axi_bready = rst_n && state_q == WAIT_W;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state_q <= IDLE;
        owner_q <= 1'b0;
        write_q <= 1'b0;
        prefer_lsu_q <= 1'b0;
        aw_have_q <= 1'b0;
        w_have_q <= 1'b0;
        aw_sent_q <= 1'b0;
        w_sent_q <= 1'b0;
        addr_q <= 32'b0;
        prot_q <= 3'b0;
        wdata_q <= 32'b0;
        strb_q <= 4'b0;
        rdata_q <= 32'b0;
        resp_q <= 2'b0;
    end else begin
        case (state_q)
            IDLE: if (ifu_axi_arvalid || lsu_pending) begin
                owner_q <= choose_lsu;
                write_q <= choose_lsu && !lsu_axi_arvalid;
                state_q <= (choose_lsu && !lsu_axi_arvalid) ? COLLECT_W : COLLECT_R;
            end
            COLLECT_R: if (up_ar_fire) begin
                addr_q <= owner_q ? lsu_axi_araddr : ifu_axi_araddr;
                prot_q <= owner_q ? lsu_axi_arprot : ifu_axi_arprot;
                state_q <= SEND_R;
            end
            SEND_R: if (ar_fire) state_q <= WAIT_R;
            WAIT_R: if (r_fire) begin
                rdata_q <= m_axi_rdata;
                resp_q <= m_axi_rresp;
                state_q <= RESP_R;
            end
            COLLECT_W: begin
                if (up_aw_fire) begin
                    addr_q <= lsu_axi_awaddr;
                    prot_q <= lsu_axi_awprot;
                    aw_have_q <= 1'b1;
                end
                if (up_w_fire) begin
                    wdata_q <= lsu_axi_wdata;
                    strb_q <= lsu_axi_wstrb;
                    w_have_q <= 1'b1;
                end
                if ((aw_have_q || up_aw_fire) && (w_have_q || up_w_fire))
                    state_q <= SEND_W;
            end
            SEND_W: begin
                if (aw_fire) aw_sent_q <= 1'b1;
                if (w_fire) w_sent_q <= 1'b1;
                if ((aw_sent_q || aw_fire) && (w_sent_q || w_fire))
                    state_q <= WAIT_W;
            end
            WAIT_W: if (b_fire) begin
                resp_q <= m_axi_bresp;
                state_q <= RESP_W;
            end
            RESP_R, RESP_W: if (done) begin
                prefer_lsu_q <= !owner_q;
                owner_q <= 1'b0;
                write_q <= 1'b0;
                aw_have_q <= 1'b0;
                w_have_q <= 1'b0;
                aw_sent_q <= 1'b0;
                w_sent_q <= 1'b0;
                state_q <= IDLE;
            end
            default: state_q <= IDLE;
        endcase
    end
end

// A01-A04/A08: safety properties, not an unbounded liveness proof.
`ifndef SYNTHESIS
a03_lsu_request_contract: assert property (@(posedge clk) disable iff (!rst_n)
    !(lsu_axi_arvalid && (lsu_axi_awvalid || lsu_axi_wvalid)));
a02_owner_type_holding: assert property (@(posedge clk) disable iff (!rst_n)
    state_q != IDLE && !done |=> $stable({owner_q, write_q}));
a02_one_request_owner: assert property (@(posedge clk) disable iff (!rst_n)
    $onehot0({ifu_axi_arready, lsu_axi_arready,
              (lsu_axi_awready || lsu_axi_wready)}));
a04_one_response_owner: assert property (@(posedge clk) disable iff (!rst_n)
    $onehot0({ifu_axi_rvalid, lsu_axi_rvalid, lsu_axi_bvalid}));
a03_write_requires_both_slots: assert property (@(posedge clk) disable iff (!rst_n)
    state_q == SEND_W |-> owner_q && write_q && aw_have_q && w_have_q);
a03_response_requires_both_sent: assert property (@(posedge clk) disable iff (!rst_n)
    state_q == WAIT_W || state_q == RESP_W |-> aw_sent_q && w_sent_q);
a04_response_blocks_requests: assert property (@(posedge clk) disable iff (!rst_n)
    state_q == RESP_R || state_q == RESP_W |->
        !(ifu_axi_arready || lsu_axi_arready || lsu_axi_awready || lsu_axi_wready));
a01_ar_holding: assert property (@(posedge clk) disable iff (!rst_n)
    m_axi_arvalid && !m_axi_arready |=> m_axi_arvalid && $stable({m_axi_araddr,m_axi_arprot}));
a01_aw_holding: assert property (@(posedge clk) disable iff (!rst_n)
    m_axi_awvalid && !m_axi_awready |=> m_axi_awvalid && $stable({m_axi_awaddr,m_axi_awprot}));
a01_w_holding: assert property (@(posedge clk) disable iff (!rst_n)
    m_axi_wvalid && !m_axi_wready |=> m_axi_wvalid && $stable({m_axi_wdata,m_axi_wstrb}));
a01_ifu_r_holding: assert property (@(posedge clk) disable iff (!rst_n)
    ifu_axi_rvalid && !ifu_axi_rready |=> ifu_axi_rvalid && $stable({ifu_axi_rdata,ifu_axi_rresp}));
a01_lsu_r_holding: assert property (@(posedge clk) disable iff (!rst_n)
    lsu_axi_rvalid && !lsu_axi_rready |=> lsu_axi_rvalid && $stable({lsu_axi_rdata,lsu_axi_rresp}));
a01_lsu_b_holding: assert property (@(posedge clk) disable iff (!rst_n)
    lsu_axi_bvalid && !lsu_axi_bready |=> lsu_axi_bvalid && $stable(lsu_axi_bresp));
`endif
endmodule

