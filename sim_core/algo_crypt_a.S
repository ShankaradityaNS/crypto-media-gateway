# XTEA-ECB, 32 rounds. Linked at the CRYPT window.
#
# Window image ABI:
#   a0 = input ptr, a1 = length (multiple of 8), a2 = output ptr,
#   a3 = key ptr  ->  a0 = output length, a1 = image id
#   May clobber a0-a7, t0-t6, ra. Preserves s0-s11 and sp.
#
# ECB with a fixed key is here to exercise a real cipher's instruction mix,
# not to protect anything. CTR is the mode a real build would use.
    .section .text.entry, "ax"
    .globl _entry
_entry:
    mv    a4, a0                # src
    mv    a5, a2                # dst
    add   a6, a0, a1            # src end
    mv    a7, a1                # length, to return

L_blk:
    lw    t0, 0(a4)             # v0
    lw    t1, 4(a4)             # v1
    li    t2, 0                 # sum
    li    t3, 32                # rounds
    # delta, written sign-extended: every consumer is a W op, so the
    # upper bits are never read
    li    t4, 0xFFFFFFFF9E3779B9

L_rnd:
    slliw t5, t1, 4
    srliw t6, t1, 5
    xor   t5, t5, t6
    addw  t5, t5, t1
    andi  t6, t2, 3
    slli  t6, t6, 2
    add   t6, a3, t6
    lw    t6, 0(t6)
    addw  t6, t6, t2
    xor   t5, t5, t6
    addw  t0, t0, t5

    addw  t2, t2, t4            # sum += delta

    slliw t5, t0, 4
    srliw t6, t0, 5
    xor   t5, t5, t6
    addw  t5, t5, t0
    srliw t6, t2, 11
    andi  t6, t6, 3
    slli  t6, t6, 2
    add   t6, a3, t6
    lw    t6, 0(t6)
    addw  t6, t6, t2
    xor   t5, t5, t6
    addw  t1, t1, t5

    addi  t3, t3, -1
    bnez  t3, L_rnd

    sw    t0, 0(a5)
    sw    t1, 4(a5)
    addi  a4, a4, 8
    addi  a5, a5, 8
    bltu  a4, a6, L_blk

    mv    a0, a7
    li    a1, 0xE0A
    ret
    