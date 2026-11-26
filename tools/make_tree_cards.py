"""Makes the card trees' two leaf textures (godot/scripts/world/card_tree.gd) from photographed foliage:
  needle_branch.png  2048 x 1024  a pine branch at real scale (~2-3 m: needle bundles 4-6 cm): stem along x (0 = the trunk
                     end .. 1 = the tip), side shoots, small twigs off them, real needle bundles stamped along all of them
  needle_tuft.png    1024 x 1024  a clump of needle twigs at a branch tip (~0.7 m across): the pines' foliage tufts
  leaf_cluster.png   1024 x 1024  a clump of real leaves at real size (~0.8 m: the bushes' card)
  leaf_spray.png     1024 x 1024  twigs + small real leaves (the airy look: green bushes + leafy tree clusters)
  leaf_tile.png      1024 x 1024  the same leaves as a dense SEAMLESS patch: the leafy crowns repeat it across their cards
RGBA, transparent texels carry the foliage colour (no dark fringe in the mips). Colours are light and only slightly
green: the card shader multiplies them by each tree's own instance colour, so every biome keeps its greens; the photos
give the detail (needle strands, leaf veins, the light / dark between leaves).
Sources: ambientCG PineNeedles001 + LeafSet005 (CC0), the 2K-JPG zips (Color, Opacity).
Run: python tools/make_tree_cards.py <PineNeedles001 folder> <LeafSet005 folder> <out folder> [<beech prefix>]
Optional 4th argument: the textures.com "3D Scanned European Beech Tree Leaves Atlas 01" maps, as their common path prefix
(e.g. C:/Users/Luka/Downloads/TCom_Leaves_EuropeanBeech01_2K_ -> ..._albedo.tif, _alpha, _normal, _translucency): makes
  leaf_beech.png    1024 x 1024  real beech twigs in a clump (the bushes; preferred over leaf_cluster.png when it exists)
  leaf_beech_n.png  1024 x 1024  the same layout: RGB = tangent-space normal (OpenGL), A = translucency
  leaf_beech_tile.png / _tile_n.png  the twigs as a dense seamless patch (the leafy crowns; over leaf_tile.png)
textures.com licence: may ship inside the game, may NOT be redistributed as files: both are gitignored (the repo is public),
so a fresh clone uses leaf_cluster.png until this is run with the atlas.
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


def sprite(c, o, b, tint, lum_mean, grow=0, shrink=0, rel_max=1.8):
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
    rel = np.clip(lum / max(m, 1e-3), 0.0, rel_max)
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
    """A pine branch at real scale: the card spans a branch of ~2-3 m (2048 px), so a 4-6 cm needle bundle is ~35-45 px.
    Main stem, side shoots, small side twigs off those, needle bundles all along them."""
    c, o = load(folder, "PineNeedles001")
    bs = [b for b in boxes(o > 0.4) if (b[3] - b[2]) > 300]
    rng = random.Random(2611)
    tint = (0.82, 1.0, 0.74)
    spr = []
    for b in bs:
        s = sprite(c, o, b, tint, 0.8, grow=14)
        a = np.asarray(s)[..., 3]
        cols = np.nonzero(a.max(axis=0) > 100)[0]
        x0 = cols[0] if len(cols) else 0
        rows = np.nonzero(a[:, x0:x0 + 12].max(axis=1) > 100)[0]
        y0 = rows.mean() if len(rows) else a.shape[0] / 2
        # pre-shrink to stamp size (the stamps are ~25-45 px long)
        k = 64.0 / s.size[0]
        s = s.resize((64, max(2, int(s.size[1] * k))), Image.LANCZOS)
        spr.append((s, (x0 / a.shape[1], y0 / a.shape[0])))
    W, H = 2048, 1024
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))

    def grow(p0, ang, ln, curl, wander):
        pts = []; q = list(p0); a = ang
        for _ in range(int(ln)):
            pts.append(tuple(q))
            a += curl + rng.uniform(-wander, wander)
            q = [q[0] + math.cos(a), q[1] + math.sin(a)]
            if q[1] < 8 or q[1] > H - 8 or q[0] > W - 8 or q[0] < 2:
                break
        return pts
    stem = grow([4.0, H * 0.5], 0.0, W - 14, 0.0, 0.01)
    shoots = [(stem, 1.0)]
    n_side = 30
    for i in range(n_side):
        t = 0.04 + i / n_side * 0.9 + rng.uniform(-0.01, 0.01)
        s0 = stem[int(t * (len(stem) - 1))]
        sd = 1 if i % 2 == 0 else -1
        side = grow(list(s0), sd * rng.uniform(0.55, 0.9), H * 0.46 * (1 - t * 0.6) * rng.uniform(0.8, 1.05), -sd * 0.0015, 0.01)
        shoots.append((side, 0.7))
        # small twigs off the side shoot
        for j in range(25, len(side) - 30, 55):
            sd2 = 1 if (j // 55) % 2 == 0 else -1
            p = side[j]
            pa = math.atan2(side[j + 2][1] - p[1], side[j + 2][0] - p[0])
            tw = grow(list(p), pa + sd2 * rng.uniform(0.6, 0.95), rng.uniform(70, 130) * (1 - j / len(side) * 0.5), 0.0, 0.02)
            shoots.append((tw, 0.45))
    stamps = []
    for pts, k in shoots:
        step = 5 if k > 0.9 else 6
        for j in range(0, len(pts) - 2, step):
            x, y = pts[j]
            x2, y2 = pts[min(j + 2, len(pts) - 1)]
            d = math.degrees(math.atan2(y2 - y, x2 - x))
            tt = j / max(len(pts), 1)
            for side in (-1, 1):
                ln = rng.uniform(34, 46) * (0.7 + 0.3 * k) * (1 - 0.3 * tt)
                stamps.append((rng.random(), (x, y), d + side * rng.uniform(28, 62), ln, rng.uniform(0.72, 1.06)))
    stamps.sort(key=lambda s: s[0])
    for _, at, deg, ln, shade in stamps:
        s, anc = rng.choice(spr)
        paste(img, s, at, -deg, ln / s.size[0], shade, anc)
    from PIL import ImageDraw
    dr = ImageDraw.Draw(img)
    for pts, k in shoots:
        for j in range(len(pts) - 1):
            w = (7 if k > 0.9 else 4 if k > 0.6 else 2) * (1 - j / len(pts) * 0.5)
            dr.line([pts[j], pts[j + 1]], fill=(112, 98, 70, 255), width=max(1, int(round(w))))
    bleed(img, (0.62, 0.72, 0.55)).save(f"{out}/needle_branch.png")


def tufts(folder, out):
    """needle_tuft.png 1024 x 1024: a clump of needles at a pine branch tip, as seen from above / the side: short twigs
    fanning forward (+x) from the branch's end (left middle), real needle bundles all along them (~0.8 m: needles ~5 cm)."""
    c, o = load(folder, "PineNeedles001")
    bs = [b for b in boxes(o > 0.4) if (b[3] - b[2]) > 300]
    rng = random.Random(7331)
    tint = (0.82, 1.0, 0.74)
    spr = []
    for b in bs:
        s = sprite(c, o, b, tint, 0.8, grow=14)
        a = np.asarray(s)[..., 3]
        cols = np.nonzero(a.max(axis=0) > 100)[0]
        x0 = cols[0] if len(cols) else 0
        rows = np.nonzero(a[:, x0:x0 + 12].max(axis=1) > 100)[0]
        y0 = rows.mean() if len(rows) else a.shape[0] / 2
        k = 64.0 / s.size[0]
        s = s.resize((64, max(2, int(s.size[1] * k))), Image.LANCZOS)
        spr.append((s, (x0 / a.shape[1], y0 / a.shape[0])))
    # a FAN of twigs spreading forward (+x) from the branch's end at the left middle, like the tip of a pine branch:
    # the card is laid along the branch with u = forward
    S = 1024
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    twigs = []
    for i in range(44):
        a = rng.gauss(0.0, 0.55)
        a = max(-1.45, min(1.45, a))
        ln = S * rng.uniform(0.35, 0.8) * (1.0 - 0.35 * abs(a) / 1.45)
        p0 = (S * 0.08 + rng.uniform(0, S * 0.25), S / 2 + rng.uniform(-30, 30))
        pts = []; q = list(p0); ang = a
        for _ in range(int(ln)):
            pts.append(tuple(q))
            ang += rng.uniform(-0.018, 0.018) - ang * 0.0015
            q = [q[0] + math.cos(ang), q[1] + math.sin(ang)]
            if q[0] < 4 or q[0] > S - 8 or q[1] < 8 or q[1] > S - 8:
                break
        twigs.append(pts)
    stamps = []
    for pts in twigs:
        for j in range(0, len(pts) - 2, 4):
            x, y = pts[j]
            x2, y2 = pts[j + 2]
            d = math.degrees(math.atan2(y2 - y, x2 - x))
            tt = j / len(pts)
            for side in (-1, 1):
                stamps.append((rng.random(), (x, y), d + side * rng.uniform(22, 58), rng.uniform(38, 54) * (1 - 0.3 * tt), rng.uniform(0.66, 1.06)))
    stamps.sort(key=lambda s: s[0])
    for _, at, deg, ln, shade in stamps:
        s, anc = rng.choice(spr)
        paste(img, s, at, -deg, ln / s.size[0], shade, anc)
    from PIL import ImageDraw
    dr = ImageDraw.Draw(img)
    for pts in twigs:
        for j in range(len(pts) - 1):
            dr.line([pts[j], pts[j + 1]], fill=(92, 84, 60, 255), width=max(1, int(round(3 * (1 - j / len(pts))))))
    bleed(img, (0.62, 0.72, 0.55)).save(f"{out}/needle_tuft.png")


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
    # real scale: the card holds ~0.8 m of foliage (the leafy crowns repeat it across big cards), a leaf ~6-10 cm
    S = 1024
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    rng = random.Random(90210)
    items = []
    for i in range(95):
        a = rng.random() * math.tau
        r = math.sqrt(rng.random()) * S * 0.36
        at = (S / 2 + math.cos(a) * r, S / 2 + math.sin(a) * r)
        depth = rng.random()
        items.append((depth, at, rng.uniform(0, 360), rng.uniform(80, 125), 0.68 + 0.4 * depth))
    items.sort(key=lambda t: t[0])
    for _, at, deg, ln, shade in items:
        s, anc, _ = rng.choice(singles)
        paste(img, s, at, deg, ln / s.size[1], shade, anc)
    bleed(img, (0.6, 0.72, 0.48)).save(f"{out}/leaf_cluster.png")
    # the crowns' version: a dense seamless patch (~0.8 m of foliage at real leaf size)
    T = 3 * S
    acc = Image.new("RGBA", (T, T), (0, 0, 0, 0))
    rng = random.Random(90211)
    items = sorted([(rng.random(), (rng.random() * S, rng.random() * S), rng.uniform(0, 360), rng.uniform(80, 125)) for _ in range(190)], key=lambda t: t[0])
    for depth, at, deg, ln in items:
        s_, anc, _ = rng.choice(singles)
        _tile_paste(lambda a, sp=s_, d=deg, l=ln, sh=0.68 + 0.4 * depth, an=anc: paste(acc, sp, a, d, l / sp.size[1], sh, an), S, at)
    bleed(acc.crop((S, S, 2 * S, 2 * S)), (0.6, 0.72, 0.48)).save(f"{out}/leaf_tile.png")


