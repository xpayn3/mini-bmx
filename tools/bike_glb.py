"""Shared helpers for the Blender bike exporters (export_tues.py, export_dhframe.py): the game's material
list, decimating + extracting a part as world-space triangles, and the glb writer (dh.glb node layout)."""
import bpy, os, json, struct, math
import numpy as np

MATS = [("paint", [0.62, 0.035, 0.03, 1.0], 0.35, 0.22), ("chrome", [0.80, 0.80, 0.82, 1.0], 1.0, 0.16),
        ("black", [0.025, 0.025, 0.028, 1.0], 0.7, 0.38), ("rubber", [0.018, 0.018, 0.018, 1.0], 0.0, 0.85),
        ("chain", [0.22, 0.22, 0.24, 1.0], 0.9, 0.45), ("plastic", [0.03, 0.03, 0.032, 1.0], 0.0, 0.55),
        ("gold", [0.90, 0.52, 0.10, 1.0], 1.0, 0.25)]
MI = {m[0]: i for i, m in enumerate(MATS)}



def reduce_ratio(f):
    return 0.1 if f > 12000 else 0.15 if f > 5000 else 0.3 if f > 2000 else 0.5 if f > 800 else 1.0


def extract(o):
    """world-space triangles + smooth normals of one part: (positions, normals, material names per tri)"""
    f0 = len(o.data.polygons)
    with bpy.context.temp_override(object=o, active_object=o, selected_objects=[o]):
        tri = o.modifiers.new("t", 'TRIANGULATE'); bpy.ops.object.modifier_apply(modifier=tri.name)
        r = reduce_ratio(f0)
        if r < 1.0:
            m = o.modifiers.new("d", 'DECIMATE'); m.ratio = r
            bpy.ops.object.modifier_apply(modifier=m.name)
        try:
            bpy.ops.object.shade_smooth_by_angle(angle=math.radians(40))
        except RuntimeError:
            pass   # keeps the normals the file came with (glTF imports)
    me = o.data
    mw = o.matrix_world
    nm = mw.to_3x3().inverted().transposed()
    P = np.empty(len(me.vertices) * 3, np.float64); me.vertices.foreach_get("co", P); P = P.reshape(-1, 3)
    W = np.array(mw)[:3, :3]; T = np.array(mw)[:3, 3]
    P = P @ W.T + T
    L = np.empty(len(me.loops), np.int64); me.loops.foreach_get("vertex_index", L)
    N = np.empty(len(me.loops) * 3, np.float64); me.corner_normals.foreach_get("vector", N); N = N.reshape(-1, 3)
    N = N @ np.array(nm).T
    N /= np.maximum(np.linalg.norm(N, axis=1, keepdims=True), 1e-9)
    mi = np.empty(len(me.polygons), np.int64); me.polygons.foreach_get("material_index", mi)
    names = [m.name if m else "" for m in me.materials] or [""]
    return P, L, N, mi, names



