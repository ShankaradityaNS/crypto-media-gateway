#include <verilated.h>
#include <verilated_vcd_c.h>
#include "Vcore_top.h"
#include "Vcore_top___024root.h"
#include <cstdio>
#include <cstring>

// Runs one riscv-tests binary and reports its verdict.
//
// The tests report through gp (TESTNUM), per the upstream convention that
// sim_core/env/riscv_test.h preserves:
//
//   gp == 1              every case passed
//   gp == (n << 1) | 1   case n failed
//   gp |= 1337           an unexpected trap fired; the low bits still hold
//                        whichever case was running when it happened
//
// Plusargs:
//   +imem=<hex>   32-bit words, loaded by tcm.sv itself
//   +dmem=<hex>   64-bit words, preloaded into DTCM here (optional)
//   +vcd=<file>   enable tracing (off by default; 54 tests is a lot of disk)
//   +sigout=<file> dump the 8 KB signature region as raw bytes after halt

static vluint64_t sim_time = 0;
static Vcore_top* top;
static VerilatedVcdC* vcd = nullptr;
static bool tracing = false;

static void tick()
{
    top->clk = 0; top->eval(); if (tracing) vcd->dump(sim_time); sim_time++;
    top->clk = 1; top->eval(); if (tracing) vcd->dump(sim_time); sim_time++;
}

// x0 has no storage; mem is indexed [1:31]
static uint64_t reg(int n)
{
    if(n == 0) return 0;
    return top->rootp->core_top__DOT__u_rf__DOT__mem[n-1];
}

// Returns the text after '=' for a +name=value plusarg, or nullptr.
static const char* plusarg(const char* name)
{
    const char* a = Verilated::commandArgsPlusMatch(name);
    if(!a || !a[0]) return nullptr;
    const char* eq = strchr(a, '=');
    return (eq && eq[1]) ? eq + 1 : nullptr;
}

// .data is loaded from here rather than with a $readmemh inside dmem.sv,
// so the RTL stays free of simulation-only constructs. Many rv64ui tests
// load their operands from .data; without this they fault on the first
// load and report a trap that has nothing to do with the instruction
// under test.
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

// The signature region is where algorithm output lands. Dumped raw so a host
// script can decrypt it and compare against the original input.
static int dump_sig(const char* path)
{
    FILE* f = fopen(path, "wb");
    if(!f) return -1;
    for(int i = 0; i < 1024; i++) {
        uint64_t w = top->rootp->core_top__DOT__u_sigmem__DOT__mem[i];
        unsigned char b[8];
        for(int k = 0; k < 8; k++) b[k] = (unsigned char)(w >> (8*k));
        fwrite(b, 1, 8, f);
    }
    fclose(f);
    return 8192;
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
    const int MAX_CYCLES = 2000000;

    while (cycles < MAX_CYCLES)
    {
        tick();
        cycles++;
        if(top->halt_req) { halted = true; break; }
    }

    if(tracing) vcd->close();

    const char* sfile = plusarg("sigout=");
    if(sfile && dump_sig(sfile) < 0)
        printf("[TB] warning: cannot write %s\n", sfile);

    uint64_t gp    = reg(3);
    uint64_t instr = top->rootp->core_top__DOT__u_csr__DOT__minstret_q;
    uint64_t mcyc  = top->rootp->core_top__DOT__u_csr__DOT__mcycle_q;
    double   cpi   = instr ? (double)mcyc / (double)instr : 0.0;

    int rc = 1;

    if(!halted)
        printf("[TB] TIMEOUT %5d cyc  gp=0x%lx\n", cycles, gp);
    else if (gp == 1) {
        printf("[TB] PASS %6d cyc  %6lu instr  CPI %.2f\n", cycles, instr, cpi);
        rc = 0;
    }
    else if ((gp & 1337) == 1337)
        // An unexpected trap. The surviving low bits name the case that was
        // running, which is usually more useful than the trap itself.
        printf("[TB] TRAP %6d cyc  gp=0x%lx (during case %lu)\n",
               cycles, gp, gp & ~(uint64_t)1337);
    else if (gp & 1)
        printf("[TB] FAIL %6d cyc  case %lu  gp=0x%lx\n", cycles, gp >> 1, gp);
    else
        printf("[TB] BAD  %6d cyc  gp=0x%lx (no verdict written)\n", cycles, gp);

    delete top;
    return rc;
}