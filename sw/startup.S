.section .text.start
.global _start
_start:
    li t0, 0x10000000
    li t1, 66
    sb t1, 0(t0)          # 'B'

    la t2, trap_handler
    csrw mtvec, t2

    li t1, 67
    sb t1, 0(t0)          # 'C' -- confirms we got past the csrw alive

    la sp, _stack_top

    li t1, 68
    sb t1, 0(t0)          # 'D' -- confirms sp setup didn't fault

        # Enable FPU (FS=Initial) and Vector unit (VS=Initial) in mstatus.
    # FS = bits [14:13], VS = bits [10:9]. Initial state = 0b01 each.
    li   t3, (1 << 13) | (1 << 9)
    csrs mstatus, t3

    li t1, 69
    sb t1, 0(t0)          # 'E' -- confirms mstatus write survived

    call main
loop:
    j loop

trap_handler:
    li t0, 0x10000000
    li t1, 84             # 'T'
    sb t1, 0(t0)
    csrr t3, mcause
1:  j 1b