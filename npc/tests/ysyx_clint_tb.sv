`timescale 1ns/1ps
module ysyx_clint_tb;
reg clk=0, rst_n=0, req_valid=0, req_write=0;
reg [31:0] req_addr=0, req_wdata=0;
reg [2:0] req_size=2;
reg [3:0] req_wstrb=15;
wire [31:0] rsp_data;
wire rsp_error;
ysyx_clint dut (.*);
always #5 clk=~clk;
task tick; @(posedge clk); #1; endtask
task put(input [31:0] a,input [31:0] d);
    @(negedge clk); req_valid=1;req_write=1;req_addr=a;req_wdata=d;
    #1; assert(!rsp_error) else $fatal(1,"word write rejected");
    tick();
    assert(rsp_data==d) else $fatal(1,"word write failed or lost to tick");
    @(negedge clk);req_valid=0;req_write=0;
endtask
initial begin
    tick();rst_n=1;
    put(32'h0200bffc,32'h12345678);
    put(32'h0200bff8,32'hffffffff);
    // Write wins over tick; next tick carries once into high half.
    req_addr=32'h0200bffc;
    #1;assert(rsp_data==32'h12345678) else $fatal(1,"half preservation");
    tick();assert(rsp_data==32'h12345679) else $fatal(1,"counter rollover");
    req_addr=32'h0200bff8;
    #1;assert(rsp_data==0) else $fatal(1,"low rollover");
    @(negedge clk);req_size=0;req_valid=1;req_write=1;req_wdata=32'hdeadbeef;
    #1;assert(rsp_error) else $fatal(1,"byte accepted");
    tick();req_write=0;req_size=2;
    #1;assert(rsp_data==1) else $fatal(1,"invalid write changed counter");
    @(negedge clk);req_write=1;req_wstrb=1;
    #1;assert(rsp_error) else $fatal(1,"partial strobe accepted");
    tick();req_write=0;req_wstrb=15;
    #1;assert(rsp_data==2) else $fatal(1,"partial write effect");
    req_addr=32'h02004000;
    #1;assert(rsp_error && rsp_data==0) else $fatal(1,"S5 register prematurely implemented");
    req_addr=32'h0200bff9;
    #1;assert(rsp_error) else $fatal(1,"bad offset accepted");
    @(negedge clk);rst_n=0;req_addr=32'h0200bffc;req_valid=0;
    tick();assert(rsp_data==0) else $fatal(1,"reset high");
    req_addr=32'h0200bff8;
    #1;assert(rsp_data==0) else $fatal(1,"reset low");
    $display("CLINT: PASS word read/write, rollover, write priority, rejected accesses, reset");
    $finish;
end
endmodule
