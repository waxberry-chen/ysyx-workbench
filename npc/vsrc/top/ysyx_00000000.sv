// Frozen ysyxSoC CPU BlackBox ABI. Internal assertions enforce the disabled
// ChipLink/external-IRQ configuration; enabling either requires a new contract.
module ysyx_00000000 #(parameter PC_RST = 32'h20000000) (
    input clock,
    input reset,
    input io_interrupt,
    input io_master_awready,
    output io_slave_awready,
    output io_master_awvalid,
    input io_slave_awvalid,
    output [31:0] io_master_awaddr,
    input [31:0] io_slave_awaddr,
    output [3:0] io_master_awid,
    input [3:0] io_slave_awid,
    output [7:0] io_master_awlen,
    input [7:0] io_slave_awlen,
    output [2:0] io_master_awsize,
    input [2:0] io_slave_awsize,
    output [1:0] io_master_awburst,
    input [1:0] io_slave_awburst,
    input io_master_wready,
    output io_slave_wready,
    output io_master_wvalid,
    input io_slave_wvalid,
    output [31:0] io_master_wdata,
    input [31:0] io_slave_wdata,
    output [3:0] io_master_wstrb,
    input [3:0] io_slave_wstrb,
    output io_master_wlast,
    input io_slave_wlast,
    output io_master_bready,
    input io_slave_bready,
    input io_master_bvalid,
    output io_slave_bvalid,
    input [1:0] io_master_bresp,
    output [1:0] io_slave_bresp,
    input [3:0] io_master_bid,
    output [3:0] io_slave_bid,
    input io_master_arready,
    output io_slave_arready,
    output io_master_arvalid,
    input io_slave_arvalid,
    output [31:0] io_master_araddr,
    input [31:0] io_slave_araddr,
    output [3:0] io_master_arid,
    input [3:0] io_slave_arid,
    output [7:0] io_master_arlen,
    input [7:0] io_slave_arlen,
    output [2:0] io_master_arsize,
    input [2:0] io_slave_arsize,
    output [1:0] io_master_arburst,
    input [1:0] io_slave_arburst,
    output io_master_rready,
    input io_slave_rready,
    input io_master_rvalid,
    output io_slave_rvalid,
    input [1:0] io_master_rresp,
    output [1:0] io_slave_rresp,
    input [31:0] io_master_rdata,
    output [31:0] io_slave_rdata,
    input io_master_rlast,
    output io_slave_rlast,
    input [3:0] io_master_rid,
    output [3:0] io_slave_rid
);
assign io_slave_awready = '0;
assign io_slave_wready = '0;
assign io_slave_bvalid = '0;
assign io_slave_bresp = '0;
assign io_slave_bid = '0;
assign io_slave_arready = '0;
assign io_slave_rvalid = '0;
assign io_slave_rresp = '0;
assign io_slave_rdata = '0;
assign io_slave_rlast = '0;
assign io_slave_rid = '0;
    wire [2:0] unused_arprot;
    wire [2:0] unused_awprot;
ysyx_soc_cpu #(.PC_RST(PC_RST)) subsystem (
    .clk(clock), .rst_n(!reset),
    .m_axi_arid(io_master_arid),
    .m_axi_arlen(io_master_arlen),
    .m_axi_arburst(io_master_arburst),
    .m_axi_wlast(io_master_wlast),
    .m_axi_rid(io_master_rid),
    .m_axi_rlast(io_master_rlast),
    .commit_pc(),
    .commit_inst(),
    .commit_valid(),
    .commit_is_mmio(),
    .commit_exception(),
    .commit_exception_cause(),
    .commit_redirect_valid(),
    .commit_redirect_reason(),
    .commit_mem_valid(),
    .commit_mem_write(),
    .commit_mem_addr(),
    .commit_mem_error(),
    .m_axi_arvalid(io_master_arvalid),
    .m_axi_arready(io_master_arready),
    .m_axi_araddr(io_master_araddr),
    .m_axi_arprot(unused_arprot),
    .m_axi_arsize(io_master_arsize),
    .m_axi_rvalid(io_master_rvalid),
    .m_axi_rready(io_master_rready),
    .m_axi_rdata(io_master_rdata),
    .m_axi_rresp(io_master_rresp),
    .m_axi_awvalid(io_master_awvalid),
    .m_axi_awready(io_master_awready),
    .m_axi_awaddr(io_master_awaddr),
    .m_axi_awprot(unused_awprot),
    .m_axi_awsize(io_master_awsize),
    .m_axi_wvalid(io_master_wvalid),
    .m_axi_wready(io_master_wready),
    .m_axi_wdata(io_master_wdata),
    .m_axi_wstrb(io_master_wstrb),
    .m_axi_bvalid(io_master_bvalid),
    .m_axi_bready(io_master_bready),
    .m_axi_bresp(io_master_bresp),
    .monitor_bus(),
    .m_axi_awid(io_master_awid),
    .m_axi_awlen(io_master_awlen),
    .m_axi_awburst(io_master_awburst),
    .m_axi_bid(io_master_bid)
);
`ifndef SYNTHESIS
always @(posedge clock) if (!reset) begin
    assert (!io_interrupt) else $fatal(1, "External IRQ is outside M5 S1 contract");
    assert (!(io_slave_arvalid || io_slave_awvalid || io_slave_wvalid))
        else $fatal(1, "ChipLink/slave request on disabled CPU slave port");
end
`endif
endmodule
