//Configuration. This is the one file to edit when re-sizing the design;
//everything else derives from it. Synthesis picks these up at elaboration,
//so a resize is a rebuild, not a redesign.
package cmg_config;

    //instruction memory
    //Resident code is never swapped: main loop, dispatcher, trap handler
    //DMA control. Must be large enough for all of it.
    localparam int RESIDENT_BYTES = 8192;

    //One uniform slot size for shared pool. An algorithm that does not
    //fit fails at link time, which is the failure mode we want.
    localparam int SLOT_BYTES = 8192;

    //How many slots in the pool. Either window can select any of them, so
    //the split between compression and encryption algo is a loading
    //decision rather than a HW one.
    localparam int NUM_SLOTS = 6;       // 2 active + 2 staging + 2 golden

    // Slot roles are a convention, not something the RTL knows. Nothing
    // privileges any slot number; these name the integrator's choice.
    localparam int GOLDEN_COMP_SLOT   = 4;
    localparam int GOLDEN_CRYPT_SLOT  = 5;
    localparam int DEFAULT_COMP_SLOT  = GOLDEN_COMP_SLOT;
    localparam int DEFAULT_CRYPT_SLOT = GOLDEN_CRYPT_SLOT;

    //data memory
    localparam int DTCM_BYTES = 16384;
    localparam int SIG_BYTES = 8192;

endpackage
