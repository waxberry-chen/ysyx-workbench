module ysyx_csr (
    input           clk, 
    input           rst_n,
    input           timer_irq,
    output          interrupt_pending,
    // csr r/w interface
    input [12-1:0]  csr_addr,
    input [32-1:0]  csr_wdata,
    input           csr_we,
    output [32-1:0]  csr_rdata,
    // trap event
    input           trap_valid,
    input [32-1:0]  trap_epc,
    input [32-1:0]  trap_cause,
    input           mret_valid,
    // addr targets
    output [32-1:0] trap_target,
    output [32-1:0] mret_target
);

// DPI-C for CSRs
`ifndef SYNTHESIS
`ifdef NPC_SIM_DPI
import "DPI-C" function void set_csr_ptr(input logic [32-1:0] r1 [], input logic [32-1:0] r2 [],input logic [32-1:0] r3 [],input logic [32-1:0] r4 []);
`endif
`endif

// one-hot addr->idx
wire [4-1:0] csr_idx;
// one-hot we
wire [4-1:0] csr_idx_we;
// input pack
wire [32-1:0] csr_d [4-1:0];
// output pack
wire [32-1:0] csr_q [4-1:0];
// csrs
wire [32-1:0] csr_mstatus,csr_mtvec,csr_mepc,csr_mcause;

assign csr_idx[0] = (csr_addr == 12'h300);  // mstatus
assign csr_idx[1] = (csr_addr == 12'h305);
assign csr_idx[2] = (csr_addr == 12'h341);
assign csr_idx[3] = (csr_addr == 12'h342);

assign csr_idx_we[0] = (csr_idx[0] && csr_we) | trap_valid | mret_valid;    // mstatus
assign csr_idx_we[1] = (csr_idx[1] && csr_we);  // mtvec
assign csr_idx_we[2] = (csr_idx[2] && csr_we) | trap_valid;  // mepc
assign csr_idx_we[3] = (csr_idx[3] && csr_we) | trap_valid;  // mcause

wire [32-1:0] mstatus_trap, mstatus_mret;
assign mstatus_trap = {csr_mstatus[31:13], 2'b11, csr_mstatus[10:8], csr_mstatus[3], csr_mstatus[6:4], 1'b0, csr_mstatus[2:0]};
assign mstatus_mret = {csr_mstatus[31:13], 2'b11, csr_mstatus[10:8], 1'b1, csr_mstatus[6:4], csr_mstatus[7], csr_mstatus[2:0]};

// Minimal M-only contract: MPP is hardwired to M; only MIE/MPIE are writable.
// Timer only: unsupported interrupt bits read zero and ignore writes.
// mip.MTIP is read-only hardware state; a CSR write cannot acknowledge it.
reg [31:0] csr_mie;
wire [31:0] csr_mip = timer_irq ? 32'h80 : 32'b0;
assign interrupt_pending = csr_mstatus[3] && csr_mie[7] && timer_irq;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) csr_mie <= 32'b0;
    else if (csr_we && csr_addr == 12'h304) csr_mie <= csr_wdata & 32'h80;
end
wire [31:0] mstatus_write = (csr_wdata & 32'h00000088) | 32'h00001800;
assign csr_d[0] = trap_valid ? mstatus_trap : (mret_valid ? mstatus_mret : mstatus_write);
assign csr_d[1] = csr_wdata & 32'hfffffffc; // Direct mode only.
assign csr_d[2] = ((trap_valid) ? trap_epc : csr_wdata) & 32'hfffffffc; // IALIGN=32. low 2-bit may cause min capacitance
assign csr_d[3] = (trap_valid) ? trap_cause : csr_wdata;
// unused bits min capacitance DRC violations can be fixed by boundary optimization using compile_ultra in DC. 

genvar i;
generate
    for (i=0;i<4;i=i+1) begin:gen_csr
        // Keep exported CSR pointers backed by persistent register storage.
        ysyx_gnrl_dfflrs #(32, (i == 0 ? 32'h1800 : 32'b0))
            csr_dfflr (csr_idx_we[i], csr_d[i], csr_q[i], clk, rst_n);
    end
endgenerate

// csr unpack
assign csr_mstatus  = csr_q[0];
assign csr_mtvec    = csr_q[1];
assign csr_mepc     = csr_q[2];
assign csr_mcause   = csr_q[3];

`ifndef SYNTHESIS
`ifdef NPC_SIM_DPI
initial begin
    set_csr_ptr(csr_mstatus, csr_mtvec, csr_mepc, csr_mcause);
end
`endif
`endif

assign csr_rdata = csr_addr == 12'h304 ? csr_mie : csr_addr == 12'h344 ? csr_mip :
                  (csr_idx[3])?csr_mcause:(csr_idx[2])?csr_mepc:(csr_idx[1])?csr_mtvec:(csr_idx[0])?csr_mstatus:32'b0; // Unknown addresses never alias mstatus.
assign trap_target = csr_mtvec;
assign mret_target = csr_mepc;

endmodule
