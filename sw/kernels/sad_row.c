#include "common.h"
#include <riscv_vector.h>

//Process 1 row of 16 pixels using RVV instructions
//Op: vector-load -> dummy offset subtraction -> XOR "crypto" stub -> writeback
void sad_row_kernel(void)
{
    uint8_t *src = (uint8_t *)SRC_ADDR;
    uint8_t *ref = (uint8_t *)REF_ADDR;
    uint8_t *dst = (uint8_t *)DST_ADDR;

    //vsetvli: set vector length for 16 x 8-bit elements.
    //This is the RVV idiom for "how many elements can I process this instruction"
    //size_t v1 = __riscv_vsetvli(ROW_PIXELS, __RISCV_VSEW_8, __RISCV_VLMUL_M1);
    size_t v1 = __riscv_vsetvl_e8m1(ROW_PIXELS);

    //Vector Load: pull 16 pixels (128 bits) from src in 1 instruction
    vuint8m1_t v_src = __riscv_vle8_v_u8m1(src, v1);
    vuint8m1_t v_ref = __riscv_vle8_v_u8m1(ref, v1);

    //Dummy "Offset Subtraction" - stand-in for a read DC-offset or
    //motion-compensation step. Saturating subtract avoids underflow wraparound
    //uint8m1_t v_diff = __riscv_vssub_vv_u8m1(v_src, v_ref, v1);
    vuint8m1_t v_diff = __riscv_vssubu_vv_u8m1(v_src, v_ref, v1);


    //Inline XOR "crypto primitive" stub - stand-in for a real AES round.
    //XOR with a fixed pattern (0xA5) just to exercide the crypto-stage slot
    //in the pipeline; swap for a real AES round function later.
    vuint8m1_t v_out = __riscv_vxor_vx_u8m1(v_diff, 0xA5, v1);

    //Vector store: write the row back to hardcoded diestination
    __riscv_vse8_v_u8m1(dst, v_out, v1);
}