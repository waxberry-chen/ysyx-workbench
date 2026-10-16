module ysyx_regfile (
        input               clk,
        input               rst_n,
        input   [4 : 0]     rf_rs1, rf_rs2, rf_rd,
        input               rf_we,
        input   [31 : 0]    rf_wd,

        output  [31 : 0]    rf_rd0, rf_rd1
    );
    reg [31 : 0]    reg_file    [0 : 31];

    // Host observation only. SYNTHESIS takes precedence over the DPI switch.
`ifndef SYNTHESIS
`ifdef NPC_SIM_DPI
    import "DPI-C" function void set_gpr_ptr(input logic [31 : 0] a []);
    initial begin
        set_gpr_ptr(reg_file);
    end
`endif
`endif

    // Preserve the deterministic reset state used by NPC/DiffTest in hardware.
    // x0 has no write path; its constant storage entry also serves the DPI view.
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (integer i = 0; i < 32; i = i + 1)
                reg_file[i] <= 32'b0;
        end else if(rf_we && rf_rd != 5'H0) begin
            reg_file[rf_rd] <= rf_wd;
        end
    end

    assign rf_rd0 = (rf_rs1 == 5'd0) ? 32'b0 : reg_file[rf_rs1];
    assign rf_rd1 = (rf_rs2 == 5'd0) ? 32'b0 : reg_file[rf_rs2];

endmodule
