`default_nettype none
module ysyx_axi4lite_uart (
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
    output reg tx_valid,
    output reg [7:0] tx_data
);
wire rd_en, wr_en;
wire [31:0] rd_addr, rd_data, wr_addr, wr_data;
wire [2:0] rd_prot, wr_prot;
wire [3:0] wr_strb;
wire [1:0] rd_resp, wr_resp;
ysyx_axi4lite_slave_frontend frontend (
    .clk(clk),
    .rst_n(rst_n),
    .s_axi_arvalid(s_axi_arvalid),
    .s_axi_arready(s_axi_arready),
    .s_axi_araddr(s_axi_araddr),
    .s_axi_arprot(s_axi_arprot),
    .s_axi_rvalid(s_axi_rvalid),
    .s_axi_rready(s_axi_rready),
    .s_axi_rdata(s_axi_rdata),
    .s_axi_rresp(s_axi_rresp),
    .s_axi_awvalid(s_axi_awvalid),
    .s_axi_awready(s_axi_awready),
    .s_axi_awaddr(s_axi_awaddr),
    .s_axi_awprot(s_axi_awprot),
    .s_axi_wvalid(s_axi_wvalid),
    .s_axi_wready(s_axi_wready),
    .s_axi_wdata(s_axi_wdata),
    .s_axi_wstrb(s_axi_wstrb),
    .s_axi_bvalid(s_axi_bvalid),
    .s_axi_bready(s_axi_bready),
    .s_axi_bresp(s_axi_bresp),
    .rd_en(rd_en),
    .rd_addr(rd_addr),
    .rd_prot(rd_prot),
    .rd_data(rd_data),
    .rd_resp(rd_resp),
    .wr_en(wr_en),
    .wr_addr(wr_addr),
    .wr_prot(wr_prot),
    .wr_data(wr_data),
    .wr_strb(wr_strb),
    .wr_resp(wr_resp)
);

wire unused_inputs = ^{rd_en,rd_addr,rd_prot,wr_prot[1:0],wr_data[31:8]};
wire write_ok = wr_addr == 32'ha00003f8 && !wr_prot[2] &&
                (wr_strb == 4'b0000 || wr_strb == 4'b0001);
assign rd_data = 32'b0;
assign rd_resp = 2'b10;
assign wr_resp = write_ok ? 2'b00 : 2'b10;
// Always-ready simulation sink: one event at write execution, independent of BREADY.
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin tx_valid <= 0; tx_data <= 0; end
    else begin
        tx_valid <= wr_en && write_ok && wr_strb[0];
        if (wr_en && write_ok && wr_strb[0]) tx_data <= wr_data[7:0];
    end
end
`ifndef SYNTHESIS
a09_tx_iff_effect: assert property (@(posedge clk) disable iff (!rst_n)
    1'b1 |=> tx_valid == $past(wr_en && write_ok && wr_strb[0]));
a09_tx_payload: assert property (@(posedge clk) disable iff (!rst_n)
    wr_en && write_ok && wr_strb[0] |=> tx_valid && tx_data == $past(wr_data[7:0]));
`endif

endmodule
`default_nettype wire
