
// Preserve the Core's two adapters; export the arbiter's single master port.
// monitor_bus bits [0:13]: IF ARV/ARR/RV/RR, LSU ARV/ARR/RV/RR,
// LSU AWV/AWR/WV/WR/BV/BR. These are passive harness observations.
module ysyx_core_axi4 #(parameter PC_RST = 32'h20000000,
    parameter BPU_MODE = 2, parameter BPU_INDEX_BITS = 7) (
    output [3:0] m_axi_arid, m_axi_awid,
    output [7:0] m_axi_arlen, m_axi_awlen,
    output [1:0] m_axi_arburst, m_axi_awburst,
    output m_axi_wlast,
    input [3:0] m_axi_rid, m_axi_bid,
    input m_axi_rlast,
    input wire  clk,
    input wire  rst_n,
    input wire  timer_irq,
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
wire  ifu_axi_arvalid;
wire  ifu_axi_arready;
wire [31:0] ifu_axi_araddr;
wire [2:0] ifu_axi_arprot;
wire [2:0] ifu_axi_arsize;
wire  ifu_axi_rvalid;
wire  ifu_axi_rready;
wire [31:0] ifu_axi_rdata;
wire [1:0] ifu_axi_rresp;
wire  lsu_axi_awvalid;
wire  lsu_axi_awready;
wire [31:0] lsu_axi_awaddr;
wire [2:0] lsu_axi_awprot;
wire [2:0] lsu_axi_awsize;
wire  lsu_axi_wvalid;
wire  lsu_axi_wready;
wire [31:0] lsu_axi_wdata;
wire [3:0] lsu_axi_wstrb;
wire  lsu_axi_bvalid;
wire  lsu_axi_bready;
wire [1:0] lsu_axi_bresp;
wire  lsu_axi_arvalid;
wire  lsu_axi_arready;
wire [31:0] lsu_axi_araddr;
wire [2:0] lsu_axi_arprot;
wire [2:0] lsu_axi_arsize;
wire  lsu_axi_rvalid;
wire  lsu_axi_rready;
wire [31:0] lsu_axi_rdata;
wire [1:0] lsu_axi_rresp;
assign monitor_bus = {lsu_axi_bready, lsu_axi_bvalid, lsu_axi_wready, lsu_axi_wvalid, lsu_axi_awready, lsu_axi_awvalid, lsu_axi_rready, lsu_axi_rvalid, lsu_axi_arready, lsu_axi_arvalid, ifu_axi_rready, ifu_axi_rvalid, ifu_axi_arready, ifu_axi_arvalid};
ysyx_core #(.PC_RST(PC_RST), .BPU_MODE(BPU_MODE), .BPU_INDEX_BITS(BPU_INDEX_BITS)) core (
    .clk(clk),
    .rst_n(rst_n),
    .timer_irq(timer_irq),
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
    .ifu_axi_arvalid(ifu_axi_arvalid),
    .ifu_axi_arready(ifu_axi_arready),
    .ifu_axi_araddr(ifu_axi_araddr),
    .ifu_axi_arprot(ifu_axi_arprot),
    .ifu_axi_arsize(ifu_axi_arsize),
    .ifu_axi_rvalid(ifu_axi_rvalid),
    .ifu_axi_rready(ifu_axi_rready),
    .ifu_axi_rdata(ifu_axi_rdata),
    .ifu_axi_rresp(ifu_axi_rresp),
    .lsu_axi_awvalid(lsu_axi_awvalid),
    .lsu_axi_awready(lsu_axi_awready),
    .lsu_axi_awaddr(lsu_axi_awaddr),
    .lsu_axi_awprot(lsu_axi_awprot),
    .lsu_axi_awsize(lsu_axi_awsize),
    .lsu_axi_wvalid(lsu_axi_wvalid),
    .lsu_axi_wready(lsu_axi_wready),
    .lsu_axi_wdata(lsu_axi_wdata),
    .lsu_axi_wstrb(lsu_axi_wstrb),
    .lsu_axi_bvalid(lsu_axi_bvalid),
    .lsu_axi_bready(lsu_axi_bready),
    .lsu_axi_bresp(lsu_axi_bresp),
    .lsu_axi_arvalid(lsu_axi_arvalid),
    .lsu_axi_arready(lsu_axi_arready),
    .lsu_axi_araddr(lsu_axi_araddr),
    .lsu_axi_arprot(lsu_axi_arprot),
    .lsu_axi_arsize(lsu_axi_arsize),
    .lsu_axi_rvalid(lsu_axi_rvalid),
    .lsu_axi_rready(lsu_axi_rready),
    .lsu_axi_rdata(lsu_axi_rdata),
    .lsu_axi_rresp(lsu_axi_rresp)
);
ysyx_axi4_arbiter arbiter (
    .m_axi_arid(m_axi_arid),
    .m_axi_awid(m_axi_awid),
    .m_axi_arlen(m_axi_arlen),
    .m_axi_awlen(m_axi_awlen),
    .m_axi_arburst(m_axi_arburst),
    .m_axi_awburst(m_axi_awburst),
    .m_axi_wlast(m_axi_wlast),
    .m_axi_rid(m_axi_rid),
    .m_axi_bid(m_axi_bid),
    .m_axi_rlast(m_axi_rlast),

    .clk(clk),
    .rst_n(rst_n),
    .ifu_axi_arvalid(ifu_axi_arvalid),
    .ifu_axi_arready(ifu_axi_arready),
    .ifu_axi_araddr(ifu_axi_araddr),
    .ifu_axi_arprot(ifu_axi_arprot),
    .ifu_axi_arsize(ifu_axi_arsize),
    .ifu_axi_rvalid(ifu_axi_rvalid),
    .ifu_axi_rready(ifu_axi_rready),
    .ifu_axi_rdata(ifu_axi_rdata),
    .ifu_axi_rresp(ifu_axi_rresp),
    .lsu_axi_awvalid(lsu_axi_awvalid),
    .lsu_axi_awready(lsu_axi_awready),
    .lsu_axi_awaddr(lsu_axi_awaddr),
    .lsu_axi_awprot(lsu_axi_awprot),
    .lsu_axi_awsize(lsu_axi_awsize),
    .lsu_axi_wvalid(lsu_axi_wvalid),
    .lsu_axi_wready(lsu_axi_wready),
    .lsu_axi_wdata(lsu_axi_wdata),
    .lsu_axi_wstrb(lsu_axi_wstrb),
    .lsu_axi_bvalid(lsu_axi_bvalid),
    .lsu_axi_bready(lsu_axi_bready),
    .lsu_axi_bresp(lsu_axi_bresp),
    .lsu_axi_arvalid(lsu_axi_arvalid),
    .lsu_axi_arready(lsu_axi_arready),
    .lsu_axi_araddr(lsu_axi_araddr),
    .lsu_axi_arprot(lsu_axi_arprot),
    .lsu_axi_arsize(lsu_axi_arsize),
    .lsu_axi_rvalid(lsu_axi_rvalid),
    .lsu_axi_rready(lsu_axi_rready),
    .lsu_axi_rdata(lsu_axi_rdata),
    .lsu_axi_rresp(lsu_axi_rresp),
    .m_axi_arvalid(m_axi_arvalid),
    .m_axi_arready(m_axi_arready),
    .m_axi_araddr(m_axi_araddr),
    .m_axi_arprot(m_axi_arprot),
    .m_axi_arsize(m_axi_arsize),
    .m_axi_rvalid(m_axi_rvalid),
    .m_axi_rready(m_axi_rready),
    .m_axi_rdata(m_axi_rdata),
    .m_axi_rresp(m_axi_rresp),
    .m_axi_awvalid(m_axi_awvalid),
    .m_axi_awready(m_axi_awready),
    .m_axi_awaddr(m_axi_awaddr),
    .m_axi_awprot(m_axi_awprot),
    .m_axi_awsize(m_axi_awsize),
    .m_axi_wvalid(m_axi_wvalid),
    .m_axi_wready(m_axi_wready),
    .m_axi_wdata(m_axi_wdata),
    .m_axi_wstrb(m_axi_wstrb),
    .m_axi_bvalid(m_axi_bvalid),
    .m_axi_bready(m_axi_bready),
    .m_axi_bresp(m_axi_bresp)
);
endmodule

