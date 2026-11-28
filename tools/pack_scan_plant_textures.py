"""Pack Megascans maps for Godot (companion of make_scan_plants.py, run after it):
    python tools/pack_scan_plant_textures.py <dir of unzipped downloads> <godot/assets/plants_scan>
Per download -> <out>/<id>/col.png (RGB base colour, A opacity; 255 for solid scans), nrm.png (RGB OpenGL normal,
A translucency; 128 without one) and, when the download has billboard maps, bcol.png / bnrm.png (the far LOD3's).
Reads any of Fab's layouts: classic <..>_2K_BaseColor.jpg / _Opacity / _Normal / _Translucency (single-channel maps
keep their value in R), UE packages Textures/T_<id>_2K_B-O.png / _B / _N (DirectX: green flipped) / _ORT / _ORM /
_Billboard_B-O / _Billboard_N-T, glTF textures/*_albedo.jpeg / *_normal.jpeg, and img_base / img_normal saved out of a glb.
Colour: the opaque texels' mean linear brightness brought to TARGET (the scans are calibrated for another exposure, ~10x
darker than this game's foliage), transparent texels filled with the nearest leaf colour (no black in the mipmaps).
At most 2048 px."""
import glob, os, re, sys
import numpy as np
from PIL import Image, ImageFilter

TARGET_LEAF = 0.12
TARGET_SOLID = 0.14
MAXPX = 2048


def plant_id(folder):
    n = os.path.basename(folder).lower()
    n = re.sub(r" \(\d+\)$", "", n)
    n = n.replace("grass_clumps_rbojr", "grass_clumps_b_x")   # (two downloads of the same name)
    n = re.sub(r"_(ue|gltf)?_?(low|mid|high|2k|4k)$", "", n)
    n = re.sub(r"_(ue|gltf)$", "", n)
    n = re.sub(r"_[a-z0-9]{5,10}$", "", n) if not n.endswith("_x") else n[:-2]
    return n


def lift(rgb, alpha, target):
    c = np.asarray(rgb, np.float32) / 255.0
    lin = np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)
    a = np.asarray(alpha, np.float32) / 255.0 > 0.5
    lum = (0.2126 * lin[..., 0] + 0.7152 * lin[..., 1] + 0.0722 * lin[..., 2])[a]
    # only ever lifted: the UE / glTF packages are already at this exposure (pale plants like cotton grass stay pale);
    # the classic FBX downloads' colour maps come out ~10x darker
    g = max(target / max(float(lum.mean()), 1e-4), 1.0) if lum.size else 1.0
    lin = np.clip(lin * g, 0.0, 1.0)
    s = np.where(lin <= 0.0031308, lin * 12.92, 1.055 * lin ** (1 / 2.4) - 0.055)
    return Image.fromarray(np.clip(s * 255.0 + 0.5, 0, 255).astype(np.uint8)), g


