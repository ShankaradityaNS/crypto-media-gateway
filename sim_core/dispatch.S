    .option norelax
    .include "expect.S"

    .equ CSR_SLOT_COMP,   0x7C5
    .equ CSR_SLOT_CRYPT,  0x7C6
    .equ CSR_SLOT_COMMIT, 0x7C7
    .equ CSR_SLOT_LIVE,   0x7C8

    .equ COMP_ENTRY,  0xFFFFFFFF80002000
    .equ CRYPT_ENTRY, 0xFFFFFFFF80004000
    .equ SIG_BASE,    0xFFFFFFFF80020000
    .equ HALT_ADDR,   0xFFFFFFFF90000000

    .equ IMG_LEN, 4096
    .equ IMG_W,   64

    .section .text.init, "ax"
    .globl _start
_start:
    la   t0, trap_handler
    csrw mtvec, t0
    la   sp, __stack_top

    # ---- the core must see the image we built ----
    la   t0, img_data
    li   t1, IMG_LEN
    add  t1, t0, t1
    li   t3, 0
L_isum:
    lbu  t2, 0(t0)
    add  t3, t3, t2
    addi t0, t0, 1
    bltu t0, t1, L_isum
    li   gp, 1
    li   t0, IMG_SUM
    beq  t3, t0, L_ok1
    mv   gp, t3
    j    halt
L_ok1:

    # ---- windows onto the frame-N pair: comp slot 0, crypt slot 1 ----
    li   t0, 0
    csrw CSR_SLOT_COMP, t0
    li   t0, 1
    csrw CSR_SLOT_CRYPT, t0
    li   t0, 1
    csrw CSR_SLOT_COMMIT, t0

    # ---- frame N: compress ----
    la   a0, img_data
    li   a1, IMG_LEN
    la   a2, comp_buf
    li   a3, IMG_W
    li   t1, COMP_ENTRY
    jalr t1
    mv   s0, a1                 # x8  comp image id
    mv   t4, a0                 # compressed length

    # ---- frame N: encrypt ----
    la   a0, comp_buf
    mv   a1, t4
    li   a2, SIG_BASE
    la   a3, xtea_key
    li   t1, CRYPT_ENTRY
    jalr t1
    mv   s1, a1                 # x9  crypt image id
    mv   s2, a0                 # x18 ciphertext length

    li   t0, SIG_BASE
    add  t1, t0, s2
    li   s3, 0                  # x19 frame N checksum
L_sumN:
    lbu  t2, 0(t0)
    add  s3, s3, t2
    addi t0, t0, 1
    bltu t0, t1, L_sumN

    # ---- a swap request arrives mid-frame: stage it, do not apply it ----
    li   t0, 2
    csrw CSR_SLOT_COMP, t0
    li   t0, 3
    csrw CSR_SLOT_CRYPT, t0

    csrr s5, CSR_SLOT_COMMIT    # x21 outstanding
    csrr s4, CSR_SLOT_LIVE      # x20 must STILL be old, even after that read

    # ---- frame boundary ----
    li   t0, 1
    csrw CSR_SLOT_COMMIT, t0
    csrr s6, CSR_SLOT_LIVE      # x22

    # ---- frame N+1: compress ----
    la   a0, img_data
    li   a1, IMG_LEN
    la   a2, comp_buf
    li   a3, IMG_W
    li   t1, COMP_ENTRY
    jalr t1
    mv   s7, a1                 # x23
    mv   t4, a0

    # ---- frame N+1: encrypt ----
    la   a0, comp_buf
    mv   a1, t4
    li   a2, SIG_BASE + 4096
    la   a3, xtea_key
    li   t1, CRYPT_ENTRY
    jalr t1
    mv   s8, a1                 # x24
    mv   s9, a0                 # x25

    li   t0, SIG_BASE + 4096
    add  t1, t0, s9
    li   s10, 0                 # x26 frame N+1 checksum
L_sumN1:
    lbu  t2, 0(t0)
    add  s10, s10, t2
    addi t0, t0, 1
    bltu t0, t1, L_sumN1

    # ---- verify ----
    li   gp, 2
    li   t0, 0xC0A
    bne  s0, t0, fail
    li   gp, 3
    li   t0, 0xE0A
    bne  s1, t0, fail
    li   gp, 4
    li   t0, IMG_LEN
    bne  s2, t0, fail

    li   gp, 5
    li   t0, SUM_N
    beq  s3, t0, L_ok5
    mv   gp, s3
    j    halt
L_ok5:

    li   gp, 6
    li   t0, 0x100              # live still comp 0 / crypt 1
    bne  s4, t0, fail
    li   gp, 7
    li   t0, 1
    bne  s5, t0, fail
    li   gp, 8
    li   t0, 0x302              # live now comp 2 / crypt 3
    bne  s6, t0, fail

    li   gp, 9
    li   t0, 0xC0B
    bne  s7, t0, fail
    li   gp, 10
    li   t0, 0xE0B
    bne  s8, t0, fail
    li   gp, 11
    li   t0, 1024
    bne  s9, t0, fail

    li   gp, 12
    li   t0, SUM_N1
    beq  s10, t0, L_ok12
    mv   gp, s10
    j    halt
L_ok12:

    li   gp, 1
    j    halt

fail:
    slli gp, gp, 1
    ori  gp, gp, 1
halt:
    li   t0, HALT_ADDR
    sw   zero, 0(t0)
L_spin:
    j    L_spin

trap_handler:
    csrr t0, mcause
    csrr t1, mepc
    andi t0, t0, 0xF
    slli t0, t0, 16
    li   t2, 0xFFFF
    and  t1, t1, t2
    or   gp, t0, t1
    li   t0, HALT_ADDR
    sw   zero, 0(t0)
L_tspin:
    j    L_tspin

    .section .data
    .globl img_data
img_data:
    .incbin "image64.raw"
    .globl xtea_key
xtea_key:
    .word 0x0BADC0DE
    .word 0x12345678
    .word 0x9ABCDEF0
    .word 0x0F1E2D3C
    .balign 8
    .globl comp_buf
comp_buf:
    .space 4096
    