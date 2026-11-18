"""Export the rigged rear derailleur (SRAM-style AXS, built by the bike HDA) and the chain path
for every gear, to assets/drivetrain.glb.

Source: the same .hip / HDA as export_dh.py. The HDA's "gear" parm (1..cassette_n, fractional =
mid-shift) moves the parallelogram, knuckle, cage and pulleys, and re-routes the 108-link chain.

What goes in the file:
  * the derailleur, cooked at gear 1 and reduced, split into rigid PIECES (connected parts). For every
    piece the rigid transform from its gear-1 pose to each gear's pose is solved (Kabsch fit on its
    points); pieces that move the same are merged into one node. Each node's extras.gears holds, per
    gear, [tx, ty, tz, qx, qy, qz, qw]: the node's transform in the bike frame (its pivot = the
    piece's gear-1 centroid, geometry stored relative to it). Pulley nodes are flagged so the game can
    spin them with the chain.
  * the chain: per gear, the 108 roller centres in order round the loop (bike frame, metres), plus
    the roller radius / inner width / pitch so the game can build the links itself (instanced).
  * per gear, the teeth on the selected cog.

Bike frame: +X forward, +Y up, +Z rider's right, metres (same as dh.glb before pivots).

Run with Houdini 21 hython:
  & "C:\\Program Files\\Side Effects Software\\Houdini 21.0.440\\bin\\hython.exe" tools\\export_drivetrain.py
"""
import json, os, struct, time
import numpy as np
import hou

HIP = r"W:\AR9\houdini_bike_2026-09-09\BIKE PROCEDURAL\bicycle_procedural test .hip"
NODE = "/obj/Bicycle/bike_skeleton1"
OUT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "assets", "drivetrain.glb")
REDUCE_PCT = float(os.environ.get("RD_REDUCE_PCT", "14"))

# same switches as export_dh.py, minus the drivetrain ones
OFF = ["anim_fast", "do_rider", "use_path", "sus_sim", "do_cam", "rider_react", "hose_dyn", "chain_dyn",
       "rderail_txt" ]
DERAIL_DROP = {"rderail_model_led", "rderail_model_button", "rderail_model_batt_tab", "rderail_model_trim"}

MATERIALS = [  # name, baseColor (linear), metallic, roughness
    ("black",   [0.025, 0.025, 0.028, 1.0], 0.6, 0.4),
    ("alloy",   [0.55, 0.55, 0.58, 1.0], 1.0, 0.3),
    ("plastic", [0.03, 0.03, 0.032, 1.0], 0.0, 0.55),
    ("accent",  [0.70, 0.02, 0.02, 1.0], 0.3, 0.35),
]
NAME_MAT = {"rderail_model_bolt": 1, "jockey_cap": 1, "rderail_model_mount": 1, "rderail_model_battery": 2,
            "rderail_model_batt_holder": 2, "rderail_model_motor": 0, "jockey": 2}


def node():
    n = hou.node(NODE)
    for k in OFF:
        p = n.parm(k)
        if p is not None:
            p.deleteAllKeyframes(); p.set(0)
    n.parm("dpost_auto").set(0); n.parm("dpost_down").set(1.0)
    n.setInput(0, None); n.setInput(1, None)
    return n


