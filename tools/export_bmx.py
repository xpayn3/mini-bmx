"""Export the BMX from W:\\AR9\\houdini_bmx\\bmx_latest.hip to assets/bmx.glb
for the game. Splits the bike into animatable nodes:

  bmx
   +- frame            (static: frame, stays, seat, chain)
   +- steer            (pivot on the head-tube axis: fork + cockpit + front pegs)
   |   +- wheel_front  (pivot on front axle)
   +- wheel_rear       (pivot on rear axle, includes the cog)
   +- crank            (pivot on the BB: arms, pedals, chainring)

Run with Houdini 21 hython:
  & "C:\\Program Files\\Side Effects Software\\Houdini 21.0.440\\bin\\hython.exe" tools\\export_bmx.py
Axes: +X forward, +Y up, +Z rider's right. Metres.
"""
import json, os, struct, sys
import numpy as np
import hou

HIP = r"W:\AR9\houdini_bmx\bmx_latest.hip"
OUT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "assets", "bmx.glb")

CLASSIFY = r"""
string n = s@name; string pt = s@part;
int g = 0;
if ((pt == "wheel" || pt == "spoke") && match("*_front", n)) g = 2;
else if ((pt == "wheel" || pt == "spoke") && match("*_rear", n)) g = 3;
else if (pt == "fork" || pt == "cockpit") g = 1;
if (n == "peg" || n == "axle_head") g = (v@P.x > 0.1) ? 1 : 0;
if (pt == "crank" || n == "chainring") g = 4;
if (n == "cog") g = 3;
i@grp = g;

int m = 0;                                     // paint
string chrome[] = {"rim_front","rim_rear","hub_front","hub_rear","front_axle","rear_axle",
  "peg","spoke_front","spoke_rear","spoke_head_front","spoke_head_rear","nipple_front",
  "nipple_rear","valve_front","valve_rear","hub_endcap_f","hub_endcap_r","axle_head",
  "steerer","steerer_lower","headset_top","bolt_head","bolt_shank","sp_nut","st_clamp",
  "seatpost","crank_spindle","pedal_spindle","crown_race","stem_bolt"};
string blackm[] = {"handlebar_l","handlebar_r","bar_cross","stem_dm_base","crank_arm",
  "chainring","cog","bar_plug_l","bar_plug_r",
  "stem_body","stem_face","stem_clamp","stem_barclamp","top_cap"};   // clamp stem (dh)
string rubber[] = {"tire_front","tire_rear","bar_grip_l","bar_grip_r"};
string plastic[] = {"saddle_model","bar_pad","pedal_body"};
if (find(chrome, n) >= 0) m = 1;
if (find(blackm, n) >= 0) m = 2;
if (find(rubber, n) >= 0) m = 3;
if (pt == "chain") m = 4;
if (find(plastic, n) >= 0) m = 5;
i@mat = m;
"""

MATERIALS = [  # name, baseColor (linear), metallic, roughness
    ("paint",   [0.62, 0.035, 0.03, 1.0], 0.35, 0.22),
    ("chrome",  [0.80, 0.80, 0.82, 1.0], 1.0, 0.16),
    ("black",   [0.025, 0.025, 0.028, 1.0], 0.7, 0.38),
    ("rubber",  [0.018, 0.018, 0.018, 1.0], 0.0, 0.85),
    ("chain",   [0.22, 0.22, 0.24, 1.0], 0.9, 0.45),
    ("plastic", [0.03, 0.03, 0.032, 1.0], 0.0, 0.55),
]
GROUPS = ["frame", "steer", "wheel_front", "wheel_rear", "crank"]


def verb(name, parms=None):
    v = hou.sopNodeTypeCategory().nodeVerb(name)
    if parms:
        v.setParms(parms)
    return v


