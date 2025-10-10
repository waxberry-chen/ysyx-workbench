module ysyx_25030087_alu (
    input    [31:0] alu_a,
    input    [31:0] alu_b,
    output   [31:0] alu_out
);
    reg [31:0] alu_out_r;
    always @(alu_a or alu_b) begin
        alu_out_r = alu_a + alu_b;
    end
    assign alu_out = alu_out_r;

endmodule
