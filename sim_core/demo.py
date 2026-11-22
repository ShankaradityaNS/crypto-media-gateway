#!/usr/bin/env python3
"""
Crypto Media Gateway - end to end demonstration.

A real 720p frame is fed through the RTL core one 64x48 tile at a time.
Partway through the frame the compression and encryption algorithms are
hot-swapped: the harness writes new slot numbers into DTCM, the core stages
them in the shadow CSRs and commits at a tile boundary. The core calls the
same two architectural addresses before and after the swap; the hardware
redirects them to different physical slots.

Every tile's reported image IDs and CSR_SLOT_LIVE value are read back out of
the signature region and checked against what was requested, so the swap is
evidenced by the hardware rather than asserted by the script.

usage: demo.py [frame.gray]
"""
import struct, subprocess, sys, time, math, os

W, H     = 1280, 720
TW, TH   = 64, 48
NX, NY   = W // TW, H // TH
TILE_LEN = TW * TH

KEY   = [0x0BADC0DE, 0x12345678, 0x9ABCDEF0, 0x0F1E2D3C]
DELTA = 0x9E3779B9
M     = 0xFFFFFFFF

INFILE = sys.argv[1] if len(sys.argv) > 1 else 'frame0.gray'
SIM    = './obj_dir_riscv/Vcore_top'

# slot -> (description, expected image id)
COMP  = {0: ("DPCM lossless",   0xC0A),
         2: ("2x2 average 4:1", 0xC0B)}
CRYPT = {1: ("XTEA 32 rounds",  0xE0A),
         3: ("XTEA 16 rounds",  0xE0B)}

ROUNDS   = {1: 32, 3: 16}       # crypt slot -> XTEA round count
LOSSLESS = {0}                  # comp slots that reconstruct bit-exact

# (first tile row, comp slot, crypt slot)
SCHEDULE = [(0, 0, 1), (7, 2, 3)]


def schedule_ranges():
    out = []
    for i, (first, cs, ks) in enumerate(SCHEDULE):
        last = SCHEDULE[i + 1][0] - 1 if i + 1 < len(SCHEDULE) else NY - 1
        out.append((first, last, cs, ks))
    return out


def config_for_row(ty):
    cfg = SCHEDULE[0]
    for s in SCHEDULE:
        if ty >= s[0]:
            cfg = s
    return cfg[1], cfg[2]


# ---------- host-side reference implementations ----------

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
        v0, v1 = struct.unpack('<II', data[i:i + 8])
        v0, v1 = dec_block(v0, v1, rounds)
        out += struct.pack('<II', v0, v1)
    return bytes(out)


def undpcm(data):
    out, prev = bytearray(), 0
    for b in data:
        prev = (prev + b) & 0xFF
        out.append(prev)
    return bytes(out)


def unavg(data):
    """32x24 back to 64x48 by pixel replication."""
    sw, sh = TW // 2, TH // 2
    out = bytearray(TILE_LEN)
    for y in range(sh):
        for x in range(sw):
            v = data[y * sw + x]
            out[(2 * y) * TW + 2 * x]         = v
            out[(2 * y) * TW + 2 * x + 1]     = v
            out[(2 * y + 1) * TW + 2 * x]     = v
            out[(2 * y + 1) * TW + 2 * x + 1] = v
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
            chunk = data[i:i + 8].ljust(8, b'\0')
            f.write("%016x\n" % int.from_bytes(chunk, 'little'))


def stats(b):
    return min(b), max(b), sum(b) / float(len(b))


def rule(c='-'):
    print(c * 74)


# ---------- input ----------

if not os.path.exists(INFILE):
    sys.exit("no such file: %s" % INFILE)
frame = open(INFILE, 'rb').read()
if len(frame) != W * H:
    sys.exit("%s is %d bytes; expected %d for %dx%d grayscale"
             % (INFILE, len(frame), W * H, W, H))

