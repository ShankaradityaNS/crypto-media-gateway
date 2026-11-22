#include <verilated.h>
#include <verilated_vcd_c.h>
#include "Vcore_mem.h"
#include <cstdio>
#include <cstdint>

static Vcore_mem*    top;
static VerilatedVcdC* tfp;
static uint64_t      tstamp = 0;
static int           errors = 0;

//Memory map, mirrored from core_pkg.sv. Written out in full rather than
//derived: if these ever drift from the package the test is worthless, and a
//hard-coded copy makes the drift visible instead of silently consistent.
static const uint64_t DTCM_BASE = 0xFFFFFFFF80010000ULL;
static const uint64_t DTCM_SIZE = 16384;
static const uint64_t SIG_BASE  = 0xFFFFFFFF80020000ULL;
static const uint64_t SIG_SIZE  = 8192;
static const uint64_t HALT_ADDR = 0xFFFFFFFF90000000ULL;

enum { F3_B = 0, F3_H = 1, F3_W = 2, F3_D = 3,
       F3_BU = 4, F3_HU = 5, F3_WU = 6 };

//Source word for every store test. Each width must take its bits from the
//LOW end of store_data regardless of the address offset, so a value with
//eight distinct bytes catches an implementation that grabs the wrong one.
static const uint64_t SRC = 0x1122334455667788ULL;

static void dump()
{
    tfp->dump(tstamp++);
    tfp->dump(tstamp++);
}

static void drive(uint64_t addr, uint64_t data, int f3, int rd, int wr)
{
    top->addr       = addr;
    top->store_data = data;
    top->funct3     = f3;
    top->mem_read   = rd;
    top->mem_write  = wr;
    top->eval();
    dump();
}

static void fail(const char* what)
{
    printf("[TB] FAIL t=%-5lu %-26s en=%d strb=%02x wdata=%016lx "
           "mis_l=%d mis_s=%d af_l=%d af_s=%d halt=%d sig_en=%d in_sig=%d\n",
           tstamp - 2, what,
           top->dmem_en, (unsigned)top->dmem_wstrb, (uint64_t)top->dmem_wdata,
           top->misaligned_load, top->misaligned_store,
           top->access_fault_load, top->access_fault_store,
           top->halt_req, top->sigmem_en, top->in_sig);
    errors++;
}

//A store is correct when the enable is up, the strobe is exactly the expected
//mask, and every byte the strobe enables carries the right value. Bytes the
//strobe masks off are deliberately NOT checked: the memory never samples them,
//so their content is a free variable of the implementation.
static void chk_store(const char* what, uint64_t off, int f3,
                      uint8_t want_strb, uint64_t want_word)
{
    drive(DTCM_BASE + off, SRC, f3, 0, 1);
    bool bad = !top->dmem_en
            || top->dmem_wstrb != want_strb
            || top->misaligned_store
            || top->access_fault_store;
    for (int i = 0; i < 8 && !bad; i++) {
        if (!((want_strb >> i) & 1)) continue;
        uint8_t got  = (uint8_t)((uint64_t)top->dmem_wdata >> (8 * i));
        uint8_t want = (uint8_t)(want_word >> (8 * i));
        if (got != want) bad = true;
    }
    if (bad) fail(what);
}

//The enable must be suppressed on a fault. The trap is raised in this same
//cycle, but the write would commit on this clock edge, so an unsuppressed
//enable means a trap AND a corrupted word.
static void chk_mis_store(const char* what, uint64_t off, int f3)
{
    drive(DTCM_BASE + off, SRC, f3, 0, 1);
    if (!top->misaligned_store || top->dmem_en || top->sigmem_en) fail(what);
}

static void chk_mis_load(const char* what, uint64_t off, int f3)
{
    drive(DTCM_BASE + off, 0, f3, 1, 0);
    if (!top->misaligned_load || top->dmem_en || top->sigmem_en) fail(what);
}

static void chk_aligned_ok(const char* what, uint64_t off, int f3, int rd, int wr)
{
    drive(DTCM_BASE + off, SRC, f3, rd, wr);
    if (top->misaligned_load || top->misaligned_store) fail(what);
}

static void chk_unmapped(const char* what, uint64_t addr)
{
    drive(addr, SRC, F3_D, 0, 1);
    if (!top->access_fault_store || top->dmem_en || top->sigmem_en) fail(what);
    drive(addr, 0, F3_D, 1, 0);
    if (!top->access_fault_load || top->dmem_en || top->sigmem_en) fail(what);
}

