#!/usr/bin/env python3
import struct

KEY   = [0x0BADC0DE, 0x12345678, 0x9ABCDEF0, 0x0F1E2D3C]
DELTA = 0x9E3779B9
M     = 0xFFFFFFFF

def enc_block(v0, v1, rounds):
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

def xtea(data, rounds):
    out = bytearray()
    for i in range(0, len(data), 8):
        v0, v1 = struct.unpack('<II', data[i:i+8])
        v0, v1 = enc_block(v0, v1, rounds)
        out += struct.pack('<II', v0, v1)
    return bytes(out)

def dpcm(data):
    out, prev = bytearray(), 0
    for b in data:
        out.append((b - prev) & 0xFF)
        prev = b
    return bytes(out)

def avg2x2(data, w):
    h = len(data) // w
    out = bytearray()
    for y in range(0, h, 2):
        for x in range(0, w, 2):
            s = (data[y * w + x]       + data[y * w + x + 1] +
                 data[(y + 1) * w + x] + data[(y + 1) * w + x + 1])
            out.append(s >> 2)
    return bytes(out)

raw     = open('image64.raw', 'rb').read()
frameN  = xtea(dpcm(raw), 32)
frameN1 = xtea(avg2x2(raw, 64), 16)

img_sum = sum(raw)     & M
sum_n   = sum(frameN)  & M
sum_n1  = sum(frameN1) & M

with open('expect.S', 'w') as f:
    f.write("    .equ IMG_SUM, 0x%08X\n" % img_sum)
    f.write("    .equ SUM_N,   0x%08X\n" % sum_n)
    f.write("    .equ SUM_N1,  0x%08X\n" % sum_n1)

print("image                       %4d bytes, checksum 0x%08X" % (len(raw), img_sum))
print("frame N    DPCM   -> XTEA-32 %4d bytes, checksum 0x%08X" % (len(frameN), sum_n))
print("frame N+1  avg2x2 -> XTEA-16 %4d bytes, checksum 0x%08X" % (len(frameN1), sum_n1))