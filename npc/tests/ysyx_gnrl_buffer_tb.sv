`timescale 1ns/1ps
`default_nettype none

module ysyx_gnrl_buffer_tb;

reg clk = 1'b0;
reg rst_n = 1'b0;

reg        reg_in_valid = 1'b0;
wire       reg_in_ready;
reg  [7:0] reg_in_data = 8'b0;
wire       reg_out_valid;
reg        reg_out_ready = 1'b0;
wire [7:0] reg_out_data;
reg        reg_flush = 1'b0;

reg        fifo_in_valid = 1'b0;
wire       fifo_in_ready;
reg  [7:0] fifo_in_data = 8'b0;
wire       fifo_out_valid;
reg        fifo_out_ready = 1'b0;
wire [7:0] fifo_out_data;
reg        fifo_flush = 1'b0;

always #5 clk = ~clk;

ysyx_gnrl_rv_reg #(
    .DW(8)
) u_rv_reg (
    .in_valid (reg_in_valid),
    .in_ready (reg_in_ready),
    .in_data  (reg_in_data),
    .out_valid(reg_out_valid),
    .out_ready(reg_out_ready),
    .out_data (reg_out_data),
    .flush    (reg_flush),
    .clk      (clk),
    .rst_n    (rst_n)
);

ysyx_gnrl_fifo #(
    .DW   (8),
    .DEPTH(2)
) u_fifo (
    .in_valid (fifo_in_valid),
    .in_ready (fifo_in_ready),
    .in_data  (fifo_in_data),
    .out_valid(fifo_out_valid),
    .out_ready(fifo_out_ready),
    .out_data (fifo_out_data),
    .flush    (fifo_flush),
    .clk      (clk),
    .rst_n    (rst_n)
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
        $display("Generic buffer test failed: %0s", message);
        $fatal;
    end
end
endtask

initial begin
    tick;
    tick;
    rst_n = 1'b1;
    tick;

    // rv_reg: capture, hold under backpressure, and replace on pop+push.
    check(reg_in_ready && !reg_out_valid,
          "rv_reg is not empty after reset");
    reg_in_valid = 1'b1;
    reg_in_data = 8'h11;
    tick;
    reg_in_valid = 1'b0;
    check(reg_out_valid && reg_out_data == 8'h11 && !reg_in_ready,
          "rv_reg did not capture its input");
    tick;
    check(reg_out_valid && reg_out_data == 8'h11,
          "rv_reg output changed under backpressure");

    reg_out_ready = 1'b1;
    reg_in_valid = 1'b1;
    reg_in_data = 8'h22;
    #1;
    check(reg_in_ready, "rv_reg cannot replace a consumed item");
    tick;
    reg_in_valid = 1'b0;
    reg_out_ready = 1'b0;
    check(reg_out_valid && reg_out_data == 8'h22,
          "rv_reg simultaneous pop and push failed");

    reg_flush = 1'b1;
    #1;
    check(!reg_out_valid && !reg_in_ready,
          "rv_reg did not block handshakes during flush");
    tick;
    reg_flush = 1'b0;
    #1;
    check(!reg_out_valid && reg_in_ready,
          "rv_reg was not empty after flush");

    // FIFO: fill two entries and hold the head while the output is stalled.
    check(fifo_in_ready && !fifo_out_valid,
          "FIFO is not empty after reset");
    fifo_in_valid = 1'b1;
    fifo_in_data = 8'ha1;
    tick;
    fifo_in_data = 8'hb2;
    tick;
    fifo_in_valid = 1'b0;
    check(fifo_out_valid && fifo_out_data == 8'ha1 && !fifo_in_ready,
          "FIFO full or head state is incorrect");
    tick;
    check(fifo_out_valid && fifo_out_data == 8'ha1,
          "FIFO head changed under backpressure");

    // A full FIFO can pop its head and accept a replacement in one cycle.
    fifo_out_ready = 1'b1;
    fifo_in_valid = 1'b1;
    fifo_in_data = 8'hc3;
    #1;
    check(fifo_in_ready, "full FIFO cannot perform simultaneous pop and push");
    tick;
    fifo_in_valid = 1'b0;
    fifo_out_ready = 1'b0;
    #1;
    check(fifo_out_valid && fifo_out_data == 8'hb2 && !fifo_in_ready,
          "FIFO ordering failed after simultaneous pop and push");

    fifo_out_ready = 1'b1;
    tick;
    check(fifo_out_valid && fifo_out_data == 8'hc3,
          "FIFO lost its replacement item");
    tick;
    fifo_out_ready = 1'b0;
    #1;
    check(!fifo_out_valid && fifo_in_ready,
          "FIFO did not become empty after draining");

    fifo_in_valid = 1'b1;
    fifo_in_data = 8'hd4;
    tick;
    fifo_in_valid = 1'b0;
    fifo_flush = 1'b1;
    #1;
    check(!fifo_out_valid && !fifo_in_ready,
          "FIFO did not block handshakes during flush");
    tick;
    fifo_flush = 1'b0;
    #1;
    check(!fifo_out_valid && fifo_in_ready,
          "FIFO was not empty after flush");

    $display("ysyx generic ready/valid buffer directed test: PASS");
    $finish;
end

endmodule

`default_nettype wire
