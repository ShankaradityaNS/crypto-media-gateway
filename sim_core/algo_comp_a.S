# Differential PCM. out[0] = in[0], out[i] = in[i] - in[i-1] mod 256.
# Lossless, output length == input length.
#
# Window image ABI: a0=in, a1=len, a2=out, a3=width
#                   -> a0 = out len, a1 = image id
# May clobber a0-a7, t0-t6, ra. Preserves s0-s11 and sp.
    .section .text.entry, "ax"
    .globl _entry
_entry:
    mv   a4, a0                 # src
    mv   a5, a2                 # dst
    add  a6, a0, a1             # src end
    li   t0, 0                  # prev
L_px:
    lbu  t1, 0(a4)
    sub  t2, t1, t0
    andi t2, t2, 0xFF
    sb   t2, 0(a5)
    mv   t0, t1
    addi a4, a4, 1
    addi a5, a5, 1
    bltu a4, a6, L_px
    mv   a0, a1                 # out len == in len
    li   a1, 0xC0A
    ret
    