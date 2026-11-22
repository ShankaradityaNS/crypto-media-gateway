/* Memory map mirrors rtl/core/core_pkg.sv. Keep the two in step -- a
   mismatch does not fail the link, it shows up at runtime as an access
   fault, which is a much longer walk back to the cause. */

MEMORY
{
    itcm (rx) : ORIGIN = 0xFFFFFFFF80000000, LENGTH = 8K
    dtcm (rw) : ORIGIN = 0xFFFFFFFF80010000, LENGTH = 16K
    sig  (rw) : ORIGIN = 0xFFFFFFFF80020000, LENGTH = 8K
}

ENTRY(_start)

SECTIONS
{
    /* RVTEST_CODE_BEGIN puts the reset vector, trap vector and the whole
       test body in .text.init, so it has to come first: _start must land
       exactly on the reset PC. */
    .text : {
        *(.text.init)
        *(.text)
        *(.text.*)
        . = ALIGN(4);
    } > itcm

    .data : {
        . = ALIGN(8);
        /* const data and string literals are read with ordinary loads, so
           they must live in DTCM -- ITCM is not in the data-side memory map
           and a load from it takes an access fault. */
        *(.rodata)   *(.rodata.*)
        *(.srodata)  *(.srodata.*)
        . = ALIGN(8);
        *(.data)   *(.data.*)
        PROVIDE(__global_pointer$ = . + 0x800);
        *(.sdata)  *(.sdata.*)
        . = ALIGN(8);
        __bss_start = .;
        *(.bss)    *(.bss.*)
        *(.sbss)   *(.sbss.*)
        *(COMMON)
        . = ALIGN(8);
        __bss_end = .;
    } > dtcm

    /* Stack grows down from the top of DTCM. There is no guard region: an
       overflow runs into .bss, and the access-fault logic cannot catch it
       because the address is still inside DTCM. */
    __stack_top = ORIGIN(dtcm) + LENGTH(dtcm);

    /* riscv-tests signals pass/fail through gp, not through a signature,
       so nothing lands here for this suite. The region is declared anyway
       so adding a signature-based flow later needs no change here. */
    .signature : {
        . = ALIGN(16);
        *(.signature)
        . = ALIGN(8);
    } > sig

    /DISCARD/ : {
        *(.comment)
        *(.note*)
        *(.eh_frame*)
        *(.riscv.attributes)
    }
}