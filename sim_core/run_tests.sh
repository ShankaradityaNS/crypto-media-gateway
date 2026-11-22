#!/usr/bin/env bash
# Builds and runs a riscv-tests directory against the core.
#   ./run_tests.sh            -> rv64ui
#   ./run_tests.sh rv64mi     -> machine-mode tests
# Artefacts land in build/<suite>/. No waveforms by default; to get one,
# re-run a single test with +vcd=<file>.
set -u

# Tests that request hardware this core deliberately omits. Expected to fail;
# they must not mask a real regression, so they are listed explicitly rather
# than skipped.
EXPECTED="fence_i ma_data mcsr pmpaddr"

ROOT=$(cd "$(dirname "$0")/.." && pwd)
SUITE=${1:-rv64ui}
SRC=$ROOT/riscv-tests/isa/$SUITE
OUT=$ROOT/build/$SUITE
SIM=$ROOT/sim_core/obj_dir_riscv/Vcore_top

# Matches the core: RV64I base, Zicsr for the CSR accesses the env makes,
# Zifencei so fence.i assembles (the core treats it as a no-op).
ARCH=rv64i_zicsr_zifencei

make -C "$ROOT/sim_core" riscv > /dev/null || { echo "simulator build failed"; exit 1; }
mkdir -p "$OUT"

pass=0; fail=0; skip=0; failed=""

for s in "$SRC"/*.S; do
    name=$(basename "$s" .S)
    elf=$OUT/$name.elf

    if ! riscv64-unknown-elf-gcc -march=$ARCH -mabi=lp64 \
            -nostdlib -nostartfiles -Wl,--no-warn-rwx-segments \
            -I "$ROOT/sim_core/env" \
            -I "$ROOT/riscv-tests/env" \
            -I "$ROOT/riscv-tests/isa/macros/scalar" \
            -T "$ROOT/sim_core/link.ld" \
            "$s" -o "$elf" > "$OUT/$name.buildlog" 2>&1; then
        printf '%-18s SKIP  build failed (%s)\n' "$name" "$OUT/$name.buildlog"
        skip=$((skip+1)); continue
    fi

    riscv64-unknown-elf-objcopy -O binary \
        --only-section=.text --only-section=.rodata "$elf" "$OUT/$name.itcm.bin"
    riscv64-unknown-elf-objcopy -O binary \
        --only-section=.data "$elf" "$OUT/$name.dtcm.bin"

    python3 "$ROOT/sim_core/bin2hex.py" "$OUT/$name.itcm.bin" 32 > "$OUT/$name.itcm.hex"
    python3 "$ROOT/sim_core/bin2hex.py" "$OUT/$name.dtcm.bin" 64 > "$OUT/$name.dtcm.hex"

    line=$("$SIM" +imem="$OUT/$name.itcm.hex" +dmem="$OUT/$name.dtcm.hex" 2>&1 \
           | grep '\[TB\]' | head -1)

    printf '%-18s %s\n' "$name" "$line"
    case "$line" in
        *PASS*) pass=$((pass+1)) ;;
        *)      fail=$((fail+1)); failed="$failed $name" ;;
    esac
done

echo
echo "pass $pass   fail $fail   skip $skip"
[ -n "$failed" ] && echo "failed:$failed"

unexpected=""
for f in $failed; do
    case " $EXPECTED " in *" $f "*) ;; *) unexpected="$unexpected $f" ;; esac
done
[ -n "$unexpected" ] && echo "UNEXPECTED FAILURES:$unexpected"
exit $([ -n "$unexpected" ] && echo 1 || echo 0)
