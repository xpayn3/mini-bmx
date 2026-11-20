"""Rig the Sketchfab "DH bike frame" (CC-BY 4.0, Once_a_goat_death, see godot/assets/dhframe_LICENSE.txt) as a second
frame for the game: its frame, single-pivot swingarm, coil shock; the fork, bars, wheels and cranks are ours (dh.glb).

Run with Blender (4.1 or newer):
  & "C:\\Program Files\\Blender Foundation\\Blender 4.1\\blender.exe" -b -P tools\\export_dhframe.py -- <scene.gltf>

Writes godot/assets/dhframe.glb in the dh.glb node layout. The frame is scaled + turned about the bottom bracket
so its axle sits where dh.glb's does; our steer / fork_lower follow the head tube. The swingarm turns about its
one pivot P2: in the game's four-bar solver that is G1 = G2 = P2, C1 = the axle, C2 = the link bolt, so the
solver closes a rigid triangle; the shock's lower eye rides on the swingarm.
"""
import bpy, sys, os, json, struct, math
import numpy as np
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from bike_glb import extract, write_glb, dh_rotors, glb_local_parts

GLTF = sys.argv[-1]
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DH = os.path.join(ROOT, "godot", "assets", "dh.glb")
OUT = os.path.join(ROOT, "godot", "assets", "dhframe.glb")

# dh.glb numbers (BB at x = 0): rear axle, rest geometry
f = open(DH, "rb").read(); jl = struct.unpack("<I", f[12:16])[0]; dh = json.loads(f[20:20 + jl])
dh_extras = dh["nodes"][0]["extras"]
BBD = np.array([0.0, 0.33009]); AD = np.array(dh_extras["suspension"]["rear"]["A"])

def b2g(p):   # Blender (glTF import: x forward, y lateral, z up) -> game (x fwd, y up, z right)
    return np.stack([p[..., 0], p[..., 2], -p[..., 1]], -1)

def parts_of(o):
    P, L, N, mi, names = extract(o)
    n = len(mi); L = L.reshape(n, 3); N = N.reshape(n, 3, 3)
    return P[L].reshape(-1, 3), N.reshape(-1, 3), mi, names

DERAIL = os.path.join(ROOT, "godot", "assets", "parts", "tues_derailleur.glb")
ROTORS = dh_rotors(DH)
TUES_CRANKS = glb_local_parts(os.path.join(ROOT, "godot", "assets", "parts", "tues_cranks.glb"))   # relative to its BB
DERAIL_PARTS = glb_local_parts(DERAIL)   # the Tues rear derailleur, relative to its axle
# ---------------------------------------------------------------- our parts from dh.glb (steer, fork lowers, crank)
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=DH)
ours = {}; piv = {}
for name in ("steer", "fork_lower", "crank", "frame"):
    o = bpy.data.objects[name]
    piv[name] = b2g(np.array(o.matrix_world.translation))[:2]
    P, N, mi, names = parts_of(o)
    P = b2g(P); N = b2g(N)
    lst = []
    for k in sorted(set(mi.tolist())):
        sel = np.repeat(mi == k, 3)
        if name == "frame" and names[k] != "plastic": continue   # only the saddle of the GLORY frame
        lst.append((P[sel], N[sel], names[k]))
    ours[name] = lst
# the Tues pedals in place of the GLORY's (the crank's "plastic" surface is the pedal pair)
def per_side(parts):   # {side: (pos, nrm, mat)} split by the sign of each triangle's z
    out = {}
    for p, n, m in parts:
        tri_z = p.reshape(-1, 3, 3)[:, :, 2].mean(1)
        for side in (-1, 1):
            sel = np.repeat(np.sign(tri_z) == side, 3)
            if sel.any(): out.setdefault(side, []).append((p[sel], n[sel], m))
    return out
old = [e for e in ours["crank"] if e[2] == "plastic"]
ours["crank"] = [e for e in ours["crank"] if e[2] != "plastic"]
new = per_side([e for e in TUES_CRANKS if e[2] == "plastic"])
oldside = per_side(old)
for side in (-1, 1):
    cd = np.concatenate([e[0] for e in oldside[side]]).mean(0)        # the GLORY pedal's centre (absolute)
    ct = np.concatenate([e[0] for e in new[side]]).mean(0)            # the Tues pedal's centre (relative to its BB)
    ours["crank"] += [(p - ct + cd, n, "plastic") for p, n, m in new[side]]
print("dh pivots", {k: v.round(4).tolist() for k, v in piv.items()})

# ---------------------------------------------------------------- the Sketchfab frame
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=GLTF)
for name in ("Object_4", "Object_6", "Object_17"):
    o = bpy.data.objects[name]
    bpy.context.view_layer.objects.active = o
    for ob in bpy.data.objects: ob.select_set(False)
    o.select_set(True)
    bpy.ops.object.mode_set(mode='EDIT'); bpy.ops.mesh.select_all(action='SELECT')
    bpy.ops.mesh.separate(type='LOOSE'); bpy.ops.object.mode_set(mode='OBJECT')

