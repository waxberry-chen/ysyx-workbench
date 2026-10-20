`timescale 1ns/1ps
module ysyx_soc_wrapper_tb;
reg clock = '0;
reg reset = '0;
reg io_interrupt = '0;
reg io_master_awready = '0;
wire io_slave_awready;
wire io_master_awvalid;
reg io_slave_awvalid = '0;
wire [31:0] io_master_awaddr;
reg [31:0] io_slave_awaddr = '0;
wire [3:0] io_master_awid;
reg [3:0] io_slave_awid = '0;
wire [7:0] io_master_awlen;
reg [7:0] io_slave_awlen = '0;
wire [2:0] io_master_awsize;
reg [2:0] io_slave_awsize = '0;
wire [1:0] io_master_awburst;
reg [1:0] io_slave_awburst = '0;
reg io_master_wready = '0;
wire io_slave_wready;
wire io_master_wvalid;
reg io_slave_wvalid = '0;
wire [31:0] io_master_wdata;
reg [31:0] io_slave_wdata = '0;
wire [3:0] io_master_wstrb;
reg [3:0] io_slave_wstrb = '0;
wire io_master_wlast;
reg io_slave_wlast = '0;
wire io_master_bready;
reg io_slave_bready = '0;
reg io_master_bvalid = '0;
wire io_slave_bvalid;
reg [1:0] io_master_bresp = '0;
wire [1:0] io_slave_bresp;
reg [3:0] io_master_bid = '0;
wire [3:0] io_slave_bid;
reg io_master_arready = '0;
wire io_slave_arready;
wire io_master_arvalid;
reg io_slave_arvalid = '0;
wire [31:0] io_master_araddr;
reg [31:0] io_slave_araddr = '0;
wire [3:0] io_master_arid;
reg [3:0] io_slave_arid = '0;
wire [7:0] io_master_arlen;
reg [7:0] io_slave_arlen = '0;
wire [2:0] io_master_arsize;
reg [2:0] io_slave_arsize = '0;
wire [1:0] io_master_arburst;
reg [1:0] io_slave_arburst = '0;
wire io_master_rready;
reg io_slave_rready = '0;
reg io_master_rvalid = '0;
wire io_slave_rvalid;
reg [1:0] io_master_rresp = '0;
wire [1:0] io_slave_rresp;
reg [31:0] io_master_rdata = '0;
wire [31:0] io_slave_rdata;
reg io_master_rlast = '0;
wire io_slave_rlast;
reg [3:0] io_master_rid = '0;
wire [3:0] io_slave_rid;
ysyx_25030087 dut (.*);
always #5 clock=~clock;
task tick; @(posedge clock); #1; endtask
initial begin
    reset=1;
    repeat (20) tick();
    @(negedge clock);reset=0;
    if ($test$plusargs("badirq")) io_interrupt=1;
    if ($test$plusargs("badslave")) io_slave_arvalid=1;
    for (integer i=0;i<100;i=i+1) begin
        tick();
        if (io_master_arvalid) break;
        if (i==99) $fatal(1,"No first fetch");
    end
    repeat (8) begin
        assert(io_master_arvalid && io_master_araddr==32'h20000000 &&
               io_master_arsize==2 && io_master_arlen==0 && io_master_arid==0 &&
               io_master_arburst==1) else $fatal(1,"default MROM fetch/hold contract");
        assert(!(io_master_awvalid || io_master_wvalid || io_slave_arready ||
                 io_slave_awready || io_slave_wready || io_slave_rvalid || io_slave_bvalid))
            else $fatal(1,"wrapper tie-off");
        tick();
    end
    @(negedge clock);io_master_arready=1;
    tick();
    @(negedge clock);io_master_arready=0;reset=1;
    tick();
    assert(!(io_master_arvalid || io_master_awvalid || io_master_wvalid ||
             io_master_rready || io_master_bready)) else $fatal(1,"reset did not quiesce");
    $display("Wrapper: PASS default MROM PC, 20-cycle reset, backpressure, disabled slave");
    $finish;
end
endmodule
