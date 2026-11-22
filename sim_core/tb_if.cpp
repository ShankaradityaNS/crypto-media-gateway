#include <verilated.h>
#include <verilated_vcd_c.h>
#include "Vif_tb_top.h"
#include <cstdio>

static vluint64_t sim_time = 0;
static Vif_tb_top* top;
static VerilatedVcdC* vcd;
static int errors = 0;

static void tick()
{
    top->clk = 0; top->eval(); vcd->dump(sim_time++);
    top->clk = 1; top->eval(); vcd->dump(sim_time++);
}

static void expect(const char* what, uint64_t pc, uint32_t instr)
{
    if(!top->if_valid)
    { 
        printf("[TB] Fail %s: not valid\n", what);
        errors++;
        return;
    }
    if(top->if_pc != pc || top->if_instr != instr)
    {
        printf("[TB] Fail %s: pc=%lx instr=%08x (want %lx / %08x)\n", what, (uint64_t)top->if_pc, (uint32_t)top->if_instr, pc, instr);
        errors++;
    }
}

int main(int argc, char** argv)
{
    Verilated::commandArgs(argc, argv);
    Verilated::traceEverOn(true);
    top = new Vif_tb_top;
    vcd = new VerilatedVcdC;
    top->trace(vcd, 99);
    vcd->open("wave.vcd");

    top->rst_n = 0; top->stall = 0;
    top->branch_taken = 0; top->branch_target = 0;
    for(int i=0;i<3;i++) tick();
    top->rst_n = 1;

    tick();             //first fetch
    expect("instr 0", 0x80000000, 0x00000013);
    tick();
    expect("instr 1", 0x80000004, 0x00100093);

    //stall holds the PC
    top->stall = 1;
    tick();
    expect("stalled", 0x80000004, 0x00100093);
    top->stall =0;
    tick();
    expect("resumed", 0x80000008, 0x00200113);

    //branch redirect
    top->branch_taken = 1; top->branch_target =0x80000000;
    tick();
    top->branch_taken = 0;
    if(top->if_valid)
    {
        printf("[TB] Fail: not flushed after branch\n");
        errors++;
    }
    tick();
    expect("after branch", 0x80000000, 0x00000013);

    printf("[TB] %s (%d errors)\n", errors ? "FAIL" : "PASS", errors);
    vcd->close();
    delete top;
    return errors ? 1 : 0;
}