module ysyx_core #(
        parameter PC_RST = 32'H80000000,
        parameter I_CACHE_DEPTH = 8,
        parameter D_CACHE_DEPTH = 8
    )
    (
        input           clk, rstn,
        output  [31: 0] pc_cur, inst,
        output          commit_wb, commit_is_mmio
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
    wire        [31 : 0]                        dm_rd_raw, dm_rd, dm_wd;
    wire        [31 : 0]                        dm_addr;
    wire                                        dm_we, dm_re;
    wire [1:0] mask;    

    // single cycle, always commit
    assign commit_wb = 1;

    // load/store mmio address, used by rtl harness to skip ref
    assign commit_is_mmio = (inst[6:0] == 7'b0000011 || inst[6:0] == 7'b0100011) && alu_res[31:28] == 4'ha;

    // // program counter
    ysyx_gnrl_dffrs #(
        .DW(32),
        .RST(32'h80000000)
    ) pc (
        .dnxt   (pc_next), 
        .qout   (pc_cur),
        .clk    (clk),
        .rst_n  (rstn)
    );
    
    // PC #(
    //     .PC_RST(32'h80000000)
    // ) pc (
    //     .clk(clk),
    //     .rstn(rstn),
    //     .pc_next(pc_next),
    //     .pc_cur(pc_cur)
    // );

    ysyx_i_ram #(
        .DEPTH(I_CACHE_DEPTH)
    ) i_ram (
        .rstn(rstn),
        .addr(pc_cur),
        .inst(inst)
    );


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
        .dm_re_raw      (dm_re)             // to d-cache
    );

    assign rf_rs1   =   inst[19 : 15];
    assign rf_rs2   =   inst[24 : 20];
    assign rf_rd    =   inst[11 : 7];
    ysyx_regfile reg_file (
        .clk    (clk    ),
        .rf_rs1 (rf_rs1 ),
        .rf_rs2 (rf_rs2 ),
        .rf_rd  (rf_rd  ),
        .rf_we  (rf_we  ),
        .rf_wd  (rf_wd  ),
        .rf_rd0 (rf_rd0 ),
        .rf_rd1 (rf_rd1 )
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
    assign pc_next = (jal | br) ? pc_jal_br : (jalr ? pc_jalr : pc_add4);

    ysyx_d_ram_ctrl #(
        .DEPTH(D_CACHE_DEPTH)
    ) d_ram_ctrl (
        .addr_raw(alu_res),
        .wd_raw(rf_rd1),
        .rd_raw(dm_rd_raw),
        .we_raw(dm_we_raw),
        .dm_type(dm_type),
        .addr(dm_addr),
        .wd(dm_wd),
        .rd(dm_rd),
        .we(dm_we),
        .mask(mask)
    );

    ysyx_d_ram #(
        .DEPTH(D_CACHE_DEPTH)
    ) d_ram (
        .clk(clk),
        .addr(dm_addr),
        .wd(dm_wd),
        .we(dm_we),
        .rd(dm_rd_raw),
        .re(dm_re),
        .mask(mask)
    );

    ysyx_gnrl_data_mux #(
        .DW(32),
        .N (4)
    ) rf_sel (
        .out_data   (rf_wd), 
        .in_data    ({32'h0, dm_rd, pc_add4, alu_res}),
        .sel        (rf_wd_sel)
    );

`ifdef DEBUG
    assign putchar = dm_we_raw && (&dm_addr);
    assign c = rf_rd1[7 : 0];
`endif

endmodule