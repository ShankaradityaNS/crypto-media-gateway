    .section .text
    .globl _start
_start:
    j     _start_real          # word 0 jumps over the handler

trap_handler:                  # ITCM_BASE + 0x04
    csrr  x20, mstatus         # inside the handler: MIE must be 0, MPIE 1
    csrr  x21, mepc
    addi  x22, x21, 4
    csrw  mepc, x22
    mret

_start_real:                   # ITCM_BASE + 0x18
    lui   x3, 0x80000
    addi  x3, x3, 4
    csrw  mtvec, x3

    # mie masking: write all ones, only MEIE should stick
    li    x4, -1
    csrw  mie, x4
    csrr  x5, mie

    # mip with no external request
    csrr  x6, mip

    # enable interrupts globally and read it back
    li    x7, 8                # mstatus.MIE, bit 3
    csrs  mstatus, x7
    csrr  x8, mstatus

    ecall                      # trap; the handler captures mstatus

    csrr  x9, mstatus          # after mret: MIE restored, MPIE set

    lui   x30, 0x90000
    sd    x0, 0(x30)
halt_loop:
    j     halt_loop