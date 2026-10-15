`default_nettype none
module axi4lite_redirect_test_top (
 input wire clk,rst_n,redirect_valid,
 input wire [31:0] redirect_target,
 output wire if_ctx_valid,if_ctx_error,
 output wire [31:0] if_ctx_pc,if_ctx_inst,if_ctx_pred_npc,
 output wire if_ctx_pred_taken,
 output wire tap_ifu_arvalid,tap_ifu_arready,tap_ifu_rvalid,tap_ifu_rready,
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
 output wire  m_axi_arvalid,
 input wire  m_axi_arready,
 output wire [31:0] m_axi_araddr,
 output wire [2:0] m_axi_arprot,
 input wire  m_axi_rvalid,
 output wire  m_axi_rready,
 input wire [31:0] m_axi_rdata,
 input wire [1:0] m_axi_rresp,
 output wire  m_axi_awvalid,
 input wire  m_axi_awready,
 output wire [31:0] m_axi_awaddr,
 output wire [2:0] m_axi_awprot,
 output wire  m_axi_wvalid,
 input wire  m_axi_wready,
 output wire [31:0] m_axi_wdata,
 output wire [3:0] m_axi_wstrb,
 input wire  m_axi_bvalid,
 output wire  m_axi_bready,
 input wire [1:0] m_axi_bresp
);
localparam [31:0] PC_RST=32'h80000000;
wire if_ctx_ready=1'b0;
wire        imem_req_valid;
wire        imem_req_ready;
wire [31:0] imem_req_addr;
wire        imem_rsp_valid;
wire        imem_rsp_ready;
wire [31:0] imem_rsp_data;
wire        imem_rsp_error;

wire  ifu_axi_arvalid;
wire  ifu_axi_arready;
wire [31:0] ifu_axi_araddr;
wire [2:0] ifu_axi_arprot;
wire  ifu_axi_rvalid;
wire  ifu_axi_rready;
wire [31:0] ifu_axi_rdata;
wire [1:0] ifu_axi_rresp;
ysyx_ifu #(
    .PC_RST   (PC_RST),
    .IFQ_DEPTH(2)
) u_ifu (
    .clk              (clk),
    .rst_n            (rst_n),
    .redirect_valid   (redirect_valid),
    .redirect_target  (redirect_target),
    .if_ctx_valid     (if_ctx_valid),
    .if_ctx_ready     (if_ctx_ready),
    .if_ctx_pc        (if_ctx_pc),
    .if_ctx_inst      (if_ctx_inst),
    .if_ctx_error     (if_ctx_error),
    .if_ctx_pred_taken(if_ctx_pred_taken),
    .if_ctx_pred_npc  (if_ctx_pred_npc),
    .imem_req_valid   (imem_req_valid),
    .imem_req_ready   (imem_req_ready),
    .imem_req_addr    (imem_req_addr),
    .imem_rsp_valid   (imem_rsp_valid),
    .imem_rsp_ready   (imem_rsp_ready),
    .imem_rsp_data    (imem_rsp_data),
    .imem_rsp_error   (imem_rsp_error)
);

ysyx_ifu_axi4lite_adapter u_adapter (
    .clk           (clk),
    .rst_n         (rst_n),
    .imem_req_valid(imem_req_valid),
    .imem_req_ready(imem_req_ready),
    .imem_req_addr (imem_req_addr),
    .imem_rsp_valid(imem_rsp_valid),
    .imem_rsp_ready(imem_rsp_ready),
    .imem_rsp_data (imem_rsp_data),
    .imem_rsp_error(imem_rsp_error),
    .m_axi_arvalid (ifu_axi_arvalid),
    .m_axi_arready (ifu_axi_arready),
    .m_axi_araddr  (ifu_axi_araddr),
    .m_axi_arprot  (ifu_axi_arprot),
    .m_axi_rvalid  (ifu_axi_rvalid),
    .m_axi_rready  (ifu_axi_rready),
    .m_axi_rdata   (ifu_axi_rdata),
    .m_axi_rresp   (ifu_axi_rresp)
);
ysyx_axi4lite_arbiter arbiter (.clk(clk),.rst_n(rst_n),
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
.m_axi_bresp(m_axi_bresp),
.ifu_axi_arvalid(ifu_axi_arvalid),
.ifu_axi_arready(ifu_axi_arready),
.ifu_axi_araddr(ifu_axi_araddr),
.ifu_axi_arprot(ifu_axi_arprot),
.ifu_axi_rvalid(ifu_axi_rvalid),
.ifu_axi_rready(ifu_axi_rready),
.ifu_axi_rdata(ifu_axi_rdata),
.ifu_axi_rresp(ifu_axi_rresp)
);
assign tap_ifu_arvalid=ifu_axi_arvalid;
assign tap_ifu_arready=ifu_axi_arready;
assign tap_ifu_rvalid=ifu_axi_rvalid;
assign tap_ifu_rready=ifu_axi_rready;
endmodule
`default_nettype wire
