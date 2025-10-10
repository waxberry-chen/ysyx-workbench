`include "ysyx_25030087_defs.v"
module ysyx_25030087_top(
    input clk,
    input rst,
    input [31:0] inst,

    output [31:0] pc
);
    wire reg_w_en, imm_en_w;
    wire [`ysyx_25030087_REG_ADDR_WIDTH-1:0] rs1_w, rs2_w, rd_w;
    wire [31:0] immi_sext_w;

    ysyx_25030087_IFU IFU(
        .clk(clk),
        .rst(rst),
        .pc_o(pc)
    );

    ysyx_25030087_IDU IDU(
        .inst       (inst),
        .operand_rs1(rs1_w),
        .operand_rs2(rs2_w),
        .immi_sext  (immi_sext_w),
        .operand_rd (rd_w),
        .reg_w_en   (reg_w_en),
        .imm_en     (imm_en_w)
    );


    ysyx_25030087_EXU EXU(
        .clk        (clk),
        .rst        (rst),
        .w_en       (reg_w_en),
        .imm_en     (imm_en_w),
        .rs1_addr   (rs1_w),
        .rs2_addr   (rs2_w),
        .imm        (immi_sext_w),
        .rd_addr    (rd_w)
    );

endmodule
