"""Packs the Poly Haven rock scans' textures for godot/assets/rocks_scan (tools/make_scan_rocks.py makes the meshes):
  <asset>_col.png  RGB = colour x the scan's AO, A = roughness      <asset>_nrm.png  RGB = normal (OpenGL)
1024 x 1024. Run: python tools/make_scan_rock_textures.py <dir with the downloaded glTF folders>
"""
import os
import sys
import numpy as np
from PIL import Image

OUT = os.path.join(os.path.dirname(__file__), "..", "godot", "assets", "rocks_scan")
SIZE = 1024
ASSETS = {"boulder_01": "boulder01", "namaqualand_boulder_02": "nboulder02", "rock_09": "rock09", "namaqualand_stones_01": "nstone"}


def img(d, a, kind):
    return Image.open(os.path.join(d, a, "textures", "%s_%s_2k.jpg" % (a, kind))).convert("RGB").resize((SIZE, SIZE), Image.LANCZOS)


if __name__ == "__main__":
    src = sys.argv[1]
    for a, oid in ASSETS.items():
        col = np.asarray(img(src, a, "diff"), np.float32) / 255.0
        arm = np.asarray(img(src, a, "arm"), np.float32) / 255.0
        ao = arm[..., 0:1]
        rgb = col * (0.35 + 0.65 * ao)
        out = np.dstack([rgb, arm[..., 1]])
        Image.fromarray((out * 255 + 0.5).astype(np.uint8), "RGBA").save(os.path.join(OUT, oid + "_col.png"))
        img(src, a, "nor_gl").save(os.path.join(OUT, oid + "_nrm.png"))
        print(oid, "done")
