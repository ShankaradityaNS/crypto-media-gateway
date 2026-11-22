//Verilator testbench: acts as the virtual camera
//Dumps 16384 bytes into the SRAM via port A, then watches the
//FSM/exit gate drain it, and checks the bytes come back intact

#include <verilated.h>
#include <verilated_vcd_c.h>
#include "Vgateway_top.h"
#include <cstdio>
#include <vector>
#include <algorithm>

#define BYTES   16384
#define AWORDS  512     // 256-bit write words
#define BWORDS  1024    // 128-bit read words
#define FRAME   921600
#define TILES   ((FRAME + BYTES - 1) / BYTES)   // 57, last one padded

static vluint64_t sim_time = 0;
static Vgateway_top* top;
static VerilatedVcdC* vcd;
static bool trace_on = true;          // ADD

//Advance 1 full clock cycle (lo then high) during waves each half
static void tick()
{
    top->clk = 0; top->eval(); if(trace_on) vcd->dump(sim_time); sim_time++;
    top->clk = 1; top->eval(); if(trace_on) vcd->dump(sim_time); sim_time++;
}

static int run_tile(const uint8_t *src, std::vector<uint8_t> &out)
{
    for(int w=0;w<AWORDS;w++)
    {
        for(int k=0;k<8;k++)
        {
            uint32_t v=0;
            for(int b=0;b<4;b++)
            {
                v |= (uint32_t)src[w*32 + k*4 + b] << (8*b);
            }
            top->a_wdata[k] = v;
        }
        top->a_en = 1;
        top->a_addr = w;
        tick();
    }
    top->a_en = 0;
    top->compute_done = 1;
    tick();
    top->compute_done = 0;

    int cycles = 0;
    while(top->state != 2 && cycles < BWORDS * 8)
    {
        tick();
        if(top->drain_valid)
        {
            for(int b=0;b<8;b++)
            {
                out.push_back((top->drain_data >> (8*b)) & 0xFF);
            }
        }
        cycles++;
    }
    top->consumer_ack = 1;
    tick();
    top->consumer_ack = 0;
    tick();
    return cycles;
}

int main(int argc, char** argv)
{
    Verilated::commandArgs(argc, argv);
    Verilated::traceEverOn(true);

    top = new Vgateway_top;
    vcd = new VerilatedVcdC;
    top->trace(vcd, 99);
    vcd->open("wave.vcd");

    //reset
    top->rst_n = 0;
    top->a_en = 0; 
    top->a_addr = 0;
    for(int i=0;i<8;i++)
        top->a_wdata[i] = 0;
    top->compute_done = 0; top->consumer_ack = 0;
    for(int i=0;i<5;i++) tick();
    top->rst_n = 1;
    tick();
    top->mode = 0;

    //virtual camera: write a mock frame, pack bytes into 256-bit words, little-endian
    //std::vector<uint8_t> golden(BYTES);
    //for(int i=0;i<BYTES;i++) golden[i] = (uint8_t)(i & 0xFF);
    std::vector<uint8_t> frame(TILES * BYTES, 0);
    FILE *f = fopen("frame.y", "rb");
    if(!f)
    {
        printf("[TB] cannot open frame.\n");
        return 1;
    }
    fread(frame.data(), 1, FRAME, f);
    fclose(f);
    // ... loop tiles, write drained bytes to out.y

    std::vector<uint8_t> out;
    long total = 0;
    for(int t=0;t<TILES;t++)
    {
        total += run_tile(&frame[t*BYTES], out);
        trace_on = false;
    }

    int errors = 0;
    if(out.size() != frame.size())
    {
        printf("[TB] count mismatch: %zu vs %zu\n", out.size(), frame.size());
        errors++;
    }

    size_t n = std::min(out.size(), frame.size());
    for(size_t i=0;i<n;i++)
    {
        if(out[i] != frame[i])
        {
            if(errors < 10)
                printf("[TB] mismatch at %zu\n", i);
                errors++;
        }
    }

    FILE *o = fopen("out.y", "wb");
    size_t nw = std::min(out.size(), (size_t)FRAME);
    fwrite(out.data(), 1, nw, o);
    fclose(o);

    printf("[TB] %d tiles, %ld cycles, %s (%d errors)\n", TILES, total, errors ? "FAIL" : "PASS", errors);

    /*
    for(int w=0;w<AWORDS;w++)
    {
        for(int k=0;k<8;k++)
        {
            uint32_t v = 0;
            for(int b=0;b<4;b++)
                v |= (uint32_t)golden[w*32 + k*4 + b] << (8*b);
            top->a_wdata[k] = v;
        }
        top->a_en = 1;
        top->a_addr = w;
        tick();
    }
    top->a_en = 0;

    printf("[TB] Wrote %d bytes, state=%d\n", BYTES, (int)top->state);

    //signal compute done, FSM should go EMPTY->DIRTY
    top->compute_done = 1;
    tick();
    top->compute_done = 0;
    printf("[TB] After compute_done: state=%d (expect 1=DIRTY)\n", (int)top->state);

    //let the drain walker run, capture what comes out
    std::vector<uint8_t> drained;
    int cycles = 0;
    const int MAX_CYCLES = BYTES * 4;

    top->mode = 0;      //pass-through; set this during reset

    while(top->state != 2 && cycles < BWORDS * 8)
    {
        // 2=READY
        tick();
        if(top->drain_valid)
        {
          for(int b=0;b<8;b++)
          {
            //drained.push_back((top->drain_data[b] >> (8*b)) & 0xFF);
            drained.push_back((top->drain_data >> (8 * b)) & 0xFF);
          }  
        } 
        cycles++;
    }

    printf("[TB] Drain finished: state=%d, %d cycles, %zu bytes\n",
                top->state, cycles, drained.size());

    //check integrity
    int errors = 0;
    size_t n = drained.size() < golden.size() ? drained.size() : golden.size();
    for(size_t i=0;i<n;i++)
    {
        if(drained[i] != golden[i])
        {
            if(errors < 10)
                printf("[TB] Mismatch at %zu: got %02X expected %02X\n",
                        i, drained[i], golden[i]);
                        errors++;
        }
    }
    if(drained.size() != golden.size())
        printf("[TB] Count Mismatch: drained %zu, expected %d\n",
                drained.size(), BYTES);

    printf("[TB] %s (%d byte errors)\n", errors ? "FAIL" : "PASS", errors);

    //consumer takes it, FSM should return to EMPTY
    top->consumer_ack = 1;
    tick();
    top->consumer_ack = 0;
    tick();
    printf("[TB] after ack: state=%d (expect 0=EMPTY)\n", top->state);

    */

    vcd->close();
    delete top;
    return errors ? 1 : 0;

}