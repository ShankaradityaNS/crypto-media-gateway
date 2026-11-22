//Execute stage. ALU, operand selection, branch resolution
//Purely combinational; the pipeline register lives outside
module core_ex import core_pkg::*; (
    input logic [XLEN-1:0] pc,
    input logic [XLEN-1:0] rs1_data,
    input logic [XLEN-1:0] rs2_data,
    input logic [XLEN-1:0] imm,

    input alu_op_e          alu_op,
    input logic             alu_src_imm,
    input logic             alu_src_pc,
    input logic             is_word_op,
    input logic             is_branch,
    input logic             is_jump,
    input logic             is_jalr,
    input logic [2:0]       funct3,

    output logic [XLEN-1:0] alu_result,
    output logic            branch_taken,
    output logic [XLEN-1:0] branch_target
);

    logic [XLEN-1:0] op_a, op_b;
    assign op_a = alu_src_pc ? pc : rs1_data;
    assign op_b = alu_src_imm ? imm : rs2_data;

    //Shift amounts are masked here, not in decode: the immediate
    //decoder produces a full 12-bit value for SLLI, whose upper bits
    //are actually funct7. RV64 shifts use 6 bits, word shifts use 5.
    logic [5:0] shamt6;
    logic [4:0] shamt5;
    assign shamt6 = op_b[5:0];
    assign shamt5 = op_b[4:0];

    //---64-bit datapath
    logic [XLEN-1:0] res64;
    always_comb begin
        res64 = '0;
        unique case (alu_op)
            ALU_ADD:        res64 = op_a + op_b;
            ALU_SUB:        res64 = op_a - op_b;
            ALU_SLL:        res64 = op_a << shamt6;
            ALU_SLT:        res64 = {63'b0, ($signed(op_a) < $signed(op_b))};
            ALU_SLTU:       res64 = {63'b0, (op_a < op_b)};
            ALU_XOR:        res64 = op_a ^ op_b;
            ALU_SRL:        res64 = op_a >> shamt6;
            ALU_SRA:        res64 = $signed(op_a) >>> shamt6;
            ALU_OR:         res64 = op_a | op_b;
            ALU_AND:        res64 = op_a & op_b;
            ALU_PASS_B:     res64 = op_b;
        endcase
    end

    //---32-bit datapath
    //Only ADD, SUB, SLL, SRL, and SRA have W variants in RV64
    //These cannot be derived by truncating res64: SRLW must shift a 
    //32-bit value, filling from bit 31 not from bit 63
    logic [31:0] res32;
    always_comb begin
        unique case (alu_op)
            ALU_SLL:    res32 = op_a[31:0] << shamt5;
            ALU_SRL:    res32 = op_a[31:0] >> shamt5;
            ALU_SRA:    res32 = $signed(op_a[31:0]) >>> shamt5;
            ALU_SUB:    res32 = op_a[31:0] - op_b[31:0];
            default:    res32 = op_a[31:0] + op_b[31:0];
        endcase
    end

    logic [XLEN-1:0] arith_result;
    assign arith_result = is_word_op ? {{32{res32[31]}}, res32} : res64;

    //JAL and JALR  write the return address, not the ALU result
    assign alu_result = is_jump ? (pc + 64'd4) : arith_result;

    //branch resolution
    logic beq, blt, bltu;
    assign beq = (rs1_data == rs2_data);
    assign blt = ($signed(rs1_data) < $signed(rs2_data));
    assign bltu = (rs1_data < rs2_data);

    logic cond;
    always_comb begin
        unique case (funct3)
            3'b000: cond = beq;     //BEQ
            3'b001: cond = !beq;    //BNE
            3'b100: cond = blt;     //BLT
            3'b101: cond = !blt;    //BGE
            3'b110: cond = bltu;    //BLTU
            3'b111: cond = !bltu;   //BGEU
            default: cond = 1'b0;
        endcase
    end

    assign branch_taken = (is_branch && cond) || is_jump;

    //JALR targets rs1+imm with bit 0 forced to zero; everything
    //else targets pc+imm
    assign branch_target = is_jalr ? ((rs1_data + imm) & ~64'd1) : (pc+imm);

    endmodule
    
    