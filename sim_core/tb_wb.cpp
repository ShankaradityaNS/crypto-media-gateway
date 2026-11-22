#include <verilated.h>
#include "Vcore_wb.h"
#include <cstdio>

static Vcore_wb* top;
static int errors = 0;

static void chk(const char* what, int want_we, uint64_t want_data)
{
    top->eval();
    if(top->rf_we != want_we)
    {
        printf("[TB] Fail %-20s we=%d want=%d\n", what, (int)top->rf_we, want_we);
        errors++;
    }
    else if(want_we && top->rf_wdata != want_data)
    {
        printf("[TB] Fail %-20s data=%016lx want=%016lx\n", what, (uint64_t)top->rf_wdata,
                want_data);
                errors++;
    }
}

int main(int argc, char** argv)
{
    Verilated::commandArgs(argc, argv);
    top = new Vcore_wb;

    top->alu_result = 0xAAAAAAAAAAAAAAAAULL;
    top->load_result = 0xBBBBBBBBBBBBBBBBULL;
    top->csr_valid = 0;

    //ALU result selected
    top->wb_from_mem = 0; top->reg_write = 1; top->valid = 1; top->rd_addr = 5;
    chk("alu result", 1, 0xAAAAAAAAAAAAAAAAULL);

    //load result selected
    top->wb_from_mem = 1;
    chk("load result", 1, 0xBBBBBBBBBBBBBBBBULL);

    //reg_write low means no write
    top->reg_write = 0;
    chk("no reg_write", 0, 0);

    //flushed instruction must not commit
    top->reg_write = 1; top->valid = 0;
    chk("flushed", 0, 0);

    //writes to x0 are suppresed
    top->valid = 1; top->rd_addr = 0;
    chk("rd is x0", 0, 0);

    //waddr passes through
    top->rd_addr = 31;
    top->eval();
    if(top->rf_waddr != 31)
    {
        printf("[TB] Fail waddr: got %d want 31\n", (int)top->rf_waddr);
        errors++;
    }

    printf("[TB] %s (%d errors)\n", errors ? "FAIL" : "PASS", errors);
    delete top;
    return errors ? 1 : 0;
}
