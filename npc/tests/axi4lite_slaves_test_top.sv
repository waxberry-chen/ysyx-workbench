`default_nettype none
module axi4lite_slaves_test_top #(parameter logic [31:0] SRAM_BYTES = 32'h00100000) (
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
    input wire [1:0] select_slave,
    output wire tx_valid,
    output wire [7:0] tx_data
);
wire  s_axi_arready_ports [0:2];
assign s_axi_arready = select_slave < 3 ? s_axi_arready_ports[select_slave] : '0;
wire  s_axi_rvalid_ports [0:2];
assign s_axi_rvalid = select_slave < 3 ? s_axi_rvalid_ports[select_slave] : '0;
wire [31:0] s_axi_rdata_ports [0:2];
assign s_axi_rdata = select_slave < 3 ? s_axi_rdata_ports[select_slave] : '0;
wire [1:0] s_axi_rresp_ports [0:2];
assign s_axi_rresp = select_slave < 3 ? s_axi_rresp_ports[select_slave] : '0;
wire  s_axi_awready_ports [0:2];
assign s_axi_awready = select_slave < 3 ? s_axi_awready_ports[select_slave] : '0;
wire  s_axi_wready_ports [0:2];
assign s_axi_wready = select_slave < 3 ? s_axi_wready_ports[select_slave] : '0;
wire  s_axi_bvalid_ports [0:2];
assign s_axi_bvalid = select_slave < 3 ? s_axi_bvalid_ports[select_slave] : '0;
wire [1:0] s_axi_bresp_ports [0:2];
assign s_axi_bresp = select_slave < 3 ? s_axi_bresp_ports[select_slave] : '0;
ysyx_axi4lite_sram #(.SRAM_BYTES(SRAM_BYTES)) sram (
    .clk(clk),
    .rst_n(rst_n),
    .s_axi_arvalid(s_axi_arvalid && select_slave == 2'd0),
    .s_axi_arready(s_axi_arready_ports[0]),
    .s_axi_araddr(s_axi_araddr),
    .s_axi_arprot(s_axi_arprot),
    .s_axi_rvalid(s_axi_rvalid_ports[0]),
    .s_axi_rready(s_axi_rready && select_slave == 2'd0),
    .s_axi_rdata(s_axi_rdata_ports[0]),
    .s_axi_rresp(s_axi_rresp_ports[0]),
    .s_axi_awvalid(s_axi_awvalid && select_slave == 2'd0),
    .s_axi_awready(s_axi_awready_ports[0]),
    .s_axi_awaddr(s_axi_awaddr),
    .s_axi_awprot(s_axi_awprot),
    .s_axi_wvalid(s_axi_wvalid && select_slave == 2'd0),
    .s_axi_wready(s_axi_wready_ports[0]),
    .s_axi_wdata(s_axi_wdata),
    .s_axi_wstrb(s_axi_wstrb),
    .s_axi_bvalid(s_axi_bvalid_ports[0]),
    .s_axi_bready(s_axi_bready && select_slave == 2'd0),
    .s_axi_bresp(s_axi_bresp_ports[0])
);
ysyx_axi4lite_uart uart (
    .clk(clk),
    .rst_n(rst_n),
    .s_axi_arvalid(s_axi_arvalid && select_slave == 2'd1),
    .s_axi_arready(s_axi_arready_ports[1]),
    .s_axi_araddr(s_axi_araddr),
    .s_axi_arprot(s_axi_arprot),
    .s_axi_rvalid(s_axi_rvalid_ports[1]),
    .s_axi_rready(s_axi_rready && select_slave == 2'd1),
    .s_axi_rdata(s_axi_rdata_ports[1]),
    .s_axi_rresp(s_axi_rresp_ports[1]),
    .s_axi_awvalid(s_axi_awvalid && select_slave == 2'd1),
    .s_axi_awready(s_axi_awready_ports[1]),
    .s_axi_awaddr(s_axi_awaddr),
    .s_axi_awprot(s_axi_awprot),
    .s_axi_wvalid(s_axi_wvalid && select_slave == 2'd1),
    .s_axi_wready(s_axi_wready_ports[1]),
    .s_axi_wdata(s_axi_wdata),
    .s_axi_wstrb(s_axi_wstrb),
    .s_axi_bvalid(s_axi_bvalid_ports[1]),
    .s_axi_bready(s_axi_bready && select_slave == 2'd1),
    .s_axi_bresp(s_axi_bresp_ports[1]),
    .tx_valid(tx_valid),
    .tx_data(tx_data)
);
ysyx_axi4lite_clint clint (
    .clk(clk),
    .rst_n(rst_n),
    .s_axi_arvalid(s_axi_arvalid && select_slave == 2'd2),
    .s_axi_arready(s_axi_arready_ports[2]),
    .s_axi_araddr(s_axi_araddr),
    .s_axi_arprot(s_axi_arprot),
    .s_axi_rvalid(s_axi_rvalid_ports[2]),
    .s_axi_rready(s_axi_rready && select_slave == 2'd2),
    .s_axi_rdata(s_axi_rdata_ports[2]),
    .s_axi_rresp(s_axi_rresp_ports[2]),
    .s_axi_awvalid(s_axi_awvalid && select_slave == 2'd2),
    .s_axi_awready(s_axi_awready_ports[2]),
    .s_axi_awaddr(s_axi_awaddr),
    .s_axi_awprot(s_axi_awprot),
    .s_axi_wvalid(s_axi_wvalid && select_slave == 2'd2),
    .s_axi_wready(s_axi_wready_ports[2]),
    .s_axi_wdata(s_axi_wdata),
    .s_axi_wstrb(s_axi_wstrb),
    .s_axi_bvalid(s_axi_bvalid_ports[2]),
    .s_axi_bready(s_axi_bready && select_slave == 2'd2),
    .s_axi_bresp(s_axi_bresp_ports[2])
);
endmodule
`default_nettype wire
