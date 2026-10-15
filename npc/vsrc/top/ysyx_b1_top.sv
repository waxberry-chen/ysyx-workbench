`default_nettype none
// B1 route indices: 0 SRAM, 1 UART, 2 CLINT, 3 default DECERR.
// The host may preload SRAM during initial reset and consume UART TX events;
// all running CPU transactions and device side effects are handled by RTL.
module ysyx_b1_top #(parameter logic [31:0] SRAM_BYTES = 32'h00100000) (
    input wire  clk,
    input wire  rst_n,
`ifdef B1_SIM_SHIM
    input wire [4:0] sim_accept,
    input wire [7:0] sim_delay [0:4],
`endif
    output wire [31:0] commit_pc,
    output wire [31:0] commit_inst,
    output wire  commit_valid,
    output wire  commit_is_mmio,
    output wire  commit_exception,
    output wire [31:0] commit_exception_cause,
    output wire  commit_redirect_valid,
    output wire [1:0] commit_redirect_reason,
    output wire  commit_mem_valid,
    output wire  commit_mem_write,
    output wire [31:0] commit_mem_addr,
    output wire  commit_mem_error,
    output wire [13:0] monitor_bus,
    output wire [3:0] monitor_ar, monitor_aw, monitor_w, monitor_r, monitor_b,
    output wire [7:0] monitor_rresp, monitor_bresp,
    output wire tx_valid,
    output wire [7:0] tx_data
);
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
ysyx_core_axi4lite cpu (
    .clk(clk),
    .rst_n(rst_n),
    .commit_pc(commit_pc),
    .commit_inst(commit_inst),
    .commit_valid(commit_valid),
    .commit_is_mmio(commit_is_mmio),
    .commit_exception(commit_exception),
    .commit_exception_cause(commit_exception_cause),
    .commit_redirect_valid(commit_redirect_valid),
    .commit_redirect_reason(commit_redirect_reason),
    .commit_mem_valid(commit_mem_valid),
    .commit_mem_write(commit_mem_write),
    .commit_mem_addr(commit_mem_addr),
    .commit_mem_error(commit_mem_error),
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
    .m_axi_bresp(m_axi_bresp),
    .monitor_bus(monitor_bus)
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
`ifdef B1_SIM_SHIM
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
`else
assign d_axi_arvalid = m_axi_arvalid;
assign m_axi_arready = d_axi_arready;
assign d_axi_araddr = m_axi_araddr;
assign d_axi_arprot = m_axi_arprot;
assign m_axi_rvalid = d_axi_rvalid;
assign d_axi_rready = m_axi_rready;
assign m_axi_rdata = d_axi_rdata;
assign m_axi_rresp = d_axi_rresp;
assign d_axi_awvalid = m_axi_awvalid;
assign m_axi_awready = d_axi_awready;
assign d_axi_awaddr = m_axi_awaddr;
assign d_axi_awprot = m_axi_awprot;
assign d_axi_wvalid = m_axi_wvalid;
assign m_axi_wready = d_axi_wready;
assign d_axi_wdata = m_axi_wdata;
assign d_axi_wstrb = m_axi_wstrb;
assign m_axi_bvalid = d_axi_bvalid;
assign d_axi_bready = m_axi_bready;
assign m_axi_bresp = d_axi_bresp;
`endif
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
    .m_axi_arvalid(x_arvalid),
    .m_axi_arready(x_arready),
    .m_axi_araddr(x_araddr),
    .m_axi_arprot(x_arprot),
    .m_axi_rvalid(x_rvalid),
    .m_axi_rready(x_rready),
    .m_axi_rdata(x_rdata),
    .m_axi_rresp(x_rresp),
    .m_axi_awvalid(x_awvalid),
    .m_axi_awready(x_awready),
    .m_axi_awaddr(x_awaddr),
    .m_axi_awprot(x_awprot),
    .m_axi_wvalid(x_wvalid),
    .m_axi_wready(x_wready),
    .m_axi_wdata(x_wdata),
    .m_axi_wstrb(x_wstrb),
    .m_axi_bvalid(x_bvalid),
    .m_axi_bready(x_bready),
    .m_axi_bresp(x_bresp)
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
for(genvar i=0;i<4;i=i+1) begin : observe
    assign monitor_ar[i] = x_arvalid[i] && x_arready[i];
    assign monitor_aw[i] = x_awvalid[i] && x_awready[i];
    assign monitor_w[i] = x_wvalid[i] && x_wready[i];
    assign monitor_r[i] = x_rvalid[i] && x_rready[i];
    assign monitor_b[i] = x_bvalid[i] && x_bready[i];
    assign monitor_rresp[i*2 +: 2] = x_rresp[i];
    assign monitor_bresp[i*2 +: 2] = x_bresp[i];
end
endmodule
`default_nettype wire
