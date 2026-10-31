// RV32E control-flow predecode at instruction-response acceptance.
// This is not the architectural decoder: illegal instructions still reach IDU
// and raise its normal trap. Never speculate using a faulting response.
module ysyx_predecode (
    input [31:0] pc, inst,
    input error,
    output is_branch, is_jal,
    output [31:0] target
);
wire branch_encoding = inst[6:0] == 7'h63 &&
                       (inst[14:12] == 3'd0 || inst[14:12] == 3'd1 || inst[14]);
assign is_branch = !error && branch_encoding && !inst[19] && !inst[24];
assign is_jal = !error && inst[6:0] == 7'h6f && !inst[11];
wire [31:0] b_imm = {{19{inst[31]}},inst[31],inst[7],inst[30:25],inst[11:8],1'b0};
wire [31:0] j_imm = {{11{inst[31]}},inst[31],inst[19:12],inst[20],inst[30:21],1'b0};
assign target = pc + (is_jal ? j_imm : b_imm);
endmodule
