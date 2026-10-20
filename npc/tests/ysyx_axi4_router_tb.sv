`timescale 1ns/1ps
module ysyx_axi4_router_tb;
reg clk = '0;
reg rst_n = '0;
reg s_axi_arvalid = '0;
wire s_axi_arready;
reg [31:0] s_axi_araddr = '0;
reg [2:0] s_axi_arsize = '0;
reg [2:0] s_axi_arprot = '0;
wire s_axi_rvalid;
reg s_axi_rready = '0;
wire [31:0] s_axi_rdata;
wire [1:0] s_axi_rresp;
wire [3:0] s_axi_rid;
wire s_axi_rlast;
reg s_axi_awvalid = '0;
wire s_axi_awready;
reg [31:0] s_axi_awaddr = '0;
reg [2:0] s_axi_awsize = '0;
reg [2:0] s_axi_awprot = '0;
reg s_axi_wvalid = '0;
wire s_axi_wready;
reg [31:0] s_axi_wdata = '0;
reg [3:0] s_axi_wstrb = '0;
wire s_axi_bvalid;
reg s_axi_bready = '0;
wire [1:0] s_axi_bresp;
wire [3:0] s_axi_bid;
wire m_axi_arvalid;
reg m_axi_arready = '0;
wire [31:0] m_axi_araddr;
wire [2:0] m_axi_arsize;
wire [2:0] m_axi_arprot;
reg m_axi_rvalid = '0;
wire m_axi_rready;
reg [31:0] m_axi_rdata = '0;
reg [1:0] m_axi_rresp = '0;
reg [3:0] m_axi_rid = '0;
reg m_axi_rlast = '0;
wire m_axi_awvalid;
reg m_axi_awready = '0;
wire [31:0] m_axi_awaddr;
wire [2:0] m_axi_awsize;
wire [2:0] m_axi_awprot;
wire m_axi_wvalid;
reg m_axi_wready = '0;
wire [31:0] m_axi_wdata;
wire [3:0] m_axi_wstrb;
reg m_axi_bvalid = '0;
wire m_axi_bready;
reg [1:0] m_axi_bresp = '0;
reg [3:0] m_axi_bid = '0;
ysyx_axi4_router dut (.*);
always #5 clk=~clk;
task tick; @(posedge clk); #1; endtask
always @(posedge clk) if (rst_n)
    assert(!(m_axi_arvalid || m_axi_awvalid || m_axi_wvalid))
        else $fatal(1,"CLINT request escaped CPU");
initial begin #200000; $fatal(1,"router test watchdog"); end
// Present either/both independent write channels and hold until handshaken.
task send(input bit aw, input bit w);
    bit ad,wd,af,wf;
    ad=!aw;wd=!w;
    @(negedge clk);s_axi_awvalid=aw;s_axi_wvalid=w;
    while (!(ad&&wd)) begin
        #1;af=s_axi_awvalid&&s_axi_awready;wf=s_axi_wvalid&&s_axi_wready;
        tick();ad=ad||af;wd=wd||wf;
        @(negedge clk);s_axi_awvalid=!ad;s_axi_wvalid=!wd;
    end
endtask
task write_word(input [31:0] address,input [31:0] data,input integer order);
    s_axi_awaddr=address;s_axi_awsize=2;s_axi_wdata=data;s_axi_wstrb=15;
    if(order==0)send(1,1);
    else if(order<0)begin send(1,0);repeat(3)tick();send(0,1);end
    else begin send(0,1);repeat(3)tick();send(1,0);end
    // Accepted payload must be isolated from changes at the source pins.
    s_axi_awaddr=32'h10000000;s_axi_wdata=32'hdeadbeef;
    while(!s_axi_bvalid)tick();
    repeat(20)begin
        assert(s_axi_bvalid && s_axi_bresp==0 && s_axi_bid==0)
            else $fatal(1,"local write response holding");
        tick();
    end
    @(negedge clk);s_axi_bready=1;tick();
    @(negedge clk);s_axi_bready=0;
endtask
task read_word(input [31:0] address, input [2:0] size, output [31:0] data,input bit error);
    @(negedge clk);s_axi_araddr=address;s_axi_arsize=size;s_axi_arvalid=1;
    while(!s_axi_arready)tick();
    tick();@(negedge clk);s_axi_arvalid=0;s_axi_araddr=32'h10000000;
    while(!s_axi_rvalid)tick();
    data=s_axi_rdata;
    repeat(12)begin
        assert(s_axi_rvalid && s_axi_rdata==data && s_axi_rid==0 && s_axi_rlast &&
               s_axi_rresp==(error?2:0)) else $fatal(1,"local read response snapshot/holding");
        tick();
    end
    @(negedge clk);s_axi_rready=1;tick();
    @(negedge clk);s_axi_rready=0;
endtask
reg [31:0] data;
initial begin
    tick();@(negedge clk);rst_n=1;
    for(integer order=-1;order<=1;order=order+1)begin
        write_word(32'h0200bffc,32'h12345678,order);
        read_word(32'h0200bffc,2,data,0);
        assert(data==32'h12345678) else $fatal(1,"AW/W route/latch");
        write_word(32'h0200bff8,0,order);
        read_word(32'h0200bff8,2,data,0);
        assert(data>=20) else $fatal(1,"write replayed under B backpressure");
    end
    read_word(32'h0200bff8,0,data,1);
    read_word(32'h02004000,2,data,1);
    // Reset an unconsumed local response; no stale R after release.
    @(negedge clk);s_axi_araddr=32'h0200bff8;s_axi_arsize=2;s_axi_arvalid=1;
    tick();@(negedge clk);s_axi_arvalid=0;
    while(!s_axi_rvalid)tick();
    @(negedge clk);rst_n=0;tick();
    assert(!s_axi_rvalid && !s_axi_bvalid) else $fatal(1,"local response survived reset");
    @(negedge clk);rst_n=1;
    repeat(3)begin tick();assert(!s_axi_rvalid && !s_axi_bvalid) else $fatal(1,"stale local response");end
    read_word(32'h0200bffc,2,data,0);
    assert(data==0) else $fatal(1,"timer reset");
    $display("CLINT router: PASS AW/W orders, payload capture, response stalls, no repeated write, errors, reset");
    $finish;
end
endmodule
