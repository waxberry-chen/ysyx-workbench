`default_nettype none
module ysyx_axi4lite_clint (
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
    output wire [1:0]   s_axi_bresp
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

// Only the testbench presets this register for rollover experiments.
// Production behavior always resets to zero and advances one tick per clock.
reg [63:0] mtime_q /* verilator public_flat_rw */;
wire read_ok = !rd_prot[2] && (rd_addr == 32'ha0000048 || rd_addr == 32'ha000004c);
wire unused_inputs = ^{rd_en,rd_prot[1:0],wr_en,wr_addr,wr_prot,wr_data,wr_strb};
assign rd_data = !read_ok ? 32'b0 : (rd_addr[2] ? mtime_q[63:32] : mtime_q[31:0]);
assign rd_resp = read_ok ? 2'b00 : 2'b10;
assign wr_resp = 2'b10;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) mtime_q <= 64'b0;
    else mtime_q <= mtime_q + 64'd1;
end
`ifndef SYNTHESIS
// A10 sampling/rollover is checked by the external-cycle reference in the TB.
a06_read_error_zero: assert property (@(posedge clk) disable iff (!rst_n)
    s_axi_rvalid && s_axi_rresp != 0 |-> s_axi_rdata == 0);
`endif

endmodule
`default_nettype wire
