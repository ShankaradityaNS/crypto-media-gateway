//Minimal riscv-tests environment for the crypto-media-gateway core

//The stock env/p/riscv_test.h cannot be used here: it requires PMP
// (pmpaddr0, pmpcfg0), Smrnmi (mnstatus), supervisor mode (satp, medeleg,
// mideleg), mie and mhartid, none of which this core implements, and it
// reports results by writing a `tohost` word that a host harness polls.
//
// This version keeps every macro name and keeps gp (TESTNUM) meaning
// exactly what it means upstream, so the test sources are used unmodified.
// The result is reported by storing to HALT_ADDR, which the testbench
// already watches, leaving the verdict in gp for it to read.

#ifndef _ENV_CMG_CORE_H
#define _ENV_CMG_CORE_H

#define TESTNUM gp

//Mirrors HALT_ADDR in rtl/core/core_pkg.sv. This is a 32-bit
//state to enable, so 'li' assembles it as a single lui
#define CMG_HALT_ADDR 0xFFFFFFFF90000000

//ISA Init. This Core is RV64I + Zicsr + Zifencei: no FPU and no vector
// state to enable, so init is empty. RV64M is aliased to the same thing
// so the rv64mi machine-mode tests can use this header too.

#define RVTEST_RV64U .macro init; .endm
#define RVTEST_RV64M .macro init; .endm

#define INIT_XREG                                                       \
  li x1, 0;  li x2, 0;  li x4, 0;  li x5, 0;                            \
  li x6, 0;  li x7, 0;  li x8, 0;  li x9, 0;                            \
  li x10, 0; li x11, 0; li x12, 0; li x13, 0;                           \
  li x14, 0; li x15, 0; li x16, 0; li x17, 0;                           \
  li x18, 0; li x19, 0; li x20, 0; li x21, 0;                           \
  li x22, 0; li x23, 0; li x24, 0; li x25, 0;                           \
  li x26, 0; li x27, 0; li x28, 0; li x29, 0;                           \
  li x30, 0; li x31, 0;

//Entry
//Word 0 is the reset vector and jumps over the trap vector, so the
//handler sits at a small fixed offset -- which matters because a test
//that faults before mtvec is written still has somewhere to land.

//Unlike the stock env we do NOT mret into the test body. The stock
// sequence clears mstatus and mrets, which requests user mode via
// MPP = 0; this core is M-mode only. Falling through keeps it in M-mode
// throughout and removes a step that could fail for reasons unrelated to
// the instruction under test.

#define RVTEST_CODE_BEGIN                                               \
        .section .text.init;                                            \
        .align 6;                                                       \
        .weak mtvec_handler;                                            \
        .globl _start;                                                  \
_start:                                                                 \
        j cmg_reset_vector;                                             \
        .align 2;                                                       \
cmg_trap_vector:                                                        \
        /* An ecall is how RVTEST_PASS and RVTEST_FAIL arrive here. */   \
        csrr t5, mcause;                                                \
        li   t6, 11;                    /* environment call from M */   \
        beq  t5, t6, cmg_halt;                                          \
        /* Otherwise defer to the test's own handler if it defines one.  \
           rv64mi tests do; rv64ui tests do not, and the weak symbol     \
           resolves to zero for them. */                                \
        la   t5, mtvec_handler;                                         \
        beqz t5, cmg_unexpected;                                        \
        jr   t5;                                                        \
cmg_unexpected:                                                         \
        /* Mark the number so a stray fault can never be mistaken for a  \
           pass, matching the upstream convention. */                    \
        ori  TESTNUM, TESTNUM, 1337;                                    \
cmg_halt:                                                               \
        li   t5, CMG_HALT_ADDR;                                         \
        sd   zero, 0(t5);                                               \
cmg_spin:                                                               \
        j    cmg_spin;                                                  \
cmg_reset_vector:                                                       \
        INIT_XREG;                                                      \
        li   TESTNUM, 0;                                                \
        la   t0, cmg_trap_vector;                                       \
        csrw mtvec, t0;                                                 \
        init;                                                           \
1:

#define RVTEST_CODE_END unimp

// Pass/fail. Both land in the trap vector via ecall and halt there, with
// the verdict in gp: 1 on pass, and on failure (n << 1) | 1 where n is
// the failing test number -- the upstream encoding, so the standard
// decoding of gp still applies.

#define RVTEST_PASS                                                     \
        fence;                                                          \
        li TESTNUM, 1;                                                  \
        ecall

#define RVTEST_FAIL                                                     \
        fence;                                                          \
1:      beqz TESTNUM, 1b;                                               \
        sll TESTNUM, TESTNUM, 1;                                        \
        or  TESTNUM, TESTNUM, 1;                                        \
        ecall

// Data section. No tohost: nothing polls memory here.

#define RVTEST_DATA_BEGIN .align 4; .global begin_signature; begin_signature:
#define RVTEST_DATA_END   .align 4; .global end_signature;   end_signature:

#endif