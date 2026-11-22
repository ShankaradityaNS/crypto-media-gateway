#!/usr/bin/env python3
import struct

KEY   = [0x0BADC0DE, 0x12345678, 0x9ABCDEF0, 0x0F1E2D3C]
DELTA = 0x9E3779B9
M     = 0xFFFFFFFF

def enc_block(v0, v1, rounds=32):
    s = 0
    for _ in range(rounds):
        t  = ((((v1 << 4) & M) ^ (v1 >> 5)) + v1) & M
        t ^= (s + KEY[s & 3]) & M
        v0 = (v0 + t) & M
        s  = (s + DELTA) & M
        t  = ((((v0 << 4) & M) ^ (v0 >> 5)) + v0) & M
        t ^= (s + KEY[(s >> 11) & 3]) & M
        v1 = (v1 + t) & M
    return v0, v1

raw = open('image64.raw', 'rb').read()
out = bytearray()
for i in range(0, len(raw), 8):
    v0, v1 = struct.unpack('<II', raw[i:i+8])
    v0, v1 = enc_block(v0, v1)
    out += struct.pack('<II', v0, v1)

chk = sum(out) & M
open('xtea_expect.bin', 'wb').write(bytes(out))
with open('expect.S', 'w') as f:
    f.write("    .equ EXPECT_SUM, 0x%08X\n" % chk)
    f.write("    .equ IMG_SUM,    0x%08X\n" % (sum(raw) & M))
print("image checksum     0x%08X" % (sum(raw) & M))
print("ciphertext         %d bytes, checksum 0x%08X" % (len(out), chk))

zeros = bytes(len(raw))
outz = bytearray()
for i in range(0, len(zeros), 8):
    a, b = struct.unpack('<II', zeros[i:i+8])
    a, b = enc_block(a, b)
    outz += struct.pack('<II', a, b)
print("if DTCM never loaded: checksum 0x%08X" % (sum(outz) & M))