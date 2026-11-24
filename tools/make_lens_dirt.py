"""Makes godot/assets/textures/lens/lens_dirt.png: the lens dirt map for the camera lens
(godot/shaders/lens_fx.gdshaderinc). One screen's worth, 4096 x 2304 (16:9), not tiled.
  R = smears: ambientCG Smear004 (CC0), its Roughness map: fingerprint / wipe smears
  G = smudges: ambientCG SurfaceImperfections001 (CC0), its Opacity map: dried splashes, stains, smudges
  B = fine dust specks + fibres, generated here (seeded)
Each scan is cropped to 16:9 and its levels stretched to 0..1 (black = clean).
Run: python tools/make_lens_dirt.py <Smear004_4K-JPG_Roughness.jpg> <SurfaceImperfections001_4K-JPG_Opacity.jpg>
(the 4K-JPG zips from https://ambientcg.com/view?id=Smear004 and ?id=SurfaceImperfections001)
"""
import os
import sys
import numpy as np
from PIL import Image, ImageFilter

Image.MAX_IMAGE_PIXELS = None
W, H = 4096, 2304
rng = np.random.default_rng(20261124)


def scan(path):
    im = Image.open(path).convert("L")
    w, h = im.size
    ch = int(w * H / W)          # crop the middle to 16:9, then fit
    top = max(0, (h - ch) // 2)
    im = im.crop((0, top, w, top + min(ch, h))).resize((W, H), Image.LANCZOS)
    a = np.asarray(im, np.float32) / 255.0
    lo, hi = np.percentile(a, 2), np.percentile(a, 99.7)
    return np.clip((a - lo) / max(hi - lo, 1e-3), 0, 1)


def specks():
    """fine dust grains + a few fibres, more toward the edges (no round blobs: they read as circles)"""
    out = np.zeros((H, W), np.float32)
    n = 0
    while n < 9000:
        x, y = rng.uniform(0, W), rng.uniform(0, H)
        ex, ey = abs(x / W - 0.5) * 2, abs(y / H - 0.5) * 2
        if rng.uniform() > 0.1 + ((ex ** 4 + ey ** 4) ** 0.25) ** 2:
            continue
        n += 1
        if rng.uniform() < 0.05:     # a fibre
            L = rng.uniform(20, 90)
            ang, bend = rng.uniform(0, np.pi), rng.uniform(-0.7, 0.7)
            t = np.linspace(0, 1, int(L * 2))
            px = (x + np.cos(ang + bend * t) * L * t).astype(int)
            py = (y + np.sin(ang + bend * t) * L * t).astype(int)
            ok = (px >= 0) & (px < W) & (py >= 0) & (py < H)
            out[py[ok], px[ok]] = np.maximum(out[py[ok], px[ok]], rng.uniform(0.35, 0.7))
        else:
            rad = rng.uniform(0.8, 3.5)
            xi, yi, r = int(x), int(y), int(np.ceil(rad)) + 1
            x0, x1, y0, y1 = max(0, xi - r), min(W, xi + r + 1), max(0, yi - r), min(H, yi + r + 1)
            gy, gx = np.mgrid[y0:y1, x0:x1]
            d = np.sqrt((gx - x) ** 2 + (gy - y) ** 2)
            out[y0:y1, x0:x1] = np.maximum(out[y0:y1, x0:x1], np.clip(rad + 0.5 - d, 0, 1) * rng.uniform(0.35, 1.0))
    return np.asarray(Image.fromarray((out * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(0.7)), np.float32) / 255


if len(sys.argv) < 3:
    sys.exit(__doc__)
img = np.stack([scan(sys.argv[1]), scan(sys.argv[2]), specks()], -1)
out = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "godot", "assets", "textures", "lens", "lens_dirt.png")
os.makedirs(os.path.dirname(out), exist_ok=True)
Image.fromarray((img * 255).astype(np.uint8)).save(out, optimize=True)
print("wrote", os.path.abspath(out), round(os.path.getsize(out) / 1e6, 1), "MB; mean r/g/b:", [round(float(c.mean()), 3) for c in img.transpose(2, 0, 1)])
