#ifndef COMMON_H
#define COMMON_H

#include <stdint.h>

#define ROW_PIXELS 16       //1 row = 16 pixels = 128 bits @ 8-bit/pixel
#define SRC_ADDR 0x80010000 //hardcoded i/p row addr (matches linker script)
#define REF_ADDR 0x80011000 //hardcoded ref row (for SAD diff)
#define DST_ADDR 0x80012000 //hardcoded o/p addr

#define DST_SCALAR_ADDR 0x80013000

#define UART_BASE 0x10000000UL
static inline void uart_putc(char c)
{
    volatile uint8_t *uart = (volatile uint8_t *)UART_BASE;
    *uart = c;
}
static inline void uart_puts(const char *s)
{
    while(*s) uart_putc(*s++);
}
static inline void uart_puthex(uint8_t v)
{
    const char hex[] = "0123456789ABCDEF";
    uart_putc(hex[(v >> 4) & 0xF]);
    uart_putc(hex[v & 0xF]);
}
static inline uint64_t read_instret(void)
{
    uint64_t v;
    asm volatile ("rdinstret %0" : "=r"(v));
    return v;
}
static inline void uart_puthex64(uint64_t v)
{
    const char hex[] = "0123456789ABCDEF";
    for(int i=15;i>=0;i--)
        uart_putc(hex[(v >> (i*4)) & 0xF]);
}
static inline void uart_putdec(uint64_t v)
{
    char buf[24]; int i=0;
    if(!v)
    {
        uart_putc('0');
        return;
    }
    while (v)
    {
        buf[i++] = '0' + (v % 10);
        v = v/10;
    }
    while (i--)
    {
        uart_putc(buf[i]);
    }
    
    
}
#endif