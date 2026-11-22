//Tightly coupled instruction memory with a  resident region and pool of
//aliased algo slots. Single cycle synchronous read.
// PHYSICAL                        ARCHITECTURAL (what the core addresses)
//   [0 .. R-1]        resident      base + 0              resident, fixed
//   [R .. R+S-1]      slot 0        base + R*4            COMP  -> slot[comp_slot]
//   [R+S .. R+2S-1]   slot 1        base + R*4 + S*4      CRYPT -> slot[crypt_slot]
//   ...               slot N-1
//
// No slot is privileged. The fill port addresses physical words, so the boot
// DMA can load resident code as well as slots; a fill that lands inside a slot
// a window currently points at is suppressed and flagged on wreject, because
// rewriting instructions under the fetch unit has no defined result.
module tcm #(
    parameter int RESIDENT_WORDS = 2048,
    parameter int SLOT_WORDS     = 2048,
    parameter int NUM_SLOTS      = 6,

    //derived - do not override
    parameter int SLOT_SEL_W = (NUM_SLOTS > 1) ? $clog2(NUM_SLOTS) : 1,
    parameter int WORDS      = RESIDENT_WORDS + SLOT_WORDS * NUM_SLOTS,
    parameter int AW       = $clog2(WORDS),
    parameter int VIS_WORD   = RESIDENT_WORDS + 2 * SLOT_WORDS,
    parameter int VIS_AW     = $clog2(VIS_WORD)
)(
    input logic         clk,
    input logic         en,
    input logic [63:0]  addr,
    output logic [31:0] rdata,

    //Window selectors. Tied off in  core_top for now; driven by the
    //slot select CSRs in step 3.
    input logic [SLOT_SEL_W-1:0] comp_slot,
    input logic [SLOT_SEL_W-1:0] crypt_slot,

    //Fill port(physical word addr)
    input logic          we,
    input logic [AW-1:0] waddr,
    input logic [31:0]   wdata,
    output logic         wreject
);
    localparam logic [31:0] RES_W = 32'(RESIDENT_WORDS);
    localparam logic [31:0] SLT_W = 32'(SLOT_WORDS);

    logic [31:0] mem [0:WORDS-1];

    `ifndef SYNTHESIS
        //simulation only. In hardware the resident region is filled by the
        // boot DMA, so there is nothing to initialise at elaboration.
        string hexfile;
        initial begin
            if($value$plusargs("imem=%s", hexfile))
                $readmemh (hexfile, mem);
        end

        initial begin
            if(NUM_SLOTS < 3)
                if (NUM_SLOTS < 3) $fatal(1, "tcm: NUM_SLOTS must be >= 3");
        end
    `endif

        //where each window currently sits in physical space
        logic [31:0] comp_base, crypt_base;
        assign comp_base = RES_W + (32'(comp_slot) * SLT_W);
        assign crypt_base = RES_W + (32'(crypt_slot) * SLT_W);

        //read path:architectural word offset -> physical word
        logic [VIS_AW-1:0] word_off;
        assign word_off = addr[VIS_AW+1:2];

        logic [31:0] off32;
        assign off32 = {{(32-VIS_AW){1'b0}}, word_off};

        logic [31:0] phys_calc;
        always_comb begin
            if (off32 < RES_W)
                phys_calc = off32;           //resident
            else if (off32 < (RES_W + SLT_W))
                phys_calc = comp_base + (off32 - RES_W);         //COMP window
            else
                phys_calc = crypt_base + (off32 - RES_W - SLT_W);        //CRYPT Window
        end

        logic [AW-1:0] phys_word;
        assign phys_word = phys_calc[AW-1:0];

        //fil path; suppress writes to a slot a window points at
        logic [31:0] w32;
        assign w32 = {{(32-AW){1'b0}}, waddr};

        logic in_comp_live, in_crypt_live, slot_locked;
        assign in_comp_live = (w32 >= comp_base) && (w32 < (comp_base + SLT_W));
        assign in_crypt_live = (w32 >= crypt_base) && (w32 < (crypt_base + SLT_W));
        assign slot_locked = in_comp_live || in_crypt_live;

        assign wreject = we && slot_locked;

        logic fill_ok;
        assign fill_ok = we && !slot_locked;

        always_ff @( posedge clk ) begin
            if (fill_ok) mem[waddr] <= wdata;
            if (en) rdata <= mem[phys_word];
        end

endmodule
