#include <verilated.h>
#include <verilated_vcd_c.h>
#include "Vregfile.h"
#include <cstdio>


static vluint64_t sim_time = 0;
static Vregfile* top;
static VerilatedVcdC* vcd;
static int errors = 0;

static void tick()
{
    top->clk = 0; top->eval(); vcd->dump(sim_time++);
    top->clk = 1; top->eval(); vcd->dump(sim_time++);
}

static void check(const char* what, uint64_t got, uint64_t want)
{
    if(got != want)
    {
        printf("[TB] Fail %s: got %016llx want %016llx\n", what, (unsigned long long)got, (unsigned long long)want);
        errors;
    }
}

//drive a write, no read
static void wr(int addr, uint64_t data)
{
    top->rd_we = 1; top->rd_addr = addr; top->rd_data = data;
    tick();
    top->rd_we = 0;
}

int main(int argc, char** argv)
{
    Verilated::commandArgs(argc, argv);
    Verilated::traceEverOn(true);
    top = new Vregfile;
    vcd = new VerilatedVcdC;
    top->trace(vcd, 99);
    vcd->open("wave.vcd");

    top->rst_n = 0;
    top->rs1_addr = 0; top->rs2_addr = 0;
    top->rd_we = 0; top->rd_addr = 0; top->rd_data = 0;
    for(int i=0;i<3;i++) tick();
    top->rst_n = 1;
    tick();

    //1. x0 stays 0 even after a write to it
    wr(0, 0xABCDEF);
    top->rs1_addr = 0; top->eval();
    check("x0 reads 0", top->rs1_data, 0);

    //2. normal write the read back
    wr(5, 0x0123456789ABCDEFULL);
    top->rs1_addr = 5; top->eval();
    check("x5 readback", top->rs1_data, 0x0123456789ABCDEFULL);

    //3. Both ports independent
    wr(7, 0x1111111122222222ULL);
    top->rs1_addr = 5; top->rs2_addr = 7; top->eval();
    check("Port A holds x5", top->rs1_data, 0x0123456789ABCDEFULL);
    check("Port B holds x7", top->rs2_data, 0x1111111122222222ULL);

    //4. Write-through: read the register being written this cycle
    top->rs1_addr = 9;
    top->rd_we = 1; top->rd_addr = 9; top->rd_data = 0xAAAABBBBCCCCDDDDULL;
    top->eval();
    check("write-through", top->rs1_data, 0xAAAABBBBCCCCDDDDULL);
    tick();
    top->rd_we = 0;
    top->eval();
    check("post-write x9", top->rs1_data, 0xAAAABBBBCCCCDDDDULL);

    //5. writes are suppressed when rd_we is low
    top->rd_we = 0; top->rd_addr = 5; top->rd_data = 0;
    tick();
    top->rs1_addr = 5; top->eval();
    check("x5 unchanged", top->rs1_data, 0x0123456789ABCDEFULL);

    printf("[TB] %s (%d errors)\n", errors ? "FAIL" : "PASS", errors);
    vcd->close();
    delete top;
    return errors ? 1 : 0;
}