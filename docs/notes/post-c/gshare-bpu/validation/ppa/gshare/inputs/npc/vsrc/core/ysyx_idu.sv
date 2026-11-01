module
    ysyx_idu (
        input       [31 : 0]    inst,

        output reg  [2 : 0]     imm_type,   // imm type, total 6
        output                  alu_src0_sel, alu_src1_sel,
        output reg  [4 : 0]     alu_ctrl,
        output      [2 : 0]     br_type,
        output                  br_en, jal, jalr,
        output                  rf_we,
        output reg  [1 : 0]     rf_wd_sel,
        output      [2 : 0]     dm_type,
        output                  dm_we_raw,
        output                  dm_re_raw, 
        output                  csr_we,     // csr write enable
        output      [12-1:0]    csr_addr,   // csr addr
        output                  trap_valid,
        output      [32-1:0]    trap_cause,
        output                  mret_valid
    );

    // RV32E + six Zicsr operations over the implemented machine CSR bank.
    // All unrecognized encodings trap; M/C and x16-x31 are not implemented.
    wire [6:0] opcode = inst[6:0];
    wire [2:0] funct3 = inst[14:12];
    wire [6:0] funct7 = inst[31:25];
    wire is_r_type = opcode == 7'h33;
    wire is_i_basic = opcode == 7'h13;
    wire is_load = opcode == 7'h03;
    wire is_store = opcode == 7'h23;
    wire is_branch = opcode == 7'h63;
    wire is_lui = opcode == 7'h37;
    wire is_auipc = opcode == 7'h17;
    wire is_jal = opcode == 7'h6f;
    wire is_jalr = opcode == 7'h67;
    wire is_csr = opcode == 7'h73 &&
                  (funct3 == 3'b001 || funct3 == 3'b010 || funct3 == 3'b011 ||
                   funct3 == 3'b101 || funct3 == 3'b110 || funct3 == 3'b111);
    wire is_ecall = inst == 32'h00000073;
    wire is_mret = inst == 32'h30200073;
    // Explicit project execution-environment convention: harness termination.
    // This encoding is not claimed as a hardware breakpoint exception.
    wire is_ebreak = inst == 32'h00100073;
    // Data operations are serialized through LSU completion; FENCE is a no-op.
    // Base FENCE ignores fm/rs1/rd, including reserved configurations. No FENCE.I.
    wire is_fence = opcode == 7'h0f && funct3 == 3'b000;
    wire csr_exists = inst[31:20] == 12'h300 || inst[31:20] == 12'h305 ||
                      inst[31:20] == 12'h304 || inst[31:20] == 12'h344 ||
                      inst[31:20] == 12'h341 || inst[31:20] == 12'h342;
    wire uses_rd = is_r_type || is_i_basic || is_load || is_lui || is_auipc ||
                   is_jal || is_jalr || is_csr;
    wire uses_rs1 = is_r_type || is_i_basic || is_load || is_store || is_branch ||
                    is_jalr || (is_csr && !funct3[2]);
    wire uses_rs2 = is_r_type || is_store || is_branch;
    wire regs_legal = !(uses_rd && inst[11]) && !(uses_rs1 && inst[19]) &&
                       !(uses_rs2 && inst[24]);
    wire encoding_legal =
        (is_r_type && (funct7 == 7'h00 ||
                     (funct7 == 7'h20 && (funct3 == 0 || funct3 == 5)))) ||
        (is_i_basic && ((funct3 != 1 && funct3 != 5) ||
                       (funct3 == 1 && funct7 == 0) ||
                       (funct3 == 5 && (funct7 == 0 || funct7 == 7'h20)))) ||
        (is_load && (funct3 == 0 || funct3 == 1 || funct3 == 2 || funct3 == 4 || funct3 == 5)) ||
        (is_store && (funct3 == 0 || funct3 == 1 || funct3 == 2)) ||
        (is_branch && (funct3 == 0 || funct3 == 1 || funct3 >= 4)) ||
        is_lui || is_auipc || is_jal || (is_jalr && funct3 == 0) ||
        (is_csr && csr_exists) || is_ecall || is_mret || is_ebreak || is_fence;
    wire legal = encoding_legal && regs_legal;

    always @(*) begin
        imm_type = 3'd0;
        if (is_i_basic || is_load || is_jalr) imm_type = 3'd1;
        if (is_store) imm_type = 3'd2;
        if (is_branch) imm_type = 3'd3;
        if (is_lui || is_auipc) imm_type = 3'd4;
        if (is_jal) imm_type = 3'd5;
        alu_ctrl = 5'b00000;
        if (is_lui) alu_ctrl = 5'b11000;
        if (is_r_type) alu_ctrl = {funct7[5], 1'b0, funct3};
        if (is_i_basic) alu_ctrl = {2'b00, funct3};
        if (is_i_basic && funct3 == 5 && funct7 == 7'h20) alu_ctrl = 5'b10101;
        rf_wd_sel = 2'd0;
        if (is_jal || is_jalr) rf_wd_sel = 2'd1;
        if (is_load) rf_wd_sel = 2'd2;
        if (is_csr) rf_wd_sel = 2'd3;
    end

    assign alu_src0_sel = is_auipc || is_jal || is_branch;
    assign alu_src1_sel = is_i_basic || is_load || is_store || is_branch ||
                          is_lui || is_auipc || is_jal || is_jalr;
    assign br_type = funct3;
    assign br_en = legal && is_branch;
    assign jal = legal && is_jal;
    assign jalr = legal && is_jalr;
    assign rf_we = legal && uses_rd;
    assign dm_type = funct3;
    assign dm_we_raw = legal && is_store;
    assign dm_re_raw = legal && is_load;
    // CSRRW[I] always writes; CSRRS/RC[I] suppress writes for zero register/zimm.
    // This tests the encoded operand, not the value in a nonzero register.
    assign csr_we = legal && is_csr && (funct3[1:0] == 2'b01 || inst[19:15] != 0);
    assign csr_addr = is_csr ? inst[31:20] : 12'b0;
    assign trap_valid = !legal || is_ecall;
    assign trap_cause = !legal ? 32'd2 : (is_ecall ? 32'd11 : 32'd0);
    assign mret_valid = legal && is_mret;
endmodule
