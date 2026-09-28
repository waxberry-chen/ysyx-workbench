`timescale 1ns/1ps
`default_nettype none

module ysyx_ifu_axi4lite_adapter_integ_tb;

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
wire        imem_req_ready;
wire [31:0] imem_req_addr;
wire        imem_rsp_valid;
wire        imem_rsp_ready;
wire [31:0] imem_rsp_data;
wire        imem_rsp_error;

wire        m_axi_arvalid;
reg         m_axi_arready = 1'b0;
wire [31:0] m_axi_araddr;
wire [2:0]  m_axi_arprot;
reg         m_axi_rvalid = 1'b0;
wire        m_axi_rready;
reg  [31:0] m_axi_rdata = 32'b0;
reg  [1:0]  m_axi_rresp = 2'b00;

integer ar_handshakes = 0;
integer r_handshakes = 0;

always #5 clk = ~clk;

always @(posedge clk) begin
    if (rst_n && m_axi_arvalid && m_axi_arready)
        ar_handshakes <= ar_handshakes + 1;
    if (rst_n && m_axi_rvalid && m_axi_rready)
        r_handshakes <= r_handshakes + 1;
end

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
    .imem_rsp_data    (imem_rsp_data),
    .imem_rsp_error   (imem_rsp_error)
);

ysyx_ifu_axi4lite_adapter u_adapter (
    .clk           (clk),
    .rst_n         (rst_n),
    .imem_req_valid(imem_req_valid),
    .imem_req_ready(imem_req_ready),
    .imem_req_addr (imem_req_addr),
    .imem_rsp_valid(imem_rsp_valid),
    .imem_rsp_ready(imem_rsp_ready),
    .imem_rsp_data (imem_rsp_data),
    .imem_rsp_error(imem_rsp_error),
    .m_axi_arvalid (m_axi_arvalid),
    .m_axi_arready (m_axi_arready),
    .m_axi_araddr  (m_axi_araddr),
    .m_axi_arprot  (m_axi_arprot),
    .m_axi_rvalid  (m_axi_rvalid),
    .m_axi_rready  (m_axi_rready),
    .m_axi_rdata   (m_axi_rdata),
    .m_axi_rresp   (m_axi_rresp)
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
    input [8*112-1:0] message;
begin
    if (!condition) begin
        $display("IFU + AXI4-Lite adapter integration test failed: %0s",
                 message);
        $fatal;
    end
end
endtask

task capture_ifu_request;
    input [31:0] expected_addr;
begin
    check(imem_req_valid && imem_req_ready &&
          imem_req_addr == expected_addr,
          "IFU local request was not ready for capture");
    tick;
    check(m_axi_arvalid && m_axi_araddr == expected_addr &&
          m_axi_arprot == 3'b101,
          "captured IFU request did not reach AXI AR");
end
endtask

task accept_ar;
    input [31:0] expected_addr;
begin
    check(m_axi_arvalid && m_axi_araddr == expected_addr,
          "unexpected AXI read address");
    m_axi_arready = 1'b1;
    tick;
    m_axi_arready = 1'b0;
    settle;
    check(m_axi_rready && !m_axi_arvalid,
          "adapter did not wait for AXI read data");
end
endtask

task return_axi_data;
    input [31:0] data;
begin
    check(m_axi_rready, "adapter was not ready for scripted AXI data");
    m_axi_rdata = data;
    m_axi_rresp = 2'b00;
    m_axi_rvalid = 1'b1;
    tick;
    m_axi_rvalid = 1'b0;
    settle;
    check(imem_rsp_valid && imem_rsp_data == data && !imem_rsp_error,
          "AXI data did not reach the local response buffer");
end
endtask

task consume_stale_response;
    input [31:0] expected_target;
begin
    check(imem_rsp_valid && imem_rsp_ready,
          "IFU did not accept a stale local response");
    tick;
    check(!if_ctx_valid && imem_req_valid && imem_req_ready &&
          imem_req_addr == expected_target,
          "stale response entered IFQ or redirect target was lost");
end
endtask

initial begin
    tick;
    tick;
    rst_n = 1'b1;
    settle;

    // Redirect before AR handshake: the adapter owns the accepted local
    // request, completes it later, and IFU drops the stale response.
    capture_ifu_request(PC_RST);
    redirect_target = 32'h8000_0100;
    redirect_valid = 1'b1;
    tick;
    redirect_valid = 1'b0;
    settle;
    check(m_axi_arvalid && m_axi_araddr == PC_RST && !if_ctx_valid,
          "pre-AR redirect cancelled or corrupted the accepted request");
    accept_ar(PC_RST);
    return_axi_data(32'hdead_0000);
    consume_stale_response(32'h8000_0100);

    // Redirect after AR handshake while waiting for R.
    capture_ifu_request(32'h8000_0100);
    accept_ar(32'h8000_0100);
    redirect_target = 32'h8000_0200;
    redirect_valid = 1'b1;
    tick;
    redirect_valid = 1'b0;
    settle;
    check(m_axi_rready && !if_ctx_valid,
          "post-AR redirect did not preserve the outstanding AXI read");
    return_axi_data(32'hdead_0100);
    consume_stale_response(32'h8000_0200);

    // Redirect and the AXI R handshake occur on the same edge.  The adapter
    // captures R while IFU enters DROP, then delivers the buffered stale
    // response on the following cycle.
    capture_ifu_request(32'h8000_0200);
    accept_ar(32'h8000_0200);
    redirect_target = 32'h8000_0300;
    redirect_valid = 1'b1;
    m_axi_rdata = 32'hdead_0200;
    m_axi_rresp = 2'b00;
    m_axi_rvalid = 1'b1;
    check(m_axi_rready, "adapter refused R coincident with redirect");
    tick;
    redirect_valid = 1'b0;
    m_axi_rvalid = 1'b0;
    settle;
    consume_stale_response(32'h8000_0300);

    // Redirect in the same cycle that the buffered response reaches IFU.
    // IFU consumes and drops it without entering an extra DROP cycle.
    capture_ifu_request(32'h8000_0300);
    accept_ar(32'h8000_0300);
    return_axi_data(32'hdead_0300);
    redirect_target = 32'h8000_0400;
    redirect_valid = 1'b1;
    check(imem_rsp_ready,
          "IFU refused a response coincident with redirect");
    tick;
    redirect_valid = 1'b0;
    settle;
    check(!if_ctx_valid && imem_req_valid && imem_req_ready &&
          imem_req_addr == 32'h8000_0400,
          "same-cycle redirect/response recovery is incorrect");

    // A subsequent non-stale response must enter IFQ with its original PC.
    capture_ifu_request(32'h8000_0400);
    accept_ar(32'h8000_0400);
    return_axi_data(32'h1234_5678);
    tick;
    settle;
    check(if_ctx_valid && if_ctx_pc == 32'h8000_0400 &&
          if_ctx_inst == 32'h1234_5678 && !if_ctx_error &&
          !if_ctx_pred_taken && if_ctx_pred_npc == 32'h8000_0404,
          "non-stale AXI response did not enter IFQ correctly");
    check(ar_handshakes == 5 && r_handshakes == 5,
          "AXI transaction count is incorrect");

    if_ctx_ready = 1'b1;
    tick;
    if_ctx_ready = 1'b0;

    $display("ysyx IFU + AXI4-Lite adapter integration test: PASS");
    $finish;
end

endmodule

`default_nettype wire
