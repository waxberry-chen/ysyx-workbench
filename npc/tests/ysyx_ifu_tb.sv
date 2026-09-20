`timescale 1ns/1ps
`default_nettype none

module ysyx_ifu_tb;

localparam [31:0] PC_RST = 32'h8000_0000;

reg         clk = 1'b0;
reg         rst_n = 1'b0;
reg         redirect_valid = 1'b0;
reg  [31:0] redirect_target = 32'b0;
wire        if_ctx_valid;
reg         if_ctx_ready = 1'b0;
wire [31:0] if_ctx_pc;
wire [31:0] if_ctx_inst;
wire        if_ctx_error;
wire        if_ctx_pred_taken;
wire [31:0] if_ctx_pred_npc;
wire        imem_req_valid;
reg         imem_req_ready = 1'b0;
wire [31:0] imem_req_addr;
reg         imem_rsp_valid = 1'b0;
wire        imem_rsp_ready;
reg  [31:0] imem_rsp_data = 32'b0;

always #5 clk = ~clk;

ysyx_ifu #(
    .PC_RST   (PC_RST),
    .IFQ_DEPTH(2)
) u_ifu (
    .clk              (clk),
    .rst_n            (rst_n),
    .redirect_valid   (redirect_valid),
    .redirect_target  (redirect_target),
    .if_ctx_valid     (if_ctx_valid),
    .if_ctx_ready     (if_ctx_ready),
    .if_ctx_pc        (if_ctx_pc),
    .if_ctx_inst      (if_ctx_inst),
    .if_ctx_error     (if_ctx_error),
    .if_ctx_pred_taken(if_ctx_pred_taken),
    .if_ctx_pred_npc  (if_ctx_pred_npc),
    .imem_req_valid   (imem_req_valid),
    .imem_req_ready   (imem_req_ready),
    .imem_req_addr    (imem_req_addr),
    .imem_rsp_valid   (imem_rsp_valid),
    .imem_rsp_ready   (imem_rsp_ready),
    .imem_rsp_data    (imem_rsp_data)
);

task tick;
begin
    @(posedge clk);
    #1;
end
endtask

task settle;
begin
    #1;
end
endtask

task check;
    input condition;
    input [8*96-1:0] message;
begin
    if (!condition) begin
        $display("IFU test failed: %0s", message);
        $fatal;
    end
end
endtask

