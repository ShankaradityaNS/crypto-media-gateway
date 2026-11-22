#!/usr/bin/env python3
# A whole 720p frame through the core, one 64x48 tile at a time.
import struct, subprocess, sys, time

W, H   = 1280, 720
TW, TH = 64, 48
NX, NY = W // TW, H // TH          # 20 x 15 = 300 tiles
KEY    = [0x0BADC0DE, 0x12345678, 0x9ABCDEF0, 0x0F1E2D3C]
DELTA  = 0x9E3779B9
M      = 0xFFFFFFFF
ROUNDS = 32

def dec_block(v0, v1, rounds):
    s = (DELTA * rounds) & M
    for _ in range(rounds):
        t  = ((((v0 << 4) & M) ^ (v0 >> 5)) + v0) & M
        t ^= (s + KEY[(s >> 11) & 3]) & M
        v1 = (v1 - t) & M
        s  = (s - DELTA) & M
        t  = ((((v1 << 4) & M) ^ (v1 >> 5)) + v1) & M
        t ^= (s + KEY[s & 3]) & M
        v0 = (v0 - t) & M
    return v0, v1

def xtea_dec(data, rounds):
    out = bytearray()
    for i in range(0, len(data), 8):
        v0, v1 = struct.unpack('<II', data[i:i+8])
        v0, v1 = dec_block(v0, v1, rounds)
        out += struct.pack('<II', v0, v1)
    return bytes(out)

def undpcm(data):
    out, prev = bytearray(), 0
    for b in data:
        prev = (prev + b) & 0xFF
        out.append(prev)
    return bytes(out)

def get_tile(frame, tx, ty):
    t = bytearray()
    for r in range(TH):
        off = (ty * TH + r) * W + tx * TW
        t += frame[off:off + TW]
    return bytes(t)

def write_hex64(data, path):
    with open(path, 'w') as f:
        for i in range(0, len(data), 8):
            chunk = data[i:i+8].ljust(8, b'\0')
            f.write("%016x\n" % int.from_bytes(chunk, 'little'))

frame = open('frame0.gray', 'rb').read()
if len(frame) != W * H:
    sys.exit("frame0.gray is %d bytes, expected %d" % (len(frame), W * H))

key        = b''.join(struct.pack('<I', k) for k in KEY)
recon      = bytearray(W * H)
cipher_all = bytearray()
cycles     = 0
t0         = time.time()

for ty in range(NY):
    for tx in range(NX):
        tile = get_tile(frame, tx, ty)
        write_hex64(tile + key, 'dtcm.hex')
        r = subprocess.run(['./obj_dir_riscv/Vcore_top',
                            '+imem=hotswap.hex', '+dmem=dtcm.hex',
                            '+sigout=sigout.bin'],
                           capture_output=True, text=True)
        if 'PASS' not in r.stdout:
            sys.exit("tile (%d,%d): %s" % (tx, ty, r.stdout.strip()))
        cycles += int(r.stdout.split()[2])

        cipher = open('sigout.bin', 'rb').read()[:TW * TH]
        cipher_all += cipher
        px = undpcm(xtea_dec(cipher, ROUNDS))
        for row in range(TH):
            off = (ty * TH + row) * W + tx * TW
            recon[off:off + TW] = px[row * TW:(row + 1) * TW]
    print("tile row %2d/%d   %5.1fs" % (ty + 1, NY, time.time() - t0), flush=True)

open('cipher_frame.bin', 'wb').write(bytes(cipher_all))
open('recon.gray', 'wb').write(bytes(recon))

print("\n%d tiles, %d core cycles, %.1fs wall" % (NX * NY, cycles, time.time() - t0))
if bytes(recon) == frame:
    print("frame recovered exactly: %d bytes" % len(frame))
else:
    bad = sum(1 for a, b in zip(recon, frame) if a != b)
    print("MISMATCH: %d of %d bytes differ" % (bad, len(frame)))