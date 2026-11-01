// Base ALU controls retain their previous encoding; M operation codes are absent.

module ysyx_alu (
        input                   [31 : 0]        alu_src0, alu_src1,
        input                   [4 : 0]         alu_ctrl,

        output      reg         [31 : 0]        alu_res
    );

    always @(*) begin
        alu_res = 32'H0;
        case(alu_ctrl)
            5'B00000:                                                          // add
                alu_res = alu_src0 + alu_src1;
            5'B10000:                                                          // sub
                alu_res = alu_src0 - alu_src1;
            5'B00001:                                                          // sll
                alu_res = alu_src0 << alu_src1[4 : 0];
            5'B00010:                                                          // slt
                alu_res = {31'H0, $signed(alu_src0) < $signed(alu_src1)};
            5'B00011:                                                          // sltu
                alu_res = {31'H0, alu_src0 < alu_src1};
            5'B00100:                                                          // xor
                alu_res = alu_src0 ^ alu_src1;
            5'B00101:                                                          // srl
                alu_res = alu_src0 >> alu_src1[4 : 0];
            5'B10101:                                                          // sra
                alu_res = $signed(alu_src0) >>> alu_src1[4 : 0];
            5'B00110:                                                          // or
                alu_res = alu_src0 | alu_src1;
            5'B00111:                                                          // and
                alu_res = alu_src0 & alu_src1;
            5'B11000:                                                          // alu_src1
                alu_res = alu_src1;
            default: alu_res = 32'H0;
        endcase
    end

endmodule