def _tile_paste(paste_fn, S, at, *args):
    """Paste at `at` and at every wrapped copy one tile over, onto a 3S x 3S canvas (crop the middle S x S: seamless)."""
    for oy in (-1, 0, 1):
        for ox in (-1, 0, 1):
            paste_fn((at[0] + S + ox * S, at[1] + S + oy * S), *args)


def spray(folder, out):
    """leaf_spray.png 1024 x 1024: the airy bush look the user picked (2026-11-26, like the dry shrub): thin twigs branching
    up / out from the bottom middle, small real leaves (LeafSet005 singles, ~6-8 cm on a ~1 m card) along them, light
    through the gaps. The green bushes' and the leafy trees' card (one spray per card, no repeat)."""
    c, o = load(folder, "LeafSet005")
    bs = [b for b in boxes(o > 0.4) if (b[1] - b[0]) >= 300 and (b[3] - b[2]) <= (b[1] - b[0]) * 0.6]   # single leaves
    tint = (0.86, 1.0, 0.72)
    leaves_ = []
    for b in bs:
        s_ = sprite(c, o, b, tint, 0.72, shrink=3)
        k = 96.0 / s_.size[1]
        leaves_.append(s_.resize((max(2, int(s_.size[0] * k)), 96), Image.LANCZOS))
    S = 1024
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    rng = random.Random(4711)
    twigs = []

    def grow(p0, ang, ln, depth):
        pts = []; q = list(p0); a = ang
        for _ in range(int(ln)):
            pts.append(tuple(q))
            a += rng.uniform(-0.03, 0.03) + (-math.pi / 2 - a) * 0.002   # (wandering, drawn up a little)
            q = [q[0] + math.cos(a), q[1] + math.sin(a)]
            if q[0] < 10 or q[0] > S - 10 or q[1] < 10 or q[1] > S - 10:
                break
        twigs.append((pts, depth))
        if depth < 2:
            for j in range(int(len(pts) * 0.2), len(pts) - 20, rng.randint(55, 95)):
                side = 1 if rng.random() < 0.5 else -1
                grow(pts[j], a + side * rng.uniform(0.4, 0.9), (len(pts) - j) * rng.uniform(0.5, 0.8), depth + 1)
    for i in range(9):
        ang = -math.pi / 2 + rng.uniform(-1.15, 1.15)
        grow((S / 2 + rng.uniform(-30, 30), S * 0.94), ang, S * rng.uniform(0.45, 0.8), 0)
    # leaves along the twigs, alternate sides, back ones darker
    stamps = []
    for pts, depth in twigs:
        k = 0
        for j in range(int(len(pts) * 0.4), len(pts) - 2, rng.randint(48, 70)):
            x, y = pts[j]
            x2, y2 = pts[j + 2]
            d = math.degrees(math.atan2(y2 - y, x2 - x))
            side = 1 if k % 2 == 0 else -1
            k += 1
            if rng.random() < 0.18:
                continue   # (a gap: bare twig)
            stamps.append((rng.random(), (x, y), d + side * rng.uniform(35, 75), rng.uniform(44, 62), rng.uniform(0.66, 1.06)))
        if rng.random() < 0.6:   # often a leaf at the tip, sometimes the bare twig sticks out
            x, y = pts[-1]
            x0, y0 = pts[max(0, len(pts) - 4)]
            stamps.append((rng.random(), (x, y), math.degrees(math.atan2(y - y0, x - x0)), rng.uniform(46, 60), 1.0))
    from PIL import ImageDraw
    dr = ImageDraw.Draw(img)
    for pts, depth in twigs:
        for j in range(len(pts) - 1):
            w = (5 if depth == 0 else 3 if depth == 1 else 2) * (1 - j / len(pts) * 0.6)
            dr.line([pts[j], pts[j + 1]], fill=(104, 86, 62, 255), width=max(1, int(round(w))))
    stamps.sort(key=lambda t: t[0])
    for _, at, deg, ln, shade in stamps:
        s_ = rng.choice(leaves_)
        # (the leaf's stalk at its bottom: anchor there; turned so it points along `deg`, image y down)
        paste(img, s_, at, -(deg + 90), ln / s_.size[1], shade, (0.5, 0.97))
    bleed(img, (0.6, 0.72, 0.48)).save(f"{out}/leaf_spray.png")


