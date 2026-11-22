#include "common.h"
#include <riscv_vector.h>

//Same row shape (16 pixels/128 bits), different ops: pure XOR  pass
//with no offset setup. This is the "other kernel" for the switch/hot-swap test
void xor_row_kernel(void)
{
    uint8_t *src = (uint8_t *)SRC_ADDR;
    uint8_t *dst = (uint8_t *)DST_ADDR;

    //size_t v1 = __riscv_vsetvli(ROW_PIXELS, __RISCV_VSEW_8, __RISCV_VLMUL_M1);
    size_t v1 = __riscv_vsetvl_e8m1(ROW_PIXELS);

    vuint8m1_t v_src = __riscv_vle8_v_u8m1(src, v1);
    vuint8m1_t v_out = __riscv_vxor_vx_u8m1(v_src, 0x5A, v1);

    __riscv_vse8_v_u8m1(dst, v_out, v1);
}