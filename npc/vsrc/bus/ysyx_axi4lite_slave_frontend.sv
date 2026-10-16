

// One transaction at a time. Backend read samples on AR acceptance; write
// executes for one cycle after both AW/W slots have been captured.
module ysyx_axi4lite_slave_frontend (
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
    output wire rd_en,
    output wire [31:0] rd_addr,
    output wire [2:0] rd_prot,
    input wire [31:0] rd_data,
    input wire [1:0] rd_resp,
    output wire wr_en,
    output wire [31:0] wr_addr,
    output wire [2:0] wr_prot,
    output wire [31:0] wr_data,
    output wire [3:0] wr_strb,
    input wire [1:0] wr_resp
);

typedef enum logic [2:0] {IDLE, COLLECT_R, COLLECT_W, EXEC_W, RESP_R, RESP_W} state_t;
state_t state_q;
reg prefer_write_q, aw_have_q, w_have_q;
reg [31:0] addr_q, data_q, rdata_q;
reg [2:0] prot_q;
reg [3:0] strb_q;
reg [1:0] resp_q;
wire pending_w = s_axi_awvalid || s_axi_wvalid;
wire choose_w = pending_w && (!s_axi_arvalid || prefer_write_q);
wire aw_fire = s_axi_awvalid && s_axi_awready;
wire w_fire = s_axi_wvalid && s_axi_wready;
assign s_axi_arready = rst_n && state_q == COLLECT_R;
assign s_axi_awready = rst_n && state_q == COLLECT_W && !aw_have_q;
assign s_axi_wready = rst_n && state_q == COLLECT_W && !w_have_q;
assign s_axi_rvalid = rst_n && state_q == RESP_R;
assign s_axi_bvalid = rst_n && state_q == RESP_W;
assign s_axi_rdata = rdata_q;
assign s_axi_rresp = resp_q;
assign s_axi_bresp = resp_q;
assign rd_en = s_axi_arvalid && s_axi_arready;
assign rd_addr = s_axi_araddr;
assign rd_prot = s_axi_arprot;
assign wr_en = rst_n && state_q == EXEC_W;
assign wr_addr = addr_q;
assign wr_prot = prot_q;
assign wr_data = data_q;
assign wr_strb = strb_q;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state_q <= IDLE;
        prefer_write_q <= 0; aw_have_q <= 0; w_have_q <= 0;
        addr_q <= 0; data_q <= 0; prot_q <= 0; strb_q <= 0;
        rdata_q <= 0; resp_q <= 0;
    end else case (state_q)
        IDLE: if (s_axi_arvalid || pending_w)
            state_q <= choose_w ? COLLECT_W : COLLECT_R;
        COLLECT_R: if (rd_en) begin
            rdata_q <= rd_data; resp_q <= rd_resp; state_q <= RESP_R;
        end
        COLLECT_W: begin
            if (aw_fire) begin
                addr_q <= s_axi_awaddr; prot_q <= s_axi_awprot; aw_have_q <= 1;
            end
            if (w_fire) begin
                data_q <= s_axi_wdata; strb_q <= s_axi_wstrb; w_have_q <= 1;
            end
            if ((aw_have_q || aw_fire) && (w_have_q || w_fire)) state_q <= EXEC_W;
        end
        EXEC_W: begin resp_q <= wr_resp; state_q <= RESP_W; end
        RESP_R: if (s_axi_rready) begin prefer_write_q <= 1; state_q <= IDLE; end
        RESP_W: if (s_axi_bready) begin
            prefer_write_q <= 0; aw_have_q <= 0; w_have_q <= 0; state_q <= IDLE;
        end
        default: state_q <= IDLE;
    endcase
end
`ifndef SYNTHESIS
a03_write_complete: assert property (@(posedge clk) disable iff (!rst_n)
    wr_en || s_axi_bvalid |-> aw_have_q && w_have_q);
a07_write_once: assert property (@(posedge clk) disable iff (!rst_n)
    wr_en |=> !wr_en);
a04_one_type: assert property (@(posedge clk) disable iff (!rst_n)
    !(s_axi_arready && (s_axi_awready || s_axi_wready)) && !(s_axi_rvalid && s_axi_bvalid));
a04_response_blocks_requests: assert property (@(posedge clk) disable iff (!rst_n)
    s_axi_rvalid || s_axi_bvalid |-> !(s_axi_arready || s_axi_awready || s_axi_wready || wr_en || rd_en));
a01_r_holding: assert property (@(posedge clk) disable iff (!rst_n)
    s_axi_rvalid && !s_axi_rready |=> s_axi_rvalid && $stable({s_axi_rdata,s_axi_rresp}));
a01_b_holding: assert property (@(posedge clk) disable iff (!rst_n)
    s_axi_bvalid && !s_axi_bready |=> s_axi_bvalid && $stable(s_axi_bresp));
`endif
endmodule

