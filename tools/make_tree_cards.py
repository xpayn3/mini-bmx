"""Makes the card trees' two leaf textures (godot/scripts/world/card_tree.gd) from photographed foliage:
  needle_branch.png  512 x 256  a pine branch: stem along x (0 = the trunk end .. 1 = the tip), side shoots, and real
                     needle bundles stamped along both, angled forward
  leaf_cluster.png   512 x 512  a rounded cluster of real leaves (the bush / leafy-crown card)
RGBA, transparent texels carry the foliage colour (no dark fringe in the mips). Colours are light and only slightly
green: the card shader multiplies them by each tree's own instance colour, so every biome keeps its greens; the photos
give the detail (needle strands, leaf veins, the light / dark between leaves).
Sources: ambientCG PineNeedles001 + LeafSet005 (CC0), the 2K-JPG zips (Color, Opacity).
Run: python tools/make_tree_cards.py <PineNeedles001 folder> <LeafSet005 folder> <out folder>
"""
import math
import random
import sys
from collections import deque

import numpy as np
from PIL import Image


def boxes(mask, step=4):
    """Bounding boxes (y1, y2, x1, x2, full resolution) of the connected opaque blobs, found on a 1/step grid."""
    m = mask[::step, ::step]
    seen = np.zeros_like(m, bool)
    hh, ww = m.shape
    out = []
    for y0, x0 in zip(*np.nonzero(m)):
        if seen[y0, x0]:
            continue
        q = deque([(y0, x0)]); seen[y0, x0] = True
        y1 = y2 = y0; x1 = x2 = x0
        n = 0
        while q:
            y, x = q.popleft(); n += 1
            y1, y2, x1, x2 = min(y1, y), max(y2, y), min(x1, x), max(x2, x)
            for dy in (-1, 0, 1):
                for dx in (-1, 0, 1):
                    ny, nx = y + dy, x + dx
                    if 0 <= ny < hh and 0 <= nx < ww and m[ny, nx] and not seen[ny, nx]:
                        seen[ny, nx] = True; q.append((ny, nx))
        if n > 30:
            out.append(((y1 - 1) * step, (y2 + 2) * step, (x1 - 1) * step, (x2 + 2) * step))
    return out


def load(folder, name):
    c = np.asarray(Image.open(f"{folder}/{name}_2K-JPG_Color.jpg").convert("RGB"), np.float32) / 255.0
    o = np.asarray(Image.open(f"{folder}/{name}_2K-JPG_Opacity.jpg").convert("L"), np.float32) / 255.0
    return c, o


def sprite(c, o, b, tint, lum_mean, grow=0, shrink=0):
    """One cut-out (RGBA PIL image): the photo's brightness detail x a light tint. grow: thicken the opacity by that many
    pixels (needle strands are ~3 px at 2K and would vanish once scaled down onto a card); shrink: trim the edge (the
    scan's leaves carry a light halo)."""
    y1, y2, x1, x2 = [max(0, v) for v in b]
    cc = c[y1:y2, x1:x2]; oo = o[y1:y2, x1:x2]
    if grow or shrink:
        from PIL import ImageFilter
        im = Image.fromarray((oo * 255).astype(np.uint8), "L")
        if grow:
            im = im.filter(ImageFilter.MaxFilter(grow * 2 + 1))
            cim = Image.fromarray((cc * 255).astype(np.uint8), "RGB").filter(ImageFilter.MaxFilter(grow * 2 + 1))
            # (the strands' colour spread out with them: the dark background would show inside the thickened strands)
            cc = np.asarray(cim, np.float32) / 255.0
        if shrink:
            im = im.filter(ImageFilter.MinFilter(shrink * 2 + 1))
        oo = np.asarray(im, np.float32) / 255.0
    lum = cc @ np.array([0.3, 0.59, 0.11], np.float32)
    inside = oo > 0.5
    m = float(lum[inside].mean()) if inside.any() else 0.5
    # keep a little of the photo's own hue (yellow midribs, red stalks) around the tint
    rel = np.clip(lum / max(m, 1e-3), 0.0, 1.8)
    hue = cc / np.maximum(lum[..., None], 1e-3)
    col = rel[..., None] * lum_mean * (np.array(tint, np.float32) * 0.8 + hue * 0.2)
    rgba = np.dstack([np.clip(col, 0, 1), oo])
    return Image.fromarray((rgba * 255).astype(np.uint8), "RGBA")


def paste(canvas, spr, at, ang, scale, shade, anchor):
    """Rotate (deg) + scale a sprite and alpha-composite it so its anchor (fraction of its size) lands on `at`."""
    w, h = spr.size
    s = spr.resize((max(1, int(w * scale)), max(1, int(h * scale))), Image.LANCZOS)
    if shade != 1.0:
        a = np.asarray(s, np.float32)
        a[..., :3] *= shade
        s = Image.fromarray(np.clip(a, 0, 255).astype(np.uint8), "RGBA")
    ax, ay = anchor[0] * s.size[0], anchor[1] * s.size[1]
    r = s.rotate(ang, resample=Image.BICUBIC, expand=True)
    # where the anchor went after the turn about the sprite's centre
    cx, cy = s.size[0] / 2, s.size[1] / 2
    t = math.radians(ang)
    dx, dy = ax - cx, ay - cy
    rx = dx * math.cos(t) + dy * math.sin(t)
    ry = -dx * math.sin(t) + dy * math.cos(t)
    px = int(at[0] - (r.size[0] / 2 + rx))
    py = int(at[1] - (r.size[1] / 2 + ry))
    canvas.alpha_composite(r, (px, py)) if px >= 0 and py >= 0 else _paste_clip(canvas, r, px, py)


