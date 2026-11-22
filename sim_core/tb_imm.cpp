#include <verilated.h>
#include "Vcore_imm.h"
#include <cstdio>

static Vcore_imm* top;
static int errors = 0;

static void chk(const char* what, uint32_t instr, uint64_t want)
{
    top->instr = instr;
    top->eval();
    if(top->imm != want)
    {
        printf("[TB] Fail %-22s instr=%08x imm=%016lx want=%016lx\n",
                    what, instr, (uint64_t)top->imm, want);
        errors++;
    }
}

int main(int argc, char** argv)
{
    Verilated::commandArgs(argc, argv);
    top = new Vcore_imm;

    //I-type: addi x1, x0, -1  -> 0xFFF00093
    chk("I negative", 0xFFF00093, 0xFFFFFFFFFFFFFFFFULL);
    //I-type: addi x1, x0, 1   -> 0x00100093
    chk("I positive", 0x00100093, 0x0000000000000001ULL);
    //I-type: addi x1, x0, 2047 -> 0x7FF00093  (largest positive)
    chk("I max", 0x7FF00093, 0x00000000000007FFULL);
    //I-type: addi x1, x0, -2048 -> 0x80000093 (most negative)
    chk("I min", 0x80000093, 0xFFFFFFFFFFFFF800ULL);

    //S-type: sd x1, 8(x2)   -> 0x00113423
    chk("S positive", 0x00113423, 0x0000000000000008ULL);
    //S-type: sd x1, -8(x2)  -> 0xFE113C23
    chk("S negative", 0xFE113C23, 0xFFFFFFFFFFFFFFF8ULL);

    //B-type: beq x0, x0, +8    -> 0x00000463
    chk("B positive", 0x00000463, 0x0000000000000008ULL);
    //B-type: beq x0, x0, -8    -> 0xFE000CE3
    chk("B negative", 0xFE000CE3, 0xFFFFFFFFFFFFFFF8ULL);

    //U-type: lui x1, 0x12345 -> 0x123450B7
    chk("U positive", 0x123450B7, 0x0000000012345000ULL);
    //U-type: lui x1, 0xFFFFF -> 0xFFFFF0B7  (sign-extended in RV64)
    chk("U negative", 0xFFFFF0B7, 0xFFFFFFFFFFFFF000ULL);

    //J-type: jal x1, +8    -> 0x008000EF
    chk("J positive", 0x008000EF, 0x0000000000000008ULL);
    //J-type: jal x1, -8    -> 0xFF9FF0EF
    chk("J negative", 0xFF9FF0EF, 0xFFFFFFFFFFFFFFF8ULL);

    printf("[TB] %s (%d errors)\n", errors ? "FAIL" : "PASS", errors);
    delete top;
    return errors ? 1 : 0;
}