#include "common.h"

extern void sad_row_kernel(void);
extern void xor_row_kernel(void);
extern void collapse_row_kernel(void);
extern void sad_row_scalar(void);

//Test data placed at he fixed addr via linker section
__attribute__((section(".src_row"))) uint8_t src_row[ROW_PIXELS] = {10, 20, 30,
                40, 50, 60, 70, 80, 90, 100, 110, 120, 130, 140, 150, 160};
__attribute__((section(".ref_row"))) uint8_t ref_row[ROW_PIXELS] = {5, 5, 5,
                5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5};

typedef void (*kernel_fn)(void);

#define PROFILE_NORMAL 0
#define PROFILE_COLLAPSE 1

static kernel_fn profile_table[2] = {sad_row_kernel, collapse_row_kernel};

static void dump_row(uint8_t *p)
{
    for(int i=0;i<ROW_PIXELS;i++)
    {
        uart_puthex(p[i]);
        uart_putc(' ');
    }
}

int main(void)
{
    //Item 1: Instruction count comparison
    uint64_t t0 = read_instret();
    sad_row_scalar();
    uint64_t t1 = read_instret();
    sad_row_kernel();
    uint64_t t2 = read_instret();

    uart_puts("\r\nscalar instret: "); uart_putdec(t1 - t0);
    uart_puts("\r\nvector instret: "); uart_putdec(t2 - t1);
    uart_puts("\r\n");

    //sanity: both paths must produce identical bytes
    uart_puts("Scalar out: ");
    dump_row((uint8_t *)DST_SCALAR_ADDR);
    uart_puts("\r\nVector out: ");
    dump_row((uint8_t *)DST_ADDR);
    uart_puts("\r\n\r\n");

    //Item 3: switch test
    int profile = PROFILE_NORMAL;
    for(int frame=0;frame<10;frame++)
    {
        //Trigger: "jamming detected" at frame 5
        if(frame == 5 && profile == PROFILE_NORMAL)
        {
            profile = PROFILE_COLLAPSE;
            uart_puts(">>> Link Degraded - switching profile\r\n");
        }
        uint64_t a = read_instret();
        profile_table[profile]();
        uint64_t b = read_instret();

        uart_puts("Frame: ");
        uart_putdec(frame);
        uart_puts("Profile: ");
        uart_putdec(profile);
        uart_puts(" Instret ");
        uart_putdec(b - a);
        uart_puts("  Out: ");
        dump_row((uint8_t *)DST_ADDR);
        uart_puts("\r\n");
    }
    /*
    sad_row_kernel();
    uart_putc('2');           // kernel returned
    uart_puts("SAD+XOR result: ");
    sad_row_kernel();       //run kernel A
    xor_row_kernel();
    uart_puts("SAD+XOR result: ");
    uint8_t *dst = (uint8_t *)DST_ADDR;
    for(int i=0;i<ROW_PIXELS;i++)
    {
        uart_puthex(dst[i]);
        uart_putc(' ');
    }
    uart_puts("\r\n");
    */
    while(1) {}
    return 0;
}