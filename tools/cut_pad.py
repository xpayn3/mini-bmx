"""Cut the white background off the Xbox controller photo for Settings > Controller.

    python tools/cut_pad.py <photo.jpg|png>   ->  godot/assets/ui/xbox_pad.png

The background is flood-filled from the borders (near-white only, so the white
controller's own shading stays), the soft floor shadow under it is dropped too,
and the edge gets a 1-2 px feather. The canvas is NOT cropped: pad_map.gd places
the buttons by fractions of the photo's size.
"""
import sys
from collections import deque
from pathlib import Path
from PIL import Image, ImageFilter

src = Path(sys.argv[1])
out = Path(__file__).resolve().parent.parent / "godot" / "assets" / "ui" / "xbox_pad.png"
im = Image.open(src).convert("RGB")
w, h = im.size
px = im.load()

def bg(c, tol):
    return min(c) >= tol and max(c) - min(c) < 12

mask = Image.new("L", (w, h), 255)   # 255 = keep
m = mask.load()
seen = bytearray(w * h)
q = deque()
for x in range(w):
    q.append((x, 0)); q.append((x, h - 1))
for y in range(h):
    q.append((0, y)); q.append((w - 1, y))
while q:
    x, y = q.popleft()
    i = y * w + x
    if seen[i]:
        continue
    seen[i] = 1
    # pure white everywhere; a little greyer allowed in the bottom quarter (the floor shadow)
    if not bg(px[x, y], 200 if y > h * 0.86 else 236 if y > h * 0.8 else 247):
        continue
    m[x, y] = 0
    for nx, ny in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
        if 0 <= nx < w and 0 <= ny < h and not seen[ny * w + nx]:
            q.append((nx, ny))
mask = mask.filter(ImageFilter.MinFilter(3)).filter(ImageFilter.GaussianBlur(1.0))
rgba = im.convert("RGBA")
rgba.putalpha(mask)
out.parent.mkdir(parents=True, exist_ok=True)
rgba.save(out)
print("saved", out, rgba.size)
