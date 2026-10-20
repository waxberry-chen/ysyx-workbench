`timescale 1ns/1ps


module ysyx_ifu_axi4_adapter_tb;

reg         clk = 1'b0;
reg         rst_n = 1'b0;
reg         imem_req_valid = 1'b0;
wire        imem_req_ready;
reg  [31:0] imem_req_addr = 32'b0;
wire        imem_rsp_valid;
reg         imem_rsp_ready = 1'b0;
wire [31:0] imem_rsp_data;
wire        imem_rsp_error;
wire        m_axi_arvalid;
reg         m_axi_arready = 1'b0;
wire [31:0] m_axi_araddr;
wire [2:0]  m_axi_arprot;
wire [2:0]  m_axi_arsize;
reg         m_axi_rvalid = 1'b0;
wire        m_axi_rready;
reg  [31:0] m_axi_rdata = 32'b0;
reg  [1:0]  m_axi_rresp = 2'b0;

always #5 clk = ~clk;

ysyx_ifu_axi4_adapter u_adapter (
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
    .m_axi_arsize  (m_axi_arsize),
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
    input [8*96-1:0] message;
begin
    if (!condition) begin
        $display("IFU AXI4 single-beat adapter test failed: %0s", message);
        $fatal;
    end
end
endtask

task run_response_code;
    input [1:0] response;
    input [31:0] data;
begin
    imem_req_addr = 32'h8000_0100 + {28'b0, response, 2'b00};
    imem_req_valid = 1'b1;
    tick;
    imem_req_valid = 1'b0;
    settle;
    check(m_axi_arsize == 2 && m_axi_arvalid && m_axi_araddr == imem_req_addr,
          "captured request did not reach AR channel");

    m_axi_arready = 1'b1;
    tick;
    m_axi_arready = 1'b0;
    m_axi_rdata = data;
    m_axi_rresp = response;
    m_axi_rvalid = 1'b1;
    tick;
    m_axi_rvalid = 1'b0;
    settle;

    check(imem_rsp_valid && imem_rsp_data == data,
          "AXI response data was not buffered");
    check(imem_rsp_error == (response != 2'b00),
          "AXI response code was mapped incorrectly");

    imem_rsp_ready = 1'b1;
    tick;
    imem_rsp_ready = 1'b0;
    settle;
    check(imem_req_ready && !imem_rsp_valid,
          "adapter did not return to idle after local response");
end
endtask

initial begin
    tick;
    check(!imem_req_ready && !m_axi_arvalid && !m_axi_rready &&
          !imem_rsp_valid,
          "interface was active during reset");
    tick;
    rst_n = 1'b1;
    settle;
    check(imem_req_ready, "adapter is not ready after reset");

    // Capture a local request, then hold the AXI address channel stalled.
    imem_req_addr = 32'h8000_0000;
    imem_req_valid = 1'b1;
    tick;
    imem_req_valid = 1'b0;
    settle;
    check(!imem_req_ready && m_axi_arvalid &&
          m_axi_araddr == 32'h8000_0000 && m_axi_arprot == 3'b101,
          "AR request payload is incorrect");
    tick;
    check(m_axi_arsize == 2 && m_axi_arvalid && m_axi_araddr == 32'h8000_0000,
          "AR request changed during first stalled cycle");
    tick;
    check(m_axi_arsize == 2 && m_axi_arvalid && m_axi_araddr == 32'h8000_0000,
          "AR request changed during second stalled cycle");

    m_axi_arready = 1'b1;
    tick;
    m_axi_arready = 1'b0;
    settle;
    check(!m_axi_arvalid && m_axi_rready,
          "adapter did not enter AXI response wait state");

    // A delayed AXI response must be accepted even while the local consumer
    // is blocked, then held in the registered response buffer.
    tick;
    tick;
    m_axi_rdata = 32'h1122_3344;
    m_axi_rresp = 2'b00;
    m_axi_rvalid = 1'b1;
    tick;
    m_axi_rvalid = 1'b0;
    settle;
    check(imem_rsp_valid && imem_rsp_data == 32'h1122_3344 &&
          !imem_rsp_error && !m_axi_rready,
          "OKAY response was not buffered correctly");
    tick;
    check(imem_rsp_valid && imem_rsp_data == 32'h1122_3344 &&
          !imem_rsp_error,
          "local response changed during first stalled cycle");
    tick;
    check(imem_rsp_valid && imem_rsp_data == 32'h1122_3344 &&
          !imem_rsp_error,
          "local response changed during second stalled cycle");

    imem_rsp_ready = 1'b1;
    tick;
    imem_rsp_ready = 1'b0;
    settle;
    check(imem_req_ready && !imem_rsp_valid,
          "OKAY transaction did not complete");

    // AXI4 single-beat supports only OKAY as a successful normal response.  Verify
    // that every non-zero encoding becomes a local access error.
    run_response_code(2'b01, 32'haaaa_0001);
    run_response_code(2'b10, 32'haaaa_0002);
    run_response_code(2'b11, 32'haaaa_0003);

    // Reset abandons an accepted but incomplete transaction and suppresses
    // all AXI/local handshake outputs.
    imem_req_addr = 32'h8000_0200;
    imem_req_valid = 1'b1;
    tick;
    imem_req_valid = 1'b0;
    check(m_axi_arvalid, "reset test did not reach SEND_AR");
    rst_n = 1'b0;
    settle;
    check(!imem_req_ready && !m_axi_arvalid && !m_axi_rready &&
          !imem_rsp_valid,
          "reset did not quiesce the adapter");
    tick;
    rst_n = 1'b1;
    settle;
    check(imem_req_ready && !m_axi_arvalid && !imem_rsp_valid,
          "adapter did not return to idle after reset");

    $display("ysyx IFU AXI4 single-beat adapter directed test: PASS");
    $finish;
end

endmodule


