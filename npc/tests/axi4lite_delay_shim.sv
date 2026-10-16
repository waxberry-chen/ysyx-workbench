
module axi_delay_channel #(parameter integer WIDTH=32) (
 input wire clk, rst_n, accept_enable,
 input wire [7:0] delay_cycles,
 input wire in_valid, output wire in_ready, input wire [WIDTH-1:0] in_data,
 output wire out_valid, input wire out_ready, output wire [WIDTH-1:0] out_data
);
 reg full;
 reg [7:0] remaining;
 reg [WIDTH-1:0] payload;
 assign in_ready = rst_n && !full && accept_enable;
 assign out_valid = rst_n && full && remaining == 0;
 assign out_data = payload;
 always @(posedge clk or negedge rst_n) begin
   if (!rst_n) begin full<=0; remaining<=0; payload<=0; end
   else if (in_valid && in_ready) begin full<=1; payload<=in_data; remaining<=delay_cycles; end
   else if (full) begin
     if (remaining != 0) remaining <= remaining-1'b1;
     else if (out_ready) full<=0;
   end
 end
 assert property (@(posedge clk) disable iff (!rst_n)
   out_valid && !out_ready |=> out_valid && $stable(out_data));
endmodule
// Simulation-only five independent registered channels, no hidden device behavior.
module axi4lite_delay_shim (
 input wire clk, rst_n,
 input wire [4:0] accept_enable,
 input wire [7:0] delay_cycles [0:4],
 input wire  s_axi_arvalid,
 output wire  s_axi_arready,
 input wire [31:0] s_axi_araddr,
 input wire [2:0] s_axi_arprot,
 output wire  s_axi_rvalid,
 input wire  s_axi_rready,
 output wire [31:0] s_axi_rdata,
 output wire [1:0] s_axi_rresp,
 input wire  s_axi_awvalid,
 output wire  s_axi_awready,
 input wire [31:0] s_axi_awaddr,
 input wire [2:0] s_axi_awprot,
 input wire  s_axi_wvalid,
 output wire  s_axi_wready,
 input wire [31:0] s_axi_wdata,
 input wire [3:0] s_axi_wstrb,
 output wire  s_axi_bvalid,
 input wire  s_axi_bready,
 output wire [1:0] s_axi_bresp,
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
 axi_delay_channel #(.WIDTH(35)) ar (
 .clk(clk), .rst_n(rst_n), .accept_enable(accept_enable[0]), .delay_cycles(delay_cycles[0]),
 .in_valid(s_axi_arvalid), .in_ready(s_axi_arready), .in_data({s_axi_arprot, s_axi_araddr}),
 .out_valid(m_axi_arvalid), .out_ready(m_axi_arready), .out_data({m_axi_arprot, m_axi_araddr})
 );
 axi_delay_channel #(.WIDTH(35)) aw (
 .clk(clk), .rst_n(rst_n), .accept_enable(accept_enable[1]), .delay_cycles(delay_cycles[1]),
 .in_valid(s_axi_awvalid), .in_ready(s_axi_awready), .in_data({s_axi_awprot, s_axi_awaddr}),
 .out_valid(m_axi_awvalid), .out_ready(m_axi_awready), .out_data({m_axi_awprot, m_axi_awaddr})
 );
 axi_delay_channel #(.WIDTH(36)) w (
 .clk(clk), .rst_n(rst_n), .accept_enable(accept_enable[2]), .delay_cycles(delay_cycles[2]),
 .in_valid(s_axi_wvalid), .in_ready(s_axi_wready), .in_data({s_axi_wstrb, s_axi_wdata}),
 .out_valid(m_axi_wvalid), .out_ready(m_axi_wready), .out_data({m_axi_wstrb, m_axi_wdata})
 );
 axi_delay_channel #(.WIDTH(34)) r (
 .clk(clk), .rst_n(rst_n), .accept_enable(accept_enable[3]), .delay_cycles(delay_cycles[3]),
 .in_valid(m_axi_rvalid), .in_ready(m_axi_rready), .in_data({m_axi_rresp, m_axi_rdata}),
 .out_valid(s_axi_rvalid), .out_ready(s_axi_rready), .out_data({s_axi_rresp, s_axi_rdata})
 );
 axi_delay_channel #(.WIDTH(2)) b (
 .clk(clk), .rst_n(rst_n), .accept_enable(accept_enable[4]), .delay_cycles(delay_cycles[4]),
 .in_valid(m_axi_bvalid), .in_ready(m_axi_bready), .in_data({m_axi_bresp}),
 .out_valid(s_axi_bvalid), .out_ready(s_axi_bready), .out_data({s_axi_bresp})
 );
endmodule

