#include <verilated.h>
#include "Vcore_hazard.h"
#include <cstdio>

static Vcore_hazard* top;
static int errors = 0;

enum { FWD_NONE = 0, FWD_MEM = 1, FWD_WB = 2 };

static void clear()
{
    top->ex_rs1_addr = 0; top->ex_rs2_addr = 0;
    top->mem_reg_write = 0; top->mem_rd_addr = 0;
    top->wb_reg_write = 0; top->wb_rd_addr = 0;
    top->ex_mem_read = 0; top->ex_rd_addr = 0;
    top->id_rs1_addr = 0; top->id_rs2_addr = 0;
}

static void chk(const char* what, int fa, int fb, int st)
{
    top->eval();
    if(top->fwd_a != fa || top->fwd_b != fb || top->stall != st)
    {
        printf("[TB] Fail %-22s fwd_a+%d fwd_b=%d stall=%d (want %d/%d/%d)\n",
            what, (int)top->fwd_a, (int)top->fwd_b, (int)top->stall, fa, fb, st);
        errors++;
    }
}

int main(int argc, char** argv)
{
    Verilated::commandArgs(argc, argv);
    top = new Vcore_hazard;

    //nothing in flight
    clear();
    chk("idle", FWD_NONE, FWD_NONE, 0);

    //MEM result needed by rs1 in EX
    clear();
    top->ex_rs1_addr = 5; top->mem_reg_write = 1; top->mem_rd_addr = 5;
    chk("mem to rs1", FWD_MEM, FWD_NONE, 0);

    //MEM result needed by rs2
    clear();
    top->ex_rs2_addr = 7; top->mem_reg_write = 1; top->mem_rd_addr = 7;
    chk("mem to rs2", FWD_NONE, FWD_MEM, 0);

    //WB result needed by rs1
    clear();
    top->ex_rs1_addr = 5; top->wb_reg_write = 1; top->wb_rd_addr = 5;
    chk("wb to rs1", FWD_WB, FWD_NONE, 0);

    //both match: MEM is newer and must win
    clear();
    top->ex_rs1_addr = 5;
    top->mem_reg_write = 1; top->mem_rd_addr = 5;
    top->wb_reg_write = 1; top->wb_rd_addr = 5;
    chk("mem beasts wb", FWD_MEM, FWD_NONE, 0);

    //x0 is never forwarded
    clear();
    top->ex_rs1_addr = 0; top->mem_reg_write = 1; top->mem_rd_addr = 0;
    chk("x0 not forwarded", FWD_NONE, FWD_NONE, 0);

    //write disabled means no forward
    clear();
    top->ex_rs1_addr = 5; top->mem_reg_write = 0; top->mem_rd_addr = 5;
    chk("no write no fwd", FWD_NONE, FWD_NONE, 0);

    //different register, no forward
    clear();
    top->ex_rs1_addr = 5; top->mem_reg_write = 1; top->mem_rd_addr = 6;
    chk("different register", FWD_NONE, FWD_NONE, 0);

    //both operands forwarded from different stages
    clear();
    top->ex_rs1_addr = 5; top->ex_rs2_addr = 7;
    top->mem_reg_write = 1; top->mem_rd_addr = 5;
    top->wb_reg_write = 1; top->wb_rd_addr = 7;
    chk("both operands", FWD_MEM, FWD_WB, 0);

    //load-use: load in EX, its target read by ID
    clear();
    top->ex_mem_read = 1; top->ex_rd_addr = 5; top->id_rs1_addr = 5;
    chk("load-use rs1", FWD_NONE, FWD_NONE, 1);

    clear();
    top->ex_mem_read = 1; top->ex_rd_addr = 5; top->id_rs2_addr = 5;
    chk("load-use rs2", FWD_NONE, FWD_NONE, 1);

    //load into x0 cannot cause a hazard
    clear();
    top->ex_mem_read = 1; top->ex_rd_addr = 0; top->id_rs1_addr = 0;
    chk("load to x0", FWD_NONE, FWD_NONE, 0);

    //load whose target nobady reads
    clear();
    top->ex_mem_read = 1; top->ex_rd_addr = 5; top->id_rs1_addr = 6;
    chk("load no match", FWD_NONE, FWD_NONE, 0);

    printf("[TB] %s (%d errors)\n", errors ? "FAIL" : "PASS", errors);
    delete top;
    return errors ? 1 : 0;
}