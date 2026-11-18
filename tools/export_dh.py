"""Export the full-suspension downhill bike from the bicycle project to
godot/assets/dh.glb for the game.

Source: W:\\AR9\\houdini_bike_2026-09-09\\BIKE PROCEDURAL\\bicycle_procedural test .hip,
node /obj/Bicycle/bike_skeleton1 (bike_skeleton HDA, preset DH_S3: dual-crown
200 mm fork, Horst-link four-bar rear with a 200 mm coil shock).

The bike is cooked at rest (no path, no rider, no simulated suspension: the
geometry sits at sag, which is how the asset builds it). Then, to keep the
file light:
  * small parts are switched off on the asset or dropped by name (bolts,
    bearings, seals, valves, lettering, chain pins/rollers, pivot hardware...)
  * the rest is decimated with PolyReduce (keeps the silhouette; normals are
    rebuilt with a cusp angle afterwards)

Node split (pivots in the rest pose; +X forward, +Y up, +Z rider's right, m):

  dh
   +- frame          front triangle, seat, chain, rear brake hose
   +- steer          head-tube axis: crowns, stanchions, cockpit
   |   +- fork_lower slides along the steer axis: lowers, caliper, axle
   |       +- wheel_front
   +- swing          chainstays, rotate about the main pivot G1
   +- seatstay       seatstays + dropouts + caliper + derailleur, pinned at C1/C2
   |   +- wheel_rear (cassette included)
   +- rocker         rotates about G2
   +- shock_body     rotates about the frame eye FE
   |   +- shock_spring  local +Y along the shock: scale.y compresses it
   +- shock_shaft    rotates about the rocker eye D
   +- crank

The root's extras carry the four-bar points (G1, G2, C1, C2, A, D, FE) so the
game solves the linkage itself.

Run with Houdini 21 hython:
  & "C:\\Program Files\\Side Effects Software\\Houdini 21.0.440\\bin\\hython.exe" tools\\export_dh.py
"""
import json, os, struct, time
import numpy as np
import hou

HIP = r"W:\AR9\houdini_bike_2026-09-09\BIKE PROCEDURAL\bicycle_procedural test .hip"
NODE = "/obj/Bicycle/bike_skeleton1"
OUT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "godot", "assets", "dh.glb")
REDUCE_PCT = float(os.environ.get("DH_REDUCE_PCT", "11"))   # PolyReduce: % of the polygons kept

# asset toggles switched off: animation/rider/path, decals and lettering, UV extras,
# and the small hardware the game never shows
OFF = ["anim_fast", "do_rider", "use_path", "sus_sim", "do_cam", "do_bottle", "do_btxt", "do_ttxt",
       "decal_dt", "decal_po", "decal_rim", "decal_fork", "bb_thread", "valve_threads", "stem_bolt_thr",
       "lock_thread", "tire_uv_tread", "rotor_uv_polar", "lock_uv", "cog_uv_wear", "ring_uv_wear",
       "chain_uv_wear", "chwear_txt", "hs_uv", "gtex_uv", "uv_even", "bottle_uv", "rs_tangents",
       "chain_dyn", "hose_dyn", "rider_react",
       "do_valve", "hub_fl_holes", "rim_holes", "bb_sleeve", "rs_bearing", "rs_hw", "stem_bolts",
       "spider_bolts", "jockey_caps", "fk_knob", "do_freehub", "spoke_alt"]
ON = {"dpost_auto": 0, "dpost_down": 1.0}
# dropped by name, whatever the asset still builds
DROP = {"bolt_head", "bolt_shank", "stem_bolt", "chainring_bolt", "chainring_bolt_nut", "chainring_bolt_text",
        "lockring_text", "lockring_cnc_front", "lockring_cnc_rear", "hub_bearing_front", "hub_bearing_rear",
        "hub_seal_front", "hub_seal_rear", "bb_cup", "bb_bearing", "bb_seal", "bb_sleeve",
        "rs_axle", "rs_bearing", "rs_seal", "rs_nut", "rs_washer", "rs_cap", "rs_spacer",
        "shock_rbk", "shock_knob", "rderail_model_bolt", "rderail_model_led", "rderail_model_button",
        "rderail_model_batt_tab", "hlever_bolt_l", "hlever_bolt_r", "hlever_banjo_l", "hlever_banjo_r",
        "hlever_knob_l", "hlever_knob_r", "valve_front", "valve_rear", "valve_cap_front", "valve_cap_rear",
        "freehub_rear", "chain_pin", "chain_roller", "spoke_head_front", "spoke_head_rear",
        "fork_knob_l", "fork_knob_r", "jockey_cap", "crank_boss", "crank_boss_n", "sp_nut",
        "seatpost_collar", "hlever_clamp_l", "hlever_clamp_r", "rderail_model_trim"}

