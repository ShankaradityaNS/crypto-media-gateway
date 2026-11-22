OUTPUT_ARCH( "riscv" )
ENTRY (_start)

SECTIONS {
    . = 0x80000000;
    .text : {
        *(.text.start)
        *(.text*)
    }
    .data : { *(.data*)}
    .bss : { *(.bss*)}

    . = 0x80010000;
    .src_row : { KEEP(*(.src_row))}
    . = 0x80011000;
    .ref_row : { KEEP(*(.ref_row))}
    . = 0x80012000;
    .dst_row : { KEEP(*(.dst_row))}

    _stack_top = 0x80020000;
}