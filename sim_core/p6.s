     lui  x1, 0x80010        # DTCM base, and the value we store
     sd   x1, 0(x1)          # bytes 00 00 01 80 FF FF FF FF

     ld   x3, 0(x1)
     addi x20, x0, 0x333     # independent: no stall, byte_off 3

     lb   x4, 3(x1)
     addi x21, x0, 0x7FF     # byte_off 7

     lbu  x5, 3(x1)
     addi x22, x0, 0x100     # byte_off 0

     lh   x6, 2(x1)
     addi x23, x0, 0x555     # byte_off 5

     lhu  x7, 2(x1)
     addi x24, x0, 0x2AA     # byte_off 2

     lw   x8, 0(x1)
     addi x25, x0, 0x111     # byte_off 1

     lwu  x9, 0(x1)
     addi x26, x0, 0x7       # byte_off 7

halt:
     lui  x30, 0x90000
     sd   x0, 0(x30)
1:   jal  x0, 1b
