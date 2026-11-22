#include <verilated.h>
#include "Vcore_csr.h"
#include <cstdio>

static Vcore_csr* top;
static int errors = 0;

enum { CSR_NONE = 0, CSR_RW = 1, CSR_RS = 2, CSR_RC = 3 };

#define MSCRATCH 0x340
#define MTVEC    0x305
#define MCYCLE   0xB00
#define MINSTRET 0xB02

#define ATT_CTRL    0x7C0
#define ATT_EXP     0x7C1
#define ATT_ACT     0x7C2
#define ATT_STAT    0x7C3

static void tick()
{
    top->clk = 0; top->eval();
    top->clk = 1; top->eval();
}

//perform a CSR access, reurn the value read
static uint64_t access(int addr, int op, uint64_t wdata)
{
    top->addr =  addr; top->op = op; top->wdata = wdata; top->we = 1;
    top->eval();
    uint64_t old = top->rdata;
    tick();
    top->we = 0;
    return old;
}

static uint64_t peek(int addr)
{
    top->addr = addr; top->op = CSR_NONE; top->we = 0;
    top->eval();
    return top->rdata;
}

static void chk(const char* what, uint64_t got, uint64_t want)
{
    if(got != want)
    {
        printf("[TB] Fail %-18s got %016lx want %016lx\n", what, got, want);
        errors++;
    }
}

int main(int argc, char** argv)
{
    Verilated::commandArgs(argc, argv);
    top = new Vcore_csr;
    top->rst_n = 0; top->we = 0; top->op = CSR_NONE;
    top->addr = 0; top->wdata = 0; top->instr_retired = 0;
    for(int i=0;i<3;i++) tick();
    top->rst_n = 1;

    //csrrw writes and returns the old value
    chk("rw old", access(MSCRATCH, CSR_RW, 0xAAAABBBBCCCCDDDDULL), 0);
    chk("rw new", peek(MSCRATCH), 0xAAAABBBBCCCCDDDDULL);

    //csrrs sets bits leaves others alone
    access(MSCRATCH, CSR_RW, 0x00000000000000F0ULL);
    access(MSCRATCH, CSR_RS, 0x000000000000000FULL);
    chk("rs sets", peek(MSCRATCH), 0x00000000000000FFULL);

    //csrrc clears bits
    access(MSCRATCH, CSR_RC, 0x00000000000000F0ULL);
    chk("rc clears", peek(MSCRATCH), 0x000000000000000FULL);

    //a read with op NONE must not modify
    access(MSCRATCH, CSR_NONE, 0xFFFFFFFFFFFFFFFFULL);
    chk("none no write", peek(MSCRATCH), 0x000000000000000FULL);

    //seperate CSRs are independent
    access(MTVEC, CSR_RW, 0x0000000080000100ULL);
    chk("mtvec", peek(MTVEC), 0x0000000080000100ULL);
    chk("mscartch", peek(MSCRATCH), 0x000000000000000FULL);

    //unimplemented address reads zero
    chk("unknown", peek(0x7FF), 0);

    //mcycle free-runs
    uint64_t c0 = peek(MCYCLE);
    tick(); tick(); tick();
    chk("mcycle runs", peek(MCYCLE) - c0, 3);

    //minstret only counts retirements
    uint64_t i0 = peek(MINSTRET);
    tick(); tick();
    chk("no retire", peek(MINSTRET) -i0, 0);
    top->instr_retired = 1;
    tick(); tick();
    top->instr_retired = 0;
    chk("retire counts", peek(MINSTRET) - i0, 2);

    //an explicit write to mcycle beats the increment
    access(MCYCLE, CSR_RW, 1000);
    chk("mcycle write", peek(MCYCLE), 1000);

    //attestation
    // arm wait a known number of cycles, check against the right answer
    access(ATT_EXP, CSR_RW, 10);
    access(ATT_CTRL, CSR_RW, 1);        //arm
    chk("armed", peek(ATT_STAT) & 1, 1);
    for(int i=0;i<9;i++) tick();        // 9 ticks + the access itself = 10
    access(ATT_CTRL, CSR_RW, 0);        //check
    chk("disarmed", peek(ATT_STAT) & 1, 0);
    chk("actual", peek(ATT_ACT), 10);
    chk("no mismatch", (peek(ATT_STAT) >> 1) & 1, 0);

    //arm again, but take a different number of cycles
    access(ATT_EXP, CSR_RW, 10);
    access(ATT_CTRL, CSR_RW, 1);
    for(int i=0;i<20;i++) tick();
    access(ATT_CTRL, CSR_RW, 0);
    chk("mismatch flagged", (peek(ATT_STAT) >> 1) & 1, 1);

    //secure mode
    chk("secmode off", top->secure_mode, 0);
    access(0x7C4, CSR_RW, 1);
    top->eval();
    chk("secmode on", top->secure_mode, 1);
    chk("secmode csr", peek(0x7C4) & 1, 1);
    access(0x7C4, CSR_RW, 0);
    top->eval();
    chk("secmode off again", top->secure_mode, 0);

    printf("[TB] %s (%d errors)\n", errors ? "FAIL" : "PASS", errors);
    delete top;
    return errors ? 1 : 0;

}