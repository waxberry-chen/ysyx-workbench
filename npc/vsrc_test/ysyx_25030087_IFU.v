`include "ysyx_25030087_defs.v"
module ysyx_25030087_IFU(
    input           clk,
    input           rst,
    output  [`ysyx_25030087_REG_DATA_WIDTH-1:0]  pc_o
);

    reg [31:0] pc;
    always @(posedge clk) begin
        if(rst) begin
            pc <= `ysyx_25030087_REG_DATA_WIDTH'h80000000;
        end
        else begin
            pc <= pc + 32'd4;
        end
    end

    assign pc_o = pc;

endmodule;
