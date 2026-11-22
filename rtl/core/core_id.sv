//Decode stage. Extracts addresses, immediate and control signals.
module core_id import core_pkg::*; (
    input logic [ILEN-1:0] if_instr,

    //register addresses - fixed bit positions in every format
    output logic [RAW-1:0]  rs1_addr,
    output logic [RAW-1:0]  rs2_addr,
    output logic [RAW-1:0]  rd_addr,

    //immediate from the core_imm submodule
    output logic [XLEN-1:0] imm,

    //control signals for the later stages
    output alu_op_e alu_op,
    output logic alu_src_imm,
    output logic alu_src_pc,
    output logic is_word_op,
    output logic is_branch,
    output logic is_jump,
    output logic mem_read,
    output logic mem_write,
    output logic reg_write,
    output logic wb_from_mem,

    output logic is_jalr,
    output logic [2:0] funct3_o,

    output logic [11:0] csr_addr,
    output csr_op_e csr_op,
    output logic    csr_imm_sel,

    output logic    illegal_instr,
    output logic    is_ecall,
    output logic    is_ebreak,
    output logic    is_mret
);

    assign rs1_addr = if_instr[19:15];
    assign rs2_addr = if_instr[24:20];
    assign rd_addr = if_instr[11:7];
    assign csr_addr = if_instr[31:20];

    assign funct3_o = funct3;

    core_imm u_imm (
        .instr (if_instr),
        .imm (imm)
    );

    logic [2:0] funct3;
    assign funct3 = if_instr[14:12];

    always_comb begin
            //safe defaults: an unrecognised instruction does nothing
            alu_op          = ALU_ADD;
            alu_src_imm     = 1'b0;
            alu_src_pc     = 1'b0;
            is_word_op     = 1'b0;
            is_branch     = 1'b0;
            is_jump     = 1'b0;
            mem_read     = 1'b0;
            mem_write     = 1'b0;
            reg_write     = 1'b0;
            wb_from_mem     = 1'b0;
            is_jalr         = 1'b0;
            csr_op          = CSR_NONE;
            csr_imm_sel     = 1'b0;
            illegal_instr   = 1'b1;
            is_ecall        = 1'b0;
            is_ebreak       = 1'b0;
            is_mret         = 1'b0;

    unique case (if_instr[6:0])
        OP_LUI: begin
            illegal_instr   = 1'b0;
            alu_op = ALU_PASS_B; alu_src_imm = 1'b1; reg_write = 1'b1;
        end
        OP_AUIPC: begin
            illegal_instr   = 1'b0;
            alu_op = ALU_ADD; alu_src_imm = 1'b1;
            alu_src_pc = 1'b1; reg_write = 1'b1;
        end
        OP_JAL: begin
            illegal_instr   = 1'b0;
            is_jump = 1'b1; reg_write = 1'b1;
        end
        OP_JALR: begin
            illegal_instr   = 1'b0;
            is_jump = 1'b1; alu_src_imm = 1'b1; reg_write = 1'b1;
            is_jalr = 1'b1;
        end
        OP_BRANCH: begin
            illegal_instr   = 1'b0;
            is_branch = 1'b1;
        end
        OP_LOAD: begin
            illegal_instr   = 1'b0;
            alu_op = ALU_ADD; alu_src_imm = 1'b1;
            mem_read = 1'b1; reg_write = 1'b1; wb_from_mem = 1'b1;
        end
        OP_STORE: begin
            illegal_instr   = 1'b0;
            alu_op = ALU_ADD; alu_src_imm = 1'b1; mem_write = 1'b1;
        end
        OP_IMM, OP_IMM_W: begin
            illegal_instr   = 1'b0;
            alu_src_imm = 1'b1; reg_write = 1'b1;
            is_word_op = (if_instr[6:0] == OP_IMM_W);
            unique case (funct3)
                3'b000: alu_op = ALU_ADD;           //ADDI
                3'b010: alu_op = ALU_SLT;           //SLTI
                3'b011: alu_op = ALU_SLTU;          //SLTIU
                3'b100: alu_op = ALU_XOR;           //XORI
                3'b110: alu_op = ALU_OR;            //ORI
                3'b111: alu_op = ALU_AND;           //ANDI
                3'b001: alu_op = ALU_SLL;           //SLLI
                3'b101: alu_op = if_instr[30] ? ALU_SRA     //SRAI
                                              : ALU_SRL;    //SRLI
            endcase
        end

        OP_REG, OP_REG_W: begin
            illegal_instr   = 1'b0;
            reg_write = 1'b1;
            is_word_op = (if_instr[6:0] == OP_REG_W);
            unique case (funct3)
                3'b000: alu_op = if_instr[30] ? ALU_SUB : ALU_ADD;
                3'b001: alu_op = ALU_SLL;
                3'b010: alu_op = ALU_SLT;
                3'b011: alu_op = ALU_SLTU;
                3'b100: alu_op = ALU_XOR;
                3'b101: alu_op = if_instr[30] ? ALU_SRA : ALU_SRL;
                3'b110: alu_op = ALU_OR;
                3'b111: alu_op = ALU_AND;
            endcase
        end

        OP_SYSTEM: begin
            //Bit 2 of funct3 selects the immediate form (csrrwi etc)
            if (funct3 == 3'b000) begin
                unique case(if_instr[31:20])
                    SYS_ECALL: begin
                        is_ecall = 1'b1;
                        illegal_instr = 1'b0;
                    end
                    SYS_EBREAK: begin
                        is_ebreak = 1'b1;
                        illegal_instr = 1'b0;
                    end
                    SYS_MRET: begin
                        is_mret = 1'b1;
                        illegal_instr = 1'b0;
                    end
                    default: ;      // stays illegal
                endcase
            end else begin
                illegal_instr = 1'b0;
                reg_write = 1'b1;
                csr_imm_sel = funct3[2];
                unique case (funct3[1:0])
                    2'b01:      csr_op = CSR_RW;
                    2'b10:      csr_op = CSR_RS;
                    2'b11:      csr_op = CSR_RC;
                    default:    csr_op = CSR_NONE;
            endcase
        end
        end
        OP_MISC_MEM: begin
            //fence and fence.i: no caches, so nothing to order or
            // flush. Decoded as legal, executes as a nop
            illegal_instr = 1'b0;
        end
        default: ;      //illegal not yet implemented
    endcase
    end
     
endmodule
