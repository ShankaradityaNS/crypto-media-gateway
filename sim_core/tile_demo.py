#!/usr/bin/env python3
# One 64x48 tile from a real 720p frame: compress + encrypt on the core,
# then decrypt and reverse the compression on the host and compare.
import struct, subprocess, sys

W, H   = 1280, 720
TW, TH = 64, 48
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

tx = int(sys.argv[1]) if len(sys.argv) > 1 else 10
ty = int(sys.argv[2]) if len(sys.argv) > 2 else 7

frame = open('frame0.gray', 'rb').read()
if len(frame) != W * H:
    sys.exit("frame0.gray is %d bytes, expected %d" % (len(frame), W * H))

tile = get_tile(frame, tx, ty)
key  = b''.join(struct.pack('<I', k) for k in KEY)
write_hex64(tile + key, 'dtcm.hex')

r = subprocess.run(['./obj_dir_riscv/Vcore_top',
                    '+imem=hotswap.hex', '+dmem=dtcm.hex',
                    '+sigout=sigout.bin'],
                   capture_output=True, text=True)
print(r.stdout.strip())

cipher = open('sigout.bin', 'rb').read()[:TW * TH]
recon  = undpcm(xtea_dec(cipher, ROUNDS))

if recon == tile:
    print("round trip OK: %d bytes, tile (%d,%d) recovered exactly" %
          (len(tile), tx, ty))
else:
    bad = sum(1 for a, b in zip(recon, tile) if a != b)
    print("MISMATCH: %d of %d bytes differ" % (bad, len(tile)))
    print("  original  %s" % tile[:16].hex())
    print("  recovered %s" % recon[:16].hex())

open('tile_orig.raw', 'wb').write(tile)
open('tile_recon.raw', 'wb').write(recon)