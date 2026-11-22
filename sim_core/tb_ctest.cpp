#include <verilated.h>
#include <verilated_vcd_c.h>
#include "Vcore_top.h"
#include "Vcore_top___024root.h"
#include <cstdio>
#include <cstring>
#include <cstdlib>
#include <cstdint>

// Runs a C program on the core and checks main's return value.
//   +imem=<hex>    32-bit words (.text)
//   +dmem=<hex>    64-bit words (.data image, which carries .rodata too)
//   +expect=<n>    expected value of a0 at halt
//   +vcd=<file>    enable tracing (off by default)

static vluint64_t sim_time = 0;
static Vcore_top* top;
static VerilatedVcdC* vcd = nullptr;
static bool tracing = false;

static void tick()
{
    top->clk = 0; top->eval(); if (tracing) vcd->dump(sim_time); sim_time++;
    top->clk = 1; top->eval(); if (tracing) vcd->dump(sim_time); sim_time++;
}

//x0 has no storage;  mem is indexed [1:31]
static uint64_t reg(int n)
{
    if(n == 0)  return 0;
    return top->rootp->core_top__DOT__u_rf__DOT__mem[n-1];
}
static const char* plusarg(const char* name)
{
    const char* a = Verilated::commandArgsPlusMatch(name);
    if(!a || !a[0]) return nullptr;
    const char* eq = strchr(a, '=');
    return (eq && eq[1]) ? eq + 1 : nullptr;
}

static int load_dtcm(const char* path)
{
    FILE* f = fopen(path, "r");
    if(!f) return -1;
    unsigned long long w;
    int i = 0;
    while(i < 2048 && fscanf(f, "%llx", &w) == 1)
        top->rootp->core_top__DOT__u_dtcm__DOT__mem[i++] = w;
    fclose(f);
    return i;
}

int main(int argc, char** argv)
{
     Verilated::commandArgs(argc, argv);
    top = new Vcore_top;

    const char* vcdfile = plusarg("vcd=");
    if(vcdfile) {
        Verilated::traceEverOn(true);
        vcd = new VerilatedVcdC;
        top->trace(vcd, 99);
        vcd->open(vcdfile);
        tracing = true;
    }

    top->rst_n = 0;
    for(int i=0;i<5;i++) tick();
    top->rst_n = 1;

    const char* dfile = plusarg("dmem=");
    if(dfile && load_dtcm(dfile) < 0)
        printf("[TB] warning: cannot open %s\n", dfile);

    int cycles = 0;
    bool halted = false;
    const int MAX_CYCLES = 1000000;

    while (cycles < MAX_CYCLES) {
        tick();
        cycles++;
        if(top->halt_req) { halted = true; break; }
    }

    if(tracing) vcd->close();

    uint64_t a0    = reg(10);
    uint64_t instr = top->rootp->core_top__DOT__u_csr__DOT__minstret_q;
    uint64_t mcyc  = top->rootp->core_top__DOT__u_csr__DOT__mcycle_q;

    int rc = 1;
    if(!halted)
        printf("[TB] TIMEOUT %d cyc  a0=%lu\n", cycles, a0);
    else {
        const char* e = plusarg("expect=");
        printf("[TB] halted %d cyc  %lu instr  CPI %.2f  a0=%lu\n",
               cycles, instr, instr ? (double)mcyc/(double)instr : 0.0, a0);
        if(!e) { printf("[TB] no +expect given\n"); }
        else if(a0 == strtoull(e, nullptr, 0)) { printf("[TB] PASS\n"); rc = 0; }
        else printf("[TB] FAIL  a0=%lu want %s\n", a0, e);
    }

    delete top;
    return rc;   
}