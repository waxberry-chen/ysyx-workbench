module soc_delay_channel_tb;
    reg clock=0;
    always #5 clock=~clock;
    reg reset=1,valid=0,ready=0;
    wire sr,mv;
    reg [31:0] data=0;
    wire [31:0] result;
    int unsigned sent=0,received=0,cycles=0;
    bit offered=0;
    npc_soc_delay_channel dut(clock,reset,valid,sr,data,mv,ready,result);
    initial begin
        repeat(3) @(negedge clock);
        reset=0;
        while(received<1000) begin
            // Stable input until accepted; deterministic bubbles and stalls.
            if(sent<1000 && cycles%3!=0) offered=1;
            valid=offered;
            data=32'h5a000000^sent;
            ready=cycles%7<3;
            @(posedge clock);
            if(valid && sr) begin sent++;offered=0;end
            if(mv && ready) begin
                assert(result==(32'h5a000000^received)) else $fatal(1,"Lost/reordered payload");
                received++;
            end
            @(negedge clock);
            cycles++;
            assert(cycles<200000) else $fatal(1,"Unbounded channel delay");
        end
        valid=0; repeat(10) @(negedge clock);
        assert(sent==1000 && !mv && dut.accepted==1000 && dut.delivered==1000);
        $display("DELAY PASS sent=%0d received=%0d cycles=%0d",sent,received,cycles);
        $finish;
    end
endmodule
