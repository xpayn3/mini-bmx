"""Helmets for the rider: 6D ATR-2 (two skins) and Troy Lee SE5, each an FBX of a helmet with its goggles on.

First prep the maps:   python -I tools/prep_helmet_textures.py <unpacked maps> <tex dir>
Then (Blender 4.1+):   blender -b -P tools/export_helmets.py -- <6datr211goggles2.fbx> <tldse5goggles.fbx> <tex dir>

Writes godot/assets/helmets/helmet_<id>.glb in the same convention as assets/helmet.glb: one node "helmet", centred on
its shell, +X = the face, +Y up, sized like the stock shell. Two nodes: "helmet" (the shell, material "tex_shell") and
"helmet_goggles" (the goggles + strap of the model, material "tex_goggles"), split by the FBX's material faces. The rider
mounts the shell with its own goggles by default, or the model's goggles when look.helmetGoggles = "helmet".
"""
import bpy, sys, os, json, struct, math
import numpy as np

FBX_6D, FBX_TLD, TEX = sys.argv[-3], sys.argv[-2], sys.argv[-1]
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "godot", "assets", "helmets")
os.makedirs(OUT, exist_ok=True)

SHELL_LEN = 0.344    # the stock helmet's shell: 0.344 long, 0.272 high, 0.236 wide (assets/helmet.glb)

SPECS = [
    # id, fbx, face direction, up (in the FBX's Blender world), shell material slot, goggle slot, shell maps, goggle maps
    ("6d_black", FBX_6D, (-1, 0, 0), (0, 0, 1), 0, 5, ("6d_black_base.jpg", None, None), ("goggles_base.jpg", "goggles_orm.png", "goggles_normal.png")),
    ("6d_silver", FBX_6D, (-1, 0, 0), (0, 0, 1), 0, 5, ("6d_silver_base.jpg", None, None), ("goggles_base.jpg", "goggles_orm.png", "goggles_normal.png")),
    ("tld", FBX_TLD, (0, -1, 0), (0, 0, 1), 0, 1, ("tld_base.jpg", "tld_orm.png", "tld_normal.png"), ("goggles_base.jpg", "goggles_orm.png", "goggles_normal.png")),
]


def load_mesh(path):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.fbx(filepath=path)
    o = [o for o in bpy.data.objects if o.type == 'MESH'][0]
    me = o.data
    me.calc_loop_triangles()
    mw = np.array(o.matrix_world)
    V = np.empty(len(me.vertices) * 3); me.vertices.foreach_get("co", V); V = V.reshape(-1, 3)
    V = V @ mw[:3, :3].T + mw[:3, 3]
    nm = np.linalg.inv(mw[:3, :3]).T
    uv = me.uv_layers[0].data
    tris = []
    for t in me.loop_triangles:
        vi = list(t.vertices)
        n = np.array([list(v) for v in t.split_normals]) @ nm.T
        n /= np.maximum(np.linalg.norm(n, axis=1, keepdims=True), 1e-9)
        u = np.array([list(uv[l].uv) for l in t.loops])
        tris.append((V[vi], n, u, t.material_index))
    return tris


def build(spec):
    hid, path, face, up, sh_slot, gg_slot, shell_maps, gog_maps = spec
    tris = load_mesh(path)
    ex = np.array(face, float); ey = np.array(up, float); ez = np.cross(ex, ey)
    R = np.stack([ex, ey, ez])                       # rows: the new axes
    shell = np.concatenate([t[0] for t in tris if t[3] == sh_slot])
    lo = np.percentile(shell @ R.T, 0.5, axis=0); hi = np.percentile(shell @ R.T, 99.5, axis=0)
    centre = (lo + hi) / 2
    s = SHELL_LEN / (hi[0] - lo[0])
    print(hid, "shell dims (l, h, w) = %.3f %.3f %.3f  after scale %.3f %.3f %.3f  (stock 0.344 0.272 0.236)" % (
        *(hi - lo), *((hi - lo) * s)))
    groups = {sh_slot: [], gg_slot: []}
    for p, n, u, m in tris:
        if m not in groups: continue
        groups[m].append(((p @ R.T - centre) * s, n @ R.T, u))
    return groups, (sh_slot, gg_slot), shell_maps, gog_maps