def build_net(n):
    geo = hou.node("/obj").createNode("geo", "drivetrain_export")
    om = geo.createNode("object_merge"); om.parm("objpath1").set(n.path())
    keep = geo.createNode("attribwrangle"); keep.setInput(0, om); keep.parm("class").set(1)
    keep.parm("snippet").set(
        'string drop[] = {%s};\n'
        'int rd = (s@part == "derailleur" && s@name != "hanger") || s@name == "jockey" || s@name == "jockey_cap";\n'
        'if (!rd || find(drop, s@name) >= 0) removeprim(0, @primnum, 1);' % ",".join('"%s"' % d for d in sorted(DERAIL_DROP)))
    clean = geo.createNode("attribdelete"); clean.setInput(0, keep)
    clean.parm("vtxdel").set("*"); clean.parm("ptdel").set("* ^P"); clean.parm("primdel").set("* ^name"); clean.parm("dtldel").set("*")
    conn = clean
    # rollers of the chain, separately (their order round the loop is the chain path)
    rol = geo.createNode("attribwrangle"); rol.setInput(0, om); rol.parm("class").set(1)
    rol.parm("snippet").set('if (s@name != "chain_roller") removeprim(0, @primnum, 1);')
    rc = geo.createNode("attribdelete"); rc.setInput(0, rol)
    rc.parm("vtxdel").set("*"); rc.parm("ptdel").set("* ^P"); rc.parm("primdel").set("*"); rc.parm("dtldel").set("*")
    return geo, conn, rc


def pieces(g):
    """piece id per prim and per point: prims sharing a point are one piece (union-find)"""
    npt = len(g.points()); par = np.arange(npt)
    def find(i):
        while par[i] != i:
            par[i] = par[par[i]]; i = par[i]
        return i
    prim_pts = [[v.point().number() for v in pr.vertices()] for pr in g.prims()]
    for ps in prim_pts:
        r0 = find(ps[0])
        for q in ps[1:]:
            r = find(q)
            if r != r0: par[r] = r0
    roots = np.array([find(i) for i in range(npt)])
    uniq, pt_piece = np.unique(roots, return_inverse=True)
    prim_piece = np.array([pt_piece[ps[0]] for ps in prim_pts])
    return prim_piece, pt_piece, prim_pts


def rollers(rconn):
    g = rconn.geometry()
    P = np.array(g.pointFloatAttribValues("P"), np.float64).reshape(-1, 3)
    pc, _, pts = pieces(g)
    k = pc.max() + 1
    cen = np.zeros((k, 3)); cnt = np.zeros(k)
    for pid, ps in zip(pc, pts):
        cen[pid] += P[ps].mean(0); cnt[pid] += 1
    cen /= cnt[:, None]
    return cen


def order_loop(c):
    """order roller centres round the closed chain: greedy nearest neighbour from the top-front one"""
    n = len(c); used = np.zeros(n, bool)
    i = int(np.argmax(c[:, 1] + 0.3 * c[:, 0])); out = [i]; used[i] = True
    for _ in range(n - 1):
        d = np.linalg.norm(c - c[i], axis=1); d[used] = 1e9
        i = int(np.argmin(d)); out.append(i); used[i] = True
    o = c[out]
    # run in the chain's travel direction: along the top run the chain moves backwards (-X) to the cassette
    if o[1, 0] > o[0, 0]:
        o = np.concatenate([o[:1], o[1:][::-1]])
    return o


def kabsch(A, B):
    """R, t with R @ a + t ~= b"""
    ca, cb = A.mean(0), B.mean(0)
    H = (A - ca).T @ (B - cb)
    U, S, Vt = np.linalg.svd(H)
    d = np.sign(np.linalg.det(Vt.T @ U.T))
    D = np.diag([1, 1, d])
    R = Vt.T @ D @ U.T
    return R, cb - R @ ca


def quat(R):
    w = np.sqrt(max(0.0, 1 + R[0, 0] + R[1, 1] + R[2, 2])) / 2
    x = np.sqrt(max(0.0, 1 + R[0, 0] - R[1, 1] - R[2, 2])) / 2
    y = np.sqrt(max(0.0, 1 - R[0, 0] + R[1, 1] - R[2, 2])) / 2
    z = np.sqrt(max(0.0, 1 - R[0, 0] - R[1, 1] + R[2, 2])) / 2
    x = np.copysign(x, R[2, 1] - R[1, 2]); y = np.copysign(y, R[0, 2] - R[2, 0]); z = np.copysign(z, R[1, 0] - R[0, 1])
    q = np.array([x, y, z, w]); return q / np.linalg.norm(q)