MATERIALS = [  # name, baseColor (linear), metallic, roughness
    ("paint",   [0.62, 0.035, 0.03, 1.0], 0.35, 0.22),
    ("chrome",  [0.80, 0.80, 0.82, 1.0], 1.0, 0.16),
    ("black",   [0.025, 0.025, 0.028, 1.0], 0.7, 0.38),
    ("rubber",  [0.018, 0.018, 0.018, 1.0], 0.0, 0.85),
    ("chain",   [0.22, 0.22, 0.24, 1.0], 0.9, 0.45),
    ("plastic", [0.03, 0.03, 0.032, 1.0], 0.0, 0.55),
    ("gold",    [0.90, 0.52, 0.10, 1.0], 1.0, 0.25),
]
SHOP_MAT = {"Carbon_veawe_green": 0,
            "Metal": 1, "Polished_aluminium": 1, "Discbrakes": 1, "headset": 1, "rear_sprocket": 1, "sparkle": 1,
            "Tires_mud": 3, "Handlebar_tape": 3, "Chain": 4,
            "Plastic_black": 5, "Mold_plastic": 5, "gold": 6}   # anything else: black
NAME_MAT = {"saddle_model": 5}

# ---- which node each part rides on ----
STEER = {"stanchion_l", "stanchion_r", "fk_crown_lo", "fk_crown_up", "fork_bumper", "steerer", "steerer_lower",
         "crown_race", "headset_top", "headset_bot", "brake_hose_f"}
FORK_LOWER = {"fork_blade", "fork_archd", "fork_boss", "fork_clamp", "disc_mount_f", "caliper_model_f",
              "front_axle", "hub_endcap_f", "fork_hose_guide", "fork_seal_l", "fork_seal_r"}
WHEEL_F = {"rim_front", "tire_front", "tread_knob_front", "spoke_front", "hub_front", "rotor_front"}
WHEEL_R = {"rim_rear", "tire_rear", "tread_knob_rear", "spoke_rear", "hub_rear", "rotor_rear", "cog"}
# the chain rides the chainstays: their main pivot sits by the chainring and their Horst pivot
# by the cassette, so both wraps stay (nearly) on their sprockets through the travel
SWING = {"chainstay_l", "chainstay_r", "cs_bridge", "hguide_cs", "chain_plate"}
SEATSTAY = {"seatstay_l", "seatstay_r", "ss_bridge", "dropout_l", "dropout_r", "disc_mount_r", "bm_brk_r",
            "caliper_model_r", "rear_axle", "hub_endcap_r", "hanger", "jockey"}
ROCKER = {"rs_link"}
SHOCK_BODY = {"shock_body", "shock_collar", "shock_res"}
SHOCK_SHAFT = {"shock_shaft", "shock_eye", "shock_bumper"}
SPRING = {"shock_spring"}
CRANK = {"crank_arm", "crank_spindle", "pedal_model", "spider", "chainring"}

NODES = ["frame", "steer", "fork_lower", "wheel_front", "swing", "seatstay", "wheel_rear",
         "rocker", "shock_body", "shock_spring", "shock_shaft", "crank"]
PARENT = {"fork_lower": "steer", "wheel_front": "fork_lower", "wheel_rear": "seatstay",
          "shock_spring": "shock_body"}


def setup(n):
    for k in OFF:
        p = n.parm(k)
        if p is None:
            print("  (no parm %s)" % k)
            continue
        p.deleteAllKeyframes(); p.set(0)
    for k, v in ON.items():   # dropper slammed: DH riders stand above a low saddle
        n.parm(k).deleteAllKeyframes(); n.parm(k).set(v)
    n.setInput(0, None); n.setInput(1, None)   # no track: the bike stands at the origin