def beech(prefix, out):
    c = np.asarray(Image.open(prefix + "albedo.tif").convert("RGB"), np.float32) / 255.0
    o = np.asarray(Image.open(prefix + "alpha.tif").convert("L"), np.float32) / 255.0
    nm = np.asarray(Image.open(prefix + "normal.tif").convert("RGB"), np.float32) / 255.0
    tr = np.asarray(Image.open(prefix + "translucency.tif").convert("L"), np.float32) / 255.0
    bs = [b for b in boxes(o > 0.4) if (b[1] - b[0]) * (b[3] - b[2]) > 200 * 200]
    tint = (0.86, 1.0, 0.72)
    pieces = []
    for b in bs:
        y1, y2, x1, x2 = [max(0, v) for v in b]
        col = sprite(c, o, b, tint, 0.72, shrink=1, rel_max=1.25)
        # the normal + translucency sprite of the same box (alpha = the twig's opacity, to composite with)
        n4 = np.dstack([nm[y1:y2, x1:x2], tr[y1:y2, x1:x2], o[y1:y2, x1:x2]])
        big = (y2 - y1) * (x2 - x1) > 500 * 500
        pieces.append((col, n4, big))
    S = 1024
    acc = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    nrm = np.zeros((S, S, 4), np.float32); nrm[..., 0:3] = (0.5, 0.5, 1.0)   # (flat normal, no translucency)
    ncov = np.zeros((S, S), np.float32)
    rng = random.Random(1880)
    items = []
    for i in range(11):
        a = rng.random() * math.tau
        r = math.sqrt(rng.random()) * S * 0.3
        depth = rng.random()
        items.append((depth, (S / 2 + math.cos(a) * r, S / 2 + math.sin(a) * r), rng.uniform(0, 360), 0.68 + 0.4 * depth, rng.random()))
    items.sort(key=lambda t: t[0])
    for _, at, deg, shade, pick in items:
        col, n4, big = pieces[int(pick * len(pieces)) % len(pieces)]
        size = (rng.uniform(0.4, 0.5) if big else rng.uniform(0.24, 0.3)) * S
        scale = size / max(col.size)
        # (the crowns repeat this picture: keep every twig inside its border, or repeats show straight cut edges)
        lim = S / 2 - size / 2 - 12
        dx, dy = at[0] - S / 2, at[1] - S / 2
        dl = math.hypot(dx, dy)
        if dl > lim:
            at = (S / 2 + dx / dl * max(lim, 0), S / 2 + dy / dl * max(lim, 0))
        paste(acc, col, at, deg, scale, shade, (0.5, 0.5))
        _paste_normal(nrm, ncov, n4, at, deg, scale)
    bleed(acc, (0.6, 0.72, 0.48)).save(f"{out}/leaf_beech.png")
    # where no twig covers, keep the flat normal; the normal's alpha = translucency
    img = Image.fromarray((np.clip(nrm, 0, 1) * 255).astype(np.uint8), "RGBA")
    img.save(f"{out}/leaf_beech_n.png")
    # the crowns' version: a dense SEAMLESS patch of twigs (~0.8 m of foliage), repeated across a crown's cards
    T = 3 * S
    acc = Image.new("RGBA", (T, T), (0, 0, 0, 0))
    nrm = np.zeros((T, T, 4), np.float32); nrm[..., 0:3] = (0.5, 0.5, 1.0)
    ncov = np.zeros((T, T), np.float32)
    rng = random.Random(1881)
    items = []
    for i in range(34):
        items.append((rng.random(), (rng.random() * S, rng.random() * S), rng.uniform(0, 360), rng.random()))
    items.sort(key=lambda t: t[0])
    for depth, at, deg, pick in items:
        col, n4, big = pieces[int(pick * len(pieces)) % len(pieces)]
        size = (rng.uniform(0.4, 0.5) if big else rng.uniform(0.24, 0.3)) * S
        scale = size / max(col.size)
        shade = 0.68 + 0.4 * depth
        _tile_paste(lambda a, c=col, d=deg, sc=scale, sh=shade: paste(acc, c, a, d, sc, sh, (0.5, 0.5)), S, at)
        _tile_paste(lambda a, n=n4, d=deg, sc=scale: _paste_normal(nrm, ncov, n, a, d, sc), S, at)
    bleed(acc.crop((S, S, 2 * S, 2 * S)), (0.6, 0.72, 0.48)).save(f"{out}/leaf_beech_tile.png")
    Image.fromarray((np.clip(nrm[S:2 * S, S:2 * S], 0, 1) * 255).astype(np.uint8), "RGBA").save(f"{out}/leaf_beech_tile_n.png")


