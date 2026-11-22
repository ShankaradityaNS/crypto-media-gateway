#include <verilated.h>
#include <verilated_vcd_c.h>
#include "Vcore_top.h"
#include "Vcore_top___024root.h"
#include <cstdio>

static vluint64_t sim_time = 0;
static Vcore_top* top;
static VerilatedVcdC* vcd;
static int errors = 0;

static void tick()
{
    top->clk = 0; top->eval(); vcd->dump(sim_time++);
    top->clk = 1; top->eval(); vcd->dump(sim_time++);
}

// x0 has no storage; mem is indexed [1:31]
static uint64_t reg(int n)
{
    if(n == 0) return 0;
    return top->rootp->core_top__DOT__u_rf__DOT__mem[n-1];
}

static void chk(const char* what, int n, uint64_t want)
{
    if(reg(n) != want)
    {
        printf("[TB] Fail %-14s x%-2d = %016lx want %016lx\n", what, n, reg(n), want);
        errors++;
    }
}

int main(int argc, char** argv)
{
    Verilated::commandArgs(argc, argv);
    Verilated::traceEverOn(true);
    top = new Vcore_top;
    vcd = new VerilatedVcdC;
    top->trace(vcd, 99);
    vcd->open("wave.vcd");
    top->ext_irq = 0;

    top->rst_n = 0;
    for(int i=0;i<5;i++) tick();
    top->rst_n = 1;

    int cycles = 0;
    bool halted = false;
    const int MAX_CYCLES = 100000;

    while (cycles < MAX_CYCLES)
    {
        // Assert the external request once the program is inside its loop and
        // leave it asserted. The handler masks MEIE, so irq_pending drops even
        // though the pin stays high -- which also tests that masking works.
        top->ext_irq = (cycles >= 40) ? 1 : 0;
        tick();
        cycles++;
        if(top->halt_req) { halted = true; break;}
    }

    if(!halted) {
        printf("[TB] TIMEOUT after %d cycles (no halt)\n", cycles);
        errors++;
    }
    else
        printf("[TB] halted after %d cycles\n", cycles);
    
    //run long enough for the prog plus pipeline drain
    for (int i = 0; i < 150; i++) tick();

    chk("x20 mcause",  20, 0x800000000000000BULL);
    chk("x23 handler", 23, 1);
    chk("x10 loop",    10, 100);
    chk("x24 wrong vec", 24, 0);

    printf("[TB] x21 mepc = %016lx\n", reg(21));
    
    /*
    while (cycles < MAX_CYCLES)
    {
        tick();
        cycles++;
        printf("c%-2d  ifid[v=%d pc=%03lx]  idex[v=%d pc=%03lx]  bt=%d tgt=%03lx  we=%d rd=%2d wd=%lx\n",
            cycles,
            (int)top->rootp->core_top__DOT__if_id_q.valid,
            (uint64_t)top->rootp->core_top__DOT__if_id_q.pc & 0xFFF,
            (int)top->rootp->core_top__DOT__id_ex_q.valid,
            (uint64_t)top->rootp->core_top__DOT__id_ex_q.pc & 0xFFF,
            (int)top->rootp->core_top__DOT__branch_taken,
            (uint64_t)top->rootp->core_top__DOT__branch_target & 0xFFF,
            (int)top->rootp->core_top__DOT__rf_we,
            (int)top->rootp->core_top__DOT__rf_waddr,
            (uint64_t)top->rootp->core_top__DOT__rf_wdata);
        if(top->halt_req) { halted = true; break;}
    }
    */
    printf("[TB] %s (%d errors)\n", errors ? "FAIL" : "PASS", errors);
    vcd->close();
    delete top;
    return  errors ? 1 :0;
}