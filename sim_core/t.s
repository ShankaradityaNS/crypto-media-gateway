addi x1, x0, -1
addi x1, x0, -2048
sd   x1, -8(x2)
1:  beq x0, x0, 1b
    jal x1, 1b
    lui x1, 0xFFFFF
