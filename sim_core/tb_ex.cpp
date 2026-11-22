#include <verilated.h>
#include "Vcore_ex.h"
#include <cstdio>

static Vcore_ex* top;
static int errors = 0;

//ALU op encodings follow declaration order in core_pkg.sv
enum {ADD=0, SUB=1, SLL=2, SLT=3, SLTU=4, XOR_=5, SRL=6, SRA=7, OR_=8, AND_=9, PASS_B=10};

static void clear() {
    top->pc = 0; top->rs1_data = 0; top->rs2_data = 0; top->imm = 0;
    top->alu_op = ADD; top->alu_src_imm = 0; top->alu_src_pc = 0;
    top->is_word_op = 0;top->is_branch = 0; top->is_jump = 0;
    top->is_jalr = 0; top->funct3 = 0;
}

//ALU check: rs1 op rs2, results compared
static void alu(const char* what, int op, uint64_t a,
                 uint64_t b, uint64_t want, int word = 0)
{
    clear();
    top->alu_op = op; top->rs1_data = a; top->rs2_data = b;
    top->is_word_op = word;
    top->eval();
    if(top->alu_result != want)
    {
        printf("[TB] Fail %-18s a=%016lx b=%016lx got=%016lx want=%016lx\n", what, a, b,
                (uint64_t)top->alu_result, want);
                errors++;
    }
}

//branch check
static void br(const char* what, int f3, uint64_t a, uint64_t b, uint64_t pc,
                uint64_t imm, int want_taken, uint64_t want_tgt)
{
    clear();
    top->is_branch = 1; top->funct3 = f3;
    top->rs1_data = a; top->rs2_data = b;
    top->pc = pc; top->imm = imm;
    top->eval();
    if(top->branch_taken != want_taken)
    {
        printf("[TB] Fail %-18s taken=%d want=%d\n", what
        , (int)top->branch_taken, want_taken);
        errors++;
    }
    else if (want_taken && top->branch_target != want_tgt)
    {
        printf("[TB] Fail %-18s target=%016lx want=%016lx\n", what,
        (uint64_t)top->branch_target, want_tgt);
        errors++;
    }
}

int main(int argc, char** argv)
{
    Verilated::commandArgs(argc,argv);
    top = new Vcore_ex;

    //basic 64-bit arithmetic
    alu("add",      ADD, 5, 3, 8);
    alu("add neg",  ADD, 5, -3ULL, 2);
    alu("sub",      SUB, 5, 3, 2);
    alu("sub neg",  SUB, 3, 5, -2ULL);
    alu("xor",      XOR_, 0xF0F0, 0x0FF0, 0xFF00);
    alu("or",       OR_, 0xF000, 0x000F, 0xF00F);
    alu("and",      AND_, 0xFF0F, 0x0FF0, 0x0F00);

    //shifts 64-bit
    alu("sll",      SLL, 1,4, 0x10);
    alu("srl",      SRL, 0x8000000000000000ULL, 4, 0x0800000000000000ULL);
    alu("sra neg",  SRA, 0x8000000000000000ULL, 4, 0xF800000000000000ULL);
    //shift amount must be masked to 6 bits: 65 & 63 = 1
    alu("sll mask", SLL, 1, 65, 2);

    //comparision
    alu("slt true", SLT, -1ULL, 1, 1);      //signed: -1 < 1
    alu("slt false", SLT, 1, -1ULL, 0); 
    alu("sltu false", SLTU, -1ULL, 1, 0);   //unsigned: huge > 1
    alu("sltu true", SLTU, 1, -1ULL, 1);

    //word operations
    //addw: low 32 bits added result sign extended from bi 31
    alu("addw pos",     ADD, 1, 2,3 ,1);
    alu("addw sext",    ADD, 0x7FFFFFFF, 1, 0xFFFFFFFF80000000ULL, 1);
    //srlw of 0x80000000 by 1 must fill from bit 31 not bit 63
    alu("srlw",         SRL, 0x0000000080000000ULL, 1, 0x0000000040000000ULL, 1);
    //sraw of a negative 32-bit value sign-extends within 32 bits first
    alu("sraw",         SRA, 0x0000000080000000ULL, 1, 0xFFFFFFFFC0000000ULL, 1);
    //word shift amount masks to 5 bits: 33 & 31 = 1
    alu("sllw mask",    SLL, 1, 33, 2, 1);

    //branches
    br("beq taken",     0b000, 5, 5, 0x1000, 8, 1, 0x1008);
    br("beq not",       0b000, 5, 6, 0x1000, 8, 0, 0);
    br("bne taken",     0b001, 5, 6, 0x1000, 8, 1, 0x1008);
    br("blt signed",    0b100, -1ULL, 1, 0x1000, 8, 1, 0x1008);
    br("bge signed",    0b101, 1, -1ULL, 0x1000, 8, 1, 0x1008);
    br("bltu unsign",   0b110, 1, -1ULL, 0x1000, 8, 1, 0x1008);
    br("bgeu unsign",   0b111, -1ULL, 1, 0x1000, 8, 1, 0x1008);
    br("branch back", 0b000, 5, 5, 0x1000, -8ULL, 1, 0x0FF8);

    //jumps
    clear();
    top->is_jump = 1; top->pc = 0x1000; top->imm = 0x20;
    top->eval();
    if(top->alu_result != 0x1004)
    {
        printf("[TB] Fail jal link: got %016lx want 1004\n", (uint64_t)top->alu_result);
        errors++;
    }
    if(!top->branch_taken || top->branch_target != 0x1020)
    {
        printf("[TB] Fail jal target: taken=%d tgt=%016lx\n", (int)top->branch_taken,
                (uint64_t)top->branch_target);
                errors++;
    }

    //jalr: rs1+imm with bit 0 cleared
    clear();
    top->is_jump = 1; top->is_jalr = 1; top->alu_src_imm = 1;
    top->pc = 0x1000; top->rs1_data = 0x2001; top->imm = 0x4;
    top->eval();
    if(top->branch_target != 0x2004)
    {
        printf("[TB] Fail jalr target: go %016lx want 2004\n", (uint64_t)top->branch_target);
        errors++;
    }

    //operand selection
    //auipc: pc + imm
    clear();
    top->alu_src_pc = 1; top->alu_src_imm = 1;
    top->pc = 0x1000; top->imm = 0x2000; top->rs1_data = 0xDEAD;
    top->eval();
    if(top->alu_result != 0x3000)
    {
        printf("[TB] Fail auipc: got %016lx want 3000\n", (uint64_t)top->alu_result);
        errors++;
    }

    printf("[TB] %s (%d errors)\n", errors ? "FAIL" : "PASS", errors);
    delete top;
    return errors ? 1 : 0;
}