typedef unsigned char u8;
typedef unsigned long u64;      //64 bit under lp64
volatile u64 sink;      //in .bss so crt0's clear loop matters

//cur is volatile so kernel cannot be constant-folded: the inputs are
//compile-time known and at -O2 the compiler would otherwise compute the
//answer and store a literal. ref stays plain const so the test also 
//excercises a real load from .rodata -- which is what the linker script
//change was for
static volatile u8 cur[8] = { 10, 20, 30, 40, 50, 60, 70, 80 };
static const    u8 ref[8] = { 12, 18, 35, 36, 55, 60, 65, 90 };

int main(void)
{
    u64 s = 0;
    for(int i=0;i<8;i++)
    {
        u8 a = cur[i];
        u8 b = ref[i];
        s += (a>b) ? (u64)(a - b) : (u64)(b - a);
    }
    sink = s;
    return (int)s;
}