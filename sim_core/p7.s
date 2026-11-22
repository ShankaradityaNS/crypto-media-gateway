    .section .text
    .globl _start
_start:
    lui   x1, 0x80010          # x1 = 0xFFFFFFFF80010000  (DTCM base)

    # ---- sb: bytes 0, 1, 7 of doubleword 0 ----
    sd    x0, 0(x1)            # clear
    addi  x2, x0, 0x11
    sb    x2, 0(x1)
    addi  x3, x0, 0x22
    sb    x3, 1(x1)
    addi  x4, x0, 0x33
    sb    x4, 7(x1)
    ld    x10, 0(x1)

    # ---- sh: halfwords at offsets 8 and 14 ----
    sd    x0, 8(x1)            # clear
    lui   x5, 0x1
    addi  x5, x5, 0x234        # 0x1234
    sh    x5, 8(x1)
    lui   x6, 0x5
    addi  x6, x6, 0x678        # 0x5678
    sh    x6, 14(x1)
    ld    x11, 8(x1)

    # ---- sw: words at offsets 16 and 20 ----
    sd    x0, 16(x1)           # clear
    lui   x7, 0x12345
    addi  x7, x7, 0x678        # 0x12345678
    sw    x7, 16(x1)
    lui   x8, 0x7abcd
    addi  x8, x8, 0x0ef        # 0x7abcd0ef
    sw    x8, 20(x1)
    ld    x12, 16(x1)

    lui   x30, 0x90000
    sd    x0, 0(x30)           # halt
halt_loop:
    j     halt_loop
