`include "ysyx_25030087_defs.v"
module ysyx_25030087_IDU(
    input   [`ysyx_25030087_CPU_WIDTH-1:0]      inst,

    output  reg [`ysyx_25030087_REG_ADDR_WIDTH-1:0] operand_rs1,
    output  reg [`ysyx_25030087_REG_ADDR_WIDTH-1:0] operand_rs2,
    output  reg [`ysyx_25030087_REG_ADDR_WIDTH-1:0] operand_rd,
    output  reg [31:0]                              immi_sext,
    output  reg                                     reg_w_en,
    output  reg                                     imm_en
);

    wire [6:0] op_code = inst[6:0];
    wire [2:0] funct3 = inst[14:12];
    wire [31:0] immi = {{20{inst[31]}}, inst[31:20]};
    wire [`ysyx_25030087_REG_ADDR_WIDTH-1:0] rs1 = inst[19:15];
    wire [`ysyx_25030087_REG_ADDR_WIDTH-1:0] rs2 = inst[24:20];
    wire [`ysyx_25030087_REG_ADDR_WIDTH-1:0] rd  = inst[11:7];

    always @(*) begin
        case(op_code)
            7'b0011011: begin
                if(funct3 == 3'b000)begin
                    operand_rs1 = rs1;
                    operand_rs2 = rs2;
                    immi_sext   = immi;
                    operand_rd  = rd;
                    reg_w_en    = 1'b1;
                    imm_en      = 1'b1;
                end
            end
            default: begin
                operand_rs1 = 5'b00000;
                operand_rs2 = 5'b00000;
                immi_sext   = 32'h00000000;
                operand_rd  = 5'b00000;
                reg_w_en    = 1'b0;
                imm_en      = 1'b0;
            end
        endcase
    end

endmodule