def _paste_normal(dst, cov, n4, at, deg, scale):
    """Rotate + scale a [normal rgb, translucency, opacity] sprite like paste() and write it over dst where opaque.
    The normals' x / y turn with the picture (tangent space, y up): a CCW image turn of deg turns them by deg."""
    h, w = n4.shape[:2]
    t = math.radians(deg)
    nx = n4[..., 0] * 2 - 1; ny = n4[..., 1] * 2 - 1
    rx = nx * math.cos(t) - ny * math.sin(t)
    ry = nx * math.sin(t) + ny * math.cos(t)
    rgba = np.dstack([rx * 0.5 + 0.5, ry * 0.5 + 0.5, n4[..., 2], n4[..., 4]])   # (blue dropped: rebuilt below)
    img = Image.fromarray((np.clip(rgba, 0, 1) * 255).astype(np.uint8), "RGBA")
    tr = Image.fromarray((np.clip(n4[..., 3], 0, 1) * 255).astype(np.uint8), "L")
    sw, sh = max(1, int(w * scale)), max(1, int(h * scale))
    img = img.resize((sw, sh), Image.LANCZOS).rotate(deg, resample=Image.BICUBIC, expand=True)
    tr = tr.resize((sw, sh), Image.LANCZOS).rotate(deg, resample=Image.BICUBIC, expand=True)
    px = int(at[0] - img.size[0] / 2); py = int(at[1] - img.size[1] / 2)
    a = np.asarray(img, np.float32) / 255.0
    tt = np.asarray(tr, np.float32) / 255.0
    H, W = dst.shape[:2]
    x0, y0 = max(0, px), max(0, py)
    x1, y1 = min(W, px + a.shape[1]), min(H, py + a.shape[0])
    if x1 <= x0 or y1 <= y0:
        return
    sa = a[y0 - py:y1 - py, x0 - px:x1 - px]
    st = tt[y0 - py:y1 - py, x0 - px:x1 - px]
    m = sa[..., 3:4] > 0.5
    nx = sa[..., 0] * 2 - 1; ny = sa[..., 1] * 2 - 1
    nz = np.sqrt(np.clip(1 - nx * nx - ny * ny, 0, 1))
    new = np.dstack([sa[..., 0], sa[..., 1], nz * 0.5 + 0.5, st])
    reg = dst[y0:y1, x0:x1]
    dst[y0:y1, x0:x1] = np.where(m, new, reg)


if __name__ == "__main__":
    needles(sys.argv[1], sys.argv[3])
    tufts(sys.argv[1], sys.argv[3])
    leaves(sys.argv[2], sys.argv[3])
    spray(sys.argv[2], sys.argv[3])
    if len(sys.argv) > 4:
        beech(sys.argv[4], sys.argv[3])
    print("done")
