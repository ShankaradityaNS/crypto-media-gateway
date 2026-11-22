#!/usr/bin/env python3
# Assemble the resident image and four slot images into one ITCM hex file,
# laid out exactly as a boot DMA would leave them.
import sys, struct

RESIDENT_WORDS = 2048
SLOT_WORDS     = 2048
NUM_SLOTS      = 6
TOTAL_WORDS    = RESIDENT_WORDS + SLOT_WORDS * NUM_SLOTS

def words(path):
    with open(path, 'rb') as f:
        b = f.read()
    b += b'\x00' * (-len(b) % 4)
    return list(struct.unpack('<%dI' % (len(b) // 4), b))

def main():
    if len(sys.argv) != 7:
        print("usage: build_hotswap_hex.py out.hex resident.bin "
              "slot0.bin slot1.bin slot2.bin slot3.bin")
        return 1

    mem = [0] * TOTAL_WORDS

    def place(base, path, limit):
        w = words(path)
        if len(w) > limit:
            raise SystemExit("%s is %d words, slot holds %d" %
                             (path, len(w), limit))
        mem[base:base + len(w)] = w
        print("  %-18s %4d words at physical word %d" %
              (path, len(w), base))

    place(0, sys.argv[2], RESIDENT_WORDS)
    for s in range(4):
        place(RESIDENT_WORDS + s * SLOT_WORDS, sys.argv[3 + s], SLOT_WORDS)

    with open(sys.argv[1], 'w') as f:
        for v in mem:
            f.write("%08x\n" % v)
    return 0

sys.exit(main())