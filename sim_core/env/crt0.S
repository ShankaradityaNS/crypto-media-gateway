//C runtime startup. Sets up the stack and global pointer, clears .bss,
//calls main, then halts with main's return value still in a0.
    .section .text.init
    .global _start
_start:
    //Stack grows down from top of DTCM
    la sp, __stack_top

    //gp lets the linker relax small-data accesses into gp-relative loads.
    //Relaxation must be off for this one instruction, or the linker would
    //relax the very instruction that establishes gp into a gp-relative one.
    .option push
    .option norelax
    la gp, __global_pointer$
    .option pop

    //clear .bss The linker script aligns both bounds to 8, so a doubleword
    //loop  needs no head or tail handling
    la t0, __bss_start
    la t1, __bss_end
1:  bgeu t0, t1, 2f
    sd zero, 0(t0)
    addi t0, t0, 8
    j 1b

2: call main

    //mains return value is left untouched in a0 for the testbench to read.
    //HALT_ADDR, mirrired from rtl/core/core_pkg.sv
    li t0, 0xFFFFFFFF90000000
    sd zero, 0(t0)
3:  j 3b