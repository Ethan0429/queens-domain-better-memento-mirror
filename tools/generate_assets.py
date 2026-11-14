"""Generates the screen-edge shimmer textures in Mods/HatchlingsBetterMementoMirror/Assets.

    py -3 -m pip install pillow numpy
    py -3 tools/generate_assets.py

edge-glow.png       soft spectral border, always shown while the hint plays
edge-shimmer-N.png  four phases of light bands and glints; Scripts/shimmer.lua cross-fades
                    them in sequence so the bands appear to drift around the screen edge
"""
import os
import numpy as np
from PIL import Image

W, H = 960, 540              # stretched to the viewport; the content is soft, so this is plenty
FRAMES = 4                   # must match SHIMMER_FRAMES in Scripts/shimmer.lua
BANDS = 9                    # light bands around the perimeter
OUT = os.path.join(os.path.dirname(__file__), '..', 'Mods', 'HatchlingsBetterMementoMirror', 'Assets')

CORE = np.array([0xEA, 0xFB, 0xFF]) / 255.0      # near-white spectral core
TAIL = np.array([0x5E, 0xC6, 0xE4]) / 255.0      # pale ghost-flame blue
GLINT = np.array([0xF4, 0xFD, 0xFF]) / 255.0

y, x = np.mgrid[0:H, 0:W].astype(np.float64) + 0.5
dl, dr, dt, db = x, W - x, y, H - y
dist = np.minimum(np.minimum(dl, dr), np.minimum(dt, db))
d = dist / H                                      # distance to the nearest edge, in screen heights

# Perimeter coordinate (0..1, clockwise from the top-left corner) of the nearest edge point.
P = 2.0 * (W + H)
s = np.where(dist == dt, x,
    np.where(dist == dr, W + y,
    np.where(dist == db, W + H + (W - x), 2 * W + H + (H - y)))) / P

# The border breathes in and out along its length so it reads as ethereal rather than a frame.
wave = 1 + 0.28 * np.sin(2 * np.pi * 3 * s + 1.3) + 0.16 * np.sin(2 * np.pi * 7 * s + 0.4)
corner = np.exp(-((np.minimum(dl, dr) / H) ** 2 + (np.minimum(dt, db) / H) ** 2) / 0.02)


def save(name, rgb, alpha):
    alpha = np.clip(alpha, 0, 1)
    img = np.dstack([np.clip(rgb, 0, 1), alpha])
    Image.fromarray((img * 255 + 0.5).astype(np.uint8), 'RGBA').save(os.path.join(OUT, name + '.png'), optimize=True)


def tint(core_weight, core=CORE):
    w = np.clip(core_weight, 0, 1)[..., None]
    return core * w + TAIL * (1 - w)


os.makedirs(OUT, exist_ok=True)

# Base glow: a thin bright rim with a wide, faint falloff toward the center.
glow = 0.7 * np.exp(-d / (0.014 * wave)) + 0.2 * np.exp(-d / (0.06 * wave)) + 0.12 * corner
save('edge-glow', tint(np.exp(-d / 0.02)), glow)

# Shimmer: soft bands that advance a quarter-period per frame, plus glints that twinkle per frame.
rng = np.random.default_rng(7)
count = 180
gx = rng.uniform(0, W, count); gy = rng.uniform(0, H, count)
# Pull glints toward the nearest edge so they hug the border.
for i in range(count):
    edges = [(gx[i], 0), (W - gx[i], 1), (gy[i], 2), (H - gy[i], 3)]
    near, which = min(edges)
    inset = rng.exponential(0.018 * H)
    if which == 0: gx[i] = inset
    elif which == 1: gx[i] = W - inset
    elif which == 2: gy[i] = inset
    else: gy[i] = H - inset
gr = rng.uniform(1.2, 3.2, count); gb = rng.uniform(0.45, 1.0, count); gf = rng.integers(0, FRAMES, count)

rim = np.exp(-d / (0.03 * wave))
for k in range(FRAMES):
    phase = 2 * np.pi * (BANDS * s) - k * np.pi / 2
    bands = (0.5 + 0.5 * np.cos(phase + 0.6 * np.sin(2 * np.pi * 2 * s))) ** 4
    alpha = 0.85 * rim * bands
    glints = np.zeros_like(d)
    for i in np.nonzero(gf == k)[0]:
        x0, x1 = int(max(gx[i] - 4 * gr[i], 0)), int(min(gx[i] + 4 * gr[i] + 1, W))
        y0, y1 = int(max(gy[i] - 4 * gr[i], 0)), int(min(gy[i] + 4 * gr[i] + 1, H))
        if x1 <= x0 or y1 <= y0: continue
        gxs, gys = x[y0:y1, x0:x1], y[y0:y1, x0:x1]
        r2 = ((gxs - gx[i]) ** 2 + (gys - gy[i]) ** 2) / (gr[i] ** 2)
        # A dot with a faint four-point flare.
        flare = np.exp(-r2) + 0.35 * np.exp(-((gxs - gx[i]) ** 2) / (0.15 * gr[i] ** 2) - ((gys - gy[i]) ** 2) / (6 * gr[i] ** 2)) \
                + 0.35 * np.exp(-((gys - gy[i]) ** 2) / (0.15 * gr[i] ** 2) - ((gxs - gx[i]) ** 2) / (6 * gr[i] ** 2))
        glints[y0:y1, x0:x1] = np.maximum(glints[y0:y1, x0:x1], gb[i] * flare)
    rgb = tint(np.maximum(np.exp(-d / 0.03) * bands, glints), GLINT)
    save('edge-shimmer-%d' % k, rgb, np.maximum(alpha, glints))

print('wrote textures to', os.path.abspath(OUT))
