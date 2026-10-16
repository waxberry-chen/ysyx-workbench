`timescale 1ns/1ps


module ysyx_lsu_axi4lite_adapter_tb;

reg         clk = 1'b0;
reg         rst_n = 1'b0;

reg         dmem_req_valid = 1'b0;
wire        dmem_req_ready;
reg         dmem_req_write = 1'b0;
reg  [31:0] dmem_req_addr = 32'b0;
reg  [1:0]  dmem_req_size = 2'b0;
reg  [31:0] dmem_req_wdata = 32'b0;
wire        dmem_rsp_valid;
reg         dmem_rsp_ready = 1'b0;
wire [31:0] dmem_rsp_data;
wire        dmem_rsp_error;

wire        m_axi_awvalid;
reg         m_axi_awready = 1'b0;
wire [31:0] m_axi_awaddr;
wire [2:0]  m_axi_awprot;
wire        m_axi_wvalid;
reg         m_axi_wready = 1'b0;
wire [31:0] m_axi_wdata;
wire [3:0]  m_axi_wstrb;
reg         m_axi_bvalid = 1'b0;
wire        m_axi_bready;
reg  [1:0]  m_axi_bresp = 2'b0;
wire        m_axi_arvalid;
reg         m_axi_arready = 1'b0;
wire [31:0] m_axi_araddr;
wire [2:0]  m_axi_arprot;
reg         m_axi_rvalid = 1'b0;
wire        m_axi_rready;
reg  [31:0] m_axi_rdata = 32'b0;
reg  [1:0]  m_axi_rresp = 2'b0;

integer ar_handshakes = 0;
integer r_handshakes = 0;
integer aw_handshakes = 0;
integer w_handshakes = 0;
integer b_handshakes = 0;

always #5 clk = ~clk;

always @(posedge clk) begin
    if (rst_n && m_axi_arvalid && m_axi_arready)
        ar_handshakes <= ar_handshakes + 1;
    if (rst_n && m_axi_rvalid && m_axi_rready)
        r_handshakes <= r_handshakes + 1;
    if (rst_n && m_axi_awvalid && m_axi_awready)
        aw_handshakes <= aw_handshakes + 1;
    if (rst_n && m_axi_wvalid && m_axi_wready)
        w_handshakes <= w_handshakes + 1;
    if (rst_n && m_axi_bvalid && m_axi_bready)
        b_handshakes <= b_handshakes + 1;
end

ysyx_lsu_axi4lite_adapter u_adapter (.*);

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
        $display("LSU AXI4-Lite adapter test failed: %0s", message);
        $fatal;
    end
end
endtask

task issue_read;
    input [31:0] address;
    input [1:0] size;
begin
    check(dmem_req_ready, "adapter was not ready for a read request");
    dmem_req_valid = 1'b1;
    dmem_req_write = 1'b0;
    dmem_req_addr = address;
    dmem_req_size = size;
    dmem_req_wdata = 32'b0;
    tick;
    dmem_req_valid = 1'b0;
    settle;
    check(m_axi_arvalid && m_axi_araddr == {address[31:2], 2'b00} &&
          m_axi_arprot == 3'b001 && !dmem_req_ready,
          "read request was not captured correctly");
end
endtask

task accept_read_address;
begin
    m_axi_arready = 1'b1;
    tick;
    m_axi_arready = 1'b0;
    settle;
    check(!m_axi_arvalid && m_axi_rready,
          "adapter did not enter read response wait");
end
endtask

task return_read_data;
    input [31:0] data;
    input [1:0] response;
begin
    check(m_axi_rready, "adapter was not ready for read data");
    m_axi_rdata = data;
    m_axi_rresp = response;
    m_axi_rvalid = 1'b1;
    tick;
    m_axi_rvalid = 1'b0;
    settle;
    check(dmem_rsp_valid &&
          dmem_rsp_error == (response != 2'b00),
          "read response status was not buffered correctly");
end
endtask

task issue_store;
    input [31:0] address;
    input [1:0] size;
    input [31:0] data;
begin
    check(dmem_req_ready, "adapter was not ready for a store request");
    dmem_req_valid = 1'b1;
    dmem_req_write = 1'b1;
    dmem_req_addr = address;
    dmem_req_size = size;
    dmem_req_wdata = data;
    tick;
    dmem_req_valid = 1'b0;
    settle;
    check(m_axi_awvalid && m_axi_wvalid &&
          m_axi_awaddr == {address[31:2], 2'b00} &&
          m_axi_awprot == 3'b001 && !dmem_req_ready,
          "store request was not captured correctly");
end
endtask

task return_write_response;
    input [1:0] response;
begin
    check(m_axi_bready, "adapter waited for B before both write channels");
    m_axi_bresp = response;
    m_axi_bvalid = 1'b1;
    tick;
    m_axi_bvalid = 1'b0;
    settle;
    check(dmem_rsp_valid && dmem_rsp_data == 32'b0 &&
          dmem_rsp_error == (response != 2'b00),
          "write response was not buffered correctly");
end
endtask

task consume_local_response;
begin
    dmem_rsp_ready = 1'b1;
    tick;
    dmem_rsp_ready = 1'b0;
    settle;
    check(dmem_req_ready && !dmem_rsp_valid,
          "adapter did not return to idle after local response");
end
endtask

initial begin
    tick;
    check(!dmem_req_ready && !m_axi_arvalid && !m_axi_rready &&
          !m_axi_awvalid && !m_axi_wvalid && !m_axi_bready &&
          !dmem_rsp_valid,
          "interface was active during reset");
    tick;
    rst_n = 1'b1;
    settle;
    check(dmem_req_ready, "adapter is not ready after reset");

    // Byte load at lane 3: AR payload holds under backpressure and returned
    // data is normalized to bits [7:0] before reaching LSU.
    issue_read(32'h8000_0103, 2'd0);
    tick;
    check(m_axi_arvalid && m_axi_araddr == 32'h8000_0100,
          "AR payload changed during first stalled cycle");
    tick;
    check(m_axi_arvalid && m_axi_araddr == 32'h8000_0100,
          "AR payload changed during second stalled cycle");
    accept_read_address;
    tick;
    tick;
    return_read_data(32'h8033_2211, 2'b00);
    check(dmem_rsp_data == 32'h0000_0080 && !dmem_rsp_error,
          "byte lane normalization is incorrect");
    tick;
    check(dmem_rsp_valid && dmem_rsp_data == 32'h0000_0080,
          "read response changed under local backpressure");
    tick;
    check(dmem_rsp_valid && dmem_rsp_data == 32'h0000_0080,
          "read response did not remain buffered");
    consume_local_response;

    // Halfword load at lane 2 and an AXI SLVERR response.
    issue_read(32'h8000_0106, 2'd1);
    accept_read_address;
    return_read_data(32'hbeef_1122, 2'b10);
    check(dmem_rsp_data == 32'h0000_beef && dmem_rsp_error,
          "halfword normalization or RRESP mapping is incorrect");
    consume_local_response;

    // AW-first byte store.  Keep AWREADY high for another cycle after its
    // handshake to prove that the address is not issued twice while W stalls.
    issue_store(32'h8000_0201, 2'd0, 32'h1234_56ef);
    check(m_axi_wstrb == 4'b0010 && m_axi_wdata == 32'h3456_ef00,
          "byte store lane packing is incorrect");
    m_axi_awready = 1'b1;
    tick;
    check(!m_axi_awvalid && m_axi_wvalid && !m_axi_bready,
          "AW-first completion was not tracked independently");
    tick;
    check(!m_axi_awvalid && m_axi_wvalid && aw_handshakes == 1,
          "completed AW channel was reissued");
    m_axi_awready = 1'b0;
    m_axi_wready = 1'b1;
    tick;
    m_axi_wready = 1'b0;
    settle;
    check(!m_axi_wvalid && m_axi_bready,
          "adapter did not wait for B after AW-first write");
    return_write_response(2'b00);
    consume_local_response;

    // W-first halfword store.  The active bytes move to lanes 2 and 3.
    issue_store(32'h8000_0202, 2'd1, 32'h1234_beef);
    check(m_axi_wstrb == 4'b1100 && m_axi_wdata == 32'hbeef_0000,
          "halfword store lane packing is incorrect");
    m_axi_wready = 1'b1;
    tick;
    check(m_axi_awvalid && !m_axi_wvalid && !m_axi_bready,
          "W-first completion was not tracked independently");
    tick;
    check(m_axi_awvalid && !m_axi_wvalid && w_handshakes == 2,
          "completed W channel was reissued");
    m_axi_wready = 1'b0;
    m_axi_awready = 1'b1;
    tick;
    m_axi_awready = 1'b0;
    settle;
    check(m_axi_bready, "adapter did not wait for B after W-first write");
    return_write_response(2'b01);
    check(dmem_rsp_error, "unsupported EXOKAY was not treated as an error");
    consume_local_response;

    // Word store with simultaneous AW/W and DECERR.  Hold the local response
    // stalled to check that error and data remain stable.
    issue_store(32'h8000_0300, 2'd2, 32'haabb_ccdd);
    check(m_axi_wstrb == 4'b1111 && m_axi_wdata == 32'haabb_ccdd,
          "word store packing is incorrect");
    m_axi_awready = 1'b1;
    m_axi_wready = 1'b1;
    tick;
    m_axi_awready = 1'b0;
    m_axi_wready = 1'b0;
    settle;
    check(m_axi_bready && !m_axi_awvalid && !m_axi_wvalid,
          "simultaneous AW/W handshake was not recorded");
    return_write_response(2'b11);
    tick;
    check(dmem_rsp_valid && dmem_rsp_error && dmem_rsp_data == 32'b0,
          "write error changed under local backpressure");
    tick;
    check(dmem_rsp_valid && dmem_rsp_error && dmem_rsp_data == 32'b0,
          "write error did not remain buffered");

    check(ar_handshakes == 2 && r_handshakes == 2 &&
          aw_handshakes == 3 && w_handshakes == 3 && b_handshakes == 3,
          "a transaction was duplicated or lost");
    consume_local_response;

    // Reset after AW but before W abandons the partial transaction.  The
    // shared reset contract requires the slave to discard the matching AW.
    issue_store(32'h8000_0400, 2'd2, 32'h55aa_aa55);
    m_axi_awready = 1'b1;
    tick;
    m_axi_awready = 1'b0;
    check(!m_axi_awvalid && m_axi_wvalid,
          "reset test did not reach partial-write state");
    rst_n = 1'b0;
    settle;
    check(!dmem_req_ready && !m_axi_awvalid && !m_axi_wvalid &&
          !m_axi_bready && !dmem_rsp_valid,
          "reset did not quiesce the partial write");
    tick;
    rst_n = 1'b1;
    settle;
    check(dmem_req_ready && !dmem_rsp_valid,
          "adapter did not return to idle after reset");

    $display("ysyx LSU AXI4-Lite adapter directed test: PASS");
    $finish;
end

endmodule


