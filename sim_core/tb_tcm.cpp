// Directed test of the windowed ITCM: slot aliasing and the fill interlock.
// Module-level - no core, no program image.
#include <verilated.h>
#include <verilated_vcd_c.h>
#include "Vtcm.h"
#include <cstdio>
#include <cstdint>
#include <cstring>

// Must match tcm.sv's parameter defaults
static const uint32_t RESIDENT_WORDS = 2048;
static const uint32_t SLOT_WORDS     = 2048;

static uint32_t slot_phys(uint32_t s) { return RESIDENT_WORDS + s * SLOT_WORDS; }

// Architectural byte addresses. tcm decodes only addr[14:2], so bare
// offsets are enough - no need for the real ITCM_BASE up at 0xFFFFFFFF8...
static const uint64_t RESIDENT_BASE = 0;
static const uint64_t COMP_BASE     = (uint64_t)RESIDENT_WORDS * 4;
static const uint64_t CRYPT_BASE    = COMP_BASE + (uint64_t)SLOT_WORDS * 4;

static Vtcm*          dut;
static VerilatedVcdC* tfp = nullptr;
static vluint64_t     ts  = 0;
static int            fails = 0;

static void tick() {
    dut->clk = 0; dut->eval(); if (tfp) tfp->dump(ts++);
    dut->clk = 1; dut->eval(); if (tfp) tfp->dump(ts++);
}

static void windows(uint32_t c, uint32_t k) {
    dut->comp_slot  = (uint8_t)c;
    dut->crypt_slot = (uint8_t)k;
    dut->eval();
}

// drive one fill; returns true if the interlock rejected it
static bool fill(uint32_t phys_word, uint32_t data) {
    dut->we    = 1;
    dut->waddr = (uint16_t)phys_word;
    dut->wdata = data;
    dut->eval();                       // wreject is combinational
    bool rej = dut->wreject != 0;
    tick();
    dut->we = 0; dut->eval();
    return rej;
}

static uint32_t fetch(uint64_t byte_addr) {
    dut->en   = 1;
    dut->addr = byte_addr;
    tick();                            // rdata is registered
    dut->en = 0; dut->eval();
    return dut->rdata;
}

static void chk(const char* what, uint32_t got, uint32_t want) {
    if (got != want) {
        printf("  FAIL %-40s got %08x want %08x\n", what, got, want);
        fails++;
    } else {
        printf("  ok   %-40s %08x\n", what, got);
    }
}

static void chk_rej(const char* what, bool got, bool want) {
    if (got != want) {
        printf("  FAIL %-40s wreject=%d want %d\n", what, got?1:0, want?1:0);
        fails++;
    } else {
        printf("  ok   %-40s wreject=%d\n", what, got?1:0);
    }
}

int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);
    dut = new Vtcm;

    for (int i = 1; i < argc; i++) {
        if (!strcmp(argv[i], "+vcd")) {
            Verilated::traceEverOn(true);
            tfp = new VerilatedVcdC;
            dut->trace(tfp, 99);
            tfp->open("tcm.vcd");
        }
    }

    dut->en = 0; dut->we = 0; dut->addr = 0;
    dut->waddr = 0; dut->wdata = 0;
    windows(0, 0);
    tick();

    printf("-- fill, both windows parked on slots 2 and 3 --\n");
    windows(2, 3);
    chk_rej("fill resident word 0",   fill(0,                0x11110000), false);
    chk_rej("fill slot0 word0",       fill(slot_phys(0) + 0, 0xAAAA0000), false);
    chk_rej("fill slot0 word1",       fill(slot_phys(0) + 1, 0xAAAA0001), false);
    chk_rej("fill slot1 word0",       fill(slot_phys(1) + 0, 0xBBBB0000), false);
    chk_rej("fill slot1 word1",       fill(slot_phys(1) + 1, 0xBBBB0001), false);

    printf("-- COMP aliasing: same address, different slot --\n");
    windows(0, 3);
    chk("COMP+0x0 comp_slot=0", fetch(COMP_BASE + 0), 0xAAAA0000);
    chk("COMP+0x4 comp_slot=0", fetch(COMP_BASE + 4), 0xAAAA0001);
    windows(1, 3);
    chk("COMP+0x0 comp_slot=1", fetch(COMP_BASE + 0), 0xBBBB0000);
    chk("COMP+0x4 comp_slot=1", fetch(COMP_BASE + 4), 0xBBBB0001);

    printf("-- CRYPT window maps independently --\n");
    windows(1, 0);
    chk("CRYPT+0x0 crypt_slot=0", fetch(CRYPT_BASE + 0), 0xAAAA0000);
    chk("COMP+0x0  comp_slot=1",  fetch(COMP_BASE  + 0), 0xBBBB0000);

    printf("-- resident is fixed, selectors do not move it --\n");
    chk("resident+0x0", fetch(RESIDENT_BASE + 0), 0x11110000);
    windows(3, 2);
    chk("resident+0x0 after window move", fetch(RESIDENT_BASE + 0), 0x11110000);

    printf("-- interlock: a windowed slot cannot be filled --\n");
    windows(0, 1);
    chk_rej("slot0 while comp_slot=0",  fill(slot_phys(0), 0xDEADBEEF), true);
    chk_rej("slot1 while crypt_slot=1", fill(slot_phys(1), 0xDEADBEEF), true);
    chk_rej("slot2 unwindowed",         fill(slot_phys(2), 0xCCCC0000), false);
    chk_rej("slot3 unwindowed",         fill(slot_phys(3), 0xDDDD0000), false);
    chk_rej("resident while windowed",  fill(0,            0x11110000), false);

    printf("-- rejected fills left memory untouched --\n");
    chk("COMP+0x0 slot0 intact", fetch(COMP_BASE + 0), 0xAAAA0000);
    windows(1, 0);
    chk("COMP+0x0 slot1 intact", fetch(COMP_BASE + 0), 0xBBBB0000);

    printf("-- interlock boundaries --\n");
    windows(1, 3);                     // slot1, slot3 locked; slot0, slot2 free
    chk_rej("slot0 last word, free",    fill(slot_phys(1) - 1, 0xA5A5A5A5), false);
    chk_rej("slot1 first word, locked", fill(slot_phys(1),     0xDEADBEEF), true);
    chk_rej("slot1 last word, locked",  fill(slot_phys(2) - 1, 0xDEADBEEF), true);
    chk_rej("slot2 first word, free",   fill(slot_phys(2),     0x5A5A5A5A), false);

    printf("-- boundary writes landed where intended --\n");
    windows(0, 3);
    chk("COMP last word = slot0 last",
        fetch(COMP_BASE + (uint64_t)(SLOT_WORDS - 1) * 4), 0xA5A5A5A5);
    windows(2, 3);
    chk("COMP+0x0 comp_slot=2", fetch(COMP_BASE + 0), 0x5A5A5A5A);

    printf("-- top slot, 3-bit selector --\n");
    windows(0, 1);
    chk_rej("fill slot5 unwindowed", fill(slot_phys(5), 0x55550005), false);
    windows(5, 1);
    chk("COMP+0x0 comp_slot=5", fetch(COMP_BASE + 0), 0x55550005);

    if (tfp) { tfp->close(); }
    printf("\n%s  (%d failure%s)\n", fails ? "FAIL" : "PASS",
           fails, fails == 1 ? "" : "s");
    delete dut;
    return fails ? 1 : 0;
}