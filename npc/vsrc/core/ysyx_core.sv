`default_nettype none

module ysyx_core #(
        parameter PC_RST = 32'H80000000,
        parameter I_CACHE_DEPTH = 8
    )
    (
        input           clk, rst_n,
        output  [31: 0] commit_pc, commit_inst,
        output          commit_valid, commit_is_mmio,

        // instruction memory request/response interface
        output           imem_req_valid,
        input            imem_req_ready,
        output [32-1: 0] imem_req_addr,
        input            imem_rsp_valid,
        output           imem_rsp_ready,
        input  [32-1: 0] imem_rsp_data,

        // data memory request/response interface
        output           dmem_req_valid,
        input            dmem_req_ready,
        output           dmem_req_write,
        output [32-1: 0] dmem_req_addr,
        output [2-1: 0]  dmem_req_size,
        output [32-1: 0] dmem_req_wdata,
        input            dmem_rsp_valid,
        output           dmem_rsp_ready,
        input  [32-1: 0] dmem_rsp_data

        `ifdef DEBUG
            ,
            output          putchar,
            output  [7 : 0] c
        `endif
    );

    wire        [31 : 0]                        pc_next;
    wire        [2 : 0]                         imm_type;
    wire                                        alu_src0_sel, alu_src1_sel;
    wire        [4 : 0]                         alu_ctrl;
    wire        [2 : 0]                         br_type;
    wire                                        br_en, jal, jalr;
    wire                                        rf_we;
    wire        [1 : 0]                         rf_wd_sel;
    wire        [2 : 0]                         dm_type;
    wire                                        dm_we_raw;
    wire        [4 : 0]                         rf_rs1, rf_rs2, rf_rd;
    wire        [31 : 0]                        rf_wd;
    wire        [31 : 0]                        rf_rd0, rf_rd1;
    wire        [31 : 0]                        imm;
    wire        [31 : 0]                        alu_src0, alu_src1;
    wire        [31 : 0]                        alu_res;
    wire                                        br;
    wire        [31 : 0]                        pc_add4, pc_jal_br, pc_jalr;
    wire        [31 : 0]                        dm_rd;
    wire                                        dm_re;
    wire                                        lsu_req_valid, lsu_req_ready;
    wire                                        lsu_rsp_valid, lsu_rsp_ready;

    // single cycle, always commit
    // assign commit_valid = 1;

    // load/store mmio address, used by rtl harness to skip ref
    assign commit_is_mmio = (commit_inst[6:0] == 7'b0000011 || commit_inst[6:0] == 7'b0100011) && alu_res[31:28] == 4'ha;

    // // program counter
    ysyx_gnrl_dfflrs #(
        .DW(32),
        .RST(PC_RST)
    ) u_pc (
        .lden   (commit_valid),
        .dnxt   (pc_next), 
        .qout   (commit_pc),
        .clk    (clk),
        .rst_n  (rst_n)
    );
    
    ysyx_main_fsm u_ysyx_main_fsm(
        .clk          	(clk           ),
        .rst_n        	(rst_n         ),
        .imem_req_valid(imem_req_valid),
        .imem_req_ready(imem_req_ready),
        .imem_rsp_valid(imem_rsp_valid),
        .imem_rsp_ready(imem_rsp_ready),
        .lsu_access     (dm_re | dm_we_raw),
        .lsu_req_valid  (lsu_req_valid ),
        .lsu_req_ready  (lsu_req_ready ),
        .lsu_rsp_valid  (lsu_rsp_valid ),
        .lsu_rsp_ready  (lsu_rsp_ready ),
        .commit_valid 	(commit_valid  )
    );
    
    wire inst_update;
    assign imem_req_addr = commit_pc;
    assign inst_update = imem_rsp_valid & imem_rsp_ready;

    // inst register
    ysyx_gnrl_dfflrs #(
        .DW(32),
        .RST(32'h00000013)  // nop
    ) u_inst_reg (
        .lden   (inst_update),
        .dnxt   (imem_rsp_data),
        .qout   (commit_inst),
        .clk    (clk),
        .rst_n  (rst_n)
    );

    wire csr_we;
    wire [12-1:0] csr_addr;
    wire [32-1:0] trap_cause;
    wire trap_valid, mret_valid;

    ysyx_idu inst_decoder (
        .inst           (commit_inst),
        .imm_type       (imm_type),         // use to generate imm num
        .alu_src0_sel   (alu_src0_sel),
        .alu_src1_sel   (alu_src1_sel),
        .alu_ctrl       (alu_ctrl),         // to alu
        .br_type        (br_type),          // branch type
        .br_en          (br_en),            // branch enable
        .jal            (jal),              // to pc_sel
        .jalr           (jalr),
        .rf_we          (rf_we),            // regfile
        .rf_wd_sel      (rf_wd_sel),        // regfile write select
        .dm_type        (dm_type),          // to d-cache
        .dm_we_raw      (dm_we_raw),        // d-cache & putchar
        .dm_re_raw      (dm_re),            // to d-cache
        .csr_we         (csr_we),
        .csr_addr       (csr_addr),
        .trap_valid     (trap_valid),
        .trap_cause     (trap_cause),
        .mret_valid     (mret_valid)
    );

    assign rf_rs1   =   commit_inst[19 : 15];
    assign rf_rs2   =   commit_inst[24 : 20];
    assign rf_rd    =   commit_inst[11 : 7];
    ysyx_regfile ysyx_regfile (
        .clk    (clk    ),
        .rf_rs1 (rf_rs1 ),
        .rf_rs2 (rf_rs2 ),
        .rf_rd  (rf_rd  ),
        .rf_we  (rf_we & commit_valid),
        .rf_wd  (rf_wd  ),
        .rf_rd0 (rf_rd0 ),
        .rf_rd1 (rf_rd1 )
    );

    // csr write back: normal write
    wire [32-1:0] csr_rdata, csr_wdata;
    assign csr_wdata =  (commit_inst[6:0]==7'h73)?
                        (commit_inst[14:12]==3'b010)?(rf_rd0|csr_rdata):(commit_inst[14:12]==3'b001)?rf_rd0:32'h0:32'h0;

    wire [32-1:0] trap_target, mret_target;

    ysyx_csr ysyx_csr(
        .clk    (clk), 
        .rst_n  (rst_n),
        // csr r/w interface
        .csr_addr   (csr_addr),
        .csr_wdata  (csr_wdata),
        .csr_we     (csr_we & commit_valid),
        .csr_rdata  (csr_rdata),
        // trap event
        .trap_valid (trap_valid & commit_valid),
        .trap_epc   (commit_pc),
        .trap_cause (trap_cause),
        .mret_valid (mret_valid & commit_valid),
        // addr targets
        .trap_target(trap_target),
        .mret_target(mret_target)
    );

    ysyx_gen_imm gen_imm (
        .inst       (commit_inst),
        .imm_type   (imm_type),
        
        .imm        (imm)
    );

    ysyx_gnrl_data_mux #(
        .DW (32), 
        .N  (2)
    ) alu_sel0 (
        .out_data   (alu_src0),
        .in_data    ({commit_pc, rf_rd0}), // high->1, low->0
        .sel        (alu_src0_sel)
    );

    ysyx_gnrl_data_mux #(
        .DW (32), 
        .N  (2)
    ) alu_sel1 (
        .out_data   (alu_src1),
        .in_data    ({imm, rf_rd1}), 
        .sel        (alu_src1_sel)
    );

    ysyx_alu alu (
        .alu_src0   (alu_src0),
        .alu_src1   (alu_src1),
        .alu_ctrl   (alu_ctrl),
        .alu_res    (alu_res)
    );

    ysyx_branch branch (
        .br_type    (br_type),
        .br_en      (br_en),
        .rf_rd0     (rf_rd0),
        .rf_rd1     (rf_rd1),
        .br         (br)
    );

    assign pc_add4 = commit_pc + 32'H4;
    assign pc_jal_br = alu_res;
    assign pc_jalr = alu_res & 32'HFFFFFFFE;
    // decide next pc
    assign pc_next = (jal | br) ? pc_jal_br : (jalr ? pc_jalr : (trap_valid ? trap_target: (mret_valid ? mret_target : pc_add4)));

    ysyx_lsu u_ysyx_lsu (
        .clk         (clk          ),
        .rst_n       (rst_n        ),
        .req_valid   (lsu_req_valid),
        .req_ready   (lsu_req_ready),
        .req_write   (dm_we_raw    ),
        .req_addr    (alu_res      ),
        .req_type    (dm_type      ),
        .req_wdata   (rf_rd1       ),
        .rsp_valid   (lsu_rsp_valid),
        .rsp_ready   (lsu_rsp_ready),
        .rsp_rdata   (dm_rd        ),
        .dmem_req_valid(dmem_req_valid),
        .dmem_req_ready(dmem_req_ready),
        .dmem_req_write(dmem_req_write),
        .dmem_req_addr (dmem_req_addr ),
        .dmem_req_size (dmem_req_size ),
        .dmem_req_wdata(dmem_req_wdata),
        .dmem_rsp_valid(dmem_rsp_valid),
        .dmem_rsp_ready(dmem_rsp_ready),
        .dmem_rsp_data (dmem_rsp_data )
    );

    ysyx_gnrl_data_mux #(
        .DW(32),
        .N (4)
    ) rf_sel (
        .out_data   (rf_wd), 
        .in_data    ({csr_rdata, dm_rd, pc_add4, alu_res}),
        .sel        (rf_wd_sel)
    );

`ifdef DEBUG
    assign putchar = dm_we_raw && commit_valid && (&alu_res);
    assign c = rf_rd1[7 : 0];
`endif

endmodule

`default_nettype wire
