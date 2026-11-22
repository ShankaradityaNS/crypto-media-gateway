#!/usr/bin/env python3
# Deterministic 64x64 grayscale test image: a gradient plus a disc, so the
# data has both smooth and sharp structure for a codec to react to.
W = H = 64
img = bytearray()
for y in range(H):
    for x in range(W):
        v = (x * 3 + y * 2) & 0xFF
        dx, dy = x - 32, y - 32
        if dx * dx + dy * dy < 14 * 14:
            v = (v + 160) & 0xFF
        img.append(v)
open('image64.raw', 'wb').write(bytes(img))
print("image64.raw: %d bytes" % len(img))