rule('=')
print("CRYPTO MEDIA GATEWAY - end to end demonstration")
rule('=')
print("input file          %s" % INFILE)
print("input size          %d bytes (%.2f MB)" % (len(frame), len(frame) / 1e6))
print("geometry            %dx%d, 8-bit grayscale, 1 frame" % (W, H))
print()
print("core                RV64I 5-stage, 8 KB resident + 6 x 8 KB slots")
print("DTCM                16 KB  <- a whole frame is %dx too large, so it is"
      % (len(frame) // 16384))
print("                           processed in tiles")
print("tile                %dx%d = %d bytes, %d x %d = %d tiles"
      % (TW, TH, TILE_LEN, NX, NY, NX * NY))
print()
print("per tile the core:  reads the requested slot numbers from DTCM")
print("                    writes shadow CSRs 0x7C5 (comp) / 0x7C6 (crypt)")
print("                    commits them via 0x7C7, making them live")
print("                    calls the COMP  window at 0xFFFFFFFF80002000")
print("                    calls the CRYPT window at 0xFFFFFFFF80004000")
print("                    writes ciphertext plus a trailer to the sig region")
print()
print("schedule")
for first, last, cs, ks in schedule_ranges():
    print("  tile rows %2d-%-2d    comp slot %d (%-16s)  crypt slot %d (%s)"
          % (first, last, cs, COMP[cs][0], ks, CRYPT[ks][0]))
print()
print("input content")
degenerate = False
for first, last, cs, ks in schedule_ranges():
    part = frame[first * TH * W:(last + 1) * TH * W]
    lo, hi, mean = stats(part)
    flat = (hi - lo) < 16
    degenerate = degenerate or flat
    print("  rows %2d-%-2d        pixel range %3d..%3d, mean %5.1f%s"
          % (first, last, lo, hi, mean,
             "   <-- nearly uniform" if flat else ""))
if degenerate:
    print()
    print("  WARNING: a nearly uniform region cannot exercise the lossy path.")
    print("           Pull a frame from further into the clip:")
    print("           ffmpeg -y -ss 00:00:05 -i clip.mp4 -frames:v 1 \\")
    print("                  -vf scale=1280:720 -pix_fmt gray -f rawvideo "
          "frame0.gray")
rule()

# ---------- run ----------

key        = b''.join(struct.pack('<I', k) for k in KEY)
recon      = bytearray(W * H)
cipher_all = bytearray()
manifest   = []
cycles     = 0
cur_cfg    = None
t0         = time.time()

for ty in range(NY):
    cs, ks = config_for_row(ty)
    if (cs, ks) != cur_cfg:
        if cur_cfg is not None:
            print("  >> HOT SWAP at tile row %d: comp slot %d -> %d, "
                  "crypt slot %d -> %d" % (ty, cur_cfg[0], cs, cur_cfg[1], ks))
        cur_cfg = (cs, ks)

    row_out = 0
    for tx in range(NX):
        tile = get_tile(frame, tx, ty)
        ctrl = struct.pack('<II', cs, ks)
        write_hex64(tile + key + ctrl, 'dtcm.hex')

        r = subprocess.run([SIM, '+imem=hotswap.hex', '+dmem=dtcm.hex',
                            '+sigout=sigout.bin'],
                           capture_output=True, text=True)
        if 'PASS' not in r.stdout:
            sys.exit("tile (%d,%d): %s" % (tx, ty, r.stdout.strip()))
        cycles += int(r.stdout.split()[2])

        sig = open('sigout.bin', 'rb').read()
        olen, cid, kid, live = struct.unpack('<IIII', sig[4096:4112])

        # the hardware's own account of what ran
        if cid != COMP[cs][1]:
            sys.exit("tile (%d,%d): comp id 0x%X, expected 0x%X"
                     % (tx, ty, cid, COMP[cs][1]))
        if kid != CRYPT[ks][1]:
            sys.exit("tile (%d,%d): crypt id 0x%X, expected 0x%X"
                     % (tx, ty, kid, CRYPT[ks][1]))
        if live != (ks << 8) | cs:
            sys.exit("tile (%d,%d): CSR_SLOT_LIVE 0x%X, expected 0x%X"
                     % (tx, ty, live, (ks << 8) | cs))

        cipher = sig[:olen]
        cipher_all += cipher
        row_out   += olen
        manifest.append((tx, ty, cs, ks, cid, kid, TILE_LEN, olen))

        plain = xtea_dec(cipher, ROUNDS[ks])
        px = undpcm(plain) if cs in LOSSLESS else unavg(plain)
        for row in range(TH):
            off = (ty * TH + row) * W + tx * TW
            recon[off:off + TW] = px[row * TW:(row + 1) * TW]

    print("  tile row %2d/%d   comp %d / crypt %d   %6d bytes out   %5.1fs"
          % (ty + 1, NY, cs, ks, row_out, time.time() - t0))

wall = time.time() - t0

# ---------- outputs ----------

open('out_cipher.bin', 'wb').write(bytes(cipher_all))
open('out_recon.gray', 'wb').write(bytes(recon))
with open('out_manifest.txt', 'w') as f:
    f.write("tx ty comp crypt comp_id crypt_id in_bytes out_bytes\n")
    for m in manifest:
        f.write("%2d %2d %4d %5d  0x%03X   0x%03X   %8d %9d\n" % m)

cipher_rows = len(cipher_all) // W

# ---------- results ----------

rule()
print("RESULTS")
rule()
print("core cycles         %d" % cycles)
print("wall time           %.1fs  (%.1f MHz effective in Verilator)"
      % (wall, cycles / wall / 1e6))
print("cycles per pixel    %.1f" % (cycles / float(W * H)))
print()
print("output 1            out_cipher.bin    %8d bytes   compressed + encrypted"
      % len(cipher_all))
print("output 2            out_recon.gray    %8d bytes   decrypted + decompressed"
      % len(recon))
print("manifest            out_manifest.txt  %8d tiles" % len(manifest))
print()
print("overall ratio       %d -> %d bytes = %.2f:1"
      % (len(frame), len(cipher_all), len(frame) / float(len(cipher_all))))
print()

for first, last, cs, ks in schedule_ranges():
    a = first * TH * W
    b = (last + 1) * TH * W
    seg_r, seg_o = bytes(recon[a:b]), frame[a:b]
    label = "rows %2d-%-2d" % (first, last)
    if cs in LOSSLESS:
        if seg_r == seg_o:
            print("%s        lossless, byte-exact over %d bytes"
                  % (label, len(seg_o)))
        else:
            bad = sum(1 for x, y in zip(seg_r, seg_o) if x != y)
            print("%s        MISMATCH: %d of %d bytes differ"
                  % (label, bad, len(seg_o)))
    else:
        mse = sum((x - y) ** 2 for x, y in zip(seg_r, seg_o)) / float(len(seg_o))
        if mse == 0:
            print("%s        exact - the input region is flat, so the lossy"
                  % label)
            print("                    path was not actually exercised")
        else:
            print("%s        lossy, PSNR %.2f dB  (%s)"
                  % (label, 10 * math.log10(255.0 * 255.0 / mse), COMP[cs][0]))

print()
print("every tile reported its comp id, crypt id and CSR_SLOT_LIVE back from")
print("the signature region; all %d matched the requested slots." % len(manifest))
print()
print("view the three stages:")
print("  ffmpeg -y -f rawvideo -pix_fmt gray -s %dx%d -i %s "
      "-update 1 demo_in.png" % (W, H, INFILE))
print("  ffmpeg -y -f rawvideo -pix_fmt gray -s %dx%d -i out_cipher.bin "
      "-update 1 demo_cipher.png" % (W, cipher_rows))
print("  ffmpeg -y -f rawvideo -pix_fmt gray -s %dx%d -i out_recon.gray "
      "-update 1 demo_out.png" % (W, H))
rule('=')