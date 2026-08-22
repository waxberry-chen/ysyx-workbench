module
    ysyx_i_ram #(
        parameter DEPTH = 8
    )
    (
        input               rstn,
        input   [31 : 0]    addr,
        output  [31 : 0]    inst
    );

    // reg [31 : 0]    i_ram   [0 : (1 << DEPTH) - 1];

    import "DPI-C" function void pmem_read(input bit re, input int addr, input int mask, output int rword);
    
    wire re;
    assign re = rstn;

    reg [31:0] inst_r;
    assign inst = inst_r;

    always@(*) begin
        inst_r = 32'h00000013;    // nop
        if (re) pmem_read(1'h1, addr, 32'H4, inst_r);
    end

endmodule