# Lossy 4:1 downsample, 2x2 box average. Output length = input/4.
# Walks row pointers rather than multiplying, since there is no M extension.
#
# Window image ABI: a0=in, a1=len, a2=out, a3=width
#                   -> a0 = out len, a1 = image id
    .section .text.entry, "ax"
    .globl _entry
_entry:
    mv   a4, a0                 # row base
    mv   a5, a2                 # dst
    add  a6, a0, a1             # image end
L_row:
    mv   t2, a4                 # &in[y][0]
    add  t6, a4, a3             # row end
L_col:
    lbu  t3, 0(t2)
    lbu  t4, 1(t2)
    add  t3, t3, t4
    add  t5, t2, a3             # next row
    lbu  t4, 0(t5)
    add  t3, t3, t4
    lbu  t4, 1(t5)
    add  t3, t3, t4
    srli t3, t3, 2
    sb   t3, 0(a5)
    addi a5, a5, 1
    addi t2, t2, 2
    bltu t2, t6, L_col
    add  a4, a4, a3             # skip two rows
    add  a4, a4, a3
    bltu a4, a6, L_row
    srli a0, a1, 2
    li   a1, 0xC0B
    ret
    