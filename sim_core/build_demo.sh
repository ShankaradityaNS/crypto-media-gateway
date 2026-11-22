#!/usr/bin/env bash
set -e
ARCH=rv64i_zicsr_zifencei
AS="riscv64-unknown-elf-as -march=$ARCH"
LD=riscv64-unknown-elf-ld
OC=riscv64-unknown-elf-objcopy

python3 make_image.py
python3 ref.py

build_slot() {                  # $1 = name, $2 = linker script
    $AS -o "$1.o" "$1.S"
    $LD -T "$2" -o "$1.elf" "$1.o"
    $OC -O binary --only-section=.text "$1.elf" "$1.bin"
}

build_slot algo_comp_a  comp.ld
build_slot algo_comp_b  comp.ld
build_slot algo_crypt_a crypt.ld
build_slot algo_crypt_b crypt.ld

$AS -o dispatch.o dispatch.S
$LD -T link.ld -o dispatch.elf dispatch.o
$OC -O binary --only-section=.text dispatch.elf dispatch.bin
$OC -O binary --only-section=.data dispatch.elf dtcm.bin

python3 build_hotswap_hex.py hotswap.hex dispatch.bin \
    algo_comp_a.bin algo_crypt_a.bin algo_comp_b.bin algo_crypt_b.bin
python3 bin2hex.py dtcm.bin 64 > dtcm.hex

echo "--- run ---"
./obj_dir_riscv/Vcore_top +imem=hotswap.hex +dmem=dtcm.hex