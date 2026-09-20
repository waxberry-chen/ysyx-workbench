`timescale 1ns/1ps
`default_nettype none

module ysyx_lsu_tb;

reg         clk = 1'b0;
reg         rst_n = 1'b0;
reg         op_valid = 1'b0;
wire        op_ready;
reg         op_write = 1'b0;
reg  [31:0] op_addr = 32'b0;
reg  [2:0]  op_type = 3'b0;
reg  [31:0] op_wdata = 32'b0;
wire        rsp_valid;
reg         rsp_ready = 1'b0;
wire [31:0] rsp_rdata;
wire        d_req_valid;
reg         d_req_ready = 1'b0;
wire        d_req_write;
wire [31:0] d_req_addr;
wire [1:0]  d_req_size;
wire [31:0] d_req_wdata;
reg         d_rsp_valid = 1'b0;
wire        d_rsp_ready;
reg  [31:0] d_rsp_data = 32'b0;

always #5 clk = ~clk;

ysyx_lsu dut (
    .clk         (clk),
    .rst_n       (rst_n),
    .op_valid    (op_valid),
    .op_ready    (op_ready),
    .op_write    (op_write),
    .op_addr     (op_addr),
    .op_type     (op_type),
    .op_wdata    (op_wdata),
    .rsp_valid   (rsp_valid),
    .rsp_ready   (rsp_ready),
    .rsp_rdata   (rsp_rdata),
    .d_req_valid (d_req_valid),
    .d_req_ready (d_req_ready),
    .d_req_write (d_req_write),
    .d_req_addr  (d_req_addr),
    .d_req_size  (d_req_size),
    .d_req_wdata (d_req_wdata),
    .d_rsp_valid (d_rsp_valid),
    .d_rsp_ready (d_rsp_ready),
    .d_rsp_data  (d_rsp_data)
);

task tick;
begin
    @(posedge clk);
    #1;
end
endtask

task check;
    input condition;
    input [8*80-1:0] message;
begin
    if (!condition) begin
        $display("LSU test failed: %0s", message);
        $fatal;
    end
end
endtask

initial begin
    tick;
    tick;
    rst_n = 1'b1;
    tick;
    check(op_ready, "LSU must accept an operation after reset");

    // Signed byte load. Hold the external request stalled for two cycles.
    op_valid = 1'b1;
    op_write = 1'b0;
    op_addr  = 32'h8000_0103;
    op_type  = 3'h0;
    op_wdata = 32'hdead_beef;
    tick;
    op_valid = 1'b0;
    check(d_req_valid, "load request was not presented");
    check(!d_req_write && d_req_addr == 32'h8000_0103 &&
          d_req_size == 2'd0 && d_req_wdata == 32'hdead_beef,
          "load request payload is incorrect");

    tick;
    check(d_req_valid && d_req_addr == 32'h8000_0103,
          "request changed during backpressure");
    tick;
    check(d_req_valid && d_req_addr == 32'h8000_0103,
          "request did not remain valid during backpressure");

    d_req_ready = 1'b1;
    tick;
    d_req_ready = 1'b0;
    check(!d_req_valid && d_rsp_ready,
          "LSU did not enter response-wait state");

    tick;
    tick;
    d_rsp_data  = 32'h0000_0080;
    d_rsp_valid = 1'b1;
    tick;
    d_rsp_valid = 1'b0;
    check(rsp_valid && rsp_rdata == 32'hffff_ff80,
          "signed byte load result is incorrect");

    // The backend is not ready: result must remain buffered and stable.
    tick;
    check(rsp_valid && rsp_rdata == 32'hffff_ff80,
          "response changed during backend backpressure");
    tick;
    check(rsp_valid && rsp_rdata == 32'hffff_ff80,
          "response did not remain valid during backend backpressure");

    rsp_ready = 1'b1;
    tick;
    rsp_ready = 1'b0;
    check(!rsp_valid && op_ready,
          "LSU did not return to idle after response handshake");

    // Word store checks that the second operation is accepted only after the
    // first completes and that the captured write payload reaches memory.
    op_valid = 1'b1;
    op_write = 1'b1;
    op_addr  = 32'h8000_0200;
    op_type  = 3'h2;
    op_wdata = 32'h1234_5678;
    tick;
    op_valid = 1'b0;
    check(d_req_valid && d_req_write &&
          d_req_addr == 32'h8000_0200 && d_req_size == 2'd2 &&
          d_req_wdata == 32'h1234_5678,
          "store request payload is incorrect");

    d_req_ready = 1'b1;
    tick;
    d_req_ready = 1'b0;
    d_rsp_valid = 1'b1;
    d_rsp_data  = 32'ha5a5_a5a5;
    tick;
    d_rsp_valid = 1'b0;
    check(rsp_valid && rsp_rdata == 32'b0,
          "store completion should not expose memory response data");

    rsp_ready = 1'b1;
    tick;
    check(op_ready, "LSU did not complete the store");

    $display("ysyx_lsu directed test: PASS");
    $finish;
end

endmodule

`default_nettype wire
