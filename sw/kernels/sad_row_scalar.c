#include "common.h"

//Same ops as sad_row_kernel, written scalar
__attribute__((noinline))
void sad_row_scalar(void)
{
    volatile uint8_t *src = (volatile uint8_t *)SRC_ADDR;
    volatile uint8_t *ref = (volatile uint8_t *)REF_ADDR;
    volatile uint8_t *dst = (volatile uint8_t *)DST_SCALAR_ADDR;

    for(int i=0;i<ROW_PIXELS;i++)
    {
        uint8_t a = src[i], b = ref[i];
        uint8_t d = (a > b) ? (uint8_t)(a - b) : 0;
        dst[i] = d ^ 0xA5;
    }
}