#include <verilated.h>
#include "Vcore_id.h"
#include <cstdio>

static Vcore_id* top;
static int errors = 0;


// expected control bits, in a struct so one call checks them all
struct Ctrl {
    int alu_op, alu_src_imm, alu_src_pc, is_word_op;
    int is_branch, is_jump, mem_read, mem_write, reg_write, wb_from_mem;
    int is_jalr;
    int illegal_instr;
    int is_ecall,  is_ebreak, is_mret;
};

static void chk(const char* what, uint32_t instr, Ctrl e)
{
    top->if_instr = instr;
    top->eval();
    #define F(name) \
    if(top->name != e.name) \
    { \
        printf("[TB] Fail %-12s %s: got %d want %d\n", \
                    what, #name, (int)top->name, e.name); \
        errors++; \
    }
    F(alu_op) F(alu_src_imm) F(alu_src_pc) F(is_word_op)
    F(is_branch) F(is_jump) F(mem_read) F(mem_write)
    F(reg_write) F(wb_from_mem) F(is_jalr) F(illegal_instr)
    F(is_ecall) F(is_ebreak) F(is_mret)
    #undef F
}

static void chk_regs(const char* what, uint32_t instr,
                        int rs1, int rs2, int rd)
{
    top->if_instr = instr;
    top->eval();
    if(top->rs1_addr != rs1 || top->rs2_addr != rs2 || top->rd_addr != rd)
    {
        printf("[TB] Fail %s: rs1=%d rs2=%d rd=%d (want %d/%d/%d)\n",
            what, top->rs1_addr, top->rs2_addr, top->rd_addr, rs1, rs2, rd);
        errors++;
    }
}

int main(int argc, char** argv)
{
    Verilated::commandArgs(argc, argv);
    top = new Vcore_id;

    // addi x1, x0, -1
    chk("addi",  0xFFF00093, {0,1,0,0, 0,0,0,0,1,0, 0,0, 0,0,0});
    // sub x3, x1, x2  -> 0x402081B3
    chk("sub",   0x402081B3, {1,0,0,0, 0,0,0,0,1,0, 0,0, 0,0,0});
    // sd x1, -8(x2)
    chk("sd",    0xFE113C23, {0,1,0,0, 0,0,0,1,0,0, 0,0, 0,0,0});
    // ld x1, 8(x2)  -> 0x00813083
    chk("ld",    0x00813083, {0,1,0,0, 0,0,1,0,1,1, 0,0, 0,0,0});
    // beq x0, x0, +8
    chk("beq",   0x00000463, {0,0,0,0, 1,0,0,0,0,0, 0,0, 0,0,0});
    // lui x1, 0x12345
    chk("lui",   0x123450B7, {10,1,0,0, 0,0,0,0,1,0, 0,0, 0,0,0});
    // illegal — everything inert
    chk("zero",  0x00000000, {0,0,0,0, 0,0,0,0,0,0, 0,1, 0,0,0});
    //csrrw mscratch - legal
    chk("csrrw", 0x34009173, {0,0,0,0, 0,0,0,0,1,0, 0,0, 0,0,0});
    //ecall
    chk("ecall", 0x00000073, {0,0,0,0, 0,0,0,0,0,0, 0,0, 1,0,0});
    // ebreak
    chk("ebreak",0x00100073, {0,0,0,0, 0,0,0,0,0,0, 0,0, 0,1,0});
    // mret
    chk("mret",  0x30200073, {0,0,0,0, 0,0,0,0,0,0, 0,0, 0,0,1});

    chk("fence", 0x0ff0000f, {0,0,0,0, 0,0,0,0,0,0, 0,0, 0,0,0});
    chk("fence.i", 0x0000100f, {0,0,0,0, 0,0,0,0,0,0, 0,0, 0,0,0});

    // register field extraction: sub x3, x1, x2
    chk_regs("sub regs", 0x402081B3, 1, 2, 3);

    printf("[TB] %s (%d errors)\n", errors ? "FAIL" : "PASS", errors);
    delete top;
    return errors ? 1 : 0;
}