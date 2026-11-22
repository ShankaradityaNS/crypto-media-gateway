#!/usr/bin/env python3
# Converts a flat binary from objcopy into $readmemh format: one word per
# line, little-endian, zero-padded to the memory's word width.
#
# ITCM is 4096 x 32, so width 32. DTCM is 2048 x 64, so width 64. Passing
# the wrong width produces a file that loads without complaint and executes
# garbage, so the width is required rather than guessed from the filename.

import sys

if len(sys.argv) != 3:
    sys.exit("usage: bin2hex.py <file.bin> <word-bits: 32|64>")

path  = sys.argv[1]
width = int(sys.argv[2])
if width not in (32, 64):
    sys.exit("word-bits must be 32 or 64")

nbytes = width // 8
data   = open(path, "rb").read()
data  += b"\x00" * (-len(data) % nbytes)      # pad the final partial word

for i in range(0, len(data), nbytes):
    print(f"{int.from_bytes(data[i:i+nbytes], 'little'):0{nbytes * 2}x}")