def _paste_clip(canvas, r, px, py):
    cx0, cy0 = max(0, -px), max(0, -py)
    if cx0 >= r.size[0] or cy0 >= r.size[1]:
        return
    canvas.alpha_composite(r.crop((cx0, cy0, r.size[0], r.size[1])), (max(0, px), max(0, py)))


def bleed(img, fill):
    """Transparent texels get the foliage colour (mips don't darken the cut-out's edge)."""
    a = np.asarray(img, np.float32)
    t = a[..., 3] < 1
    a[t, 0:3] = np.array(fill, np.float32) * 255
    return Image.fromarray(a.astype(np.uint8), "RGBA")


def needles(folder, out):
    c, o = load(folder, "PineNeedles001")
    bs = [b for b in boxes(o > 0.4) if (b[3] - b[2]) > 300]
    rng = random.Random(2611)
    tint = (0.82, 1.0, 0.74)
    spr = []
    for b in bs:
        s = sprite(c, o, b, tint, 0.8, grow=6)
        # the bundle's base: its left end (they all grow left -> right in the scan); anchor at the base's height
        a = np.asarray(s)[..., 3]
        cols = np.nonzero(a.max(axis=0) > 100)[0]
        x0 = cols[0] if len(cols) else 0
        rows = np.nonzero(a[:, x0:x0 + 12].max(axis=1) > 100)[0]
        y0 = rows.mean() if len(rows) else a.shape[0] / 2
        spr.append((s, (x0 / a.shape[1], y0 / a.shape[0])))
    W, H = 512, 256
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    # stem, wandering a little; side shoots off it
    stem = []
    p = [4.0, H * 0.5]; ang = 0.0
    while p[0] < W - 10:
        stem.append(tuple(p))
        ang = max(-0.1, min(0.1, ang + rng.uniform(-0.04, 0.04)))
        p = [p[0] + math.cos(ang), p[1] + math.sin(ang)]
    shoots = [(stem, 1.0)]
    for i in range(16):
        t = 0.08 + i / 16 * 0.85 + rng.uniform(-0.02, 0.02)
        s0 = stem[int(t * (len(stem) - 1))]
        sd = 1 if i % 2 == 0 else -1
        a = sd * rng.uniform(0.5, 0.85)
        ln = H * 0.5 * (1 - t * 0.65) * rng.uniform(0.75, 1.05)
        pts = []; q = list(s0)
        for _ in range(int(ln)):
            pts.append(tuple(q))
            a -= sd * 0.01
            q = [q[0] + math.cos(a), q[1] + math.sin(a)]
            if q[1] < 6 or q[1] > H - 6 or q[0] > W - 6:
                break
        shoots.append((pts, 0.65))
    # needle bundles along every stem (back to front: inner ones darker)
    stamps = []
    for pts, k in shoots:
        for j in range(0, len(pts) - 2, 3):
            x, y = pts[j]
            x2, y2 = pts[min(j + 2, len(pts) - 1)]
            d = math.degrees(math.atan2(y2 - y, x2 - x))
            tt = j / max(len(pts), 1)
            for side in (-1, 1):
                ln = rng.uniform(75, 115) * (0.55 + 0.45 * k) * (1 - 0.35 * tt)
                spread = rng.uniform(25, 60)
                stamps.append((rng.random(), (x, y), d + side * spread, ln, rng.uniform(0.75, 1.05)))
    stamps.sort(key=lambda s: s[0])
    for _, at, deg, ln, shade in stamps:
        s, anc = rng.choice(spr)
        scale = ln / s.size[0]
        # PIL turns counter-clockwise with y down: our angle is in image coordinates (y down), so negate
        paste(img, s, at, -deg, scale, shade, anc)
    # the stems over the needles (the twig the needles grow from)
    from PIL import ImageDraw
    dr = ImageDraw.Draw(img)
    for pts, k in shoots:
        for j in range(len(pts) - 1):
            w = (3 if k > 0.9 else 2) * (1 - j / len(pts) * 0.5)
            dr.line([pts[j], pts[j + 1]], fill=(118, 104, 74, 255), width=max(1, int(round(w))))
    bleed(img, (0.62, 0.72, 0.55)).save(f"{out}/needle_branch.png")


def leaves(folder, out):
    c, o = load(folder, "LeafSet005")
    bs = boxes(o > 0.4)
    bs.sort(key=lambda b: b[2])
    tint = (0.86, 1.0, 0.72)
    spr = []
    for b in bs:
        if (b[1] - b[0]) < 300:
            continue
        s = sprite(c, o, b, tint, 0.72, shrink=3)
        spr.append((s, (0.5, 0.97), (b[3] - b[2]) > (b[1] - b[0]) * 0.6))   # (anchor: the stalk at the bottom; twig cluster?)
    singles = [s for s in spr if not s[2]] or spr
    S = 512
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    rng = random.Random(90210)
    items = []
    for i in range(46):
        a = rng.random() * math.tau
        r = math.sqrt(rng.random()) * S * 0.33
        at = (S / 2 + math.cos(a) * r, S / 2 + math.sin(a) * r)
        depth = rng.random()
        items.append((depth, at, rng.uniform(0, 360), rng.uniform(95, 140), 0.68 + 0.4 * depth))
    items.sort(key=lambda t: t[0])
    for _, at, deg, ln, shade in items:
        s, anc, _ = rng.choice(singles)
        paste(img, s, at, deg, ln / s.size[1], shade, anc)
    bleed(img, (0.6, 0.72, 0.48)).save(f"{out}/leaf_cluster.png")


if __name__ == "__main__":
    needles(sys.argv[1], sys.argv[3])
    leaves(sys.argv[2], sys.argv[3])
    print("done")
