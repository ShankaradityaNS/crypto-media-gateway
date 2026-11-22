    .section .text
    .globl _start
_start:
    lui   x1, 0x80010          # x1 = 0xFFFFFFFF80010000  (DTCM base)

    # ---- seed three source words ----
    li    x2, 0x11
    sd    x2, 0(x1)
    li    x3, 0x22
    sd    x3, 8(x1)
    li    x4, 0x33
    sd    x4, 16(x1)

    # ---- canary: nothing in this program may touch offset 56 ----
    li    x28, 0x7E
    sd    x28, 56(x1)

    # ---- the case under test: each store's rs2 is produced by the load
    # ---- directly above it, so each pair stalls once and forwards into
    # ---- store_data rather than into an ALU operand
    ld    x5, 0(x1)
    sd    x5, 24(x1)
    ld    x6, 8(x1)
    sd    x6, 32(x1)
    ld    x7, 16(x1)
    sd    x7, 40(x1)

    # ---- read the copies and the canary back ----
    ld    x10, 24(x1)
    ld    x11, 32(x1)
    ld    x12, 40(x1)
    ld    x13, 56(x1)
    ld    x14, 0(x1)

    lui   x30, 0x90000
    sd    x0, 0(x30)           # halt
halt_loop:
    j     halt_loop