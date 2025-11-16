// ctrl signal: {funct7[5], funct7[0], funct3}, 5 bits in total. 
module ALU (
    input [32:0]        src0, 
    input [32:0]        src1,
    input [5:0]         ctrl,

    output [32:0] reg   alu_res
);

always(*) begin
    alu_res = 32'h0;

    case(ctrl)
        5'b00000:   // add
            alu_res = src0 + src1;
        5'b10000:   // sub
            alu_res = src0 - src1;
        5'b00001:   // sll
            alu_res = src0 << src1[4:0];          
        5'b00010:   // slt
            alu_res = {31'h0, $signed(src0) < $signed(src1)};
        5'b00011:   // sltu
            alu_res = {31'h0, src0 < src1};
        5'b00100:   // xor
            alu_res = src0 ^ src1;
        5'b00101:   // srl
            alu_res = src0 >> src1[4:0];
        5'b10101:   // sra
            alu_res = $signed(src0) >>> src[4:0];
        5'b00110:   // or
            alu_res = src0 | src1;
        5'b00111:   // and 
            alu_res = src0 & src1;
        default: 
            alu_res = 32'h0; 
    endcase
end

endmodule
