    .section .text
    .globl _start
_start:
    # --- beq.S case 21: shadow of a taken branch, 20-byte forward offset
    li    x1, 1
    beq   x0, x0, 1f
    addi  x1, x1, 1
    addi  x1, x1, 1
    addi  x1, x1, 1
    addi  x1, x1, 1
1:  addi  x1, x1, 1
    addi  x1, x1, 1

    # --- jal.S case 3: same shape, unconditional jump
    li    x2, 1
    jal   x5, 2f
    addi  x2, x2, 1
    addi  x2, x2, 1
    addi  x2, x2, 1
    addi  x2, x2, 1
2:  addi  x2, x2, 1
    addi  x2, x2, 1

    lui   x30, 0x90000
    sd    x0, 0(x30)
halt_loop:
    j     halt_loop