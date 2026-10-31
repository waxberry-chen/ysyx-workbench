// Committed-history GShare. Query is combinational; nonblocking updates mean
// a simultaneous query/training edge samples the OLD history and counter.
// Train with the index carried by the instruction, never a recomputed hash.
module ysyx_gshare #(
    parameter INDEX_BITS = 7
) (
    input clk, rst_n,
    input [31:0] query_pc,
    output [INDEX_BITS-1:0] query_index,
    output query_taken,
    input train_valid,
    input [INDEX_BITS-1:0] train_index,
    input train_taken
);
reg [INDEX_BITS-1:0] ghr_q;
reg [1:0] pht [0:(1<<INDEX_BITS)-1];
assign query_index = query_pc[INDEX_BITS+1:2] ^ ghr_q;
assign query_taken = pht[query_index][1];
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) ghr_q <= '0;
    else if (train_valid)
        ghr_q <= (ghr_q << 1) | {{(INDEX_BITS-1){1'b0}},train_taken};
end
genvar entry;
generate for (entry=0; entry<(1<<INDEX_BITS); entry=entry+1) begin : g_entry
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) pht[entry] <= 2'b01;
        else if (train_valid && train_index == INDEX_BITS'(entry)) begin
        // Read current state here: another older branch may already have
        // trained this aliased entry since the retiring branch queried it.
            if (train_taken && pht[entry] != 2'b11)
                pht[entry] <= pht[entry] + 2'd1;
            else if (!train_taken && pht[entry] != 2'b00)
                pht[entry] <= pht[entry] - 2'd1;
        end
    end
end endgenerate
`ifndef SYNTHESIS
initial assert (INDEX_BITS >= 1 && INDEX_BITS <= 12);
`endif
endmodule