static void chk_region(const char* what, uint64_t addr, int want_dtcm, int want_sig)
{
    drive(addr, 0, F3_D, 1, 0);
    int got_dtcm = top->dmem_en   ? 1 : 0;
    int got_sig  = top->sigmem_en ? 1 : 0;
    if (got_dtcm != want_dtcm || got_sig != want_sig
        || top->in_sig != want_sig
        || top->access_fault_load) fail(what);
}

int main(int argc, char** argv)
{
    Verilated::commandArgs(argc, argv);
    Verilated::traceEverOn(true);
    top = new Vcore_mem;
    tfp = new VerilatedVcdC;
    top->trace(tfp, 99);
    tfp->open("mem.vcd");

    //----------------------------------------------------------------
    //Idle: no access requested means nothing asserted anywhere. Easy to
    //break by computing a fault from !mapped without qualifying it.
    //----------------------------------------------------------------
    drive(DTCM_BASE, SRC, F3_D, 0, 0);
    if (top->dmem_en || top->sigmem_en || top->halt_req
        || top->misaligned_load || top->misaligned_store
        || top->access_fault_load || top->access_fault_store)
        fail("idle quiet");

    //----------------------------------------------------------------
    //Legal stores: 15 cases, the whole legal width x offset matrix.
    //----------------------------------------------------------------
    for (uint64_t off = 0; off < 8; off++)
        chk_store("sb", off, F3_B, (uint8_t)(1u << off), 0x88ULL << (8 * off));

    for (uint64_t off = 0; off < 8; off += 2)
        chk_store("sh", off, F3_H, (uint8_t)(3u << off), 0x7788ULL << (8 * off));

    for (uint64_t off = 0; off < 8; off += 4)
        chk_store("sw", off, F3_W, (uint8_t)(0xFu << off),
                  0x55667788ULL << (8 * off));

    chk_store("sd", 0, F3_D, 0xFF, SRC);

    //----------------------------------------------------------------
    //Alignment. Byte accesses can never fault; each wider width faults on
    //any offset that is not a multiple of its size.
    //----------------------------------------------------------------
    for (uint64_t off = 0; off < 8; off++) {
        chk_aligned_ok("sb aligned",  off, F3_B,  0, 1);
        chk_aligned_ok("lbu aligned", off, F3_BU, 1, 0);
    }
    for (uint64_t off = 1; off < 8; off += 2) {
        chk_mis_store("sh misaligned",  off, F3_H);
        chk_mis_load ("lh misaligned",  off, F3_H);
        chk_mis_load ("lhu misaligned", off, F3_HU);
    }
    for (uint64_t off = 1; off < 8; off++) {
        if (off % 4 == 0) continue;
        chk_mis_store("sw misaligned",  off, F3_W);
        chk_mis_load ("lw misaligned",  off, F3_W);
        chk_mis_load ("lwu misaligned", off, F3_WU);
    }
    for (uint64_t off = 1; off < 8; off++) {
        chk_mis_store("sd misaligned", off, F3_D);
        chk_mis_load ("ld misaligned", off, F3_D);
    }

    //----------------------------------------------------------------
    //Region decode at every boundary. Note that because both region sizes
    //are multiples of 8, an ALIGNED access can never straddle a region end
    //-- alignment checking is what keeps the decode from needing a width
    //aware range check.
    //----------------------------------------------------------------
    chk_region("dtcm first", DTCM_BASE,                     1, 0);
    chk_region("dtcm last",  DTCM_BASE + DTCM_SIZE - 8,     1, 0);
    chk_region("sig first",  SIG_BASE,                      0, 1);
    chk_region("sig last",   SIG_BASE + SIG_SIZE - 8,       0, 1);

    chk_unmapped("past dtcm",  DTCM_BASE + DTCM_SIZE);
    chk_unmapped("past sig",   SIG_BASE  + SIG_SIZE);
    chk_unmapped("below dtcm", DTCM_BASE - 8);
    chk_unmapped("itcm",       0xFFFFFFFF80000000ULL);
    chk_unmapped("zero",       0x0000000000000000ULL);
    chk_unmapped("high",       0xFFFFFFFFFFFFFFF8ULL);

    //----------------------------------------------------------------
    //Halt. A write to the halt address halts and touches no memory; a read
    //of it does not halt.
    //----------------------------------------------------------------
    drive(HALT_ADDR, 0, F3_D, 0, 1);
    if (!top->halt_req || top->dmem_en || top->sigmem_en
        || top->access_fault_store) fail("halt store");

    drive(HALT_ADDR, 0, F3_D, 1, 0);
    if (top->halt_req) fail("halt not on read");

    tfp->close();
    delete top;
    printf(errors ? "[TB] FAILED (%d errors)\n" : "[TB] PASS (%d errors)\n",
           errors);
    return errors ? 1 : 0;
}