initial begin
    tick;
    tick;
    rst_n = 1'b1;
    settle;

    // Request payload must remain stable under instruction-memory stall.
    check(imem_req_valid && imem_req_addr == PC_RST,
          "reset fetch request is incorrect");
    tick;
    check(imem_req_valid && imem_req_addr == PC_RST,
          "request changed during first stalled cycle");
    tick;
    check(imem_req_valid && imem_req_addr == PC_RST,
          "request changed during second stalled cycle");

    imem_req_ready = 1'b1;
    tick;
    imem_req_ready = 1'b0;
    settle;
    check(!imem_req_valid && imem_rsp_ready,
          "IFU did not enter response-wait state");

    // Return the first instruction and keep the backend stalled.
    imem_rsp_data = 32'h1111_1111;
    imem_rsp_valid = 1'b1;
    tick;
    imem_rsp_valid = 1'b0;
    settle;
    check(if_ctx_valid && if_ctx_pc == PC_RST &&
          if_ctx_inst == 32'h1111_1111,
          "first response did not enter IFQ");
    check(!if_ctx_error && !if_ctx_pred_taken &&
          if_ctx_pred_npc == PC_RST + 32'd4,
          "static prediction metadata is incorrect");

    // Fetch a second item while the first remains blocked at the output.
    check(imem_req_valid && imem_req_addr == PC_RST + 32'd4,
          "IFU did not prefetch behind a stalled backend");
    imem_req_ready = 1'b1;
    tick;
    imem_req_ready = 1'b0;
    imem_rsp_data = 32'h2222_2222;
    imem_rsp_valid = 1'b1;
    tick;
    imem_rsp_valid = 1'b0;
    settle;
    check(if_ctx_valid && if_ctx_pc == PC_RST &&
          if_ctx_inst == 32'h1111_1111,
          "IFQ head changed while backend was stalled");
    check(!imem_req_valid,
          "IFU issued a request without reserving an IFQ entry");

    // Drain both entries and verify FIFO order.
    if_ctx_ready = 1'b1;
    tick;
    if_ctx_ready = 1'b0;
    settle;
    check(if_ctx_valid && if_ctx_pc == PC_RST + 32'd4 &&
          if_ctx_inst == 32'h2222_2222,
          "IFQ ordering is incorrect");
    if_ctx_ready = 1'b1;
    tick;
    if_ctx_ready = 1'b0;
    settle;
    check(!if_ctx_valid, "IFQ did not become empty after draining");

    // Redirect with no outstanding request cancels the unaccepted old path.
    redirect_target = 32'h8000_0100;
    redirect_valid = 1'b1;
    settle;
    check(!imem_req_valid && !if_ctx_valid,
          "redirect did not suppress old-path traffic");
    tick;
    redirect_valid = 1'b0;
    settle;
    check(imem_req_valid && imem_req_addr == 32'h8000_0100,
          "redirect target was not selected");

    // Once accepted, a request cannot be cancelled.  A second redirect marks
    // its eventual response stale and blocks new requests until it is drained.
    imem_req_ready = 1'b1;
    tick;
    imem_req_ready = 1'b0;
    redirect_target = 32'h8000_0200;
    redirect_valid = 1'b1;
    tick;
    redirect_valid = 1'b0;
    settle;
    check(!imem_req_valid && imem_rsp_ready && !if_ctx_valid,
          "IFU did not wait to drop the outstanding old-path response");

    imem_rsp_data = 32'hdead_beef;
    imem_rsp_valid = 1'b1;
    tick;
    imem_rsp_valid = 1'b0;
    settle;
    check(!if_ctx_valid,
          "stale response entered IFQ after redirect");
    check(imem_req_valid && imem_req_addr == 32'h8000_0200,
          "IFU did not resume from the newest redirect target");

    // The first response on the new path is visible only after being queued.
    imem_req_ready = 1'b1;
    tick;
    imem_req_ready = 1'b0;
    imem_rsp_data = 32'h3333_3333;
    imem_rsp_valid = 1'b1;
    tick;
    imem_rsp_valid = 1'b0;
    settle;
    check(if_ctx_valid && if_ctx_pc == 32'h8000_0200 &&
          if_ctx_inst == 32'h3333_3333,
          "new-path response was not queued correctly");

    // Redirect and response may coincide.  The old response is consumed in
    // that cycle, the queued context is flushed, and no extra DROP cycle is
    // needed before requesting the latest target.
    if_ctx_ready = 1'b1;
    tick;
    if_ctx_ready = 1'b0;
    settle;
    check(imem_req_valid && imem_req_addr == 32'h8000_0204,
          "IFU did not advance after consuming the new-path context");
    imem_req_ready = 1'b1;
    tick;
    imem_req_ready = 1'b0;
    redirect_target = 32'h8000_0300;
    redirect_valid = 1'b1;
    imem_rsp_data = 32'hfeed_face;
    imem_rsp_valid = 1'b1;
    settle;
    check(imem_rsp_ready,
          "IFU refused a stale response in the redirect cycle");
    tick;
    redirect_valid = 1'b0;
    imem_rsp_valid = 1'b0;
    settle;
    check(!if_ctx_valid && imem_req_valid &&
          imem_req_addr == 32'h8000_0300,
          "same-cycle redirect/response recovery is incorrect");

    $display("ysyx_ifu directed test: PASS");
    $finish;
end

endmodule

`default_nettype wire
