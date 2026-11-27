"""Makes godot/assets/textures/trail_scan/<name>_col.webp + <name>_nr.webp (WebP q92: the game compresses to BC7 anyway): the photo-scanned trail surface
(godot/scripts/world/ground.gdshader, "trail scans"). Two RGBA textures per scan, 2048 x 2048, tiling:
  _col  RGB = the colour scan / its mean colour x 0.5 per channel (0.5 = average: the trail keeps each world's own dirt
              colour, the scan only says where it is lighter / darker / greyer, i.e. the stones), A = height (1..99.5 %)
  _nr   RG  = normal x, y (OpenGL, 0.5 = flat), B = roughness, A = 1
Sources, Poly Haven (CC0): rocky_trail (stony dirt: shoulders / loose), forest_ground_04 (packed dirt: the ridden line),
dry_ground_rocks (cracked hardpack with pale pebbles: dry country), forrest_ground_01 (needles, twigs, grass: forest trail edges).
Run: python tools/make_trail_scans.py <dir with the 2k JPGs: <name>_diff_2k / _nor_gl_2k / _disp_2k / _rough_2k>
"""
import os
import sys
import numpy as np
from PIL import Image

OUT = os.path.join(os.path.dirname(__file__), "..", "godot", "assets", "textures", "trail_scan")


def load(d, name, kind, mode):
    return np.asarray(Image.open(os.path.join(d, f"{name}_{kind}_2k.jpg")).convert(mode), np.float32) / 255.0


def pack(d, name):
    col = load(d, name, "diff", "RGB") ** 2.2           # linear
    mean = col.reshape(-1, 3).mean(0)
    rel = np.clip(col / np.maximum(mean, 1e-3) * 0.5, 0, 1)
    disp = load(d, name, "disp", "L")
    lo, hi = np.percentile(disp, 1), np.percentile(disp, 99.5)
    disp = np.clip((disp - lo) / max(hi - lo, 1e-3), 0, 1)
    a = np.dstack([rel, disp])
    Image.fromarray((a * 255 + 0.5).astype(np.uint8), "RGBA").save(os.path.join(OUT, name + "_col.webp"), quality=92, method=6)
    nor = load(d, name, "nor_gl", "RGB")
    rough = load(d, name, "rough", "L")
    b = np.dstack([nor[..., 0], nor[..., 1], rough, np.ones_like(rough)])
    Image.fromarray((b * 255 + 0.5).astype(np.uint8), "RGBA").save(os.path.join(OUT, name + "_nr.webp"), quality=92, method=6)
    print(name, "mean linear", mean.round(3), "rel std", rel.std().round(3), "height mean", disp.mean().round(3))


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    pack(sys.argv[1], "rocky_trail")
    pack(sys.argv[1], "forest_ground_04")
    pack(sys.argv[1], "dry_ground_rocks")
    pack(sys.argv[1], "forrest_ground_01")
