    .section .text
    .globl _start
_start:
    j     _start_real          # 0x00, jump over the handler

trap_handler:                  # ITCM_BASE + 0x04
    csrr  x20, mcause
    csrr  x21, mepc
    # Mask our own source. mip.MEIP mirrors the pin and the handler cannot
    # clear it, so without this the mret would re-trap immediately -- a real
    # handler would acknowledge at the interrupt controller instead.
    li    x22, 0x800           # MEIE
    csrc  mie, x22
    li    x23, 1               # flag: the handler ran
    mret

_start_real:
    lui   x3, 0x80000
    addi  x3, x3, 4            # mtvec = handler, direct mode
    csrw  mtvec, x3

    li    x4, 0x800            # enable MEIE
    csrw  mie, x4
    li    x5, 8                # enable mstatus.MIE
    csrs  mstatus, x5

    li    x10, 0
loop:
    addi  x10, x10, 1
    li    x11, 100
    blt   x10, x11, loop       # spin; the interrupt lands mid-loop

    lui   x30, 0x90000
    sd    x0, 0(x30)
halt_loop:
    j     halt_loop