def main(setup=None, out_path=OUT, root="bmx"):
    """setup(node) may change the bmx_skeleton's parms before the export."""
    hou.hipFile.load(HIP, suppress_save_prompt=True, ignore_load_warnings=True)
    disp = hou.node("/obj/bmx").displayNode()
    if setup:
        setup(disp)
        if disp.errors():
            raise RuntimeError(disp.path() + ": " + str(disp.errors()))
        g = disp.geometry()
        print("geometry", {a.name(): round(g.attribValue(a), 4) for a in g.globalAttribs()
               if a.name() in ("wheelbase", "trail", "front_center", "bb_height", "standover", "fork_len_used")})
    tmp = hou.node("/obj").createNode("geo", "game_export")
    om = tmp.createNode("object_merge"); om.parm("objpath1").set(disp.path())
    w1 = tmp.createNode("attribwrangle"); w1.setInput(0, om)
    w1.parm("class").set(1); w1.parm("snippet").set(CLASSIFY)
    dv = tmp.createNode("divide"); dv.setInput(0, w1)
    dv.parm("convex").set(1); dv.parm("numsides").set(3)
    w2 = tmp.createNode("attribwrangle"); w2.setInput(0, dv)
    w2.parm("class").set(3); w2.parm("snippet").set("i@ptn = vertexpoint(0, @vtxnum);")
    out = w2.geometry()
    for n in (w1, dv, w2):
        if n.errors():
            raise RuntimeError(n.path() + ": " + str(n.errors()))

    nv = [p.numVertices() for p in out.prims()]
    assert all(n == 3 for n in nv), "non-triangle prims after divide: %s" % set(nv)
    P = np.array(out.pointFloatAttribValues("P"), np.float32).reshape(-1, 3)
    ptn = np.array(out.vertexIntAttribValues("ptn"), np.int64)
    N = np.array(out.vertexFloatAttribValues("N"), np.float32).reshape(-1, 3)
    grp = np.array(out.primIntAttribValues("grp"), np.int64)
    mat = np.array(out.primIntAttribValues("mat"), np.int64)
    tris = np.arange(len(ptn)).reshape(-1, 3)[:, ::-1]   # Houdini CW -> glTF CCW
    print("tris", len(tris), "points", len(P))

    def centroid(group_id, names_mask=None):
        sel = grp == group_id
        return P[ptn[tris[sel].ravel()]].mean(0)

    # pivots from named parts
    names = out.primStringAttribValues("name")
    names = np.array(names)
    def bbox_center(*nm):
        sel = np.isin(names, nm)
        pts = P[ptn[tris[sel].ravel()]]
        return (pts.min(0) + pts.max(0)) * 0.5, pts
    front_axle, _ = bbox_center("front_axle")
    rear_axle, _ = bbox_center("rear_axle")
    bb, _ = bbox_center("crank_spindle")
    front_axle[2] = rear_axle[2] = bb[2] = 0.0
    # head-tube axis by PCA of the head tube points
    _, ht = bbox_center("headtube")
    hc = ht.mean(0); hc[2] = 0.0
    u, s, vt = np.linalg.svd(ht - ht.mean(0))
    axis = vt[0]
    if axis[1] < 0:
        axis = -axis
    axis[2] = 0.0; axis /= np.linalg.norm(axis)
    pivots = {"frame": np.zeros(3), "steer": hc, "wheel_front": front_axle,
              "wheel_rear": rear_axle, "crank": bb}
    print("pivots", {k: v.round(4).tolist() for k, v in pivots.items()}, "steer axis", axis.round(4))

    bin_chunks, views, accessors, meshes = [], [], [], []
    offset = [0]

    def add_view(arr, target):
        data = arr.tobytes()
        pad = (-len(data)) % 4
        views.append({"buffer": 0, "byteOffset": offset[0], "byteLength": len(data), "target": target})
        bin_chunks.append(data + b"\0" * pad)
        offset[0] += len(data) + pad
        return len(views) - 1

    for gi, gname in enumerate(GROUPS):
        prims = []
        for mi in range(len(MATERIALS)):
            sel = (grp == gi) & (mat == mi)
            if not sel.any():
                continue
            vids = tris[sel].ravel()                      # vertex ids
            pos = P[ptn[vids]] - pivots[gname]
            nrm = N[vids]
            key = np.concatenate([ptn[vids][:, None].astype(np.float64),
                                  np.round(nrm, 3).astype(np.float64)], 1)
            uniq, inv = np.unique(key, axis=0, return_inverse=True)
            inv = inv.ravel()
            first = np.zeros(len(uniq), np.int64); first[inv] = np.arange(len(inv))
            vpos = pos[first].astype(np.float32)
            vn = nrm[first]
            vn = (vn / np.maximum(np.linalg.norm(vn, axis=1, keepdims=True), 1e-8)).astype(np.float32)
            idx = inv.astype(np.uint32)
            pa = len(accessors)
            accessors.append({"bufferView": add_view(vpos, 34962), "componentType": 5126,
                              "count": len(vpos), "type": "VEC3",
                              "min": vpos.min(0).tolist(), "max": vpos.max(0).tolist()})
            accessors.append({"bufferView": add_view(vn, 34962), "componentType": 5126,
                              "count": len(vn), "type": "VEC3"})
            accessors.append({"bufferView": add_view(idx, 34963), "componentType": 5125,
                              "count": len(idx), "type": "SCALAR"})
            prims.append({"attributes": {"POSITION": pa, "NORMAL": pa + 1}, "indices": pa + 2,
                          "material": mi})
            print("  %-12s %-8s verts %6d tris %6d" % (gname, MATERIALS[mi][0], len(vpos), len(idx) // 3))
        meshes.append({"name": gname, "primitives": prims})

    def node(i, parent_pivot):
        t = (pivots[GROUPS[i]] - parent_pivot).tolist()
        return {"name": GROUPS[i], "mesh": i, "translation": t}
    nodes = [{"name": root, "children": [1, 2, 4, 5]},
             node(0, np.zeros(3)),
             dict(node(1, np.zeros(3)), children=[3]),
             node(2, pivots["steer"]),
             node(3, np.zeros(3)),
             node(4, np.zeros(3))]
    ground = float(P[:, 1].min())
    nodes[0]["extras"] = {"steerAxis": axis.tolist(),
                          "wheelRadius": float(front_axle[1] - ground),
                          "wheelRadiusRear": float(rear_axle[1] - ground),
                          "wheelbase": float(front_axle[0] - rear_axle[0]),
                          "bbToRearAxle": float(bb[0] - rear_axle[0])}
    gltf = {
        "asset": {"version": "2.0", "generator": "gamecycling export_bmx.py"},
        "scene": 0, "scenes": [{"nodes": [0]}], "nodes": nodes, "meshes": meshes,
        "materials": [{"name": n, "pbrMetallicRoughness": {"baseColorFactor": c, "metallicFactor": m,
                       "roughnessFactor": r}} for n, c, m, r in MATERIALS],
        "accessors": accessors, "bufferViews": views,
        "buffers": [{"byteLength": offset[0]}],
    }
    js = json.dumps(gltf).encode()
    js += b" " * ((-len(js)) % 4)
    binb = b"".join(bin_chunks)
    os.makedirs(os.path.dirname(out_path), exist_ok=True)
    with open(out_path, "wb") as f:
        f.write(struct.pack("<III", 0x46546C67, 2, 12 + 8 + len(js) + 8 + len(binb)))
        f.write(struct.pack("<II", len(js), 0x4E4F534A)); f.write(js)
        f.write(struct.pack("<II", len(binb), 0x004E4942)); f.write(binb)
    print("wrote", out_path, os.path.getsize(out_path) // 1024, "KB")


if __name__ == "__main__":
    main()
