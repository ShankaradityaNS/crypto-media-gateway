/*Compression algo img. Linked at the COMP window, NOT at a physical*/
/*slot -- the hardware translates. One image serves every slot.*/

MEMORY
{
    win (rx) : ORIGIN = 0xFFFFFFFF80002000, LENGTH = 8K
}

ENTRY(_entry)

SECTIONS
{
    /*The dispatcher jumps to the window base, so the entry point must be
    the first instruction in the img*/
    .text : {
        *(.text.entry)
        *(.text)
        *(.text.*)
        . = ALIGN(4);
    } > win

    /*The data side is not windowed. Catch any non-code section at link*/
    /*time rather than as an access fault at runtime*/
    .wdata : {
        *(.rodata) *(.rodata.*)
        *(.srodata) *(.srodata.*)
        *(.data)    *(.data.*)
        *(.sdata)   *(.sdata.*)
        *(.bss)     *(.bss.*)
        *(.sbss)    *(.sbss.*)
        *(COMMON)
    } > win
    ASSERT(SIZEOF(.wdata) == 0,
            "window image must be code-only: the data side is not windowed")

    /DISCARD/ : {
        *(.comment)
        *(.note*)
        *(.eh_frame*)
        *(.riscv.attributes)
    }
}