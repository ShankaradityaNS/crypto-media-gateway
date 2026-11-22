     lui  x1, 0x80010        # DTCM base
     addi x2, x0, 42
     sd   x2, 0(x1)
     ld   x3, 0(x1)
     addi x4, x3, 1          # load-use hazard: needs a stall
     addi x5, x0, 3
     addi x6, x0, 0
1:   addi x6, x6, 10
     addi x5, x5, -1
     bne  x5, x0, 1b
     addi x7, x0, 99
     lui  x30, 0x90000
     sd   x0, 0(x30)
2:   jal  x0, 2b
