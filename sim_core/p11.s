    .section .text
    .globl _start
_start:
    # Each shadow slot adds a distinct power of two, so the final value
    # names exactly which one escaped the flush.
    li    x1, 0
    beq   x0, x0, 1f
    addi  x1, x1, 1       # branch + 4
    addi  x1, x1, 2       # branch + 8
    addi  x1, x1, 4       # branch + 12
    addi  x1, x1, 8       # branch + 16
1:  addi  x1, x1, 16      # target

    li    x2, 0
    jal   x5, 2f
    addi  x2, x2, 1       # jal + 4
    addi  x2, x2, 2       # jal + 8
    addi  x2, x2, 4       # jal + 12
    addi  x2, x2, 8       # jal + 16
2:  addi  x2, x2, 16      # target

    lui   x30, 0x90000
    sd    x0, 0(x30)
halt_loop:
    j     halt_loop