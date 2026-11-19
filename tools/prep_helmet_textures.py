"""Helmet texture prep (system Python + Pillow): downsizes the helmet maps to 1024 and packs the Unity-style MaskMap
(R metallic, G occlusion, A smoothness) into glTF's occlusion / roughness / metallic channels.
  python -I tools/prep_helmet_textures.py <dir with the unpacked maps> <out dir>
The helmet exporter (tools/export_helmets.py) embeds what this writes."""
import sys, os
from PIL import Image
SRC, OUT = sys.argv[1], sys.argv[2]
os.makedirs(OUT, exist_ok=True)
SIZE = 1024

def find(name):
    for root, _, files in os.walk(SRC):
        if name in files: return os.path.join(root, name)
    raise SystemExit("missing " + name)

def base(name, out):
    Image.open(find(name)).convert("RGB").resize((SIZE, SIZE), Image.LANCZOS).save(os.path.join(OUT, out), quality=90)

def normal(name, out):
    Image.open(find(name)).convert("RGB").resize((SIZE, SIZE), Image.LANCZOS).save(os.path.join(OUT, out))

def orm(name, out):
    im = Image.open(find(name)).convert("RGBA").resize((SIZE, SIZE), Image.LANCZOS)
    r, g, b, a = im.split()
    inv = a.point(lambda v: 255 - v)                      # roughness = 1 - smoothness
    Image.merge("RGB", (g, inv, r)).save(os.path.join(OUT, out))   # R occlusion, G roughness, B metallic

base("HELMET_5_0.png", "6d_black_base.jpg")
base("HELMET_7_0.png", "6d_silver_base.jpg")
base("HELMET_TLDSE5_0.png", "tld_base.jpg")
normal("tldse5_DefaultMaterial_Normal.1001.png", "tld_normal.png")
orm("tldse5_DefaultMaterial_MaskMap.1001.png", "tld_orm.png")
base("oakleyairbrake_DefaultMaterial_BaseMap.1001.png", "oakley_base.jpg")
normal("oakleyairbrake_DefaultMaterial_Normal.1001.png", "oakley_normal.png")
orm("oakleyairbrake_DefaultMaterial_MaskMap.1001.png", "oakley_orm.png")
print("ok", sorted(os.listdir(OUT)))