# ---------------------------------------------------------------- glb writer
def write_glb(path, nodes, extras=None, root="dh"):
    """nodes: [{name, parent, t (xyz relative to parent), parts: [(pos, nrm, mat)]}] (parents first)"""
    bins, views, accessors, meshes, off = [], [], [], [], [0]
    def view(arr, target):
        d = arr.tobytes(); pad = (-len(d)) % 4
        views.append({"buffer": 0, "byteOffset": off[0], "byteLength": len(d), "target": target})
        bins.append(d + b"\0" * pad); off[0] += len(d) + pad
        return len(views) - 1
    gl = [{"name": root, "children": []}]; idx = {None: 0}
    total = 0
    for nd in nodes:
        entry = {"name": nd["name"], "translation": [float(v) for v in nd["t"]]}
        if "rotz" in nd: entry["rotation"] = [0.0, 0.0, math.sin(nd["rotz"] / 2), math.cos(nd["rotz"] / 2)]
        prims = []
        for mi in range(len(MATS)):
            sel = [p for p in nd.get("parts", []) if MI[p[2]] == mi]
            if not sel: continue
            pos = np.concatenate([p[0] for p in sel]) - (0 if nd.get("local") else np.array(nd["origin"]))   # local: already relative to the node
            nrm = np.concatenate([p[1] for p in sel])
            if "rotz" in nd:   # a part with its own frame (the shock spring: local +Y along the shock)
                ang = nd["rotz"]; R = np.array([[math.cos(ang), -math.sin(ang), 0], [math.sin(ang), math.cos(ang), 0], [0, 0, 1]])
                pos = pos @ R; nrm = nrm @ R
            key = np.concatenate([np.round(pos, 5), np.round(nrm, 3)], 1)
            uniq, first, inv = np.unique(key, axis=0, return_index=True, return_inverse=True)
            inv = inv.ravel()
            vpos = pos[first].astype(np.float32); vn = nrm[first]
            vn = (vn / np.maximum(np.linalg.norm(vn, axis=1, keepdims=True), 1e-8)).astype(np.float32)
            ix = inv.astype(np.uint32 if len(vpos) > 65535 else np.uint16)
            pa = len(accessors)
            accessors.append({"bufferView": view(vpos, 34962), "componentType": 5126, "count": len(vpos), "type": "VEC3",
                              "min": vpos.min(0).tolist(), "max": vpos.max(0).tolist()})
            accessors.append({"bufferView": view(vn, 34962), "componentType": 5126, "count": len(vn), "type": "VEC3"})
            accessors.append({"bufferView": view(ix, 34963), "componentType": 5125 if ix.dtype == np.uint32 else 5123,
                              "count": len(ix), "type": "SCALAR"})
            prims.append({"attributes": {"POSITION": pa, "NORMAL": pa + 1}, "indices": pa + 2, "material": mi})
            total += len(ix) // 3
        if prims:
            entry["mesh"] = len(meshes); meshes.append({"name": nd["name"], "primitives": prims})
        idx[nd["name"]] = len(gl); gl.append(entry)
        gl[idx[nd["parent"]]].setdefault("children", []).append(idx[nd["name"]])
    if extras: gl[0]["extras"] = extras
    doc = {"asset": {"version": "2.0", "generator": "gamecycling export_tues.py"}, "scene": 0, "scenes": [{"nodes": [0]}],
           "nodes": gl, "meshes": meshes,
           "materials": [{"name": n, "pbrMetallicRoughness": {"baseColorFactor": c, "metallicFactor": m, "roughnessFactor": r}} for n, c, m, r in MATS],
           "accessors": accessors, "bufferViews": views, "buffers": [{"byteLength": off[0]}]}
    js = json.dumps(doc).encode(); js += b" " * ((-len(js)) % 4)
    b = b"".join(bins)
    with open(path, "wb") as f:
        f.write(struct.pack("<III", 0x46546C67, 2, 12 + 8 + len(js) + 8 + len(b)))
        f.write(struct.pack("<II", len(js), 0x4E4F534A)); f.write(js)
        f.write(struct.pack("<II", len(b), 0x004E4942)); f.write(b)
    print("wrote", path, os.path.getsize(path) // 1024, "KB", total, "tris")




def dh_rotors(dh_path):
    """the brake discs of dh.glb's stock wheels (the game finds them with BikeFX.find_rotor and heats them): wheel-local
    triangles, so they can ride on the placeholder wheels of the other frames. Needs a clean scene."""
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=dh_path)
    out = {}
    for name in ("wheel_front", "wheel_rear"):
        o = bpy.data.objects[name]; me = o.data
        me.calc_loop_triangles()
        V = np.empty(len(me.vertices) * 3); me.vertices.foreach_get("co", V); V = V.reshape(-1, 3)
        V = np.stack([V[:, 0], V[:, 2], -V[:, 1]], 1)           # Blender -> game axes (wheel-local)
        parts = {}
        for t in me.loop_triangles:
            p = V[list(t.vertices)]
            r = np.hypot(p[:, 0], p[:, 1])
            if r.min() < 0.05 or r.max() > 0.16 or p[:, 2].min() < -0.075 or p[:, 2].max() > -0.035: continue
            n = np.cross(p[1] - p[0], p[2] - p[0]); n = n / max(np.linalg.norm(n), 1e-12)
            m = me.materials[t.material_index].name if me.materials else "black"
            parts.setdefault(m, []).append((p, np.tile(n, (3, 1))))
        out[name] = [(np.concatenate([a for a, _ in v]), np.concatenate([b for _, b in v]), m) for m, v in parts.items()]
        print("rotor", name, sum(len(a) // 3 for a, _, _ in out[name]), "tris")
    return out
