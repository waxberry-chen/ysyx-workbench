`default_nettype none

module ysyx_core #(
        parameter PC_RST = 32'H80000000,
        parameter I_CACHE_DEPTH = 8
    )
    (
        input           clk, rstn,
        output  [31: 0] pc_cur, inst,
        output          commit_wb, commit_is_mmio,

        // instruction memory request/response interface
        output           if_req_valid, 
        input            if_req_ready, 
        output [32-1: 0] if_req_addr,
        input            if_rsp_valid, 
        output           if_rsp_ready, 
        input  [32-1: 0] if_rsp_data,

        // data memory request/response interface
        output           d_req_valid,
        input            d_req_ready,
        output           d_req_write,
        output [32-1: 0] d_req_addr,
        output [2-1: 0]  d_req_size,
        output [32-1: 0] d_req_wdata,
        input            d_rsp_valid,
        output           d_rsp_ready,
        input  [32-1: 0] d_rsp_data

        `ifdef DEBUG
            ,
            output          putchar,
            output  [7 : 0] c
        `endif
    );

    wire        [31 : 0]                        pc_next;//, pc_cur;
//    wire        [31 : 0]                        inst;
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
    wire                                        lsu_op_valid, lsu_op_ready;
    wire                                        lsu_rsp_valid, lsu_rsp_ready;

    // single cycle, always commit
    // assign commit_wb = 1;

    // load/store mmio address, used by rtl harness to skip ref
    assign commit_is_mmio = (inst[6:0] == 7'b0000011 || inst[6:0] == 7'b0100011) && alu_res[31:28] == 4'ha;

    // // program counter
    ysyx_gnrl_dfflrs #(
        .DW(32),
        .RST(PC_RST)
    ) u_pc (
        .lden   (commit_wb),
        .dnxt   (pc_next), 
        .qout   (pc_cur),
        .clk    (clk),
        .rst_n  (rstn)
    );
    
    ysyx_main_fsm u_ysyx_main_fsm(
        .clk          	(clk           ),
        .rst_n        	(rstn         ),
        .if_req_valid 	(if_req_valid  ),
        .if_req_ready 	(if_req_ready  ),
        .if_rsp_valid 	(if_rsp_valid  ),
        .if_rsp_ready 	(if_rsp_ready  ),
        .lsu_access     (dm_re | dm_we_raw),
        .lsu_op_valid   (lsu_op_valid  ),
        .lsu_op_ready   (lsu_op_ready  ),
        .lsu_rsp_valid  (lsu_rsp_valid ),
        .lsu_rsp_ready  (lsu_rsp_ready ),
        .commit_wb    	(commit_wb     )
    );
    
    wire inst_update;
    assign if_req_addr = pc_cur;
    assign inst_update = if_rsp_valid & if_rsp_ready;

    // inst register
    ysyx_gnrl_dfflrs #(
        .DW(32),
        .RST(32'h00000013)  // nop
    ) u_inst_reg (
        .lden   (inst_update),
        .dnxt   (if_rsp_data), 
        .qout   (inst),
        .clk    (clk),
        .rst_n  (rstn)
    );

    wire csr_we;
    wire [12-1:0] csr_addr;
    wire [32-1:0] trap_cause;
    wire trap_valid, mret_valid;

    ysyx_idu inst_decoder (
        .inst           (inst),
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

    assign rf_rs1   =   inst[19 : 15];
    assign rf_rs2   =   inst[24 : 20];
    assign rf_rd    =   inst[11 : 7];
    ysyx_regfile ysyx_regfile (
        .clk    (clk    ),
        .rf_rs1 (rf_rs1 ),
        .rf_rs2 (rf_rs2 ),
        .rf_rd  (rf_rd  ),
        .rf_we  (rf_we & commit_wb  ),
        .rf_wd  (rf_wd  ),
        .rf_rd0 (rf_rd0 ),
        .rf_rd1 (rf_rd1 )
    );

    // csr write back: normal write
    wire [32-1:0] csr_rdata, csr_wdata;
    assign csr_wdata =  (inst[6:0]==7'h73)?
                        (inst[14:12]==3'b010)?(rf_rd0|csr_rdata):(inst[14:12]==3'b001)?rf_rd0:32'h0:32'h0;

    wire [32-1:0] trap_target, mret_target;

    ysyx_csr ysyx_csr(
        .clk    (clk), 
        .rst_n  (rstn),
        // csr r/w interface
        .csr_addr   (csr_addr),
        .csr_wdata  (csr_wdata),
        .csr_we     (csr_we & commit_wb),
        .csr_rdata  (csr_rdata),
        // trap event
        .trap_valid (trap_valid & commit_wb),
        .trap_epc   (pc_cur),
        .trap_cause (trap_cause),
        .mret_valid (mret_valid & commit_wb),
        // addr targets
        .trap_target(trap_target),
        .mret_target(mret_target)
    );

    ysyx_gen_imm gen_imm (
        .inst       (inst),
        .imm_type   (imm_type),
        
        .imm        (imm)
    );

    ysyx_gnrl_data_mux #(
        .DW (32), 
        .N  (2)
    ) alu_sel0 (
        .out_data   (alu_src0),
        .in_data    ({pc_cur, rf_rd0}), // high->1, low->0
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

    assign pc_add4 = pc_cur + 32'H4;
    assign pc_jal_br = alu_res;
    assign pc_jalr = alu_res & 32'HFFFFFFFE;
    // decide next pc
    assign pc_next = (jal | br) ? pc_jal_br : (jalr ? pc_jalr : (trap_valid ? trap_target: (mret_valid ? mret_target : pc_add4)));

    ysyx_lsu u_ysyx_lsu (
        .clk         (clk          ),
        .rst_n       (rstn         ),
        .op_valid    (lsu_op_valid ),
        .op_ready    (lsu_op_ready ),
        .op_write    (dm_we_raw    ),
        .op_addr     (alu_res      ),
        .op_type     (dm_type      ),
        .op_wdata    (rf_rd1       ),
        .rsp_valid   (lsu_rsp_valid),
        .rsp_ready   (lsu_rsp_ready),
        .rsp_rdata   (dm_rd        ),
        .d_req_valid (d_req_valid  ),
        .d_req_ready (d_req_ready  ),
        .d_req_write (d_req_write  ),
        .d_req_addr  (d_req_addr   ),
        .d_req_size  (d_req_size   ),
        .d_req_wdata (d_req_wdata  ),
        .d_rsp_valid (d_rsp_valid  ),
        .d_rsp_ready (d_rsp_ready  ),
        .d_rsp_data  (d_rsp_data   )
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
    assign putchar = dm_we_raw && commit_wb && (&alu_res);
    assign c = rf_rd1[7 : 0];
`endif

endmodule

`default_nettype wire