def cook():
    try:
        hou.hipFile.load(HIP, suppress_save_prompt=True, ignore_load_warnings=True)
    except hou.OperationFailed:
        pass   # Redshift shaders missing in hython; the bike cooks fine
    hou.setFrame(1)
    n = hou.node(NODE)
    setup(n)
    t0 = time.time()
    g0 = n.geometry()
    if n.errors():
        raise RuntimeError(n.errors())
    print("cooked %.0fs: %d prims" % (time.time() - t0, len(g0.prims())))
    D = {a.name(): g0.attribValue(a) for a in g0.globalAttribs()}

    geo = hou.node("/obj").createNode("geo", "game_export")
    om = geo.createNode("object_merge"); om.parm("objpath1").set(n.path())
    drop = geo.createNode("attribwrangle"); drop.setInput(0, om); drop.parm("class").set(1)
    drop.parm("snippet").set('string drop[] = {%s};\nif (find(drop, s@name) >= 0 || s@part == "rider") removeprim(0, @primnum, 1);'
                             % ",".join('"%s"' % d for d in sorted(DROP)))
    clean = geo.createNode("attribdelete"); clean.setInput(0, drop)
    clean.parm("vtxdel").set("*"); clean.parm("ptdel").set("* ^P"); clean.parm("primdel").set("* ^name ^part ^shop_materialpath")
    clean.parm("dtldel").set("*")
    tri = geo.createNode("divide"); tri.setInput(0, clean)
    tri.parm("convex").set(1); tri.parm("numsides").set(3)
    fuse = geo.createNode("fuse::2.0"); fuse.setInput(0, tri)   # weld split seams so PolyReduce sees surfaces
    fuse.parm("tol3d").set(1e-6)
    red = geo.createNode("polyreduce::2.0"); red.setInput(0, fuse)
    red.parm("percentage").set(REDUCE_PCT)
    nrm = geo.createNode("normal"); nrm.setInput(0, red)
    nrm.parm("type").set(1)            # vertex normals
    nrm.parm("cuspangle").set(40)
    tri2 = geo.createNode("divide"); tri2.setInput(0, nrm)
    tri2.parm("convex").set(1); tri2.parm("numsides").set(3)
    w = geo.createNode("attribwrangle"); w.setInput(0, tri2)
    w.parm("class").set(3); w.parm("snippet").set("i@ptn = vertexpoint(0, @vtxnum);")
    t0 = time.time()
    out = w.geometry()
    for x in (drop, clean, tri, fuse, red, nrm, tri2, w):
        if x.errors():
            raise RuntimeError(x.path() + ": " + str(x.errors()))
    print("reduced %.0fs: %d -> %d tris" % (time.time() - t0, len(tri.geometry().prims()), len(out.prims())))
    return out, D


