    .section .text
    .globl _start
_start:
    j     _start_real

_start_real:
    # mtvec = ITCM_BASE + 0x100, with mode bits = 01 (vectored)
    lui   x3, 0x80000
    addi  x3, x3, 0x101
    csrw  mtvec, x3

    li    x4, 0x800            # MEIE
    csrw  mie, x4
    li    x5, 8                # mstatus.MIE
    csrs  mstatus, x5

    li    x10, 0
loop:
    addi  x10, x10, 1
    li    x11, 100
    blt   x10, x11, loop

    lui   x30, 0x90000
    sd    x0, 0(x30)
halt_loop:
    j     halt_loop

    # ---- vector table at ITCM_BASE + 0x100 ----
    .org  0x100
vec_base:                      # entry 0: where a non-vectored dispatch lands
    li    x24, 0xBAD           # must stay unreached
    j     halt_from_vec

    .org  0x12c                # entry 11 = base + 4*11, machine external
vec_ext:
    csrr  x20, mcause
    csrr  x21, mepc
    li    x22, 0x800
    csrc  mie, x22
    li    x23, 1
    mret

halt_from_vec:
    lui   x30, 0x90000
    sd    x0, 0(x30)
1:  j     1b