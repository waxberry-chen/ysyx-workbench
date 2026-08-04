//==============================================================================
// Generic RTL Primitive Library
//
// This file provides a set of reusable RTL building blocks for ASIC design.
// The purpose of this library is to abstract common hardware primitives from
// functional RTL logic, improving design consistency, maintainability, and
// portability across different technology processes.
//
// Naming convention:
//   dff   : Basic D flip-flop
//   l     : Load enable / clock enable
//   r     : Reset function (typically reset to 0)
//   s     : Set function (typically set to 1)
//   c     : Clear function
//   parity: Data register with parity generation/checking support
//
// Examples:
//   ysyx_gnrl_dff       : D flip-flop
//   ysyx_gnrl_dffr      : D flip-flop with reset
//   ysyx_gnrl_dfflr     : D flip-flop with load enable and reset
//   ysyx_gnrl_sync      : Multi-stage synchronizer for CDC protection
//   ysyx_gnrl_data_mux       : Data mux
//
// These generic cells can be mapped or replaced by technology-specific
// implementations during synthesis, allowing easier migration between
// different ASIC libraries.
//==============================================================================

`include "./vsrc/gnrl/ysyx_global.sv"
// 0 delay wire
module ysyx_gnrl_0dffl # (
  parameter DW = 32
) (
  input               lden,
  input      [DW-1:0] dnxt,
  output     [DW-1:0] qout,
  input               clk
);
assign qout = dnxt;
endmodule

// dff with reset to 0
module ysyx_gnrl_dffr # (
  parameter DW   = 32
) (
  input      [DW-1:0] dnxt,
  output     [DW-1:0] qout,
  input               clk,
  input               rst_n
);
reg [DW-1:0] qout_r;
always @(posedge clk or negedge rst_n)
begin : DFF_PROC
  if (rst_n == 1'b0)
    qout_r <= {DW{1'b0}};
  else
    qout_r <= dnxt;
end
assign qout = qout_r[DW-1:0];
endmodule

module ysyx_gnrl_dffl # (
  parameter DW   = 32
) (
  input               lden,
  input      [DW-1:0] dnxt,
  output     [DW-1:0] qout,
  input               clk,
  input               rst_n
);
reg [DW-1:0] qout_r;
always @(posedge clk or negedge rst_n)
begin : DFF_PROC
  if (rst_n == 1'b0)
    qout_r <= {DW{1'b0}};
  else if (lden == 1'b1)
    qout_r <= dnxt;
end
assign qout = qout_r[DW-1:0];
endmodule

// dff with enable and reset to 0
module ysyx_gnrl_dfflr # (
  parameter DW   = 32
) (
  input               lden,
  input      [DW-1:0] dnxt,
  output     [DW-1:0] qout,
  input               clk,
  input               rst_n
);
reg [DW-1:0] qout_r;
always @(posedge clk or negedge rst_n)
begin : DFF_PROC
  if (rst_n == 1'b0)
    qout_r <= {DW{1'b0}};
  else if (lden == 1'b1)
    qout_r <= dnxt;
end
assign qout = qout_r[DW-1:0];
endmodule

// dff with enable and reset to fix value
module ysyx_gnrl_dffrs # (
  parameter DW   = 32
, parameter [DW-1:0]  RST  = {DW{1'b1}}
) (
  input      [DW-1:0] dnxt,
  output     [DW-1:0] qout,
  input               clk,
  input               rst_n
);
reg [DW-1:0] qout_r;
always @(posedge clk or negedge rst_n)
begin : DFF_PROC
  if (rst_n == 1'b0)
    qout_r <= RST;
  else
    qout_r <= dnxt;
end
assign qout = qout_r[DW-1:0];
endmodule

// dff with enable and reset to fix value
module ysyx_gnrl_dfflrs # (
  parameter DW   = 32
, parameter [DW-1:0]  RST  = {DW{1'b1}}
) (
  input               lden,
  input      [DW-1:0] dnxt,
  output     [DW-1:0] qout,
  input               clk,
  input               rst_n
);
reg [DW-1:0] qout_r;
always @(posedge clk or negedge rst_n)
begin : DFF_PROC
  if (rst_n == 1'b0)
    qout_r <= RST;
  else if (lden == 1'b1)
    qout_r <= dnxt;
end
assign qout = qout_r[DW-1:0];
endmodule

module ysyx_gnrl_dfflrc # (
  parameter DW   = 32
) (
  input               clr,
  input               lden,
  input      [DW-1:0] dnxt,
  output     [DW-1:0] qout,
  input               clk,
  input               rst_n
);
reg [DW-1:0] qout_r;
always @(posedge clk or negedge rst_n)
begin : DFF_PROC
  if (rst_n == 1'b0)
    qout_r <= {DW{1'b0}};
  else if (clr == 1'b1)
    qout_r <= {DW{1'b0}};
  else if (lden == 1'b1)
    qout_r <= dnxt;
end
assign qout = qout_r[DW-1:0];
endmodule

// odd even check
module ysyx_gnrl_parity_dfflrs # (
  parameter DW   = 32
, parameter [DW-1:0]  RST  = {DW{1'b1}}
) (
  output              error,
  input               lden,
  input      [DW-1:0] dnxt,
  output     [DW-1:0] qout,
  input               clk,
  input               rst_n
);
localparam [0:0]    PAR_RESET   = (^RST) & 1;
reg [DW:0] qout_r;
always @(posedge clk or negedge rst_n)
begin : DFF_PROC
  if (rst_n == 1'b0)
    qout_r <= {PAR_RESET, RST};
  else if (lden == 1'b1)
    qout_r <= {^dnxt, dnxt};
end
assign qout = qout_r[DW-1:0];
assign error = qout_r[DW] != (^qout);
endmodule

module ysyx_gnrl_parity_dfflr # (
  parameter DW   = 32
) (
  output              error,
  input               lden,
  input      [DW-1:0] dnxt,
  output     [DW-1:0] qout,
  input               clk,
  input               rst_n
);
reg [DW:0] qout_r;
always @(posedge clk or negedge rst_n)
begin : DFF_PROC
  if (rst_n == 1'b0)
    qout_r <= {(DW+1){1'b0}};
  else if (lden == 1'b1)
    qout_r <= {^dnxt, dnxt};
end
assign qout = qout_r[DW-1:0];
assign error = qout_r[DW] != (^qout);
endmodule

// data mux, '**n' = power of n
module ysyx_gnrl_data_mux # (
  parameter DW = 8,
  parameter N  = 2,
  parameter SW = N<=1 ? 1 : N<=2**0 ? 0 : N<=2**1 ? 1 : N<=2**2 ? 2 : N<=2**3 ? 3 : N<=2**4 ? 4 : N<=2**5 ? 5 : N<=2**6 ? 6 : N<=2**7 ? 7 : N<=2**8 ? 8 : N<=2**9 ? 9 : N<=2**10 ? 10 : N<=2**11 ? 11 : N<=2**12 ? 12 : N<=2**13 ? 13 : N<=2**14 ? 14 : N<=2**15 ? 15 : N<=2**16 ? 16 : N<=2**17 ? 17 : N<=2**18 ? 18 : N<=2**19 ? 19 : N<=2**20 ? 20 : N<=2**21 ? 21 : N<=2**22 ? 22 : N<=2**23 ? 23 : N<=2**24 ? 24 : N<=2**25 ? 25 : N<=2**26 ? 26 : N<=2**27 ? 27 : N<=2**28 ? 28 : N<=2**29 ? 29 : N<=2**30 ? 30 : N<=2**31 ? 31 : 32
)(
  output   [DW-1:0] out_data,
  input  [N*DW-1:0] in_data,
  input    [SW-1:0] sel
);
  wire [DW-1:0] in_data_xy [N-1:0];
  wire  [N-1:0] in_data_yx [DW-1:0];
  wire  [N-1:0] in_data_mask;
  genvar gvi, gvj;
  generate
  for (gvi=0; gvi<N; gvi=gvi+1) begin: GEN_in_data_xy
    assign in_data_xy[gvi] = in_data[gvi*DW +: DW];   // indexed part-select
    assign in_data_mask[gvi] = (gvi[SW-1:0] == sel);
    for (gvj=0; gvj<DW; gvj=gvj+1) begin: GEN_in_data_yx
      assign in_data_yx[gvj][gvi] = in_data_xy[gvi][gvj];
    end 
  end 
  for (gvi=0; gvi<DW; gvi=gvi+1) begin: GEN_out_data
    assign out_data[gvi] = |(in_data_mask & in_data_yx[gvi]);
  end 
  endgenerate
endmodule