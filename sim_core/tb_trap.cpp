#include <verilated.h>
#include "Vcore_trap.h"
#include <cstdio>

static Vcore_trap* top;
static int errors = 0;

#define CAUSE_ILLEGAL       2
#define CAUSE_BREAKPOINT    3
#define CAUSE_LOAD_ALIGN    4
#define CAUSE_STORE_ALIGN   6
#define CAUSE_ECALL_M       11

static void clear()
{
    top->valid = 1;
    top->illegal_instr = 0; top->is_ecall = 0; top->is_ebreak = 0;
    top->misaligned_load = 0; top->misaligned_store = 0;
    top->is_mret = 0;
    top->pc = 0x80001000; top->mtvec = 0x80000100; top->mepc = 0x80002000;
}

static void chk(const char* what, int taken, uint64_t cause, int redir, uint64_t rpc)
{
    top->eval();
    if(top->trap_taken != taken)
    {
        printf("[TB] Fail %-18s taken=%d want=%d\n", what, (int)top->trap_taken, taken);
        errors++;
        return;
    }
    if(taken && top->trap_cause != cause)
    {
        printf("[TB] Fail %-18s cause=%u want=%lu\n", what, 
            (int)top->redirect, cause);
            errors++;
    }
    if(top->redirect != redir)
    {
        printf("[TB] Fail %-18s redirect=%d want=%d\n", what, (int)top->redirect,
                    redir);
        errors++;
    }
    else if(redir && top->redirect_pc != rpc)
    {
        printf("[TB] Fail %-18s rpc=%016lx want=%016lx\n", what,
            (uint64_t)top->redirect_pc, rpc);
            errors++;
    }
}

int main(int argc, char** argv)
{
    Verilated::commandArgs(argc, argv);
    top = new Vcore_trap;

    //no exception
    clear();
    chk("quiet", 0, 0, 0, 0);

    //illegal instruction
    clear(); top->illegal_instr = 1;
    chk("illegal", 1, CAUSE_ILLEGAL, 1, 0x80000100);

    //ecall
    clear(); top->is_ecall = 1;
    chk("ecall", 1, CAUSE_ECALL_M, 1, 0x80000100);

    //ebreak
    clear(); top->is_ebreak = 1;
    chk("ebreak", 1, CAUSE_BREAKPOINT, 1, 0x80000100);

    //misaligned load and store
    clear(); top->misaligned_load = 1;
    chk("load align", 1, CAUSE_LOAD_ALIGN, 1, 0x80000100);
    clear(); top->misaligned_store = 1;
    chk("store align", 1, CAUSE_STORE_ALIGN, 1, 0x80000100);

    //mret returns to mepc,  and is not a trap
    clear(); top->is_mret = 1;
    chk("mret", 0, 0, 1, 0x80002000);
    if(!top->trap_return)
    {
        printf("[TB] ail mret: trap_return low\n");
        errors++;
    }

    //priority: illegal wins over ecall
    clear(); top->illegal_instr = 1; top->is_ecall = 1;
    chk("illegal first", 1, CAUSE_ILLEGAL, 1, 0x80000100);

    //an invalid instruction traps nothing
    clear(); top->valid = 0; top->illegal_instr = 1;
    chk("not valid", 0, 0, 0, 0);

    //mepc captures the faulting PC
    clear(); top->illegal_instr = 1;
    top->eval();
    if(top->trap_epc != 0x80001000)
    {
        printf("[TB] Fail epc: got %016lx want 80001000\n", (uint64_t)top->trap_epc);
        errors++;
    }

    printf("[TB] %s (%d errors)\n", errors ? "FAIL" : "PASS", errors);
    delete top;
    return errors ? 1 : 0;
}