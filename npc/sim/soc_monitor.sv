// Passive simulation-only binding. CPU BlackBox ABI and data path stay unchanged.
module npc_soc_cpu_monitor (
    input clock, reset,
    input commit_valid, input [31:0] pc, inst, a0,
    input [31:0] gpr [0:15],
    input [31:0] mstatus, mtvec, mepc, mcause,
    input exception, input [31:0] cause,
    input mem_valid, mem_write, mmio, input [31:0] mem_addr,
    input arvalid, arready, awvalid, awready, wvalid, wready,
    input rvalid, rready, bvalid, bready,
    input [31:0] araddr, awaddr, wdata, rdata,
    input [2:0] arsize, awsize, input [3:0] strb,
    input [1:0] rresp, bresp
);
// C++ asks for this snapshot after eval() has completed the committing edge,
// including nonblocking GPR/CSR/architectural-PC updates. No extra CPU ports.
import "DPI-C" context function void npc_soc_state_scope();
initial npc_soc_state_scope();
export "DPI-C" function npc_soc_state;
function int npc_soc_state(input int index);
    if (index >= 0 && index < 16) return int'(gpr[index]);
    case (index)
        16: return int'(pc);
        17: return int'(mstatus);
        18: return int'(mtvec);
        19: return int'(mepc);
        20: return int'(mcause);
        default: return 0;
    endcase
endfunction
import "DPI-C" function void npc_soc_commit(input int pc, inst, a0, flags, cause, addr);
import "DPI-C" function void npc_soc_bus(input int reset_active, flags, araddr, awaddr,
    wdata, rdata, arsize, awsize, strb, rresp, bresp);
always @(posedge clock) begin
    npc_soc_bus(int'(reset), int'({bvalid&&bready,rvalid&&rready,wvalid&&wready,
                 awvalid&&awready,arvalid&&arready}), araddr, awaddr,
                 wdata,rdata,int'(arsize),int'(awsize),int'(strb),int'(rresp),int'(bresp));
    if (!reset && commit_valid)
        npc_soc_commit(pc,inst,a0,int'({mmio,mem_write,mem_valid,exception}),cause,mem_addr);
end
endmodule
bind ysyx_25030087 npc_soc_cpu_monitor cpu_monitor (
    .clock(clock), .reset(reset),
    .commit_valid(subsystem.commit_valid), .pc(subsystem.commit_pc),
    .inst(subsystem.commit_inst), .a0(subsystem.cpu.core.u_gpr.reg_file[10]),
    .gpr(subsystem.cpu.core.u_gpr.reg_file),
    .mstatus(subsystem.cpu.core.u_csr.csr_mstatus),
    .mtvec(subsystem.cpu.core.u_csr.csr_mtvec),
    .mepc(subsystem.cpu.core.u_csr.csr_mepc),
    .mcause(subsystem.cpu.core.u_csr.csr_mcause),
    .exception(subsystem.commit_exception), .cause(subsystem.commit_exception_cause),
    .mem_valid(subsystem.commit_mem_valid), .mem_write(subsystem.commit_mem_write),
    .mmio(subsystem.commit_is_mmio), .mem_addr(subsystem.commit_mem_addr),
    .arvalid(io_master_arvalid), .arready(io_master_arready),
    .awvalid(io_master_awvalid), .awready(io_master_awready),
    .wvalid(io_master_wvalid), .wready(io_master_wready),
    .rvalid(io_master_rvalid), .rready(io_master_rready),
    .bvalid(io_master_bvalid), .bready(io_master_bready),
    .araddr(io_master_araddr), .awaddr(io_master_awaddr),
    .wdata(io_master_wdata), .rdata(io_master_rdata),
    .arsize(io_master_arsize), .awsize(io_master_awsize), .strb(io_master_wstrb),
    .rresp(io_master_rresp), .bresp(io_master_bresp)
);

// Read-only access to the actual upstream 8 KiB array for final comparison.
// Poisoning/data/bss initialization still use CPU stores through AXI.
module npc_soc_sram_monitor(input [31:0] mem [0:2047]);
import "DPI-C" context function void npc_soc_sram_scope();
initial npc_soc_sram_scope();
export "DPI-C" function npc_soc_sram_word;
function int npc_soc_sram_word(input int index);
    return int'(mem[index]);
endfunction
endmodule
bind mem_2048x32 npc_soc_sram_monitor sram_monitor(.mem(Memory));

// Observe actual UART register strobes (APB setup phase), not CPU intent.
module npc_soc_uart_monitor (
    input clock,reset,reg_we,reg_re,
    input [2:0] addr, input [7:0] wdata,rdata
);
import "DPI-C" function void npc_soc_uart(input int write_access,addr,data);
always @(posedge clock) if (!reset && (reg_we || reg_re))
    npc_soc_uart(int'(reg_we),int'(addr),reg_we ? int'(wdata) : int'(rdata));
endmodule
bind uart_top_apb npc_soc_uart_monitor uart_monitor (
    .clock(clock),.reset(reset),.reg_we(reg_we),.reg_re(reg_re),
    .addr(reg_adr),.wdata(reg_dat8_w),.rdata(reg_dat8_r)
);