def main():
    try:
        hou.hipFile.load(HIP, suppress_save_prompt=True, ignore_load_warnings=True)
    except hou.OperationFailed:
        pass
    hou.setFrame(1)
    n = node()
    ncog = int(n.parm("cassette_n").eval())
    geo, conn, rconn = build_net(n)

    poses, chains, teeth = [], [], []
    for gi in range(1, ncog + 1):
        n.parm("gear").set(gi)
        t0 = time.time()
        g = conn.geometry()
        if n.errors():
            raise RuntimeError(n.errors())
        P = np.array(g.pointFloatAttribValues("P"), np.float64).reshape(-1, 3)
        poses.append(P)
        D = {a.name(): n.geometry().attribValue(a) for a in n.geometry().globalAttribs() if a.name() in ("sel_cog_teeth",)}
        teeth.append(int(D.get("sel_cog_teeth", 0)))
        c = order_loop(rollers(rconn))
        chains.append(c)
        print("gear %d: %.0fs, derailleur pts %d, rollers %d, cog %dT, loop pitch %.2f-%.2f mm" % (
            gi, time.time() - t0, len(P), len(c), teeth[-1],
            1000 * np.linalg.norm(np.diff(c, axis=0), axis=1).min(), 1000 * np.linalg.norm(np.diff(c, axis=0), axis=1).max()))
        if len(P) != len(poses[0]):
            raise RuntimeError("derailleur topology changed between gears")

    # pieces at gear 1 (point -> piece via its prims)
    n.parm("gear").set(1)
    g = conn.geometry()
    prim_piece, piece_of_pt, prim_pts = pieces(g)
    # the two pulleys come out welded into one piece: split it by which pulley each point is nearer
    nm_list = g.primStringAttribValues("name")
    P0 = poses[0]
    for pid in set(int(prim_piece[i]) for i, nm in enumerate(nm_list) if nm == "jockey"):
        sel = np.where(piece_of_pt == pid)[0]
        pts = P0[sel]
        if np.linalg.norm(pts.max(0) - pts.min(0)) < 0.04:
            continue
        a = pts[np.argmax(pts[:, 1])]; b = pts[np.argmin(pts[:, 1])]   # top and bottom pulley
        for _ in range(5):   # 2-means
            near_b = np.linalg.norm(pts - b, axis=1) < np.linalg.norm(pts - a, axis=1)
            a = pts[~near_b].mean(0); b = pts[near_b].mean(0)
        new = piece_of_pt.max() + 1
        piece_of_pt[sel[near_b]] = new
        for i, ps in enumerate(prim_pts):
            if prim_piece[i] == pid: prim_piece[i] = piece_of_pt[ps[0]]
    names_of_piece = {}
    for pid, nm in zip(prim_piece, g.primStringAttribValues("name")):
        names_of_piece.setdefault(int(pid), nm)
    # carry the piece id through the reduce as a prim attribute
    pa = geo.createNode("attribwrangle"); pa.setInput(0, conn); pa.parm("class").set(1)
    pa.parm("snippet").set("int ids[] = {%s};\ni@piece = ids[@primnum];" % ",".join(str(int(x)) for x in prim_piece))
    conn = pa
    npc = piece_of_pt.max() + 1
    # rigid transform per piece per gear
    T = np.zeros((npc, ncog, 4, 4))
    worst = 0
    for pid in range(npc):
        sel = piece_of_pt == pid
        A = poses[0][sel]
        for gi in range(ncog):
            B = poses[gi][sel]
            if len(A) >= 3:
                R, t = kabsch(A, B)
            else:
                R, t = np.eye(3), (B - A).mean(0)
            e = np.abs(A @ R.T + t - B).max()
            if e > 1e-3 and gi == ncog - 1:
                print("  non-rigid piece %d (%s): %d pts, %.1f mm" % (pid, names_of_piece.get(pid, "?"), len(A), e * 1000))
            worst = max(worst, e)
            M = np.eye(4); M[:3, :3] = R; M[:3, 3] = t; T[pid, gi] = M
    # pulleys are rebuilt with their teeth turned for every gear (point order changes), so a point fit is
    # meaningless: they take the cage's rotation and follow their own centre (the game spins them)
    cage = [pid for pid in range(npc) if names_of_piece.get(pid) == "rderail_model_cage"]
    cage = max(cage, key=lambda p: (piece_of_pt == p).sum())
    for pid in range(npc):
        if names_of_piece.get(pid) != "jockey":
            continue
        sel = piece_of_pt == pid
        cA = (poses[0][sel].min(0) + poses[0][sel].max(0)) / 2
        for gi in range(ncog):
            B = poses[gi][sel]; cB = (B.min(0) + B.max(0)) / 2
            R = T[cage, gi][:3, :3]
            M = np.eye(4); M[:3, :3] = R; M[:3, 3] = cB - R @ cA; T[pid, gi] = M
    print("pieces %d, worst rigid-fit error %.3f mm (pulleys excepted)" % (npc, worst * 1000))
    # cluster pieces that move alike (pulleys always on their own: they spin)
    clusters, cl_of = [], np.zeros(npc, int)
    for pid in range(npc):
        nm = names_of_piece.get(pid, "")
        spin = nm == "jockey"
        for ci, (rep, sp) in enumerate(clusters):
            if sp or spin:
                continue
            if np.abs(T[pid] - T[rep]).max() < 2e-4:
                cl_of[pid] = ci; break
        else:
            cl_of[pid] = len(clusters); clusters.append((pid, spin))
    print("moving groups:", len(clusters), "(pulleys:", sum(1 for _, s in clusters if s), ")")

    # reduced geometry at gear 1, keeping the piece id
    tri = geo.createNode("divide"); tri.setInput(0, conn); tri.parm("convex").set(1); tri.parm("numsides").set(3)
    fuse = geo.createNode("fuse::2.0"); fuse.setInput(0, tri); fuse.parm("tol3d").set(1e-6)
    red = geo.createNode("polyreduce::2.0"); red.setInput(0, fuse); red.parm("percentage").set(REDUCE_PCT)
    nrm = geo.createNode("normal"); nrm.setInput(0, red); nrm.parm("type").set(1); nrm.parm("cuspangle").set(40)
    tri2 = geo.createNode("divide"); tri2.setInput(0, nrm); tri2.parm("convex").set(1); tri2.parm("numsides").set(3)
    w = geo.createNode("attribwrangle"); w.setInput(0, tri2); w.parm("class").set(3)
    w.parm("snippet").set("i@ptn = vertexpoint(0, @vtxnum);")
    out = w.geometry()
    Pr = np.array(out.pointFloatAttribValues("P"), np.float64).reshape(-1, 3)
    ptn = np.array(out.vertexIntAttribValues("ptn"), np.int64)
    N = np.array(out.vertexFloatAttribValues("N"), np.float64).reshape(-1, 3)
    pcs = np.array(out.primIntAttribValues("piece"))
    nms = np.array(out.primStringAttribValues("name"))
    tris = np.arange(len(ptn)).reshape(-1, 3)[:, ::-1]
    mat = np.array([NAME_MAT.get(s, 0) for s in nms])
    print("reduced to %d tris" % len(tris))

    bin_chunks, views, accessors, meshes, nodes = [], [], [], [], [{"name": "drivetrain", "children": []}]
    off = [0]

    def view(arr, target=None):
        d = arr.tobytes(); pad = (-len(d)) % 4
        v = {"buffer": 0, "byteOffset": off[0], "byteLength": len(d)}
        if target: v["target"] = target
        views.append(v); bin_chunks.append(d + b"\0" * pad); off[0] += len(d) + pad
        return len(views) - 1

    for ci, (rep, spin) in enumerate(clusters):
        sel_t = cl_of[pcs] == ci
        if not sel_t.any():
            continue
        vids = tris[sel_t].ravel()
        piv = Pr[ptn[vids]].mean(0)
        if spin:   # a pulley: pivot on its axle = centre of its bounding box
            pp = Pr[ptn[vids]]; piv = (pp.min(0) + pp.max(0)) / 2
        prims = []
        for mi in range(len(MATERIALS)):
            s2 = sel_t & (mat == mi)
            if not s2.any():
                continue
            v2 = tris[s2].ravel()
            pos = Pr[ptn[v2]] - piv; nn = N[v2]
            key = np.concatenate([ptn[v2][:, None].astype(np.float64), np.round(nn, 3)], 1)
            uniq, inv = np.unique(key, axis=0, return_inverse=True); inv = inv.ravel()
            first = np.zeros(len(uniq), np.int64); first[inv] = np.arange(len(inv))
            vp = pos[first].astype(np.float32)
            vn = nn[first]; vn = (vn / np.maximum(np.linalg.norm(vn, axis=1, keepdims=True), 1e-8)).astype(np.float32)
            idx = inv.astype(np.uint32 if len(vp) > 65535 else np.uint16)
            k = len(accessors)
            accessors += [{"bufferView": view(vp, 34962), "componentType": 5126, "count": len(vp), "type": "VEC3",
                           "min": vp.min(0).tolist(), "max": vp.max(0).tolist()},
                          {"bufferView": view(vn, 34962), "componentType": 5126, "count": len(vn), "type": "VEC3"},
                          {"bufferView": view(idx, 34963), "componentType": 5125 if idx.dtype == np.uint32 else 5123,
                           "count": len(idx), "type": "SCALAR"}]
            prims.append({"attributes": {"POSITION": k, "NORMAL": k + 1}, "indices": k + 2, "material": mi})
        meshes.append({"name": "rd%d" % ci, "primitives": prims})
        # per gear: where the pivot goes and how the piece is turned
        gears = []
        for gi in range(ncog):
            M = T[rep, gi]
            p = M[:3, :3] @ piv + M[:3, 3]
            gears.append([round(float(x), 6) for x in p] + [round(float(x), 7) for x in quat(M[:3, :3])])
        nodes[0]["children"].append(len(nodes))
        nodes.append({"name": ("pulley%d" % ci) if spin else ("rd%d" % ci), "mesh": len(meshes) - 1,
                      "translation": [float(x) for x in gears[0][:3]], "rotation": gears[0][3:],
                      "extras": {"gears": gears, "spin": spin}})

    D = {a.name(): n.geometry().attribValue(a) for a in n.geometry().globalAttribs()}
    nodes[0]["extras"] = {
        "cogs": teeth,
        "chain": [np.round(c, 5).ravel().tolist() for c in chains],
        "rollerR": float(D.get("chainw_roller_r", 3.9)) / 1000 if float(D.get("chainw_roller_r", 3.9)) > 0.5 else float(D.get("chainw_roller_r")),
        "innerWidth": float(D.get("chain_inner_width", 2.38)) / 1000 if float(D.get("chain_inner_width", 2.38)) > 0.5 else float(D.get("chain_inner_width")),
        "pitch": 0.0127,
        "jockeyTeeth": int(n.parm("jockey_t").eval()),
    }
    print("extras:", {k: v for k, v in nodes[0]["extras"].items() if k != "chain"})
    gltf = {"asset": {"version": "2.0", "generator": "gamecycling export_drivetrain.py"},
            "scene": 0, "scenes": [{"nodes": [0]}], "nodes": nodes, "meshes": meshes,
            "materials": [{"name": nm, "pbrMetallicRoughness": {"baseColorFactor": c, "metallicFactor": m, "roughnessFactor": r}}
                          for nm, c, m, r in MATERIALS],
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
