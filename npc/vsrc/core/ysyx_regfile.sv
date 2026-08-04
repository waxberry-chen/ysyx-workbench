module ysyx_regfile (
        input               clk,
        input   [4 : 0]     rf_rs1, rf_rs2, rf_rd,
        input               rf_we,
        input   [31 : 0]    rf_wd,

        output  [31 : 0]    rf_rd0, rf_rd1
    );
    import "DPI-C" function void set_gpr_ptr(input logic [31 : 0] a []);
    reg [31 : 0]    reg_file    [0 : 31];

    integer i;
    initial begin
        set_gpr_ptr(reg_file);
        for(i = 0; i < 32; i = i + 1) begin
            reg_file[i] = 32'H0;
        end
    end

    always @(posedge clk) begin
        if(rf_we && rf_rd != 5'H0) begin
            reg_file[rf_rd] <= rf_wd;
        end
    end

    assign rf_rd0 = reg_file[rf_rs1];
    assign rf_rd1 = reg_file[rf_rs2];

endmodule