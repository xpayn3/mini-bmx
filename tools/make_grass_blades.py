"""Makes godot/assets/textures/grass_blade/blades.png: 16 photographed grass blades, each straightened into a
64 x 512 strip, stacked top to bottom as the 16 layers of a Texture2DArray (imported with 1 x 16 slices) for the
near grass blades (godot/shaders/grass_field.gdshader).
Each strip follows its blade's (smoothed) centre line at a fixed width (the blade's typical width), so the
photo's veins, midrib, spots and dry tips line up with the blade the shader builds (the shader gives the outline).
Tip at the top row of each layer (the shader reads v = 1 - t).
  R = brightness / the blade's average brightness, x 0.5 (0.5 = average): detail only, the shader multiplies it
      onto the biome's grass colour, so every region keeps its own green
  G = how dry / brown it is there (0 = the blade's own green .. 1 = brown spot / dead tip)
  B = 1 inside the photographed blade, 0 where the fixed width ran past its edge (the shader darkens it a little)
  A = the across-the-blade slope of its surface (NormalGL red, 0.5 = flat): veins / rib shading
Sources: ambientCG Foliage001 + Foliage006 (CC0), the 2K-JPG zips (Color, Opacity, NormalGL).
Run: python tools/make_grass_blades.py <Foliage001 folder> <Foliage006 folder> <out.png>
"""
import sys
from collections import deque
import numpy as np
from PIL import Image

W, H = 64, 512


def boxes(mask, step=4):
    """Bounding boxes (slices, full resolution) of the connected opaque blobs, found on a 1/step grid."""
    m = mask[::step, ::step]
    seen = np.zeros_like(m, bool)
    hh, ww = m.shape
    out = []
    for y0, x0 in zip(*np.nonzero(m)):
        if seen[y0, x0]:
            continue
        q = deque([(y0, x0)]); seen[y0, x0] = True
        y1 = y2 = y0; x1 = x2 = x0
        while q:
            y, x = q.popleft()
            y1, y2, x1, x2 = min(y1, y), max(y2, y), min(x1, x), max(x2, x)
            for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                ny, nx = y + dy, x + dx
                if 0 <= ny < hh and 0 <= nx < ww and m[ny, nx] and not seen[ny, nx]:
                    seen[ny, nx] = True; q.append((ny, nx))
        out.append((slice(y1 * step, (y2 + 1) * step), slice(x1 * step, (x2 + 1) * step)))
    return out


def load(folder, name):
    rd = lambda k, mode: np.asarray(Image.open(f"{folder}/{name}_2K-JPG_{k}.jpg").convert(mode), np.float32) / 255.0
    return rd("Color", "RGB"), rd("Opacity", "L"), rd("NormalGL", "RGB")[..., 0]


def smooth(a, r):
    k = np.ones(2 * r + 1) / (2 * r + 1)
    return np.convolve(np.pad(a, r, mode="edge"), k, "valid")


def bilinear(img, x, y):
    x = np.clip(x, 0, img.shape[1] - 1.001); y = np.clip(y, 0, img.shape[0] - 1.001)
    x0, y0 = np.floor(x).astype(int), np.floor(y).astype(int)
    fx, fy = x - x0, y - y0
    if img.ndim == 3:
        fx, fy = fx[..., None], fy[..., None]
    return (img[y0, x0] * (1 - fx) * (1 - fy) + img[y0, x0 + 1] * fx * (1 - fy)
            + img[y0 + 1, x0] * (1 - fx) * fy + img[y0 + 1, x0 + 1] * fx * fy)


def blades(c, o, n, keep):
    """Upright blades of a scan, left to right, top row first; tip = the narrow end."""
    found = []
    for ys, xs in boxes(o > 0.5):
        h, w = ys.stop - ys.start, xs.stop - xs.start
        if h < 500 or w > h * 0.16:   # too short, or lying / branched / curly: no clean strip
            continue
        cen, half, rows = [], [], []
        for y in range(ys.start, ys.stop):
            m = np.nonzero(o[y, xs] > 0.5)[0]
            if len(m) >= 2:
                rows.append(y); cen.append(xs.start + (m[0] + m[-1]) / 2); half.append((m[-1] - m[0]) / 2)
        rows, cen, half = np.array(rows), np.array(cen), np.array(half)
        if len(rows) < 0.95 * h:      # broken in the scan
            continue
        cen = smooth(cen, 25)
        hw = np.percentile(half, 60) * 0.85            # fixed half width: a bit inside its usual edge
        # root = the wide end: index 0 must be the root
        k5 = len(half) // 5
        if half[:k5].mean() < half[-k5:].mean():   # top end narrower = tip at the top: run bottom -> top
            rows, cen = rows[::-1], cen[::-1]
        v = np.linspace(0, len(rows) - 1, H)
        yy = np.interp(v, np.arange(len(rows)), rows)
        cx = np.interp(v, np.arange(len(rows)), cen)
        u = np.linspace(-1, 1, W)
        X = cx[:, None] + u[None, :] * hw
        Y = np.repeat(yy[:, None], W, 1)
        found.append((ys.start // 600, xs.start, bilinear(c, X, Y), bilinear(o, X, Y), bilinear(n, X, Y)))
    found.sort(key=lambda f: (f[0], f[1]))
    return [f[2:] for f in found[:keep]]


def main():
    f1, f6, out = sys.argv[1], sys.argv[2], sys.argv[3]
    strips = blades(*load(f1, "Foliage001"), 8) + blades(*load(f6, "Foliage006"), 8)
    print("blades:", len(strips))
    # looked at by eye: 8 = Foliage006's long hair-thin blade (smeared), 15 = a blade broken into pieces
    strips = [s for i, s in enumerate(strips) if i not in (8, 15)]
    layers = []
    for col, op, nx in strips:
        inside = np.clip((op - 0.3) / 0.4, 0, 1)
        lum = col @ np.array([0.3, 0.59, 0.11], np.float32)
        wsum = inside.sum() + 1e-6
        mlum = (lum * inside).sum() / wsum
        det = np.clip(lum / mlum * 0.5, 0, 1)
        # dryness: warmer than the blade's own green (red up against green)
        warm = (col[..., 0] - col[..., 1]) / np.maximum(lum, 0.05)
        mwarm = (warm * inside).sum() / wsum
        dry = np.clip((warm - mwarm) / 0.6, 0, 1)
        sl = np.clip(0.5 + (nx - (nx * inside).sum() / wsum) * 1.5, 0, 1)
        layers.append(np.stack([det, dry, inside, sl], -1)[::-1])   # flip: tip at the top row
    k = 0
    while len(layers) < 16:            # fill up with good ones mirrored across (a different-looking blade)
        l = layers[(3 + 5 * k) % len(strips)][:, ::-1].copy()
        l[..., 3] = 1.0 - l[..., 3]    # mirrored: the across slope changes sign
        layers.append(l); k += 1
    img = np.concatenate(layers[:16], 0)
    Image.fromarray((img * 255 + 0.5).astype(np.uint8), "RGBA").save(out)
    print("wrote", out, img.shape)


main()