def bleed(rgb, alpha):
    a = (np.asarray(alpha, np.float32) / 255.0 > 0.35).astype(np.float32)
    c = np.asarray(rgb, np.float32)
    out = c.copy()
    filled = a.copy()
    for r in (2, 6, 16, 48, 128):
        mm = np.asarray(Image.fromarray((a * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(r)), np.float32) / 255.0
        acc = np.zeros_like(c)
        for ch in range(3):
            pre = Image.fromarray(np.clip(c[..., ch] * a, 0, 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(r))
            acc[..., ch] = np.asarray(pre, np.float32)
        col = acc / np.maximum(mm[..., None], 1e-4)
        take = (filled < 0.5) & (mm > 0.002)
        out[take] = col[take]
        filled[take] = 1.0
    mean = (c * a[..., None]).sum((0, 1)) / max(a.sum(), 1.0)
    out[filled < 0.5] = mean
    return Image.fromarray(np.clip(out, 0, 255).astype(np.uint8))


def first(folder, *pats):
    for p in pats:
        c = sorted(f for f in glob.glob(os.path.join(folder, "**", "*"), recursive=True) if re.search(p, os.path.basename(f), re.I))
        if c:
            return c[0]
    return None


def chan(path, size, idx=0):
    im = Image.open(path)
    im = im.convert("RGBA") if im.mode in ("RGBA", "LA") else im.convert("RGB")
    return im.split()[idx].resize(size, Image.LANCZOS)


def pack(folder, dst, bill):
    pre = "Billboard_" if bill else ""
    b = ""
    # base colour (+ opacity)
    bo = first(folder, r"T_.*_\d+K_%sB-O\.png$" % pre)
    bc = first(folder, r"%s_\d+K_%sBaseColor\.jpg$" % (b, pre)) if not bo else None
    if not bo and not bc and not bill:
        bc = first(folder, r"T_.*_\d+K_B\.png$", r"_albedo\.(jpe?g|png)$", r"^img_base\.png$")
    if not bo and not bc:
        return False
    if bo:
        im = Image.open(bo).convert("RGBA")
        rgb, a = im.convert("RGB"), im.split()[3]
    else:
        rgb = Image.open(bc).convert("RGB")
        op = first(folder, r"%s_\d+K_%sOpacity\.jpg$" % (b, pre))
        a = chan(op, rgb.size) if op else Image.new("L", rgb.size, 255)
    if max(rgb.size) > MAXPX:
        sz = (MAXPX, MAXPX * rgb.size[1] // rgb.size[0])
        rgb, a = rgb.resize(sz, Image.LANCZOS), a.resize(sz, Image.LANCZOS)
    leafy = np.asarray(a).mean() < 250
    rgb, g = lift(rgb, a, TARGET_LEAF if leafy else TARGET_SOLID)
    if leafy:
        rgb = bleed(rgb, a)
    Image.merge("RGBA", (*rgb.split(), a)).save(os.path.join(dst, "bcol.png" if bill else "col.png"))
    # normal (+ translucency)
    ue_n = first(folder, r"T_.*_\d+K_%sN-T\.png$" % pre) if bill else first(folder, r"T_.*_\d+K_N\.png$")
    flip = bool(ue_n)
    nm = ue_n or first(folder, r"%s_\d+K_%sNormal\.jpg$" % (b, pre), *(() if bill else (r"_normal\.(jpe?g|png)$", r"^img_normal\.png$")))
    if nm:
        nim = Image.open(nm)
        n_rgb = nim.convert("RGB").resize(rgb.size, Image.LANCZOS)
        if flip:
            r_, g_, b_ = n_rgb.split()
            n_rgb = Image.merge("RGB", (r_, g_.point(lambda v: 255 - v), b_))
    else:
        n_rgb = Image.new("RGB", rgb.size, (128, 128, 255))
    t = None
    if bill and ue_n and Image.open(ue_n).mode == "RGBA":
        t = Image.open(ue_n).split()[3].resize(rgb.size)
    elif not bill:
        ort = first(folder, r"T_.*_\d+K_ORT\.png$")
        if ort:
            t = chan(ort, rgb.size, 2)
    if t is None:
        tr = first(folder, r"%s_\d+K_%sTranslucency\.jpg$" % (b, pre))
        t = chan(tr, rgb.size) if tr else Image.new("L", rgb.size, 128)
    if leafy:
        n_rgb = bleed(n_rgb, a)
    Image.merge("RGBA", (*n_rgb.split(), t)).save(os.path.join(dst, "bnrm.png" if bill else "nrm.png"))
    print("TEX", os.path.basename(dst), "bill" if bill else "main", rgb.size, "lift x%.2f" % g, "flipG" if flip else "")
    return True


src, out = sys.argv[1], sys.argv[2]
only = sys.argv[3] if len(sys.argv) > 3 else ""
for folder in sorted(glob.glob(os.path.join(src, "*"))):
    if not os.path.isdir(folder) or (only and only not in os.path.basename(folder)):
        continue
    dst = os.path.join(out, plant_id(folder))
    if not os.path.isdir(dst):
        continue
    if not pack(folder, dst, False):
        # a glb's own textures were saved into dst by make_scan_plants.py
        pack(dst, dst, False)
    pack(folder, dst, True)
