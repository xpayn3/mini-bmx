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
    n = [n for n in g["nodes"] if n.get("name") == node_name][0]
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
