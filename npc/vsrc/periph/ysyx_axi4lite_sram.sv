
module ysyx_axi4lite_sram #(parameter logic [31:0] SRAM_BYTES = 32'h00100000) (
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

localparam logic [32:0] SRAM_END = 33'h080000000 + {1'b0, SRAM_BYTES};
localparam bit CONFIG_VALID = SRAM_BYTES != 0 && SRAM_BYTES[1:0] == 0 &&
                              SRAM_END <= 33'h100000000 && SRAM_END <= 33'h0a0000048;
// Keep invalid configurations cheap to elaborate so the intended guard fires.
localparam integer WORDS = CONFIG_VALID ? SRAM_BYTES / 4 : 1;
localparam integer INDEX_BITS = WORDS > 1 ? $clog2(WORDS) : 1;
// Simulation preload/debug access only. No reset or implicit initialization:
// the host initializes required words before execution, while reset is held.
reg [31:0] mem [0:WORDS-1] /* verilator public_flat_rw */;
wire [31:0] rd_offset = rd_addr - 32'h80000000;
wire [31:0] wr_offset = wr_addr - 32'h80000000;
wire [INDEX_BITS-1:0] rd_index = INDEX_BITS'(rd_offset >> 2);
wire [INDEX_BITS-1:0] wr_index = INDEX_BITS'(wr_offset >> 2);
wire read_ok = rd_addr[1:0] == 0 && rd_addr >= 32'h80000000 && {1'b0,rd_addr} < SRAM_END;
wire write_ok = wr_addr[1:0] == 0 && wr_addr >= 32'h80000000 && {1'b0,wr_addr} < SRAM_END && !wr_prot[2];
wire unused_inputs = ^{rd_en,rd_prot,wr_prot[1:0]};
assign rd_data = read_ok ? mem[rd_index] : 32'b0;
assign rd_resp = read_ok ? 2'b00 : 2'b10;
assign wr_resp = write_ok ? 2'b00 : 2'b10;
// With the frontend response register this is a synchronous AXI read.
// Memory writes have no reset assignment, preserving contents across reset.
always @(posedge clk) begin
    if (wr_en && write_ok)
        for (integer lane=0; lane<4; lane=lane+1)
            if (wr_strb[lane]) mem[wr_index][lane*8 +: 8] <= wr_data[lane*8 +: 8];
end
initial begin
    if (!CONFIG_VALID)
        $fatal(1, "invalid SRAM_BYTES: positive aligned capacity without MMIO overlap required");
end
`ifndef SYNTHESIS
a06_read_error_zero: assert property (@(posedge clk) disable iff (!rst_n)
    s_axi_rvalid && s_axi_rresp != 0 |-> s_axi_rdata == 0);
a07_index_in_range: assert property (@(posedge clk) disable iff (!rst_n)
    wr_en && write_ok |-> 32'(wr_index) < WORDS);
`endif

endmodule

