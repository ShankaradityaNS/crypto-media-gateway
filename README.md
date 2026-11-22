# Crypto Media Gateway

**A RISC-V SoC in which the video compression and encryption algorithms are
software images, swappable at runtime, committed atomically at a frame
boundary.**

Commercial codec silicon freezes its algorithm menu at design time; an FPGA can
be reprogrammed, but only by requalifying an entire bitstream. This design puts
both algorithms in software images held in on-chip slots, so replacing a
deprecated cipher or adopting a newer codec becomes a software update against
an unchanged hardware contract.

Written from scratch: the RV64I core and its pipeline, trap and interrupt
handling, the custom CSRs, the windowed instruction memory and its hardware
interlocks, the test environment, the cross-compiled algorithm images, and the
reference models they are checked against.

### At a glance

| | |
|---|---|
| Core | RV64I, 5-stage in-order, Zicsr + Zifencei, M-mode, no cache, no MMU |
| riscv-tests | **67 / 71** — all four failures request hardware deliberately omitted |
| Directed tests | 27/27 windowed instruction memory, 24/24 slot-select CSRs |
| CPI | 1.09 – 1.69, reproducible to the digit across 54 programs |
| Hot swap | demonstrated on a real 1280×720 frame: 300 tiles, both algorithms changed mid-frame |
| Verification | every output byte checked against an independent Python model |
| RTL defects found and fixed | 13, three of them one recurring hazard-qualification class |
| Measured cost | DPCM 7.0 instructions/pixel, XTEA-32 105 instructions/byte |

```bash
cd sim_core
make lint                 # Verilator -Wall, warnings fatal
./run_tests.sh            # rv64ui    -> 52/54
./run_tests.sh rv64mi     # rv64mi    -> 15/17
make tcm && make slotcsr  # directed  -> 27/27, 24/24
```

**Nothing has been synthesized.** Every frequency, power and area figure in
this document is a projection, not a measurement. The
[What is not done](#what-is-not-done) section at the end is deliberately
specific about the rest.

---
