// Directed test of the slot-select CSRs: shadow/live separation, commit,
// WARL range check, trap priority. Module-level on core_csr.
#include <verilated.h>
#include "Vcore_csr.h"
#include <cstdio>
#include <cstdint>

// must match core_pkg.sv
static const uint32_t CSR_SLOT_COMP   = 0x7C5;
static const uint32_t CSR_SLOT_CRYPT  = 0x7C6;
static const uint32_t CSR_SLOT_COMMIT = 0x7C7;
static const uint32_t CSR_SLOT_LIVE   = 0x7C8;

// csr_op_e ordering in core_pkg.sv
static const uint32_t OP_NONE = 0, OP_RW = 1, OP_RS = 2, OP_RC = 3;

// must match cmg_config.sv
static const uint32_t NUM_SLOTS          = 6;

static const uint32_t DEFAULT_COMP_SLOT  = 4;
static const uint32_t DEFAULT_CRYPT_SLOT = 5;

static Vcore_csr* dut;
static int fails = 0;

static void tick() {
    dut->clk = 0; dut->eval();
    dut->clk = 1; dut->eval();
}

static uint64_t rd(uint32_t a) {
    dut->addr = a; dut->op = OP_NONE; dut->we = 0;
    dut->eval();
    return dut->rdata;
}

static void wr(uint32_t a, uint64_t v, uint32_t op = OP_RW) {
    dut->addr = a; dut->op = op; dut->wdata = v; dut->we = 1;
    dut->eval();
    tick();
    dut->we = 0; dut->op = OP_NONE; dut->eval();
}

static void chk(const char* what, uint64_t got, uint64_t want) {
    if (got != want) {
        printf("  FAIL %-42s got %llx want %llx\n", what,
               (unsigned long long)got, (unsigned long long)want);
        fails++;
    } else {
        printf("  ok   %-42s %llx\n", what, (unsigned long long)got);
    }
}

int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);
    dut = new Vcore_csr;

    dut->rst_n = 0;
    dut->instr_retired = 0; dut->we = 0; dut->op = OP_NONE;
    dut->addr = 0; dut->wdata = 0;
    dut->trap_taken = 0; dut->trap_cause_i = 0; dut->trap_epc_i = 0;
    dut->trap_tval_i = 0; dut->trap_return = 0; dut->ext_irq = 0;
    tick(); tick();
    dut->rst_n = 1; dut->eval();
    tick();

    printf("-- reset defaults come from cmg_config --\n");
    chk("comp_slot_live",       dut->comp_slot_live,  DEFAULT_COMP_SLOT);
    chk("crypt_slot_live",      dut->crypt_slot_live, DEFAULT_CRYPT_SLOT);
    chk("pending comp",         rd(CSR_SLOT_COMP),    DEFAULT_COMP_SLOT);
    chk("pending crypt",        rd(CSR_SLOT_CRYPT),   DEFAULT_CRYPT_SLOT);
    chk("live pair",            rd(CSR_SLOT_LIVE),
        ((uint64_t)DEFAULT_CRYPT_SLOT << 8) | DEFAULT_COMP_SLOT);
    chk("nothing outstanding",  rd(CSR_SLOT_COMMIT),  0);

    printf("-- a shadow write does NOT move the live selector --\n");
    wr(CSR_SLOT_COMP, 2);
    chk("pending comp = 2",       rd(CSR_SLOT_COMP),   2);
    chk("live comp unchanged",    dut->comp_slot_live, DEFAULT_COMP_SLOT);
    chk("swap outstanding",       rd(CSR_SLOT_COMMIT), 1);
    wr(CSR_SLOT_CRYPT, 3);
    chk("pending crypt = 3",      rd(CSR_SLOT_CRYPT),  3);
    chk("live crypt unchanged",   dut->crypt_slot_live, DEFAULT_CRYPT_SLOT);

    printf("-- commit moves both windows at once --\n");
    wr(CSR_SLOT_COMMIT, 1);
    chk("live comp = 2",   dut->comp_slot_live,  2);
    chk("live crypt = 3",  dut->crypt_slot_live, 3);
    chk("live pair",       rd(CSR_SLOT_LIVE),    (3ULL << 8) | 2);
    chk("swap cleared",    rd(CSR_SLOT_COMMIT),  0);

    printf("-- commit with bit0 clear is a no-op --\n");
    wr(CSR_SLOT_COMP, 1);
    wr(CSR_SLOT_COMMIT, 0);
    chk("live comp still 2",    dut->comp_slot_live, 2);
    chk("pending comp still 1", rd(CSR_SLOT_COMP),   1);
    chk("still outstanding",    rd(CSR_SLOT_COMMIT), 1);

    printf("-- WARL: out-of-range slot numbers are dropped --\n");
    wr(CSR_SLOT_COMP, NUM_SLOTS);
    chk("pending comp still 1", rd(CSR_SLOT_COMP), 1);
    wr(CSR_SLOT_COMP, 99);
    chk("pending comp still 1", rd(CSR_SLOT_COMP), 1);
    wr(CSR_SLOT_COMP, NUM_SLOTS - 1);
    chk("highest legal accepted", rd(CSR_SLOT_COMP), NUM_SLOTS - 1);

    printf("-- read-modify-write is consistent --\n");
    wr(CSR_SLOT_COMP, 0);
    chk("csrrw to 0",          rd(CSR_SLOT_COMP), 0);
    wr(CSR_SLOT_COMP, 1, OP_RS);
    chk("csrrs 1 -> 1",        rd(CSR_SLOT_COMP), 1);
    wr(CSR_SLOT_COMP, 1, OP_RC);
    chk("csrrc 1 -> 0",        rd(CSR_SLOT_COMP), 0);

    printf("-- CSR_SLOT_LIVE is read-only --\n");
    wr(CSR_SLOT_LIVE, 0);
    chk("live pair untouched", rd(CSR_SLOT_LIVE), (3ULL << 8) | 2);

    printf("-- a trap in the same cycle suppresses the write --\n");
    uint64_t before = rd(CSR_SLOT_COMP);
    dut->addr = CSR_SLOT_COMP; dut->op = OP_RW; dut->wdata = 2;
    dut->we = 1; dut->trap_taken = 1; dut->eval();
    tick();
    dut->we = 0; dut->trap_taken = 0; dut->op = OP_NONE; dut->eval();
    chk("pending comp unchanged", rd(CSR_SLOT_COMP), before);

    printf("\n%s  (%d failure%s)\n", fails ? "FAIL" : "PASS",
           fails, fails == 1 ? "" : "s");
    delete dut;
    return fails ? 1 : 0;
}