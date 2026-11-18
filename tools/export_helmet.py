"""Export the rider's full-face helmet from the bicycle project to godot/assets/helmet.glb.

Source: W:\\AR9\\houdini_bike_2026-09-09\\BIKE PROCEDURAL\\bicycle_procedural test .hip,
node /obj/Bicycle/bike_skeleton1 (rider_helmet_file = full-face-mtb-helmet/FullFaceHelmet/FF_Helmet.fbx).
The asset splits it into helmet_model_{shell,peak,liner,trim,vents,bolts}; each part
keeps the colour the asset gives it (col_helmet* parms).

The helmet is taken off the rider at rest, the asset's helmet tilt is undone, and it is
centred on its shell. Axes: +X forward (face), +Y up, +Z rider's right. Metres.
The game fits it to the rider's head (src/rider.js).

Run with Houdini 21 hython:
  & "C:\\Program Files\\Side Effects Software\\Houdini 21.0.440\\bin\\hython.exe" tools\\export_helmet.py
"""
import json, os, struct
import numpy as np
import hou

HIP = r"W:\AR9\houdini_bike_2026-09-09\BIKE PROCEDURAL\bicycle_procedural test .hip"
NODE = "/obj/Bicycle/bike_skeleton1"
OUT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "godot", "assets", "helmet.glb")
TARGET_TRIS = int(os.environ.get("HELMET_TRIS", "9000"))

# part -> (colour parm, metallic, roughness)
PARTS = [("shell", "col_helmet", 0.3, 0.3), ("peak", "col_helmet_peak", 0.1, 0.35),
         ("liner", "col_helmet_liner", 0.0, 0.85), ("trim", "col_helmet_liner", 0.0, 0.6),
         ("vents", "col_helmet_vents", 0.4, 0.5), ("bolts", "col_helmet_bolts", 1.0, 0.25)]


def srgb_to_lin(c):
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def cook():
    try:
        hou.hipFile.load(HIP, suppress_save_prompt=True, ignore_load_warnings=True)
    except hou.OperationFailed:
        pass
    hou.setFrame(1)
    n = hou.node(NODE)
    for k in ("anim_fast", "use_path", "sus_sim", "do_cam"):
        p = n.parm(k)
        if p is not None:
            p.deleteAllKeyframes(); p.set(0)
    n.parm("do_rider").set(1); n.parm("rider_helmet").set(1)
    tilt = n.parm("rider_helmet_tilt").eval()
    n.setInput(0, None); n.setInput(1, None)
    cols = {}
    for _, c, _, _ in PARTS:
        cols[c] = [n.parm(c + "r").eval(), n.parm(c + "g").eval(), n.parm(c + "b").eval()]

    geo = hou.node("/obj").createNode("geo", "helmet_export")
    om = geo.createNode("object_merge"); om.parm("objpath1").set(n.path())
    keep = geo.createNode("attribwrangle"); keep.setInput(0, om); keep.parm("class").set(1)
    keep.parm("snippet").set('if (!startswith(s@name, "helmet_model_")) removeprim(0, @primnum, 1);')
    clean = geo.createNode("attribdelete"); clean.setInput(0, keep)
    clean.parm("vtxdel").set("*"); clean.parm("ptdel").set("* ^P"); clean.parm("primdel").set("* ^name")
    clean.parm("dtldel").set("*")
    tri = geo.createNode("divide"); tri.setInput(0, clean)
    tri.parm("convex").set(1); tri.parm("numsides").set(3)
    fuse = geo.createNode("fuse::2.0"); fuse.setInput(0, tri); fuse.parm("tol3d").set(1e-6)
    ntri = len(tri.geometry().prims())
    red = geo.createNode("polyreduce::2.0"); red.setInput(0, fuse)
    red.parm("percentage").set(min(100.0, 100.0 * TARGET_TRIS / max(ntri, 1)))
    nrm = geo.createNode("normal"); nrm.setInput(0, red)
    nrm.parm("type").set(1); nrm.parm("cuspangle").set(50)
    tri2 = geo.createNode("divide"); tri2.setInput(0, nrm)
    tri2.parm("convex").set(1); tri2.parm("numsides").set(3)
    w = geo.createNode("attribwrangle"); w.setInput(0, tri2)
    w.parm("class").set(3); w.parm("snippet").set("i@ptn = vertexpoint(0, @vtxnum);")
    out = w.geometry()
    for x in (keep, clean, tri, fuse, red, nrm, tri2, w):
        if x.errors():
            raise RuntimeError(x.path() + ": " + str(x.errors()))
    print("helmet: %d -> %d tris (asset tilt %.2f deg)" % (ntri, len(out.prims()), tilt))
    return out, cols, tilt


