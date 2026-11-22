    .section .text
    .globl _start

    # Word 0 is the reset vector. It jumps over the handler so that the
    # handler lands at a fixed, known address -- ITCM_BASE + 4 -- which is
    # what lets us load mtvec without a linker resolving a symbol.
    j     _start

trap_handler:                  # ITCM_BASE + 0x04
    csrr  x20, mcause
    csrr  x21, mepc
    csrr  x22, mtval
    addi  x23, x21, 4          # resume past the faulting instruction
    csrw  mepc, x23
    mret

_start:                        # ITCM_BASE + 0x1C
    lui   x1, 0x80010          # x1 = DTCM base
    li    x2, 0x55

    lui   x3, 0x80000          # mtvec = ITCM_BASE + 4; low two bits are
    addi  x3, x3, 4            #   00, which selects direct mode
    csrw  mtvec, x3

    sd    x0, 0(x1)            # canary at offset 0, must stay zero

    sh    x2, 1(x1)            # MISALIGNED. Traps, and must not write.

    li    x24, 0x7ab           # reached only if mret resumed correctly
    ld    x25, 0(x1)           # read the canary back

    lui   x30, 0x90000
    sd    x0, 0(x30)           # halt
halt_loop:
    j     halt_loop
