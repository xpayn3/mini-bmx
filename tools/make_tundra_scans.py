"""Tundra ground (ground.gdshader "tundra"): four Megascans surfaces (the user's Fab library, Fab Standard licence: may ship
in the game, not be redistributed: output gitignored under godot/assets/plants_scan/tundra_ground/) packed as two
Texture2DArray strips of 4 x 1024 px, in the trail scans' format (tools/make_trail_scans.py):
  tundra_col.png  RGB = the scan / its mean colour x 0.5 (0.5 = average), A = height (1..99.5 %)
  tundra_nr.png   RG = normal x, y (OpenGL, 0.5 = flat), B = roughness, A = 1
Layers: 0 icelandic_moss, 1 nordic_moss, 2 icelandic_stony_ground, 3 icelandic_gravel. Prints each layer's mean linear
colour: ground.gdshader's TUN_MEAN (the moss keeps its own hue at the land's brightness).
Run: python tools/make_tundra_scans.py <dir with the unzipped surface downloads> godot/assets/plants_scan/tundra_ground
"""
import glob, os, re, sys
import numpy as np
from PIL import Image

LAYERS = ["icelandic_moss", "nordic_moss", "icelandic_stony_ground", "icelandic_gravel"]
PX = 1024


def find(folder, m):
    c = [f for f in glob.glob(os.path.join(folder, "*.jpg")) if re.search(r"_\dK_%s\.jpg$" % m, f)]
    return c[0] if c else None


def load(path, mode):
    return np.asarray(Image.open(path).convert(mode).resize((PX, PX), Image.LANCZOS), np.float32) / 255.0


src, out = sys.argv[1], sys.argv[2]
os.makedirs(out, exist_ok=True)
cols, nrs = [], []
for name in LAYERS:
    folder = [d for d in glob.glob(os.path.join(src, name + "_*")) if os.path.isdir(d)][0]
    c = load(find(folder, "BaseColor"), "RGB")
    lin = np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)
    mean = lin.reshape(-1, 3).mean(0)
    rel = np.clip(lin / np.maximum(mean, 1e-4) * 0.5, 0, 1)
    disp = load(find(folder, "Displacement"), "RGB")[..., 0]
    lo, hi = np.percentile(disp, 1), np.percentile(disp, 99.5)
    disp = np.clip((disp - lo) / max(hi - lo, 1e-3), 0, 1)
    cols.append(np.dstack([rel, disp]))
    nor = load(find(folder, "Normal"), "RGB")
    rp = find(folder, "Roughness")
    rough = load(rp, "RGB")[..., 0] if rp else np.full((PX, PX), 0.85, np.float32)
    nrs.append(np.dstack([nor[..., 0], nor[..., 1], rough, np.ones_like(rough)]))
    print("TUN_MEAN %s vec3(%.4f, %.4f, %.4f)  rel std %.3f" % (name, mean[0], mean[1], mean[2], rel.std()))
Image.fromarray((np.hstack(cols) * 255 + 0.5).astype(np.uint8), "RGBA").save(os.path.join(out, "tundra_col.png"))
Image.fromarray((np.hstack(nrs) * 255 + 0.5).astype(np.uint8), "RGBA").save(os.path.join(out, "tundra_nr.png"))
for f in ("tundra_col.png", "tundra_nr.png"):
    with open(os.path.join(out, f + ".import"), "w") as fh:
        fh.write('[remap]\n\nimporter="2d_array_texture"\ntype="CompressedTexture2DArray"\n\n[params]\n\n'
                 'compress/mode=2\ncompress/high_quality=true\nmipmaps/generate=true\nslices/horizontal=4\nslices/vertical=1\n')
print("DONE")
