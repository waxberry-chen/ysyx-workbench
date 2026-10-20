// CPU subsystem: one AXI master plus CPU-local CLINT; no B1 memory devices.
module ysyx_soc_cpu #(parameter PC_RST = 32'h20000000) (
    output [3:0] m_axi_arid, m_axi_awid,
    output [7:0] m_axi_arlen, m_axi_awlen,
    output [1:0] m_axi_arburst, m_axi_awburst,
    output m_axi_wlast,
    input [3:0] m_axi_rid, m_axi_bid,
    input m_axi_rlast,
    input wire  clk,
    input wire  rst_n,
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
    output wire  m_axi_arvalid,
    input wire  m_axi_arready,
    output wire [31:0] m_axi_araddr,
    output wire [2:0] m_axi_arprot,
    output wire [2:0] m_axi_arsize,
    input wire  m_axi_rvalid,
    output wire  m_axi_rready,
    input wire [31:0] m_axi_rdata,
    input wire [1:0] m_axi_rresp,
    output wire  m_axi_awvalid,
    input wire  m_axi_awready,
    output wire [31:0] m_axi_awaddr,
    output wire [2:0] m_axi_awprot,
    output wire [2:0] m_axi_awsize,
    output wire  m_axi_wvalid,
    input wire  m_axi_wready,
    output wire [31:0] m_axi_wdata,
    output wire [3:0] m_axi_wstrb,
    input wire  m_axi_bvalid,
    output wire  m_axi_bready,
    input wire [1:0] m_axi_bresp,
    output wire [13:0] monitor_bus
);
    wire a_axi_arvalid;
    wire a_axi_arready;
    wire [31:0] a_axi_araddr;
    wire [2:0] a_axi_arsize;
    wire [2:0] a_axi_arprot;
    wire a_axi_rvalid;
    wire a_axi_rready;
    wire [31:0] a_axi_rdata;
    wire [1:0] a_axi_rresp;
    wire [3:0] a_axi_rid;
    wire a_axi_rlast;
    wire a_axi_awvalid;
    wire a_axi_awready;
    wire [31:0] a_axi_awaddr;
    wire [2:0] a_axi_awsize;
    wire [2:0] a_axi_awprot;
    wire a_axi_wvalid;
    wire a_axi_wready;
    wire [31:0] a_axi_wdata;
    wire [3:0] a_axi_wstrb;
    wire a_axi_bvalid;
    wire a_axi_bready;
    wire [1:0] a_axi_bresp;
    wire [3:0] a_axi_bid;
ysyx_core_axi4 #(.PC_RST(PC_RST)) cpu (
    .m_axi_arid(m_axi_arid),
    .m_axi_arlen(m_axi_arlen),
    .m_axi_arburst(m_axi_arburst),
    .m_axi_wlast(m_axi_wlast),
    .m_axi_rid(a_axi_rid),
    .m_axi_rlast(a_axi_rlast),
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
    .m_axi_arvalid(a_axi_arvalid),
    .m_axi_arready(a_axi_arready),
    .m_axi_araddr(a_axi_araddr),
    .m_axi_arprot(a_axi_arprot),
    .m_axi_arsize(a_axi_arsize),
    .m_axi_rvalid(a_axi_rvalid),
    .m_axi_rready(a_axi_rready),
    .m_axi_rdata(a_axi_rdata),
    .m_axi_rresp(a_axi_rresp),
    .m_axi_awvalid(a_axi_awvalid),
    .m_axi_awready(a_axi_awready),
    .m_axi_awaddr(a_axi_awaddr),
    .m_axi_awprot(a_axi_awprot),
    .m_axi_awsize(a_axi_awsize),
    .m_axi_wvalid(a_axi_wvalid),
    .m_axi_wready(a_axi_wready),
    .m_axi_wdata(a_axi_wdata),
    .m_axi_wstrb(a_axi_wstrb),
    .m_axi_bvalid(a_axi_bvalid),
    .m_axi_bready(a_axi_bready),
    .m_axi_bresp(a_axi_bresp),
    .monitor_bus(monitor_bus),
    .m_axi_awid(m_axi_awid),
    .m_axi_awlen(m_axi_awlen),
    .m_axi_awburst(m_axi_awburst),
    .m_axi_bid(a_axi_bid)
);
ysyx_axi4_router router (
    .clk(clk), .rst_n(rst_n),
    .s_axi_arvalid(a_axi_arvalid),
    .s_axi_arready(a_axi_arready),
    .s_axi_araddr(a_axi_araddr),
    .s_axi_arsize(a_axi_arsize),
    .s_axi_arprot(a_axi_arprot),
    .s_axi_rvalid(a_axi_rvalid),
    .s_axi_rready(a_axi_rready),
    .s_axi_rdata(a_axi_rdata),
    .s_axi_rresp(a_axi_rresp),
    .s_axi_rid(a_axi_rid),
    .s_axi_rlast(a_axi_rlast),
    .s_axi_awvalid(a_axi_awvalid),
    .s_axi_awready(a_axi_awready),
    .s_axi_awaddr(a_axi_awaddr),
    .s_axi_awsize(a_axi_awsize),
    .s_axi_awprot(a_axi_awprot),
    .s_axi_wvalid(a_axi_wvalid),
    .s_axi_wready(a_axi_wready),
    .s_axi_wdata(a_axi_wdata),
    .s_axi_wstrb(a_axi_wstrb),
    .s_axi_bvalid(a_axi_bvalid),
    .s_axi_bready(a_axi_bready),
    .s_axi_bresp(a_axi_bresp),
    .s_axi_bid(a_axi_bid),
    .m_axi_arvalid(m_axi_arvalid),
    .m_axi_arready(m_axi_arready),
    .m_axi_araddr(m_axi_araddr),
    .m_axi_arsize(m_axi_arsize),
    .m_axi_arprot(m_axi_arprot),
    .m_axi_rvalid(m_axi_rvalid),
    .m_axi_rready(m_axi_rready),
    .m_axi_rdata(m_axi_rdata),
    .m_axi_rresp(m_axi_rresp),
    .m_axi_rid(m_axi_rid),
    .m_axi_rlast(m_axi_rlast),
    .m_axi_awvalid(m_axi_awvalid),
    .m_axi_awready(m_axi_awready),
    .m_axi_awaddr(m_axi_awaddr),
    .m_axi_awsize(m_axi_awsize),
    .m_axi_awprot(m_axi_awprot),
    .m_axi_wvalid(m_axi_wvalid),
    .m_axi_wready(m_axi_wready),
    .m_axi_wdata(m_axi_wdata),
    .m_axi_wstrb(m_axi_wstrb),
    .m_axi_bvalid(m_axi_bvalid),
    .m_axi_bready(m_axi_bready),
    .m_axi_bresp(m_axi_bresp),
    .m_axi_bid(m_axi_bid)
);
endmodule
