`timescale 1ns/1ps
`default_nettype none

module ysyx_lsu_tb;

reg         clk = 1'b0;
reg         rst_n = 1'b0;
reg         req_valid = 1'b0;
wire        req_ready;
reg         req_write = 1'b0;
reg  [31:0] req_addr = 32'b0;
reg  [2:0]  req_type = 3'b0;
reg  [31:0] req_wdata = 32'b0;
wire        rsp_valid;
reg         rsp_ready = 1'b0;
wire [31:0] rsp_rdata;
wire        dmem_req_valid;
reg         dmem_req_ready = 1'b0;
wire        dmem_req_write;
wire [31:0] dmem_req_addr;
wire [1:0]  dmem_req_size;
wire [31:0] dmem_req_wdata;
reg         dmem_rsp_valid = 1'b0;
wire        dmem_rsp_ready;
reg  [31:0] dmem_rsp_data = 32'b0;

always #5 clk = ~clk;

ysyx_lsu dut (
    .clk         (clk),
    .rst_n       (rst_n),
    .req_valid   (req_valid),
    .req_ready   (req_ready),
    .req_write   (req_write),
    .req_addr    (req_addr),
    .req_type    (req_type),
    .req_wdata   (req_wdata),
    .rsp_valid   (rsp_valid),
    .rsp_ready   (rsp_ready),
    .rsp_rdata   (rsp_rdata),
    .dmem_req_valid(dmem_req_valid),
    .dmem_req_ready(dmem_req_ready),
    .dmem_req_write(dmem_req_write),
    .dmem_req_addr (dmem_req_addr),
    .dmem_req_size (dmem_req_size),
    .dmem_req_wdata(dmem_req_wdata),
    .dmem_rsp_valid(dmem_rsp_valid),
    .dmem_rsp_ready(dmem_rsp_ready),
    .dmem_rsp_data (dmem_rsp_data)
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
    check(req_ready, "LSU must accept an operation after reset");

    // Signed byte load. Hold the external request stalled for two cycles.
    req_valid = 1'b1;
    req_write = 1'b0;
    req_addr  = 32'h8000_0103;
    req_type  = 3'h0;
    req_wdata = 32'hdead_beef;
    tick;
    req_valid = 1'b0;
    check(dmem_req_valid, "load request was not presented");
    check(!dmem_req_write && dmem_req_addr == 32'h8000_0103 &&
          dmem_req_size == 2'd0 && dmem_req_wdata == 32'hdead_beef,
          "load request payload is incorrect");

    tick;
    check(dmem_req_valid && dmem_req_addr == 32'h8000_0103,
          "request changed during backpressure");
    tick;
    check(dmem_req_valid && dmem_req_addr == 32'h8000_0103,
          "request did not remain valid during backpressure");

    dmem_req_ready = 1'b1;
    tick;
    dmem_req_ready = 1'b0;
    check(!dmem_req_valid && dmem_rsp_ready,
          "LSU did not enter response-wait state");

    tick;
    tick;
    dmem_rsp_data  = 32'h0000_0080;
    dmem_rsp_valid = 1'b1;
    tick;
    dmem_rsp_valid = 1'b0;
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
    check(!rsp_valid && req_ready,
          "LSU did not return to idle after response handshake");

    // Word store checks that the second operation is accepted only after the
    // first completes and that the captured write payload reaches memory.
    req_valid = 1'b1;
    req_write = 1'b1;
    req_addr  = 32'h8000_0200;
    req_type  = 3'h2;
    req_wdata = 32'h1234_5678;
    tick;
    req_valid = 1'b0;
    check(dmem_req_valid && dmem_req_write &&
          dmem_req_addr == 32'h8000_0200 && dmem_req_size == 2'd2 &&
          dmem_req_wdata == 32'h1234_5678,
          "store request payload is incorrect");

    dmem_req_ready = 1'b1;
    tick;
    dmem_req_ready = 1'b0;
    dmem_rsp_valid = 1'b1;
    dmem_rsp_data  = 32'ha5a5_a5a5;
    tick;
    dmem_rsp_valid = 1'b0;
    check(rsp_valid && rsp_rdata == 32'b0,
          "store completion should not expose memory response data");

    rsp_ready = 1'b1;
    tick;
    check(req_ready, "LSU did not complete the store");

    $display("ysyx_lsu directed test: PASS");
    $finish;
end

endmodule

`default_nettype wire
