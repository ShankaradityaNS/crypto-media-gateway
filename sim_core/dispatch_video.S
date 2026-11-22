    .option norelax

    .equ CSR_SLOT_COMP,   0x7C5
    .equ CSR_SLOT_CRYPT,  0x7C6
    .equ CSR_SLOT_COMMIT, 0x7C7
    .equ CSR_SLOT_LIVE,   0x7C8

    .equ COMP_ENTRY,  0xFFFFFFFF80002000
    .equ CRYPT_ENTRY, 0xFFFFFFFF80004000
    .equ SIG_BASE,    0xFFFFFFFF80020000
    .equ SIG_TRAILER, 0xFFFFFFFF80021000       # SIG_BASE + 4096
    .equ HALT_ADDR,   0xFFFFFFFF90000000

    # DTCM layout, filled by the harness through +dmem
    .equ DTCM_BASE,  0xFFFFFFFF80010000
    .equ TILE_IN,    DTCM_BASE                 # 3072 bytes of pixels
    .equ TILE_LEN,   3072
    .equ TILE_W,     64
    .equ KEY_ADDR,   DTCM_BASE + 3072          # 16-byte XTEA key
    .equ CTRL_ADDR,  DTCM_BASE + 3088          # [0]=comp slot, [4]=crypt slot
    .equ COMP_BUF,   DTCM_BASE + 3096          # 8-byte aligned

    .section .text.init, "ax"
    .globl _start
_start:
    la   t0, trap_handler
    csrw mtvec, t0
    la   sp, __stack_top

    # ---- stage the requested algorithm pair, then commit it ----
    li   t0, CTRL_ADDR
    lw   t1, 0(t0)
    csrw CSR_SLOT_COMP, t1
    lw   t1, 4(t0)
    csrw CSR_SLOT_CRYPT, t1
    li   t1, 1
    csrw CSR_SLOT_COMMIT, t1
    csrr s0, CSR_SLOT_LIVE      # what the hardware says is live

    # ---- compress ----
    li   a0, TILE_IN
    li   a1, TILE_LEN
    li   a2, COMP_BUF
    li   a3, TILE_W
    li   t1, COMP_ENTRY
    jalr t1
    mv   s1, a0                 # compressed length
    mv   s2, a1                 # comp image id

    # ---- encrypt ----
    li   a0, COMP_BUF
    mv   a1, s1
    li   a2, SIG_BASE
    li   a3, KEY_ADDR
    li   t1, CRYPT_ENTRY
    jalr t1
    mv   s3, a0                 # ciphertext length
    mv   s4, a1                 # crypt image id

    # ---- trailer: evidence of what actually ran ----
    li   t0, SIG_TRAILER
    sw   s3, 0(t0)
    sw   s2, 4(t0)
    sw   s4, 8(t0)
    sw   s0, 12(t0)

    li   gp, 1
    j    halt

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

halt:
    li   t0, HALT_ADDR
    sw   zero, 0(t0)
L_spin:
    j    L_spin
    