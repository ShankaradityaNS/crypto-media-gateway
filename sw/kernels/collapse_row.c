#include "common.h"
#include <riscv_vector.h>

//Dynamic bitrate collapse stand-in: aggressive quantization
//Right-shift by 3 throws away the low bits (fewer distinct values ->
//fewer bits after entropy coding), then same XOR xrypto-cycle
void collapse_row_kernel(void)
{
    uint8_t *src = (uint8_t *)SRC_ADDR;
    uint8_t *dst = (uint8_t *)DST_ADDR;

    size_t v1 = __riscv_vsetvl_e8m1(ROW_PIXELS);
    vuint8m1_t v_src = __riscv_vle8_v_u8m1(src, v1);
    vuint8m1_t v_q = __riscv_vsrl_vx_u8m1(v_src, 3, v1);
    vuint8m1_t v_out = __riscv_vxor_vx_u8m1(v_q, 0xA5, v1);
    __riscv_vse8_v_u8m1(dst, v_out, v1);
}