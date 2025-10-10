`include "ysyx_25030087_defs.v"
module ysyx_25030087_EXU (
    input           clk,
    input           rst,
    input           w_en,
    input           imm_en,
    input   [`ysyx_25030087_REG_ADDR_WIDTH-1:0]   rs1_addr,
    input   [`ysyx_25030087_REG_ADDR_WIDTH-1:0]   rs2_addr,
    input   [31:0]                                imm,
    input   [`ysyx_25030087_REG_ADDR_WIDTH-1:0]   rd_addr
);
    wire [31:0] alu_a_w, alu_b_w, alu_out_w, operand2_w;
    ysyx_25030087_regfile regfile(
        .clk        (clk),
        .rst        (rst),
        .w_en       (w_en),
        .rs1_addr   (rs1_addr),
        .rs2_addr   (rs2_addr),
        .rs1_data_o (alu_a_w),
        .rs2_data_o (alu_b_w),

        .rd_addr(rd_addr),
        .rd_data(alu_out_w)
    );

    MuxKeyWithDefault #(2, 1, 32) mux_operand2(
        .key(imm_en),
        .default_out(32'h00000000),
        .lut({
            1'b0, alu_b_w,
            1'b1, imm
        }),
        .out(operand2_w)
    );

    ysyx_25030087_alu alu(
        .alu_a   (alu_a_w    ),
        .alu_b   (operand2_w ),
        .alu_out (alu_out_w  )
    );

endmodule