def write_glb(path, groups, slots, shell_maps, gog_maps, extras):
    bins, views, accessors, images, textures, materials, prims = [], [], [], [], [], [], []
    off = [0]

    def view(data, target=None):
        pad = (-len(data)) % 4
        v = {"buffer": 0, "byteOffset": off[0], "byteLength": len(data)}
        if target: v["target"] = target
        views.append(v); bins.append(data + b"\0" * pad); off[0] += len(data) + pad
        return len(views) - 1

    def tex(fname, cache={}):
        if fname is None: return None
        if fname in cache: return cache[fname]
        data = open(os.path.join(TEX, fname), "rb").read()
        images.append({"bufferView": view(data), "mimeType": "image/jpeg" if fname.endswith(".jpg") else "image/png"})
        textures.append({"source": len(images) - 1, "sampler": 0})
        cache[fname] = len(textures) - 1
        return cache[fname]

    for name, slot, maps in (("tex_shell", slots[0], shell_maps), ("tex_goggles", slots[1], gog_maps)):
        base, orm, nor = maps
        mat = {"name": name, "doubleSided": True,
               "pbrMetallicRoughness": {"baseColorTexture": {"index": tex(base)}, "metallicFactor": (0.45 if name == "tex_goggles" else 1.0) if orm else 0.0,   # the lens mask is a full mirror: it blew out to white
                                        "roughnessFactor": 1.0 if orm else 0.42}}
        if orm:
            mat["pbrMetallicRoughness"]["metallicRoughnessTexture"] = {"index": tex(orm)}
            mat["occlusionTexture"] = {"index": tex(orm)}
        if nor:
            mat["normalTexture"] = {"index": tex(nor)}
        materials.append(mat)
        T = groups[slot]
        P = np.concatenate([t[0] for t in T]); N = np.concatenate([t[1] for t in T]); U = np.concatenate([t[2] for t in T])
        U = np.stack([U[:, 0], 1.0 - U[:, 1]], 1)       # glTF's v runs down
        key = np.concatenate([np.round(P, 5), np.round(N, 3), np.round(U, 5)], 1)
        _, first, inv = np.unique(key, axis=0, return_index=True, return_inverse=True)
        inv = inv.ravel()
        vp = P[first].astype(np.float32); vn = N[first]
        vn = (vn / np.maximum(np.linalg.norm(vn, axis=1, keepdims=True), 1e-9)).astype(np.float32)
        vu = U[first].astype(np.float32)
        ix = inv.astype(np.uint32 if len(vp) > 65535 else np.uint16)
        a0 = len(accessors)
        accessors.append({"bufferView": view(vp.tobytes(), 34962), "componentType": 5126, "count": len(vp), "type": "VEC3",
                          "min": vp.min(0).tolist(), "max": vp.max(0).tolist()})
        accessors.append({"bufferView": view(vn.tobytes(), 34962), "componentType": 5126, "count": len(vn), "type": "VEC3"})
        accessors.append({"bufferView": view(vu.tobytes(), 34962), "componentType": 5126, "count": len(vu), "type": "VEC2"})
        accessors.append({"bufferView": view(ix.tobytes(), 34963), "componentType": 5125 if ix.dtype == np.uint32 else 5123,
                          "count": len(ix), "type": "SCALAR"})
        prims.append({"attributes": {"POSITION": a0, "NORMAL": a0 + 1, "TEXCOORD_0": a0 + 2}, "indices": a0 + 3,
                      "material": len(materials) - 1})
        print("  ", name, len(ix) // 3, "tris")
    doc = {"asset": {"version": "2.0", "generator": "gamecycling export_helmets.py"}, "scene": 0, "scenes": [{"nodes": [0, 1]}],
           "nodes": [{"name": "helmet", "mesh": 0}, {"name": "helmet_goggles", "mesh": 1}],
           "meshes": [{"name": "helmet", "primitives": [prims[0]]}, {"name": "helmet_goggles", "primitives": [prims[1]]}],
           "materials": materials, "textures": textures, "images": images, "samplers": [{"magFilter": 9729, "minFilter": 9987, "wrapS": 10497, "wrapT": 10497}],
           "accessors": accessors, "bufferViews": views, "buffers": [{"byteLength": off[0]}]}
    js = json.dumps(doc).encode(); js += b" " * ((-len(js)) % 4)
    b = b"".join(bins)
    with open(path, "wb") as f:
        f.write(struct.pack("<III", 0x46546C67, 2, 12 + 8 + len(js) + 8 + len(b)))
        f.write(struct.pack("<II", len(js), 0x4E4F534A)); f.write(js)
        f.write(struct.pack("<II", len(b), 0x004E4942)); f.write(b)
    print("wrote", path, os.path.getsize(path) // 1024, "KB")


for spec in SPECS:
    groups, slots, sm, gm = build(spec)
    write_glb(os.path.join(OUT, "helmet_%s.glb" % spec[0]), groups, slots, sm, gm, None)