# points read off the model in its own units (x forward, z up)
BBS = np.array([-1.298, -1.720]); AS = np.array([-3.545, -1.791]); P2S = np.array([-1.210, -1.387])
P3S = np.array([-1.384, -0.9335]); DS = np.array([-1.300, -1.080]); FES = np.array([-0.320, -0.540])
HEADS = np.array([0.851, 1.069])
# scale + turn about the BB so the head tube lands at dh's height above the BB and the axle at dh's axle height
hv = HEADS - BBS; av = AS - BBS
hy_t = piv["steer"][1] - BBD[1]; ay_t = AD[1] - BBD[1]
def ratio(t): return (hv[0] * math.sin(t) + hv[1] * math.cos(t)) / (av[0] * math.sin(t) + av[1] * math.cos(t))
lo, hi = math.radians(-12), math.radians(-2)        # the ratio falls as the turn gets more negative
for _ in range(60):
    mid = (lo + hi) / 2
    if ratio(mid) > hy_t / ay_t: hi = mid
    else: lo = mid
th = (lo + hi) / 2
s = hy_t / (hv[0] * math.sin(th) + hv[1] * math.cos(th))
c, sn = math.cos(th), math.sin(th)
print("scale %.4f turn %.2f deg" % (s, math.degrees(th)))

def T2(p):    # source (x, z) -> game (x, y)
    v = (np.asarray(p) - BBS) * s
    return BBD + np.array([c * v[0] - sn * v[1], sn * v[0] + c * v[1]])

def Tpts(P):  # Blender world points -> game
    v = (P[:, [0, 2]] - BBS) * s
    gx = c * v[:, 0] - sn * v[:, 1] + BBD[0]; gy = sn * v[:, 0] + c * v[:, 1] + BBD[1]
    return np.stack([gx, gy, -P[:, 1] * s], 1)

Z_OFF = 0.021   # sideways offset of the front triangle in the source model (game units, after scaling)

def Tnrm(N):
    nx = c * N[:, 0] - sn * N[:, 2]; ny = sn * N[:, 0] + c * N[:, 2]
    return np.stack([nx, ny, -N[:, 1]], 1)

FRAME = ("Object_4.", "Object_5", "Object_6", "Object_6.002", "Object_33", "Object_35", "Object_12", "Object_11")
SWING = ("Object_4.020", "Object_6.001", "Object_8", "Object_9")
MAT = {"Material": "paint", "material": "chrome", "oring": "black", "black": "black", "blackshiny": "black",
       "czarnyplastik": "black", "spirung": "gold", "spirungtru": "gold"}
groups = {"frame": [], "seatstay": [], "shock_body": [], "shock_shaft": [], "shock_spring": []}
for o in list(bpy.data.objects):
    if o.type != 'MESH' or len(o.data.polygons) == 0: continue
    n = o.name
    if n == "Object_4.020" or n in ("Object_6.001", "Object_8", "Object_9"): node = "seatstay"
    elif n in ("Object_17", "Object_16"): node = "shock_body"
    elif n in ("Object_17.001", "Object_15"): node = "shock_shaft"
    elif n == "Object_19": node = "shock_spring"
    elif n.startswith("Object_4.") or n in ("Object_5", "Object_6", "Object_6.002", "Object_33", "Object_35", "Object_11") or n.startswith("Object_12"):
        node = "frame"
    else: continue
    P, N, mi, names = parts_of(o)
    G = Tpts(P); GN = Tnrm(N)
    if node == "frame":
        # the model's front triangle sits ~2.1 cm to one side of the bottom bracket / seat tube (head tube centre z = +0.021, BB shell
        # centre z = 0), so the fork (centred on the bike) stood beside the head tube: bring the main beam back onto the centre line,
        # blending in over the bottom bracket region
        G[:, 2] -= Z_OFF * np.clip((G[:, 0] + 0.12) / 0.12, 0.0, 1.0)
    for k in sorted(set(mi.tolist())):
        sel = np.repeat(mi == k, 3)
        groups[node].append((G[sel], GN[sel], MAT.get(names[k], "black")))
