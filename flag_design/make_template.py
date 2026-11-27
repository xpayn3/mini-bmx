"""Draws flag_template.png (the layout guide) and flag_mask.png (the cloth's exact shape, white = cloth) for the
checkpoint feather flags. Same outline as godot/scripts/world/checkpoint_flags.gd (outline()): keep the two in step.
Run: python make_template.py [out_dir]"""
import math, sys, os
from PIL import Image, ImageDraw, ImageFont, ImageFilter
H_POLE, Y0, CW, ARC_H, BOT_X, BOT_Y, T_ARC = 3.4, 0.5, 0.8, 0.95, 0.38, 0.12, 0.6
W_PX, H_PX = 512, 1856   # = CW x (H_POLE - Y0) at 640 px per metre
def outline(t):
    yc = H_POLE - ARC_H
    if t <= T_ARC:
        u = t / T_ARC
        return BOT_X + (CW - BOT_X) * math.sin(u * math.pi / 2), (Y0 + BOT_Y) + (yc - Y0 - BOT_Y) * u
    th = (t - T_ARC) / (1 - T_ARC) * math.pi / 2
    return CW * math.cos(th), yc + ARC_H * math.sin(th)
def px(x, y): return (x / CW * W_PX, (1 - (y - Y0) / (H_POLE - Y0)) * H_PX)
out = sys.argv[1] if len(sys.argv) > 1 else os.path.dirname(os.path.abspath(__file__))
pts = [px(0, Y0), px(0, H_POLE)] + [px(*outline(1 - k / 200)) for k in range(201)]
def mask_of(pp):
    m = Image.new("L", (W_PX * 4, H_PX * 4), 0)
    ImageDraw.Draw(m).polygon([(x * 4, y * 4) for x, y in pp], fill=255)
    return m.resize((W_PX, H_PX), Image.LANCZOS)
mask = mask_of(pts); mask.save(os.path.join(out, "flag_mask.png"))
img = Image.new("RGBA", (W_PX, H_PX), (58, 58, 62, 255)); d = ImageDraw.Draw(img)
img.paste((255, 255, 255, 255), (0, 0), mask)
sl = 0.045 / CW * W_PX
d.rectangle([0, 0, sl, H_PX], fill=(255, 200, 200, 255))
for m in range(1, 30):   # 10 cm grid
    y = px(0, Y0 + m * 0.1)[1]; d.line([0, y, W_PX, y], fill=(215, 215, 220, 255))
for m in range(1, 8):
    x = px(m * 0.1, Y0)[0]; d.line([x, 0, x, H_PX], fill=(215, 215, 220, 255))
img.paste((58, 58, 62, 255), (0, 0), mask.point(lambda v: 255 - v))
# safe area: 5 cm inside the outline, clear of the sleeve, below the top of the arc's steep part
inset = int(0.05 / CW * W_PX)
pad = Image.new("L", (W_PX + 2 * inset, H_PX + 2 * inset), 0)   # (black round it: the filter must see the edge)
pad.paste(mask.point(lambda v: 255 if v > 127 else 0), (inset, inset))
safe = pad.filter(ImageFilter.MinFilter(inset * 2 + 1)).crop((inset, inset, inset + W_PX, inset + H_PX))
sd = ImageDraw.Draw(safe)
sd.rectangle([0, 0, sl + inset, H_PX], fill=0)
sd.rectangle([0, 0, W_PX, px(0, H_POLE - 0.35)[1]], fill=0)
edge = safe.filter(ImageFilter.FIND_EDGES).point(lambda v: 255 if v > 0 else 0).filter(ImageFilter.MaxFilter(3))
img.paste((30, 160, 80, 255), (0, 0), edge)
d.line(pts + [pts[0]], fill=(220, 30, 40, 255), width=3)
def font(sz, bold=False):
    for n in (["arialbd.ttf"] if bold else ["arial.ttf"]):
        try: return ImageFont.truetype(n, sz)
        except OSError: pass
    return ImageFont.load_default()
d.text((sl + 6, 120), "POLE SLEEVE (sewn round the pole: hidden)", fill=(190, 40, 40, 255), font=font(15))
d.text((70, 900), "SAFE AREA\ninside the green line:\nlogos + text", fill=(25, 120, 60, 255), font=font(26, True))
d.text((70, 1010), "red line = the flag's edge\ngrey = cut off\ngrid = 10 cm\n512 x 1856 px = 0.8 x 2.9 m\npole on the LEFT, top = top", fill=(90, 90, 95, 255), font=font(18))
d.text((sl + 6, H_PX - 34), "bottom corner tied to the pole", fill=(200, 200, 205, 255), font=font(16))
img.convert("RGB").save(os.path.join(out, "flag_template.png"))
print("wrote", W_PX, "x", H_PX, "to", out)
