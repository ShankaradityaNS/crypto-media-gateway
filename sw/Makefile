CC = riscv64-unknown-elf-gcc
ARCH = -march=rv64gcv -mabi=lp64d -mcmodel=medany
CFLAGS = $(ARCH) -O2 -nostdlib -nostartfiles -ffreestanding -Wall
LDFLAGS = -T linker.ld -nostdlib

VEC_SRCS = startup.S kernels/main.c kernels/sad_row.c kernels/xor_row.c kernels/collapse_row.c
SCALAR_SRC = kernels/sad_row_scalar.c
OUT = kernel.elf

all: $(OUT)

scalar.o: $(SCALAR_SRC)
	$(CC) $(CFLAGS) -fno-tree-vectorize -c $(SCALAR_SRC) -o scalar.o

$(OUT): $(VEC_SRCS) scalar.o linker.ld
	$(CC) $(CFLAGS) $(LDFLAGS) $(VEC_SRCS) scalar.o -o $(OUT)

run: $(OUT)
	timeout 10 qemu-system-riscv64 -M virt -cpu rv64,v=true,vlen=128 \
	    -bios none -nographic -kernel $(OUT)

disasm: $(OUT)
	riscv64-unknown-elf-objdump -d $(OUT)

clean:
	rm -f $(OUT) scalar.o