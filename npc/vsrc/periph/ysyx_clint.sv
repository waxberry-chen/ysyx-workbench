// CPU-local timer, S1 subset. One request pulse per accepted routed transaction.
// Register data is sampled on that pulse, not repeatedly while R/B is stalled.
// mtimecmp/MTIP are added in S5; their reserved offsets currently return SLVERR.
module ysyx_clint (
    input clk, input rst_n,
    input req_valid, input req_write,
    input [31:0] req_addr, input [2:0] req_size,
    input [31:0] req_wdata, input [3:0] req_wstrb,
    output [31:0] rsp_data, output rsp_error
);
reg [63:0] mtime_q;
wire low_word = req_addr == 32'h0200bff8;
wire high_word = req_addr == 32'h0200bffc;
wire legal_access = (low_word || high_word) && req_size == 3'd2 &&
                    (!req_write || req_wstrb == 4'hf);
assign rsp_error = !legal_access;
assign rsp_data = !legal_access ? 32'b0 : high_word ? mtime_q[63:32] : mtime_q[31:0];
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) mtime_q <= 64'b0;
    else if (req_valid && req_write && legal_access) begin
        // A word write wins over the whole-counter tick. Preserve the other half.
        if (high_word) mtime_q[63:32] <= req_wdata;
        else mtime_q[31:0] <= req_wdata;
    end else mtime_q <= mtime_q + 64'd1;
end
endmodule
