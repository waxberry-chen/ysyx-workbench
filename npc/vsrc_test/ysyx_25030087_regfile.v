`include "ysyx_25030087_defs.v"
module ysyx_25030087_regfile (
    input clk,
    input rst,
    input w_en,
    input [`ysyx_25030087_REG_ADDR_WIDTH-1:0] rs1_addr,
    input [`ysyx_25030087_REG_ADDR_WIDTH-1:0] rs2_addr,
    output [`ysyx_25030087_REG_DATA_WIDTH-1:0] rs1_data_o,
    output [`ysyx_25030087_REG_DATA_WIDTH-1:0] rs2_data_o,
    
    input [`ysyx_25030087_REG_ADDR_WIDTH-1:0] rd_addr,
    input [`ysyx_25030087_REG_DATA_WIDTH-1:0] rd_data
);

    // Read-friendly register name
    wire [31:0] x0_zero_w = 32'b0;
    wire [31:0] x1_ra_w;
    wire [31:0] x2_sp_w;
    wire [31:0] x3_gp_w;
    wire [31:0] x4_tp_w;
    wire [31:0] x5_t0_w;
    wire [31:0] x6_t1_w;
    wire [31:0] x7_t2_w;
    wire [31:0] x8_fp_w;
    wire [31:0] x9_s1_w;
    wire [31:0] x10_a0_w;
    wire [31:0] x11_a1_w;
    wire [31:0] x12_a2_w;
    wire [31:0] x13_a3_w;
    wire [31:0] x14_a4_w;
    wire [31:0] x15_a5_w;
    wire [31:0] x16_a6_w;
    wire [31:0] x17_a7_w;
    wire [31:0] x18_s2_w;
    wire [31:0] x19_s3_w;
    wire [31:0] x20_s4_w;
    wire [31:0] x21_s5_w;
    wire [31:0] x22_s6_w;
    wire [31:0] x23_s7_w;
    wire [31:0] x24_s8_w;
    wire [31:0] x25_s9_w;
    wire [31:0] x26_s10_w;
    wire [31:0] x27_s11_w;
    wire [31:0] x28_t3_w;
    wire [31:0] x29_t4_w;
    wire [31:0] x30_t5_w;
    wire [31:0] x31_t6_w;

    // Reg instances
    Reg #(32, 32'h00000000) x0  (.clk(clk), .rst(rst), .din(rd_data), .dout(x0_zero_w   ), .wen(1'b0));
    Reg #(32, 32'h00000000) x1  (.clk(clk), .rst(rst), .din(rd_data), .dout(x1_ra_w     ), .wen(w_en & (rd_addr == 5'd1)));
    Reg #(32, 32'h00000000) x2  (.clk(clk), .rst(rst), .din(rd_data), .dout(x2_sp_w     ), .wen(w_en & (rd_addr == 5'd2)));
    Reg #(32, 32'h00000000) x3  (.clk(clk), .rst(rst), .din(rd_data), .dout(x3_gp_w     ), .wen(w_en & (rd_addr == 5'd3)));
    Reg #(32, 32'h00000000) x4  (.clk(clk), .rst(rst), .din(rd_data), .dout(x4_tp_w     ), .wen(w_en & (rd_addr == 5'd4)));
    Reg #(32, 32'h00000000) x5  (.clk(clk), .rst(rst), .din(rd_data), .dout(x5_t0_w     ), .wen(w_en & (rd_addr == 5'd5)));
    Reg #(32, 32'h00000000) x6  (.clk(clk), .rst(rst), .din(rd_data), .dout(x6_t1_w     ), .wen(w_en & (rd_addr == 5'd6)));
    Reg #(32, 32'h00000000) x7  (.clk(clk), .rst(rst), .din(rd_data), .dout(x7_t2_w     ), .wen(w_en & (rd_addr == 5'd7)));
    Reg #(32, 32'h00000000) x8  (.clk(clk), .rst(rst), .din(rd_data), .dout(x8_fp_w     ), .wen(w_en & (rd_addr == 5'd8)));
    Reg #(32, 32'h00000000) x9  (.clk(clk), .rst(rst), .din(rd_data), .dout(x9_s1_w     ), .wen(w_en & (rd_addr == 5'd9)));
    Reg #(32, 32'h00000000) x10 (.clk(clk), .rst(rst), .din(rd_data), .dout(x10_a0_w    ), .wen(w_en & (rd_addr == 5'd10)));
    Reg #(32, 32'h00000000) x11 (.clk(clk), .rst(rst), .din(rd_data), .dout(x11_a1_w    ), .wen(w_en & (rd_addr == 5'd11)));
    Reg #(32, 32'h00000000) x12 (.clk(clk), .rst(rst), .din(rd_data), .dout(x12_a2_w    ), .wen(w_en & (rd_addr == 5'd12)));
    Reg #(32, 32'h00000000) x13 (.clk(clk), .rst(rst), .din(rd_data), .dout(x13_a3_w    ), .wen(w_en & (rd_addr == 5'd13)));
    Reg #(32, 32'h00000000) x14 (.clk(clk), .rst(rst), .din(rd_data), .dout(x14_a4_w    ), .wen(w_en & (rd_addr == 5'd14)));
    Reg #(32, 32'h00000000) x15 (.clk(clk), .rst(rst), .din(rd_data), .dout(x15_a5_w    ), .wen(w_en & (rd_addr == 5'd15)));
    Reg #(32, 32'h00000000) x16 (.clk(clk), .rst(rst), .din(rd_data), .dout(x16_a6_w    ), .wen(w_en & (rd_addr == 5'd16)));
    Reg #(32, 32'h00000000) x17 (.clk(clk), .rst(rst), .din(rd_data), .dout(x17_a7_w    ), .wen(w_en & (rd_addr == 5'd17)));
    Reg #(32, 32'h00000000) x18 (.clk(clk), .rst(rst), .din(rd_data), .dout(x18_s2_w    ), .wen(w_en & (rd_addr == 5'd18)));
    Reg #(32, 32'h00000000) x19 (.clk(clk), .rst(rst), .din(rd_data), .dout(x19_s3_w    ), .wen(w_en & (rd_addr == 5'd19)));
    Reg #(32, 32'h00000000) x20 (.clk(clk), .rst(rst), .din(rd_data), .dout(x20_s4_w    ), .wen(w_en & (rd_addr == 5'd20)));
    Reg #(32, 32'h00000000) x21 (.clk(clk), .rst(rst), .din(rd_data), .dout(x21_s5_w    ), .wen(w_en & (rd_addr == 5'd21)));
    Reg #(32, 32'h00000000) x22 (.clk(clk), .rst(rst), .din(rd_data), .dout(x22_s6_w    ), .wen(w_en & (rd_addr == 5'd22)));
    Reg #(32, 32'h00000000) x23 (.clk(clk), .rst(rst), .din(rd_data), .dout(x23_s7_w    ), .wen(w_en & (rd_addr == 5'd23)));
    Reg #(32, 32'h00000000) x24 (.clk(clk), .rst(rst), .din(rd_data), .dout(x24_s8_w    ), .wen(w_en & (rd_addr == 5'd24)));
    Reg #(32, 32'h00000000) x25 (.clk(clk), .rst(rst), .din(rd_data), .dout(x25_s9_w    ), .wen(w_en & (rd_addr == 5'd25)));
    Reg #(32, 32'h00000000) x26 (.clk(clk), .rst(rst), .din(rd_data), .dout(x26_s10_w   ), .wen(w_en & (rd_addr == 5'd26)));
    Reg #(32, 32'h00000000) x27 (.clk(clk), .rst(rst), .din(rd_data), .dout(x27_s11_w   ), .wen(w_en & (rd_addr == 5'd27)));
    Reg #(32, 32'h00000000) x28 (.clk(clk), .rst(rst), .din(rd_data), .dout(x28_t3_w    ), .wen(w_en & (rd_addr == 5'd28)));
    Reg #(32, 32'h00000000) x29 (.clk(clk), .rst(rst), .din(rd_data), .dout(x29_t4_w    ), .wen(w_en & (rd_addr == 5'd29)));
    Reg #(32, 32'h00000000) x30 (.clk(clk), .rst(rst), .din(rd_data), .dout(x30_t5_w    ), .wen(w_en & (rd_addr == 5'd30)));
    Reg #(32, 32'h00000000) x31 (.clk(clk), .rst(rst), .din(rd_data), .dout(x31_t6_w    ), .wen(w_en & (rd_addr == 5'd31)));

    MuxKeyWithDefault #(32, 5, 32) rs1_data_mux(
    .key(rs1_addr),
    .default_out(32'h00000000),
    .lut({
        5'd0    ,x0_zero_w,
        5'd1    ,x1_ra_w  ,
        5'd2    ,x2_sp_w  ,
        5'd3    ,x3_gp_w  ,
        5'd4    ,x4_tp_w  ,
        5'd5    ,x5_t0_w  ,
        5'd6    ,x6_t1_w  ,
        5'd7    ,x7_t2_w  ,
        5'd8    ,x8_fp_w  ,
        5'd9    ,x9_s1_w  ,
        5'd10   ,x10_a0_w ,
        5'd11   ,x11_a1_w ,
        5'd12   ,x12_a2_w ,
        5'd13   ,x13_a3_w ,
        5'd14   ,x14_a4_w ,
        5'd15   ,x15_a5_w ,
        5'd16   ,x16_a6_w ,
        5'd17   ,x17_a7_w ,
        5'd18   ,x18_s2_w ,
        5'd19   ,x19_s3_w ,
        5'd20   ,x20_s4_w ,
        5'd21   ,x21_s5_w ,
        5'd22   ,x22_s6_w ,
        5'd23   ,x23_s7_w ,
        5'd24   ,x24_s8_w ,
        5'd25   ,x25_s9_w ,
        5'd26   ,x26_s10_w,
        5'd27   ,x27_s11_w,
        5'd28   ,x28_t3_w ,
        5'd29   ,x29_t4_w ,
        5'd30   ,x30_t5_w ,
        5'd31   ,x31_t6_w
    }),
    .out(rs1_data_o)
    );

    MuxKeyWithDefault #(32, 5, 32) rs2_data_mux(
    .key(rs2_addr),
    .default_out(32'h00000000),
    .lut({
        5'd0    ,x0_zero_w,
        5'd1    ,x1_ra_w  ,
        5'd2    ,x2_sp_w  ,
        5'd3    ,x3_gp_w  ,
        5'd4    ,x4_tp_w  ,
        5'd5    ,x5_t0_w  ,
        5'd6    ,x6_t1_w  ,
        5'd7    ,x7_t2_w  ,
        5'd8    ,x8_fp_w  ,
        5'd9    ,x9_s1_w  ,
        5'd10   ,x10_a0_w ,
        5'd11   ,x11_a1_w ,
        5'd12   ,x12_a2_w ,
        5'd13   ,x13_a3_w ,
        5'd14   ,x14_a4_w ,
        5'd15   ,x15_a5_w ,
        5'd16   ,x16_a6_w ,
        5'd17   ,x17_a7_w ,
        5'd18   ,x18_s2_w ,
        5'd19   ,x19_s3_w ,
        5'd20   ,x20_s4_w ,
        5'd21   ,x21_s5_w ,
        5'd22   ,x22_s6_w ,
        5'd23   ,x23_s7_w ,
        5'd24   ,x24_s8_w ,
        5'd25   ,x25_s9_w ,
        5'd26   ,x26_s10_w,
        5'd27   ,x27_s11_w,
        5'd28   ,x28_t3_w ,
        5'd29   ,x29_t4_w ,
        5'd30   ,x30_t5_w ,
        5'd31   ,x31_t6_w
    }),
    .out(rs2_data_o)
    );

endmodule
