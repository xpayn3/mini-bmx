"""Fork models for the stock (GLORY / dh.glb) frame, from the exported frames' forks (assets/parts/<id>_fork.glb, written by
export_tues.py / export_fuzz.py). Plain Python + numpy:
  python -I tools/make_forks.py
Writes godot/assets/forks/<id>.glb: node "fork_crown" (crowns + stanchions, in dh's steer space, the crowns centred where dh's
are, the stanchions on dh's steering axis) and node "fork_lower" (lowers + front brake caliper, relative to the axle; its
translation = where the axle sits in steer space). The axle keeps dh's position along the fork (so the bike's geometry and the
wheel placement stay; the longer fork simply starts compressed: extras.travel = the room that is left) and the fork's own
offset across it. Also writes godot/assets/forks/dh_cockpit.glb: dh's steer mesh without its crowns / stanchions, which
BikeRig swaps in when a fork model is picked.
"""
import json, os, struct, sys, math
import numpy as np
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from bike_glb import write_glb

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
A = os.path.join(ROOT, "godot", "assets")
os.makedirs(os.path.join(A, "forks"), exist_ok=True)


def load(path):
    f = open(path, "rb").read(); jl = struct.unpack("<I", f[12:16])[0]
    g = json.loads(f[20:20 + jl]); return g, f[20 + jl + 8:]


def acc(g, b, i):
    a = g["accessors"][i]; v = g["bufferViews"][a["bufferView"]]
    dt = {5126: np.float32, 5123: np.uint16, 5125: np.uint32}[a["componentType"]]; n = {"VEC3": 3, "SCALAR": 1}[a["type"]]
    x = np.frombuffer(b, dtype=dt, count=a["count"] * n, offset=v["byteOffset"])
    return x.reshape(-1, n) if n > 1 else x


def node_tris(g, b, node_name):
    """-> list of (pos(tri*3,3), nrm, material) of one node's mesh"""
    n = [n for n in g["nodes"] if n.get("name") == node_name and "mesh" in n][0]
    out = []
    for p in g["meshes"][n["mesh"]]["primitives"]:
        P = acc(g, b, p["attributes"]["POSITION"]).astype(float); N = acc(g, b, p["attributes"]["NORMAL"]).astype(float)
        I = acc(g, b, p["indices"]).astype(int)
        out.append((P[I], N[I], g["materials"][p["material"]]["name"]))
    return out


def rot(th):
    c, s = math.cos(th), math.sin(th)
    return np.array([[c, -s, 0], [s, c, 0], [0, 0, 1]])