print("tris", {k: sum(len(p[0]) // 3 for p in v) for k, v in groups.items()})

# ---------------------------------------------------------------- pivots + linkage (game coords)
G1 = G2 = T2(P2S); C1 = T2(AS); C2 = T2(P3S); A = T2(AS); D = T2(DS); FE = T2(FES)
head = T2(HEADS)
# our saddle on the seat tube (this frame has none): the top of the seat tube is the highest frame point near x of the tube
fv = np.concatenate([p[0] for p in groups["frame"]])
tx = T2((-1.80, 0.19))[0]
near = fv[np.abs(fv[:, 0] - tx) < 0.05]
top = near[:, 1].max()
seat_c = near[near[:, 1] > top - 0.03][:, 0].mean()
sad = np.concatenate([p[0] for p in ours["frame"]])
sd = np.array([seat_c - (sad[:, 0].min() + sad[:, 0].max()) / 2, top + 0.02 - sad[:, 1].min(), 0.0])
groups["frame"] += [(p + sd, n, m) for p, n, m in ours["frame"]]
# a short seatpost from inside the tube up to the saddle rails
def cylinder(cx, y0, y1, r, n=14):
    ang = np.linspace(0, 2 * np.pi, n + 1)
    P, N = [], []
    for i in range(n):
        a0, a1 = ang[i], ang[i + 1]
        for (u, v, y) in ((a0, a1, y0), (a1, a1, y1), (a0, a0, y1)) if False else ():
            pass
        q = lambda a_, y: np.array([cx + r * np.cos(a_), y, r * np.sin(a_)])
        nn = lambda a_: np.array([np.cos(a_), 0, np.sin(a_)])
        for tri in ((q(a0, y0), q(a1, y0), q(a1, y1)), (q(a0, y0), q(a1, y1), q(a0, y1))):
            P += list(tri)
        for a_ in (a0, a1, a1, a0, a1, a0): N.append(nn(a_))
    return np.array(P), np.array(N)
pp, pn = cylinder(seat_c, top - 0.05, top + 0.035, 0.0155)
groups["frame"].append((pp, pn, "black"))
print("saddle on the seat tube at", round(seat_c, 3), round(top, 3))
shift = head - piv["steer"]
print("head tube moves %.3f, %.3f vs dh" % tuple(shift))
shift = np.array([shift[0], 0.0])     # the height already matches; slide the fork along the new head tube
def moved(lst, d): return [(p + np.array([d[0], d[1], 0.0]), n, m) for p, n, m in lst]
FAXn = piv["fork_lower"] + shift
SPn = piv["steer"] + shift

dirv = (D - FE) / np.linalg.norm(D - FE)
spr = np.concatenate([p[0] for p in groups["shock_spring"]])[:, :2]
proj = (spr - FE) @ dirv
seat0 = FE + dirv * proj.min(); spring_len = float(proj.max() - proj.min())
ang = math.atan2(dirv[1], dirv[0]) - math.pi / 2
z3 = lambda v: np.array([v[0], v[1], 0.0])
tri = [(np.array([[0, 0, 0], [0.01, 0, 0], [0, 0.01, 0]], float), np.tile([0, 0, 1.0], (3, 1)), "chrome")]
rows = [("frame", None, np.zeros(3), groups["frame"]),
        ("steer", None, z3(SPn), moved(ours["steer"], shift)),
        ("fork_lower", "steer", z3(FAXn), moved(ours["fork_lower"], shift)),
        ("wheel_front", "fork_lower", z3(FAXn), tri + ROTORS["wheel_front"]),
        ("swing", None, z3(G1), []),
        ("seatstay", None, z3(C1), groups["seatstay"] + [(p + np.array([A[0], A[1], 0.0]), n, m) for p, n, m in DERAIL_PARTS]),
        ("wheel_rear", "seatstay", z3(A), tri + ROTORS["wheel_rear"]),
        ("pulley_1", "seatstay", z3(A + np.array([0.016, -0.062])), []),
        ("pulley_2", "seatstay", z3(A + np.array([0.022, -0.138])), []),
        ("shock_body", None, z3(FE), groups["shock_body"]),
        ("shock_spring", "shock_body", z3(seat0), groups["shock_spring"]),
        ("shock_shaft", None, z3(D), groups["shock_shaft"]),
        ("crank", None, z3(piv["crank"]), ours["crank"])]
pv = {r[0]: r[2] for r in rows}
nodes = []
for name, par, origin, parts in rows:
    nd = {"local": name.startswith("wheel_"), "name": name, "parent": par, "t": origin - (pv[par] if par else np.zeros(3)), "origin": origin, "parts": parts}
    if name == "shock_spring": nd["rotz"] = ang
    nodes.append(nd)

# the old linkage solver is a four-bar: G1 = G2 makes it a rigid triangle (G1, C1, C2) turning about the pivot
extras = json.loads(json.dumps(dh_extras))
rear = extras["suspension"]["rear"]
rear.update({"G1": G1.tolist(), "G2": G2.tolist(), "C1": C1.tolist(), "C2": C2.tolist(), "A": A.tolist(), "D": D.tolist(),
             "FE": FE.tolist(), "springLen": spring_len})
extras["wheelbase"] = float(FAXn[0] - A[0]); extras["bbToRearAxle"] = float(-A[0])   # this frame has longer stays than the GLORY
extras["noDecals"] = True
extras["chain"] = {"ring_r": 0.092, "ring_z": 0.055, "cog_z": 0.060, "pulley_r": 0.0235, "pulley_z": 0.085}
write_glb(OUT, nodes, extras)
print("axle", A.round(3), "fork axle", FAXn.round(3), "shock L", np.linalg.norm(D - FE).round(3), "spring", round(spring_len, 3))
