"""Makes godot/assets/textures/mud/mud_wet.png and mud_dry.png: the detail scans of the mud on the bike
(godot/shaders/grime_mud.gdshader). One RGBA texture per scan, 1024 x 1024, tiling:
  R, G = normal x, y (OpenGL, 0.5 = flat)      B = height (levels stretched 0..1)
  A    = brightness detail: the colour scan's luminance / its mean x 0.5 (0.5 = average; the colour itself
         comes from the ground ridden, so every world's mud keeps its own colour)
Sources, Poly Haven (CC0): brown_mud_03 (wet mud) -> mud_wet, mud_cracked_dry_03 (cracked crust) -> mud_dry.
Run: python tools/make_mud_scans.py <dir with the 1k JPGs: <name>_diff_1k / _nor_gl_1k / _disp_1k>
"""
import os
import sys
import numpy as np
from PIL import Image

OUT = os.path.join(os.path.dirname(__file__), "..", "godot", "assets", "textures", "mud")


def load(d, name, kind, mode):
    return np.asarray(Image.open(os.path.join(d, f"{name}_{kind}_1k.jpg")).convert(mode), np.float32) / 255.0


def pack(d, name, out):
    nor = load(d, name, "nor_gl", "RGB")
    disp = load(d, name, "disp", "L")
    lo, hi = np.percentile(disp, 1), np.percentile(disp, 99.5)
    disp = np.clip((disp - lo) / max(hi - lo, 1e-3), 0, 1)
    col = load(d, name, "diff", "RGB")
    lum = col @ np.array([0.2126, 0.7152, 0.0722], np.float32)
    lum = np.clip(lum / max(lum.mean(), 1e-3) * 0.5, 0, 1)
    rgba = np.dstack([nor[..., 0], nor[..., 1], disp, lum])
    Image.fromarray((rgba * 255 + 0.5).astype(np.uint8), "RGBA").save(os.path.join(OUT, out))
    print(out, "height mean %.3f, brightness std %.3f" % (disp.mean(), lum.std()))


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    pack(sys.argv[1], "brown_mud_03", "mud_wet.png")
    pack(sys.argv[1], "mud_cracked_dry_03", "mud_dry.png")