# ---------------------------------------------------------------- dh: the steer mesh in components
gd, bd = load(os.path.join(A, "dh.glb"))
ax_d = np.array(gd["nodes"][0]["extras"]["steerAxis"][:2]); ax_d /= np.linalg.norm(ax_d)
steer = node_tris(gd, bd, "steer")
tris = np.concatenate([p.reshape(-1, 3, 3) for p, _, _ in steer]); nrms = np.concatenate([n.reshape(-1, 3, 3) for _, n, _ in steer])
mats = [m for p, _, m in steer for _ in range(len(p) // 3)]
key = lambda v: tuple(np.round(v * 1e4).astype(int))
parent = {}
def find(x):
    while parent.setdefault(x, x) != x:
        parent[x] = parent[parent[x]]; x = parent[x]
    return x
for t in tris:
    ks = [key(v) for v in t]
    for k in ks[1:]: parent[find(k)] = find(ks[0])
comp = {}
for i, t in enumerate(tris): comp.setdefault(find(key(t[0])), []).append(i)
fork_idx, crowns = set(), []
for idx in comp.values():
    P = tris[idx].reshape(-1, 3); t = P[:, :2] @ ax_d; ms = {mats[i] for i in idx}
    zr = P[:, 2].max() - P[:, 2].min()
    if t.max() <= 0.095 and (zr > 0.04 or "gold" in ms) and P[:, 2].min() > -0.115 and P[:, 2].max() < 0.115:
        fork_idx.update(idx)
        if len(idx) > 1000: crowns.append(((P[:, :2].min(0) + P[:, :2].max(0)) / 2, t.min(), t.max()))
print("dh steer: %d of %d triangles are fork; crowns found: %d" % (len(fork_idx), len(tris), len(crowns)))
C_d = np.mean([c[0] for c in crowns], axis=0)
crown_t_min = min(c[1] for c in crowns)
keep = np.array([i not in fork_idx for i in range(len(tris))])
cock = []
for m in sorted(set(mats)):
    sel = keep & (np.array(mats) == m)
    if sel.any(): cock.append((tris[sel].reshape(-1, 3), nrms[sel].reshape(-1, 3), m))
dh_steer_node = [n for n in gd["nodes"] if n.get("name") == "steer"][0]
write_glb(os.path.join(A, "forks", "dh_cockpit.glb"), [{"name": "steer", "parent": None, "t": [0, 0, 0], "origin": np.zeros(3), "parts": cock}], None, "cockpit")
A_dh = np.array(dh_steer_node and [n for n in gd["nodes"] if n.get("name") == "fork_lower"][0]["translation"])[:2]
t_dh = float(A_dh @ ax_d)
print("dh crowns mid", C_d.round(3), "lower crown bottom t %.3f; dh axle t %.3f offset %.3f" % (crown_t_min, t_dh, A_dh[0] * ax_d[1] - A_dh[1] * ax_d[0]))

# ---------------------------------------------------------------- each exported fork, fitted
for fid in ("tues", "fuzz"):
    g, b = load(os.path.join(A, "parts", "%s_fork.glb" % fid))
    ex = g["nodes"][0]["extras"]
    ax_s = np.array(ex["steerAxis"]); ax_s /= np.linalg.norm(ax_s)
    th = math.atan2(ax_d[1], ax_d[0]) - math.atan2(ax_s[1], ax_s[0])
    R = rot(th)
    C_s = np.array(ex["crownMid"]); A_s = np.array(ex["axle"])
    crown = node_tris(g, b, "fork_crown"); lower = node_tris(g, b, "fork_lower")
    def tcrown(p): return (np.concatenate([(p[:, :2] - C_s) @ R[:2, :2].T + C_d, p[:, 2:3]], 1))
    def rnor(n): return n @ R.T
    parts_c = [(tcrown(p), rnor(n), m) for p, n, m in crown]
    parts_l = [(p @ R.T, rnor(n), m) for p, n, m in lower]
    A_new = R[:2, :2] @ (A_s - C_s) + C_d                       # where the fork's own axle would be in steer space
    compress = t_dh - float(A_new @ ax_d)                         # < 0: the fork is longer than dh's by -compress
    A_pl = A_new + ax_d * (t_dh - float(A_new @ ax_d))            # axle: dh's place along the fork, the fork's own offset across it
    # no re-centring: the authored fork is one coaxial unit (checked by ray casting the FBX: stanchion and lowers share their centre line
    # to 0.0000), so the lowers keep exactly their authored place against the crowns; they only slide along the axis
    offs = float(A_pl[0] * ax_d[1] - A_pl[1] * ax_d[0])
    lt = np.concatenate([p for p, _, _ in parts_l]); top_t = float(A_pl @ ax_d) + float((lt[:, :2] @ ax_d).max())
    gap = crown_t_min - top_t
    print("%s: turn %.2f deg; fork %.0f mm longer than dh's (starts that much compressed); axle offset %.3f (dh %.3f); lowers top to lower crown gap %.3f"
          % (fid, math.degrees(th), -compress * 1000, offs, A_dh[0] * ax_d[1] - A_dh[1] * ax_d[0], gap))
    travel = math.floor(gap / 0.8 * 100) / 100       # the game's max compression is 0.8 x travel (20 % sag)
    write_glb(os.path.join(A, "forks", "%s.glb" % fid),
              [{"name": "fork_crown", "parent": None, "t": [0, 0, 0], "origin": np.zeros(3), "parts": parts_c},
               {"name": "fork_lower", "parent": None, "t": [float(A_pl[0]), float(A_pl[1]), 0.0], "origin": np.zeros(3), "parts": parts_l}],
              {"axle": A_pl.tolist(), "travel": travel, "extraLength": -compress}, "fork")
    print("   max travel that fits: %.2f m" % travel)


# ---------------------------------------------------------------- rear brake calipers for the stock frame
# dh's rear caliper is a handful of black components in the seatstay mesh, on the left of the wheel next to the rotor. They are cut out
# (assets/forks/dh_seatstay.glb = the seatstay without them) and the frames' rear calipers (parts/<id>_caliper_rear.glb, relative to
# their axle) are turned about the axle to the stock caliper's angle on the rotor (assets/forks/caliper_<id>.glb, relative to the axle).
ax_w = np.array([n for n in gd["nodes"] if n.get("name") == "wheel_rear"][0]["translation"][:2])
seat = node_tris(gd, bd, "seatstay")
st = np.concatenate([p.reshape(-1, 3, 3) for p, _, _ in seat]); sn = np.concatenate([n.reshape(-1, 3, 3) for _, n, _ in seat])
sm = np.array([m for p, _, m in seat for _ in range(len(p) // 3)])
parent.clear()
for t in st:
    ks = [key(v) for v in t]
    for k in ks[1:]: parent[find(k)] = find(ks[0])
comp = {}
for i, t in enumerate(st): comp.setdefault(find(key(t[0])), []).append(i)
cal_idx, main_c = set(), None
for idx in comp.values():
    P = st[idx].reshape(-1, 3); r = P[:, :2] - ax_w
    if set(sm[idx]) == {"black"} and P[:, 2].max() < -0.035 and P[:, 2].min() > -0.09 and r.min() >= 0.015 and r.max() <= 0.11:
        cal_idx.update(idx)
        if main_c is None or len(idx) > main_c[0]: main_c = (len(idx), (r.min(0) + r.max(0)) / 2)
ang_d = math.atan2(main_c[1][1], main_c[1][0])
print("dh rear caliper: %d triangles cut; main body %.0f mm from the axle at %.1f deg" % (len(cal_idx), float(np.linalg.norm(main_c[1])) * 1000, math.degrees(ang_d)))
keep = np.array([i not in cal_idx for i in range(len(st))])
parts = []
for m in sorted(set(sm)):
    sel = keep & (sm == m)
    if sel.any(): parts.append((st[sel].reshape(-1, 3), sn[sel].reshape(-1, 3), m))
write_glb(os.path.join(A, "forks", "dh_seatstay.glb"), [{"name": "seatstay", "parent": None, "t": [0, 0, 0], "origin": np.zeros(3), "parts": parts}], None, "seatstay")
for fid in ("tues", "fuzz"):
    g, b = load(os.path.join(A, "parts", "%s_caliper_rear.glb" % fid))
    mc = np.array(g["nodes"][0]["extras"]["center"])
    d = ang_d - math.atan2(mc[1], mc[0]); R = rot(d)
    cal = [(p @ R.T, n @ R.T, m) for p, n, m in node_tris(g, b, "caliper")]
    write_glb(os.path.join(A, "forks", "caliper_%s.glb" % fid), [{"name": "caliper", "parent": None, "t": [0, 0, 0], "origin": np.zeros(3), "parts": cal}], None, "caliper")
    print("%s rear caliper: turned %.1f deg about the axle (%.0f mm from it)" % (fid, math.degrees(d), float(np.linalg.norm(mc)) * 1000))


# ---------------------------------------------------------------- seat: dh's frame without its saddle, + where the post goes
# The saddle (cover, rails, clamp hardware) are components in the frame mesh above the seat tube. They are cut out
# (assets/seats/dh_frame.glb) and the glb's extras say where the stock saddle sat (origin = under its middle, at the rail
# bottom, like the parts/<id>_saddle.glb files) and the seat tube's top + direction (the post / dropper rides along it).
os.makedirs(os.path.join(A, "seats"), exist_ok=True)
fr = node_tris(gd, bd, "frame")
ft = np.concatenate([p.reshape(-1, 3, 3) for p, _, _ in fr]); fn = np.concatenate([n.reshape(-1, 3, 3) for _, n, _ in fr])
fm = np.array([m for p, _, m in fr for _ in range(len(p) // 3)])
parent.clear()
for t in ft:
    ks = [key(v) for v in t]
    for k in ks[1:]: parent[find(k)] = find(ks[0])
comp = {}
for i, t in enumerate(ft): comp.setdefault(find(key(t[0])), []).append(i)
seat_idx, tube = set(), None
for idx in comp.values():
    P = ft[idx].reshape(-1, 3); mn, mx = P.min(0), P.max(0); ms = set(fm[idx])
    if mn[1] >= 0.69 and mx[1] <= 0.83 and mn[0] >= -0.24 and mx[0] <= 0.05 and ms <= {"plastic", "chrome", "black"}:
        seat_idx.update(idx)
    if ms == {"paint"} and abs(mn[1] - 0.336) < 0.01 and abs(mx[1] - 0.723) < 0.01 and mx[0] < 0.03:   # the seat tube
        tube = P
SP_ = np.concatenate([ft[sorted(seat_idx)].reshape(-1, 3)])
stock_org = [float((SP_[:, 0].min() + SP_[:, 0].max()) / 2), float(SP_[:, 1].min() + 0.012)]
top = tube[tube[:, 1] > tube[:, 1].max() - 0.01]
post_top = [float(top[:, 0].mean()), float(tube[:, 1].max())]
c0 = tube[:, :2].mean(0); u, s_, vt = np.linalg.svd(tube[:, :2] - c0, full_matrices=False)
post_dir = vt[0] if vt[0][1] > 0 else -vt[0]
print("dh seat: %d triangles cut; stock saddle origin %s; seat tube top %s, direction %s" % (len(seat_idx), np.round(stock_org, 3), np.round(post_top, 3), post_dir.round(3)))
keepf = np.array([i not in seat_idx for i in range(len(ft))])
parts = []
for m in sorted(set(fm)):
    sel = keepf & (fm == m)
    if sel.any(): parts.append((ft[sel].reshape(-1, 3), fn[sel].reshape(-1, 3), m))
write_glb(os.path.join(A, "seats", "dh_frame.glb"), [{"name": "frame", "parent": None, "t": [0, 0, 0], "origin": np.zeros(3), "parts": parts}],
          {"stockOrigin": stock_org, "postTop": post_top, "postDir": [float(post_dir[0]), float(post_dir[1])]}, "seat")
cut = sorted(seat_idx)
sd = [(ft[[i for i in cut if fm[i] == m]].reshape(-1, 3) - np.array([stock_org[0], stock_org[1], 0.0]),
       fn[[i for i in cut if fm[i] == m]].reshape(-1, 3), m) for m in sorted({fm[i] for i in cut})]
write_glb(os.path.join(A, "seats", "saddle_dh.glb"), [{"name": "saddle", "parent": None, "t": [0, 0, 0], "origin": np.zeros(3), "parts": sd}], None, "saddle")
# the models' saddles, levelled: the long axis of the cover goes horizontal (they sat tilted to their own frames), written next to dh's
for fid in ("tues", "fuzz"):
    g, b = load(os.path.join(A, "parts", "%s_saddle.glb" % fid))
    sparts = node_tris(g, b, "saddle")
    cover = np.concatenate([p for p, _, m in sparts if m == "plastic"] or [p for p, _, _ in sparts])[:, :2]
    c0 = cover.mean(0); u, s_, vt = np.linalg.svd(cover - c0, full_matrices=False); d = vt[0] if vt[0][0] > 0 else -vt[0]
    tilt = math.atan2(d[1], d[0]); R = rot(-tilt)
    print("%s saddle: levelled by %.1f deg" % (fid, math.degrees(tilt)))
    write_glb(os.path.join(A, "seats", "saddle_%s.glb" % fid), [{"name": "saddle", "parent": None, "t": [0, 0, 0], "origin": np.zeros(3),
              "parts": [(p @ R.T, n @ R.T, m) for p, n, m in sparts]}], None, "saddle")


# ---------------------------------------------------------------- brake levers: dh's steer mesh without them + the models' levers placed where dh's sat
# dh's levers are small components on the bar (chrome blades, plastic bodies / clamps) either side of the stem. They are cut out of the steer
# mesh (assets/forks/dh_steer_nl.glb = the whole steer mesh, dh_cockpit_nl.glb = the fork-less cockpit) and the frames' levers
# (parts/<id>_levers.glb, in their own steer space) are moved so their clamp end sits where dh's does: assets/forks/levers_<id>.glb.
# Their parts are written as "plastic" / "chrome" so Handlebar.apply moves them with the bar like the stock ones.
parent.clear()
for t in tris:
    ks = [key(v) for v in t]
    for k in ks[1:]: parent[find(k)] = find(ks[0])
comp = {}
for i, t in enumerate(tris): comp.setdefault(find(key(t[0])), []).append(i)
lev_idx = set()
for idx in comp.values():
    P = tris[idx].reshape(-1, 3); ms = {mats[i] for i in idx}
    az = np.abs(P[:, 2])
    if ms <= {"chrome", "plastic"} and az.min() > 0.19 and az.max() < 0.37 and len(idx) <= 200 and 0.1 < P[:, 1].min() and P[:, 1].max() < 0.2:
        lev_idx.update(idx)
print("dh levers: %d triangles cut" % len(lev_idx))
LP = tris[sorted(lev_idx)].reshape(-1, 3)
dh_in = {s_: np.abs(LP[(LP[:, 2] * s_) > 0][:, 2]).min() for s_ in (-1, 1)}
dh_ctr = {s_: LP[(LP[:, 2] * s_) > 0][:, :2].mean(0) for s_ in (-1, 1)}
for name, drop in (("dh_steer_nl", set()), ("dh_cockpit_nl", fork_idx)):
    kp = np.array([i not in lev_idx and i not in drop for i in range(len(tris))])
    pr = []
    for m in sorted(set(mats)):
        sel = kp & (np.array(mats) == m)
        if sel.any(): pr.append((tris[sel].reshape(-1, 3), nrms[sel].reshape(-1, 3), m))
    write_glb(os.path.join(A, "forks", name + ".glb"), [{"name": "steer", "parent": None, "t": [0, 0, 0], "origin": np.zeros(3), "parts": pr}], None, "cockpit")
for fid in ("tues", "fuzz"):
    g, b = load(os.path.join(A, "parts", "%s_levers.glb" % fid))
    lp = node_tris(g, b, "levers")
    allp = np.concatenate([p for p, _, _ in lp])
    out = {}
    for s_ in (-1, 1):
        side = [(p[(p[:, 2] * s_) > 0] if False else p, n, m) for p, n, m in lp]
    res = []
    for p, n, m in lp:
        # whole triangles go to the side their middle is on
        tri_z = p.reshape(-1, 3, 3)[:, :, 2].mean(1)
        for s_ in (-1, 1):
            sel = np.repeat((tri_z * s_) > 0, 3)
            if not sel.any(): continue
            res.append((s_, p[sel], n[sel], "chrome" if m == "chrome" else "plastic"))
    final = []
    for s_ in (-1, 1):
        sp = np.concatenate([p for sd_, p, _, _ in res if sd_ == s_])
        # the clamp (the biggest connected piece) must sit round the bar: its middle goes onto dh's bar axis at the lever
        st = sp.reshape(-1, 3, 3); parent.clear()
        for t in st:
            ks = [key(v) for v in t]
            for k in ks[1:]: parent[find(k)] = find(ks[0])
        cc = {}
        for i, t in enumerate(st): cc.setdefault(find(key(t[0])), []).append(i)
        # the bar axis: each side's grips are straight cylinders on it, so the grips' middle (the model's own, and dh's) gives the offset
        gm, gb = load(os.path.join(A, "parts", "%s_cockpit.glb" % fid))
        gr = np.concatenate([p for p, _, m in node_tris(gm, gb, "cockpit") if m == "rubber"])
        gr = gr[(gr[:, 2] * s_) > 0.1]
        gin = np.abs(gr[:, 2]).min(); gr = gr[np.abs(gr[:, 2]) < gin + 0.05]   # the grip's inner end, where the lever is
        c = (gr[:, :2].min(0) + gr[:, :2].max(0)) / 2
        dr = np.concatenate([tris[i] for i in range(len(tris)) if mats[i] == "rubber" and i not in fork_idx and tris[i][:, 2].mean() * s_ > 0.1])
        din = np.abs(dr[:, 2]).min(); dr = dr[np.abs(dr[:, 2]) < din + 0.05]
        dh_ctr[s_] = (dr[:, :2].min(0) + dr[:, :2].max(0)) / 2
        d = np.array([dh_ctr[s_][0] - c[0], dh_ctr[s_][1] - c[1], s_ * (din - gin)])   # keeps the lever's place against its own grip
        print("%s lever side %+d: bbox z %.3f..%.3f, moved by %s" % (fid, s_, sp[:, 2].min(), sp[:, 2].max(), np.round(d, 3)))
        for sd_, p, n, m in res:
            if sd_ == s_: final.append((p + d, n, m))
    write_glb(os.path.join(A, "forks", "levers_%s.glb" % fid), [{"name": "levers", "parent": None, "t": [0, 0, 0], "origin": np.zeros(3), "parts": final}], None, "levers")