def main():
    out, D = cook()
    P = np.array(out.pointFloatAttribValues("P"), np.float32).reshape(-1, 3)
    ptn = np.array(out.vertexIntAttribValues("ptn"), np.int64)
    N = np.array(out.vertexFloatAttribValues("N"), np.float32).reshape(-1, 3)
    names = np.array(out.primStringAttribValues("name"))
    shops = np.array([s.rsplit("/", 1)[-1] for s in out.primStringAttribValues("shop_materialpath")])
    tris = np.arange(len(ptn)).reshape(-1, 3)[:, ::-1]        # Houdini CW -> glTF CCW
    C = P[ptn[tris]].mean(1)                                    # triangle centroids

    mm = lambda k: np.array(D[k][:2], np.float64) / 1000.0     # four-bar points, mm -> m (xy)
    G1, G2, C1, C2, A, Dp, FE = (mm(k) for k in ("rs_G1", "rs_G2", "rs_C1", "rs_C2", "rs_A", "rs_D", "rs_FE"))
    axis = np.array(D["steer_axis"], np.float64); axis[2] = 0; axis /= np.linalg.norm(axis)
    fax = np.array(D["front_axle_pos"], np.float64); rax = np.array(D["rear_axle_pos"], np.float64)
    seal = np.array(D["fk_seal_pos"], np.float64)
    ht = P[ptn[tris[names == "headtube"].ravel()]]
    hc = ((ht.min(0) + ht.max(0)) * 0.5).astype(np.float64); hc[2] = 0
    sp = P[ptn[tris[names == "crank_spindle"].ravel()]]
    bb = ((sp.min(0) + sp.max(0)) * 0.5).astype(np.float64); bb[2] = 0

    # ---- per-triangle node ----
    grp = np.full(len(tris), NODES.index("frame"))
    for nodename, s in (("steer", STEER), ("fork_lower", FORK_LOWER), ("wheel_front", WHEEL_F),
                        ("wheel_rear", WHEEL_R), ("swing", SWING), ("seatstay", SEATSTAY),
                        ("rocker", ROCKER), ("shock_body", SHOCK_BODY), ("shock_shaft", SHOCK_SHAFT),
                        ("shock_spring", SPRING), ("crank", CRANK)):
        grp[np.isin(names, list(s))] = NODES.index(nodename)
    parts = np.array(out.primStringAttribValues("part")) if out.findPrimAttrib("part") else None
    if parts is not None:
        grp[parts == "cockpit"] = NODES.index("steer")
        grp[parts == "derailleur"] = NODES.index("seatstay")
    grp[names.astype(str) == "chainring"] = NODES.index("crank")
    grp[np.char.startswith(names.astype(str), "rderail_model")] = NODES.index("seatstay")
    # parts that straddle two bodies: by position
    def nearest(sel, cands):
        d = np.stack([np.linalg.norm(C[sel][:, :2] - p, axis=1) for p, _ in cands], 1)
        grp[np.where(sel)[0]] = np.array([NODES.index(c) for _, c in cands])[d.argmin(1)]
    nearest(names == "rs_eye", [(G1, "swing"), (C1, "swing"), (C2, "seatstay")])
    nearest(names == "shock_bush", [(FE, "shock_body"), (Dp, "shock_shaft")])
    sel = names == "axle_head"
    grp[sel & (C[:, 0] > 0.3)] = NODES.index("fork_lower"); grp[sel & (C[:, 0] <= 0.3)] = NODES.index("seatstay")
    sel = names == "fork_cap"   # caps on the stanchion tops stay up; anything below the seals is on the lowers
    below = (C[:, :2] - seal[:2]) @ axis[:2] < 0
    grp[sel & below] = NODES.index("fork_lower"); grp[sel & ~below] = NODES.index("steer")
    left = sorted(set(names[grp == NODES.index("frame")].tolist()))
    print("frame parts:", left)

    mat = np.array([SHOP_MAT.get(s, 2) for s in shops])
    for k, v in NAME_MAT.items():
        mat[names == k] = v

    # ---- pivots / rest rotations ----
    shock_dir = (Dp - FE) / np.linalg.norm(Dp - FE)
    spr = P[ptn[tris[grp == NODES.index("shock_spring")].ravel()]][:, :2].astype(np.float64)
    proj = (spr - FE) @ shock_dir
    seat0 = FE + shock_dir * proj.min()
    spring_len = float(proj.max() - proj.min())
    ang = np.arctan2(shock_dir[1], shock_dir[0]) - np.pi / 2    # rotation taking +Y onto the shock axis
    q_spring = [0.0, 0.0, float(np.sin(ang / 2)), float(np.cos(ang / 2))]
    Rsp = np.array([[np.cos(ang), -np.sin(ang), 0], [np.sin(ang), np.cos(ang), 0], [0, 0, 1]])
    z3 = lambda v: np.array([v[0], v[1], 0.0])
    pivots = {"frame": np.zeros(3), "steer": hc, "fork_lower": z3(fax), "wheel_front": z3(fax),
              "swing": z3(G1), "seatstay": z3(C1), "wheel_rear": z3(rax), "rocker": z3(G2),
              "shock_body": z3(FE), "shock_spring": z3(seat0), "shock_shaft": z3(Dp), "crank": bb}
    print("pivots", {k: v.round(4).tolist() for k, v in pivots.items()})

    # ---- glb ----
    bin_chunks, views, accessors, meshes = [], [], [], []
    offset = [0]

    def add_view(arr, target):
        data = arr.tobytes()
        pad = (-len(data)) % 4
        views.append({"buffer": 0, "byteOffset": offset[0], "byteLength": len(data), "target": target})
        bin_chunks.append(data + b"\0" * pad)
        offset[0] += len(data) + pad
        return len(views) - 1

    total = 0
    mesh_of = {}
    for gi, gname in enumerate(NODES):
        prims = []
        for mi in range(len(MATERIALS)):
            sel = (grp == gi) & (mat == mi)
            if not sel.any():
                continue
            vids = tris[sel].ravel()
            pos = P[ptn[vids]].astype(np.float64) - pivots[gname]
            nrm = N[vids].astype(np.float64)
            if gname == "shock_spring":           # into the spring's own frame (+Y along the shock)
                pos = pos @ Rsp; nrm = nrm @ Rsp
            key = np.concatenate([ptn[vids][:, None].astype(np.float64), np.round(nrm, 3)], 1)
            uniq, inv = np.unique(key, axis=0, return_inverse=True)
            inv = inv.ravel()
            first = np.zeros(len(uniq), np.int64); first[inv] = np.arange(len(inv))
            vpos = pos[first].astype(np.float32)
            vn = nrm[first]
            vn = (vn / np.maximum(np.linalg.norm(vn, axis=1, keepdims=True), 1e-8)).astype(np.float32)
            idx = inv.astype(np.uint32 if len(vpos) > 65535 else np.uint16)
            pa = len(accessors)
            accessors.append({"bufferView": add_view(vpos, 34962), "componentType": 5126, "count": len(vpos),
                              "type": "VEC3", "min": vpos.min(0).tolist(), "max": vpos.max(0).tolist()})
            accessors.append({"bufferView": add_view(vn, 34962), "componentType": 5126, "count": len(vn), "type": "VEC3"})
            accessors.append({"bufferView": add_view(idx, 34963), "componentType": 5125 if idx.dtype == np.uint32 else 5123,
                              "count": len(idx), "type": "SCALAR"})
            prims.append({"attributes": {"POSITION": pa, "NORMAL": pa + 1}, "indices": pa + 2, "material": mi})
            total += len(idx) // 3
            print("  %-12s %-8s verts %6d tris %6d" % (gname, MATERIALS[mi][0], len(vpos), len(idx) // 3))
        if prims:
            mesh_of[gname] = len(meshes)
            meshes.append({"name": gname, "primitives": prims})
    print("total tris", total)

    nodes = [{"name": "dh", "children": []}]
    index = {}
    for gname in NODES:
        index[gname] = len(nodes)
        parent = PARENT.get(gname)
        ppiv = pivots[parent] if parent else np.zeros(3)
        nd = {"name": gname, "translation": (pivots[gname] - ppiv).tolist()}
        if gname in mesh_of:
            nd["mesh"] = mesh_of[gname]
        if gname == "shock_spring":
            nd["rotation"] = q_spring
        nodes.append(nd)
    for gname in NODES:
        parent = PARENT.get(gname)
        holder = nodes[index[parent]] if parent else nodes[0]
        holder.setdefault("children", []).append(index[gname])

    ground = 0.0
    p2 = lambda v: [round(float(v[0]), 6), round(float(v[1]), 6)]
    nodes[0]["extras"] = {
        "steerAxis": axis.tolist(),
        "wheelRadius": float(fax[1] - ground), "wheelRadiusRear": float(rax[1] - ground),
        "wheelbase": float(fax[0] - rax[0]), "bbToRearAxle": float(bb[0] - rax[0]),
        "suspension": {
            "fork": {"travel": float(D["fk_travel_used"]) / 1000, "sag": float(D.get("fk_sag", 0.2)) if "fk_sag" in D else 0.2},
            "rear": {"travel": float(D["rs_travel_meas"]) / 1000, "sag": 0.3,
                     "G1": p2(G1), "G2": p2(G2), "C1": p2(C1), "C2": p2(C2), "A": p2(A), "D": p2(Dp), "FE": p2(FE),
                     "springLen": spring_len},
        },
    }
    gltf = {
        "asset": {"version": "2.0", "generator": "gamecycling export_dh.py"},
        "scene": 0, "scenes": [{"nodes": [0]}], "nodes": nodes, "meshes": meshes,
        "materials": [{"name": n, "pbrMetallicRoughness": {"baseColorFactor": c, "metallicFactor": m,
                       "roughnessFactor": r}} for n, c, m, r in MATERIALS],
        "accessors": accessors, "bufferViews": views, "buffers": [{"byteLength": offset[0]}],
    }
    js = json.dumps(gltf).encode()
    js += b" " * ((-len(js)) % 4)
    binb = b"".join(bin_chunks)
    with open(OUT, "wb") as f:
        f.write(struct.pack("<III", 0x46546C67, 2, 12 + 8 + len(js) + 8 + len(binb)))
        f.write(struct.pack("<II", len(js), 0x4E4F534A)); f.write(js)
        f.write(struct.pack("<II", len(binb), 0x004E4942)); f.write(binb)
    print("wrote", OUT, os.path.getsize(OUT) // 1024, "KB")


if __name__ == "__main__":
    main()
