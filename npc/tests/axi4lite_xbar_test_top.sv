
module axi4lite_xbar_test_top #(parameter logic [31:0] SRAM_BYTES = 32'h00100000) (
    input wire clk,
    input wire rst_n,
    input wire real_decerr,
    output wire  tap_arready [0:3],
    output wire  tap_awready [0:3],
    output wire  tap_wready [0:3],
    output wire  tap_rvalid [0:3],
    output wire [31:0] tap_rdata [0:3],
    output wire [1:0] tap_rresp [0:3],
    output wire  tap_bvalid [0:3],
    output wire [1:0] tap_bresp [0:3],

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
wire  x_arready [0:3];
wire  e_arready;
assign x_arready[0] = m_axi_arready[0];
assign x_arready[1] = m_axi_arready[1];
assign x_arready[2] = m_axi_arready[2];
assign x_arready[3] = real_decerr ? e_arready : m_axi_arready[3];
wire  x_rvalid [0:3];
wire  e_rvalid;
assign x_rvalid[0] = m_axi_rvalid[0];
assign x_rvalid[1] = m_axi_rvalid[1];
assign x_rvalid[2] = m_axi_rvalid[2];
assign x_rvalid[3] = real_decerr ? e_rvalid : m_axi_rvalid[3];
wire [31:0] x_rdata [0:3];
wire [31:0] e_rdata;
assign x_rdata[0] = m_axi_rdata[0];
assign x_rdata[1] = m_axi_rdata[1];
assign x_rdata[2] = m_axi_rdata[2];
assign x_rdata[3] = real_decerr ? e_rdata : m_axi_rdata[3];
wire [1:0] x_rresp [0:3];
wire [1:0] e_rresp;
assign x_rresp[0] = m_axi_rresp[0];
assign x_rresp[1] = m_axi_rresp[1];
assign x_rresp[2] = m_axi_rresp[2];
assign x_rresp[3] = real_decerr ? e_rresp : m_axi_rresp[3];
wire  x_awready [0:3];
wire  e_awready;
assign x_awready[0] = m_axi_awready[0];
assign x_awready[1] = m_axi_awready[1];
assign x_awready[2] = m_axi_awready[2];
assign x_awready[3] = real_decerr ? e_awready : m_axi_awready[3];
wire  x_wready [0:3];
wire  e_wready;
assign x_wready[0] = m_axi_wready[0];
assign x_wready[1] = m_axi_wready[1];
assign x_wready[2] = m_axi_wready[2];
assign x_wready[3] = real_decerr ? e_wready : m_axi_wready[3];
wire  x_bvalid [0:3];
wire  e_bvalid;
assign x_bvalid[0] = m_axi_bvalid[0];
assign x_bvalid[1] = m_axi_bvalid[1];
assign x_bvalid[2] = m_axi_bvalid[2];
assign x_bvalid[3] = real_decerr ? e_bvalid : m_axi_bvalid[3];
wire [1:0] x_bresp [0:3];
wire [1:0] e_bresp;
assign x_bresp[0] = m_axi_bresp[0];
assign x_bresp[1] = m_axi_bresp[1];
assign x_bresp[2] = m_axi_bresp[2];
assign x_bresp[3] = real_decerr ? e_bresp : m_axi_bresp[3];
assign tap_arready = x_arready;
assign tap_awready = x_awready;
assign tap_wready = x_wready;
assign tap_rvalid = x_rvalid;
assign tap_rdata = x_rdata;
assign tap_rresp = x_rresp;
assign tap_bvalid = x_bvalid;
assign tap_bresp = x_bresp;
ysyx_axi4lite_xbar #(.SRAM_BYTES(SRAM_BYTES)) dut (
    .clk(clk), .rst_n(rst_n),
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
    .m_axi_arvalid(m_axi_arvalid),
    .m_axi_arready(x_arready),
    .m_axi_araddr(m_axi_araddr),
    .m_axi_arprot(m_axi_arprot),
    .m_axi_rvalid(x_rvalid),
    .m_axi_rready(m_axi_rready),
    .m_axi_rdata(x_rdata),
    .m_axi_rresp(x_rresp),
    .m_axi_awvalid(m_axi_awvalid),
    .m_axi_awready(x_awready),
    .m_axi_awaddr(m_axi_awaddr),
    .m_axi_awprot(m_axi_awprot),
    .m_axi_wvalid(m_axi_wvalid),
    .m_axi_wready(x_wready),
    .m_axi_wdata(m_axi_wdata),
    .m_axi_wstrb(m_axi_wstrb),
    .m_axi_bvalid(x_bvalid),
    .m_axi_bready(m_axi_bready),
    .m_axi_bresp(x_bresp));
ysyx_axi4lite_decerr error_sink (
    .clk(clk), .rst_n(rst_n),
    .s_axi_arvalid(m_axi_arvalid[3] && real_decerr),
    .s_axi_arready(e_arready),
    .s_axi_araddr(m_axi_araddr[3]),
    .s_axi_arprot(m_axi_arprot[3]),
    .s_axi_rvalid(e_rvalid),
    .s_axi_rready(m_axi_rready[3] && real_decerr),
    .s_axi_rdata(e_rdata),
    .s_axi_rresp(e_rresp),
    .s_axi_awvalid(m_axi_awvalid[3] && real_decerr),
    .s_axi_awready(e_awready),
    .s_axi_awaddr(m_axi_awaddr[3]),
    .s_axi_awprot(m_axi_awprot[3]),
    .s_axi_wvalid(m_axi_wvalid[3] && real_decerr),
    .s_axi_wready(e_wready),
    .s_axi_wdata(m_axi_wdata[3]),
    .s_axi_wstrb(m_axi_wstrb[3]),
    .s_axi_bvalid(e_bvalid),
    .s_axi_bready(m_axi_bready[3] && real_decerr),
    .s_axi_bresp(e_bresp));
endmodule