def main():
    out, cols, tilt = cook()
    P = np.array(out.pointFloatAttribValues("P"), np.float64).reshape(-1, 3)
    ptn = np.array(out.vertexIntAttribValues("ptn"), np.int64)
    N = np.array(out.vertexFloatAttribValues("N"), np.float64).reshape(-1, 3)
    names = np.array([s.replace("helmet_model_", "") for s in out.primStringAttribValues("name")])
    tris = np.arange(len(ptn)).reshape(-1, 3)[:, ::-1]        # Houdini CW -> glTF CCW

    # undo the asset's tilt (about the rider's left-right axis, +Z), then centre on the shell
    a = np.radians(-tilt)
    R = np.array([[np.cos(a), -np.sin(a), 0], [np.sin(a), np.cos(a), 0], [0, 0, 1]])
    P = P @ R.T; N = N @ R.T
    shell = P[ptn[tris[names == "shell"].ravel()]]
    lo, hi = shell.min(0), shell.max(0)
    c = (lo + hi) * 0.5
    P -= c
    print("shell size", (hi - lo).round(3).tolist())

    bin_chunks, views, accessors, prims, mats = [], [], [], [], []
    off = [0]

    def view(arr, target):
        d = arr.tobytes(); pad = (-len(d)) % 4
        views.append({"buffer": 0, "byteOffset": off[0], "byteLength": len(d), "target": target})
        bin_chunks.append(d + b"\0" * pad); off[0] += len(d) + pad
        return len(views) - 1

    for part, cp, met, rough in PARTS:
        sel = names == part
        if not sel.any():
            continue
        vids = tris[sel].ravel()
        pos, nrm = P[ptn[vids]], N[vids]
        key = np.concatenate([ptn[vids][:, None].astype(np.float64), np.round(nrm, 3)], 1)
        uniq, inv = np.unique(key, axis=0, return_inverse=True); inv = inv.ravel()
        first = np.zeros(len(uniq), np.int64); first[inv] = np.arange(len(inv))
        vp = pos[first].astype(np.float32)
        vn = nrm[first]; vn = (vn / np.maximum(np.linalg.norm(vn, axis=1, keepdims=True), 1e-8)).astype(np.float32)
        idx = inv.astype(np.uint32 if len(vp) > 65535 else np.uint16)
        k = len(accessors)
        accessors += [
            {"bufferView": view(vp, 34962), "componentType": 5126, "count": len(vp), "type": "VEC3",
             "min": vp.min(0).tolist(), "max": vp.max(0).tolist()},
            {"bufferView": view(vn, 34962), "componentType": 5126, "count": len(vn), "type": "VEC3"},
            {"bufferView": view(idx, 34963), "componentType": 5125 if idx.dtype == np.uint32 else 5123,
             "count": len(idx), "type": "SCALAR"}]
        mats.append({"name": part, "pbrMetallicRoughness": {
            "baseColorFactor": [srgb_to_lin(x) for x in cols[cp]] + [1.0],
            "metallicFactor": met, "roughnessFactor": rough}, "doubleSided": part in ("liner", "vents", "peak")})
        prims.append({"attributes": {"POSITION": k, "NORMAL": k + 1}, "indices": k + 2, "material": len(mats) - 1})
        print("  %-6s verts %5d tris %5d" % (part, len(vp), len(idx) // 3))

    gltf = {"asset": {"version": "2.0", "generator": "gamecycling export_helmet.py"},
            "scene": 0, "scenes": [{"nodes": [0]}],
            "nodes": [{"name": "helmet", "mesh": 0, "extras": {"shellSize": (hi - lo).tolist()}}],
            "meshes": [{"name": "helmet", "primitives": prims}], "materials": mats,
            "accessors": accessors, "bufferViews": views, "buffers": [{"byteLength": off[0]}]}
    js = json.dumps(gltf).encode(); js += b" " * ((-len(js)) % 4)
    binb = b"".join(bin_chunks)
    with open(OUT, "wb") as f:
        f.write(struct.pack("<III", 0x46546C67, 2, 12 + 8 + len(js) + 8 + len(binb)))
        f.write(struct.pack("<II", len(js), 0x4E4F534A)); f.write(js)
        f.write(struct.pack("<II", len(binb), 0x004E4942)); f.write(binb)
    print("wrote", OUT, os.path.getsize(OUT) // 1024, "KB")


if __name__ == "__main__":
    main()
