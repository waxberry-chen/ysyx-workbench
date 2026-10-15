`default_nettype none
module axi4lite_fabric_test_top #(parameter logic [31:0] SRAM_BYTES=32'd12288) (
 input wire clk,rst_n,
 input wire [4:0] sim_accept,
 input wire [7:0] sim_delay [0:4],
 output wire [4:0] shim_valid, shim_ready,
 output wire tap_sram_effect,
 output wire tx_valid, output wire [7:0] tx_data,
 output wire [3:0] monitor_ar,monitor_aw,monitor_w,monitor_r,monitor_b,
 output wire [7:0] monitor_rresp,monitor_bresp,
 input wire  ifu_axi_arvalid,
 output wire  ifu_axi_arready,
 input wire [31:0] ifu_axi_araddr,
 input wire [2:0] ifu_axi_arprot,
 output wire  ifu_axi_rvalid,
 input wire  ifu_axi_rready,
 output wire [31:0] ifu_axi_rdata,
 output wire [1:0] ifu_axi_rresp,
 input wire  lsu_axi_arvalid,
 output wire  lsu_axi_arready,
 input wire [31:0] lsu_axi_araddr,
 input wire [2:0] lsu_axi_arprot,
 output wire  lsu_axi_rvalid,
 input wire  lsu_axi_rready,
 output wire [31:0] lsu_axi_rdata,
 output wire [1:0] lsu_axi_rresp,
 input wire  lsu_axi_awvalid,
 output wire  lsu_axi_awready,
 input wire [31:0] lsu_axi_awaddr,
 input wire [2:0] lsu_axi_awprot,
 input wire  lsu_axi_wvalid,
 output wire  lsu_axi_wready,
 input wire [31:0] lsu_axi_wdata,
 input wire [3:0] lsu_axi_wstrb,
 output wire  lsu_axi_bvalid,
 input wire  lsu_axi_bready,
 output wire [1:0] lsu_axi_bresp,
 output wire [31:0] tap_araddr [0:3],
 output wire [2:0] tap_arprot [0:3],
 output wire [31:0] tap_awaddr [0:3],
 output wire [2:0] tap_awprot [0:3],
 output wire [31:0] tap_wdata [0:3],
 output wire [3:0] tap_wstrb [0:3],
 output wire [31:0] tap_rdata [0:3]
);
assign shim_valid={d_axi_bvalid,d_axi_rvalid,m_axi_wvalid,m_axi_awvalid,m_axi_arvalid};
assign shim_ready={d_axi_bready,d_axi_rready,m_axi_wready,m_axi_awready,m_axi_arready};
wire  m_axi_arvalid;
wire  x_arvalid [0:3];
wire  m_axi_arready;
wire  x_arready [0:3];
wire [31:0] m_axi_araddr;
wire [31:0] x_araddr [0:3];
wire [2:0] m_axi_arprot;
wire [2:0] x_arprot [0:3];
wire  m_axi_rvalid;
wire  x_rvalid [0:3];
wire  m_axi_rready;
wire  x_rready [0:3];
wire [31:0] m_axi_rdata;
wire [31:0] x_rdata [0:3];
wire [1:0] m_axi_rresp;
wire [1:0] x_rresp [0:3];
wire  m_axi_awvalid;
wire  x_awvalid [0:3];
wire  m_axi_awready;
wire  x_awready [0:3];
wire [31:0] m_axi_awaddr;
wire [31:0] x_awaddr [0:3];
wire [2:0] m_axi_awprot;
wire [2:0] x_awprot [0:3];
wire  m_axi_wvalid;
wire  x_wvalid [0:3];
wire  m_axi_wready;
wire  x_wready [0:3];
wire [31:0] m_axi_wdata;
wire [31:0] x_wdata [0:3];
wire [3:0] m_axi_wstrb;
wire [3:0] x_wstrb [0:3];
wire  m_axi_bvalid;
wire  x_bvalid [0:3];
wire  m_axi_bready;
wire  x_bready [0:3];
wire [1:0] m_axi_bresp;
wire [1:0] x_bresp [0:3];
ysyx_axi4lite_arbiter arbiter (.clk(clk),.rst_n(rst_n),
 .ifu_axi_arvalid(ifu_axi_arvalid),
 .ifu_axi_arready(ifu_axi_arready),
 .ifu_axi_araddr(ifu_axi_araddr),
 .ifu_axi_arprot(ifu_axi_arprot),
 .ifu_axi_rvalid(ifu_axi_rvalid),
 .ifu_axi_rready(ifu_axi_rready),
 .ifu_axi_rdata(ifu_axi_rdata),
 .ifu_axi_rresp(ifu_axi_rresp),
 .lsu_axi_arvalid(lsu_axi_arvalid),
 .lsu_axi_arready(lsu_axi_arready),
 .lsu_axi_araddr(lsu_axi_araddr),
 .lsu_axi_arprot(lsu_axi_arprot),
 .lsu_axi_rvalid(lsu_axi_rvalid),
 .lsu_axi_rready(lsu_axi_rready),
 .lsu_axi_rdata(lsu_axi_rdata),
 .lsu_axi_rresp(lsu_axi_rresp),
 .lsu_axi_awvalid(lsu_axi_awvalid),
 .lsu_axi_awready(lsu_axi_awready),
 .lsu_axi_awaddr(lsu_axi_awaddr),
 .lsu_axi_awprot(lsu_axi_awprot),
 .lsu_axi_wvalid(lsu_axi_wvalid),
 .lsu_axi_wready(lsu_axi_wready),
 .lsu_axi_wdata(lsu_axi_wdata),
 .lsu_axi_wstrb(lsu_axi_wstrb),
 .lsu_axi_bvalid(lsu_axi_bvalid),
 .lsu_axi_bready(lsu_axi_bready),
 .lsu_axi_bresp(lsu_axi_bresp),
 .m_axi_arvalid(m_axi_arvalid),
 .m_axi_arready(m_axi_arready),
 .m_axi_araddr(m_axi_araddr),
 .m_axi_arprot(m_axi_arprot),
 .m_axi_rvalid(m_axi_rvalid),
 .m_axi_rready(m_axi_rready),
 .m_axi_rdata(m_axi_rdata),
 .m_axi_rresp(m_axi_rresp),
 .m_axi_awvalid(m_axi_awvalid),
 .m_axi_awready(m_axi_awready),
 .m_axi_awaddr(m_axi_awaddr),
 .m_axi_awprot(m_axi_awprot),
 .m_axi_wvalid(m_axi_wvalid),
 .m_axi_wready(m_axi_wready),
 .m_axi_wdata(m_axi_wdata),
 .m_axi_wstrb(m_axi_wstrb),
 .m_axi_bvalid(m_axi_bvalid),
 .m_axi_bready(m_axi_bready),
 .m_axi_bresp(m_axi_bresp)
);
wire  d_axi_arvalid;
wire  d_axi_arready;
wire [31:0] d_axi_araddr;
wire [2:0] d_axi_arprot;
wire  d_axi_rvalid;
wire  d_axi_rready;
wire [31:0] d_axi_rdata;
wire [1:0] d_axi_rresp;
wire  d_axi_awvalid;
wire  d_axi_awready;
wire [31:0] d_axi_awaddr;
wire [2:0] d_axi_awprot;
wire  d_axi_wvalid;
wire  d_axi_wready;
wire [31:0] d_axi_wdata;
wire [3:0] d_axi_wstrb;
wire  d_axi_bvalid;
wire  d_axi_bready;
wire [1:0] d_axi_bresp;
axi4lite_delay_shim delay_shim (
 .clk(clk), .rst_n(rst_n), .accept_enable(sim_accept), .delay_cycles(sim_delay),
 .s_axi_arvalid(m_axi_arvalid), .m_axi_arvalid(d_axi_arvalid),
 .s_axi_arready(m_axi_arready), .m_axi_arready(d_axi_arready),
 .s_axi_araddr(m_axi_araddr), .m_axi_araddr(d_axi_araddr),
 .s_axi_arprot(m_axi_arprot), .m_axi_arprot(d_axi_arprot),
 .s_axi_rvalid(m_axi_rvalid), .m_axi_rvalid(d_axi_rvalid),
 .s_axi_rready(m_axi_rready), .m_axi_rready(d_axi_rready),
 .s_axi_rdata(m_axi_rdata), .m_axi_rdata(d_axi_rdata),
 .s_axi_rresp(m_axi_rresp), .m_axi_rresp(d_axi_rresp),
 .s_axi_awvalid(m_axi_awvalid), .m_axi_awvalid(d_axi_awvalid),
 .s_axi_awready(m_axi_awready), .m_axi_awready(d_axi_awready),
 .s_axi_awaddr(m_axi_awaddr), .m_axi_awaddr(d_axi_awaddr),
 .s_axi_awprot(m_axi_awprot), .m_axi_awprot(d_axi_awprot),
 .s_axi_wvalid(m_axi_wvalid), .m_axi_wvalid(d_axi_wvalid),
 .s_axi_wready(m_axi_wready), .m_axi_wready(d_axi_wready),
 .s_axi_wdata(m_axi_wdata), .m_axi_wdata(d_axi_wdata),
 .s_axi_wstrb(m_axi_wstrb), .m_axi_wstrb(d_axi_wstrb),
 .s_axi_bvalid(m_axi_bvalid), .m_axi_bvalid(d_axi_bvalid),
 .s_axi_bready(m_axi_bready), .m_axi_bready(d_axi_bready),
 .s_axi_bresp(m_axi_bresp), .m_axi_bresp(d_axi_bresp)
);
wire  y_arvalid [0:3];
wire  y_arready [0:3];
wire [31:0] y_araddr [0:3];
wire [2:0] y_arprot [0:3];
wire  y_rvalid [0:3];
wire  y_rready [0:3];
wire [31:0] y_rdata [0:3];
wire [1:0] y_rresp [0:3];
wire  y_awvalid [0:3];
wire  y_awready [0:3];
wire [31:0] y_awaddr [0:3];
wire [2:0] y_awprot [0:3];
wire  y_wvalid [0:3];
wire  y_wready [0:3];
wire [31:0] y_wdata [0:3];
wire [3:0] y_wstrb [0:3];
wire  y_bvalid [0:3];
wire  y_bready [0:3];
wire [1:0] y_bresp [0:3];
for(genvar k=0;k<4;k=k+1) begin : device_delays
 axi4lite_delay_shim device_shim (
 .clk(clk),.rst_n(rst_n),.accept_enable(sim_accept),.delay_cycles(sim_delay),
 .s_axi_arvalid(y_arvalid[k]),.m_axi_arvalid(x_arvalid[k]),
 .s_axi_arready(y_arready[k]),.m_axi_arready(x_arready[k]),
 .s_axi_araddr(y_araddr[k]),.m_axi_araddr(x_araddr[k]),
 .s_axi_arprot(y_arprot[k]),.m_axi_arprot(x_arprot[k]),
 .s_axi_rvalid(y_rvalid[k]),.m_axi_rvalid(x_rvalid[k]),
 .s_axi_rready(y_rready[k]),.m_axi_rready(x_rready[k]),
 .s_axi_rdata(y_rdata[k]),.m_axi_rdata(x_rdata[k]),
 .s_axi_rresp(y_rresp[k]),.m_axi_rresp(x_rresp[k]),
 .s_axi_awvalid(y_awvalid[k]),.m_axi_awvalid(x_awvalid[k]),
 .s_axi_awready(y_awready[k]),.m_axi_awready(x_awready[k]),
 .s_axi_awaddr(y_awaddr[k]),.m_axi_awaddr(x_awaddr[k]),
 .s_axi_awprot(y_awprot[k]),.m_axi_awprot(x_awprot[k]),
 .s_axi_wvalid(y_wvalid[k]),.m_axi_wvalid(x_wvalid[k]),
 .s_axi_wready(y_wready[k]),.m_axi_wready(x_wready[k]),
 .s_axi_wdata(y_wdata[k]),.m_axi_wdata(x_wdata[k]),
 .s_axi_wstrb(y_wstrb[k]),.m_axi_wstrb(x_wstrb[k]),
 .s_axi_bvalid(y_bvalid[k]),.m_axi_bvalid(x_bvalid[k]),
 .s_axi_bready(y_bready[k]),.m_axi_bready(x_bready[k]),
 .s_axi_bresp(y_bresp[k]),.m_axi_bresp(x_bresp[k])
 );
end
ysyx_axi4lite_xbar #(.SRAM_BYTES(SRAM_BYTES)) xbar (
    .clk(clk), .rst_n(rst_n),
    .s_axi_arvalid(d_axi_arvalid),
    .s_axi_arready(d_axi_arready),
    .s_axi_araddr(d_axi_araddr),
    .s_axi_arprot(d_axi_arprot),
    .s_axi_rvalid(d_axi_rvalid),
    .s_axi_rready(d_axi_rready),
    .s_axi_rdata(d_axi_rdata),
    .s_axi_rresp(d_axi_rresp),
    .s_axi_awvalid(d_axi_awvalid),
    .s_axi_awready(d_axi_awready),
    .s_axi_awaddr(d_axi_awaddr),
    .s_axi_awprot(d_axi_awprot),
    .s_axi_wvalid(d_axi_wvalid),
    .s_axi_wready(d_axi_wready),
    .s_axi_wdata(d_axi_wdata),
    .s_axi_wstrb(d_axi_wstrb),
    .s_axi_bvalid(d_axi_bvalid),
    .s_axi_bready(d_axi_bready),
    .s_axi_bresp(d_axi_bresp),
    .m_axi_arvalid(y_arvalid),
    .m_axi_arready(y_arready),
    .m_axi_araddr(y_araddr),
    .m_axi_arprot(y_arprot),
    .m_axi_rvalid(y_rvalid),
    .m_axi_rready(y_rready),
    .m_axi_rdata(y_rdata),
    .m_axi_rresp(y_rresp),
    .m_axi_awvalid(y_awvalid),
    .m_axi_awready(y_awready),
    .m_axi_awaddr(y_awaddr),
    .m_axi_awprot(y_awprot),
    .m_axi_wvalid(y_wvalid),
    .m_axi_wready(y_wready),
    .m_axi_wdata(y_wdata),
    .m_axi_wstrb(y_wstrb),
    .m_axi_bvalid(y_bvalid),
    .m_axi_bready(y_bready),
    .m_axi_bresp(y_bresp)
);
ysyx_axi4lite_sram #(.SRAM_BYTES(SRAM_BYTES)) sram (
    .clk(clk), .rst_n(rst_n),
    .s_axi_arvalid(x_arvalid[0]),
    .s_axi_arready(x_arready[0]),
    .s_axi_araddr(x_araddr[0]),
    .s_axi_arprot(x_arprot[0]),
    .s_axi_rvalid(x_rvalid[0]),
    .s_axi_rready(x_rready[0]),
    .s_axi_rdata(x_rdata[0]),
    .s_axi_rresp(x_rresp[0]),
    .s_axi_awvalid(x_awvalid[0]),
    .s_axi_awready(x_awready[0]),
    .s_axi_awaddr(x_awaddr[0]),
    .s_axi_awprot(x_awprot[0]),
    .s_axi_wvalid(x_wvalid[0]),
    .s_axi_wready(x_wready[0]),
    .s_axi_wdata(x_wdata[0]),
    .s_axi_wstrb(x_wstrb[0]),
    .s_axi_bvalid(x_bvalid[0]),
    .s_axi_bready(x_bready[0]),
    .s_axi_bresp(x_bresp[0])
);
ysyx_axi4lite_uart uart (
    .clk(clk), .rst_n(rst_n),
    .s_axi_arvalid(x_arvalid[1]),
    .s_axi_arready(x_arready[1]),
    .s_axi_araddr(x_araddr[1]),
    .s_axi_arprot(x_arprot[1]),
    .s_axi_rvalid(x_rvalid[1]),
    .s_axi_rready(x_rready[1]),
    .s_axi_rdata(x_rdata[1]),
    .s_axi_rresp(x_rresp[1]),
    .s_axi_awvalid(x_awvalid[1]),
    .s_axi_awready(x_awready[1]),
    .s_axi_awaddr(x_awaddr[1]),
    .s_axi_awprot(x_awprot[1]),
    .s_axi_wvalid(x_wvalid[1]),
    .s_axi_wready(x_wready[1]),
    .s_axi_wdata(x_wdata[1]),
    .s_axi_wstrb(x_wstrb[1]),
    .s_axi_bvalid(x_bvalid[1]),
    .s_axi_bready(x_bready[1]),
    .s_axi_bresp(x_bresp[1]),
    .tx_valid(tx_valid), .tx_data(tx_data)
);
ysyx_axi4lite_clint clint (
    .clk(clk), .rst_n(rst_n),
    .s_axi_arvalid(x_arvalid[2]),
    .s_axi_arready(x_arready[2]),
    .s_axi_araddr(x_araddr[2]),
    .s_axi_arprot(x_arprot[2]),
    .s_axi_rvalid(x_rvalid[2]),
    .s_axi_rready(x_rready[2]),
    .s_axi_rdata(x_rdata[2]),
    .s_axi_rresp(x_rresp[2]),
    .s_axi_awvalid(x_awvalid[2]),
    .s_axi_awready(x_awready[2]),
    .s_axi_awaddr(x_awaddr[2]),
    .s_axi_awprot(x_awprot[2]),
    .s_axi_wvalid(x_wvalid[2]),
    .s_axi_wready(x_wready[2]),
    .s_axi_wdata(x_wdata[2]),
    .s_axi_wstrb(x_wstrb[2]),
    .s_axi_bvalid(x_bvalid[2]),
    .s_axi_bready(x_bready[2]),
    .s_axi_bresp(x_bresp[2])
);
ysyx_axi4lite_decerr decerr (
    .clk(clk), .rst_n(rst_n),
    .s_axi_arvalid(x_arvalid[3]),
    .s_axi_arready(x_arready[3]),
    .s_axi_araddr(x_araddr[3]),
    .s_axi_arprot(x_arprot[3]),
    .s_axi_rvalid(x_rvalid[3]),
    .s_axi_rready(x_rready[3]),
    .s_axi_rdata(x_rdata[3]),
    .s_axi_rresp(x_rresp[3]),
    .s_axi_awvalid(x_awvalid[3]),
    .s_axi_awready(x_awready[3]),
    .s_axi_awaddr(x_awaddr[3]),
    .s_axi_awprot(x_awprot[3]),
    .s_axi_wvalid(x_wvalid[3]),
    .s_axi_wready(x_wready[3]),
    .s_axi_wdata(x_wdata[3]),
    .s_axi_wstrb(x_wstrb[3]),
    .s_axi_bvalid(x_bvalid[3]),
    .s_axi_bready(x_bready[3]),
    .s_axi_bresp(x_bresp[3])
);
assign tap_sram_effect = sram.wr_en && sram.write_ok && (|sram.wr_strb);
for(genvar i=0;i<4;i=i+1) begin : observe
    assign monitor_ar[i] = x_arvalid[i] && x_arready[i];
    assign monitor_aw[i] = x_awvalid[i] && x_awready[i];
    assign monitor_w[i] = x_wvalid[i] && x_wready[i];
    assign monitor_r[i] = x_rvalid[i] && x_rready[i];
    assign monitor_b[i] = x_bvalid[i] && x_bready[i];
    assign monitor_rresp[i*2 +: 2] = x_rresp[i];
    assign monitor_bresp[i*2 +: 2] = x_bresp[i];
    assign tap_araddr[i] = x_araddr[i];
    assign tap_arprot[i] = x_arprot[i];
    assign tap_awaddr[i] = x_awaddr[i];
    assign tap_awprot[i] = x_awprot[i];
    assign tap_wdata[i] = x_wdata[i];
    assign tap_wstrb[i] = x_wstrb[i];
    assign tap_rdata[i] = x_rdata[i];
end
endmodule
`default_nettype wire
