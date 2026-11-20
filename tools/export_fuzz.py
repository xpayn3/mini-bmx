"""Rig the NS Bikes Fuzz FBX (frame, fork, shock, linkage, cockpit, brakes, cranks) for the game: same recipe as
tools/export_tues.py (read that first). Run with Blender, the FBX path last:
  & "C:\\Program Files\\Blender Foundation\\Blender 4.1\\blender.exe" -b -P tools\\export_fuzz.py -- FuzzFBX.fbx
Writes godot/assets/fuzz.glb + godot/assets/parts/fuzz_*.glb. Same Horst-style linkage as the Tues: chainstay G1-C1, rear
triangle (axle A) joined at C1 / C2, rocker G2-C2 with the shock eye D; a coil shock (spring node scales with the stroke).
FBX: forward = y, up = z, lateral = x -> game (x, y, z) = (fy - bb, fz, fx)."""
import bpy, sys, os, json, struct, math
import numpy as np
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from bike_glb import MATS, MI, extract, write_glb, dh_rotors

FBX = sys.argv[-1]
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "godot", "assets")
os.makedirs(os.path.join(OUT, "parts"), exist_ok=True)

ROTORS = dh_rotors(os.path.join(OUT, "dh.glb"))   # the game's own brake discs ride on the placeholder wheels
# ---------------------------------------------------------------- load + split every mesh into loose parts
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.fbx(filepath=FBX)
for name in ("Frame", "Frame_Bearings", "Shock", "Damper", "Brakes", "Brake_levers", "Lines", "Derailleur", "Cranks", "Pedals", "Guard", "Seat", "Seatpost", "Handlebars", "Grips", "Stem"):
    o = bpy.data.objects[name]
    bpy.context.view_layer.objects.active = o
    for ob in bpy.data.objects: ob.select_set(False)
    o.select_set(True)
    bpy.ops.object.mode_set(mode='EDIT'); bpy.ops.mesh.select_all(action='SELECT')
    bpy.ops.mesh.separate(type='LOOSE'); bpy.ops.object.mode_set(mode='OBJECT')

# ---------------------------------------------------------------- the rig (FBX metres, then shifted to the BB)
BBF = np.array([-0.177, 0.344])           # bottom bracket (fy, fz)
def g2(fy, fz): return np.array([fy - BBF[0], fz])
G1 = g2(-0.197, 0.369); C1 = g2(-0.556, 0.321); G2 = g2(-0.156, 0.572); C2 = g2(-0.263, 0.590)
A = g2(-0.626, 0.364); FE = g2(-0.190, 0.458); D = g2(-0.091, 0.590); FAX = g2(0.6285, 0.357)
HEAD = g2(0.275, 0.925)
PUL1 = g2(-0.594, 0.306); PUL2 = g2(-0.634, 0.254)


def classify(base, i, mats, f, c):
    """node for one loose part. i = suffix number, c = (fy, fz) centre"""
    if base == "Frame":
        if i in (7, 8): return "swing"
        if i in (9, 10): return "seatstay"
        if i in (5, 6): return "rocker"
        return "frame"
    if base == "Frame_Bearings": return "seatstay" if i in (1, 4, 5, 6) else "frame"
    if base == "Shock": return "fork_lower" if i in (15, 16, 23, 24, 25) else "steer"
    if base == "Damper":
        if i == 10: return "shock_spring"
        if i == 4: return "steer"
        dF = math.hypot(c[0] - (-0.190), c[1] - 0.458); dD = math.hypot(c[0] - (-0.091), c[1] - 0.590)
        return "shock_body" if dF < dD else "shock_shaft"
    if base == "Brakes":
        if i in (0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 14, 15): return "seatstay"
        return "fork_lower"
    if base == "Lines": return "steer" if i == 2 else "frame"
    if base in ("Brake_levers", "Stem", "Handlebars", "Grips"): return "steer"
    if base in ("Seat", "Seatpost", "Guard"): return "frame"
    if base == "Derailleur": return "seatstay" if c[0] < -0.5 else "steer"
    if base in ("Cranks", "Pedals"): return "crank"
    return None


def matname(base, i, src, f, c):
    """the game material for a source material"""
    if base == "Frame":
        if src in ("Material.001", "Material.015", "Material.018"): return "chrome" if i in (3, 4) else "paint"
        return "chrome" if src == "Material.005" else "black"
    if base == "Frame_Bearings": return "chrome"
    if base == "Shock": return "gold" if i in (19, 20, 21, 22) else "black"
    if base == "Damper": return "gold" if i == 10 else "black"
    if base == "Grips": return "rubber" if src == "Material.012" else "black"
    if base == "Seat": return "plastic" if src == "Material.007" else "black"
    if base == "Pedals": return "plastic" if src == "Material.019" else "black"
    return "black"


def to_game(p):   # (fx, fy, fz) -> game, BB at the origin
    return np.stack([p[..., 1] - BBF[0], p[..., 2], p[..., 0]], -1)


parts = {}   # node -> list of (pos(tri*3,3), nrm, matname)
CROWN_CENTERS = []   # the two crowns (Shock.012 lower, .013 upper)
lib = {"fork": [], "cranks": [], "cockpit": [], "brakes": [], "derail": [], "rcal": [], "saddle": []}
for o in list(bpy.data.objects):
    if o.type != 'MESH' or len(o.data.polygons) == 0: continue
    base = o.name.split(".")[0]
    i = int(o.name.split(".")[1]) if "." in o.name else 0
    vs = np.empty(len(o.data.vertices) * 3); o.data.vertices.foreach_get("co", vs); vs = vs.reshape(-1, 3)
    mw = np.array(o.matrix_world); wv = vs @ mw[:3, :3].T + mw[:3, 3]
    c = ((wv[:, 1].min() + wv[:, 1].max()) / 2, (wv[:, 2].min() + wv[:, 2].max()) / 2)
    used = {p.material_index for p in o.data.polygons}   # the slots are shared by every split part
    src = sorted({o.data.materials[k].name for k in used if k < len(o.data.materials) and o.data.materials[k]})
    f = len(o.data.polygons)
    node = classify(base, i, src, f, c)
    if node is None: continue
    P, L, N, mi, names = extract(o)
    npoly = len(mi)
    L = L.reshape(npoly, 3); N = N.reshape(npoly, 3, 3)
    pos = to_game(P[L].reshape(-1, 3)); nrm = to_game(N.reshape(-1, 3))
    # winding: the FBX -> game map is a proper rotation, so it stays counter-clockwise
    for k in sorted(set(mi.tolist())):
        sel = np.repeat(mi == k, 3)
        mn = matname(base, i, names[k] if k < len(names) else "", f, c)
        parts.setdefault(node, []).append((pos[sel], nrm[sel], mn))
        entry = (node, pos[sel], nrm[sel], mn)
        if base == "Shock": lib["fork"].append(entry)
        if base == "Brakes" and node == "fork_lower": lib["fork"].append(entry)
        if base == "Seat": lib["saddle"].append(entry)
        if base == "Brakes" and i in (0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 14, 15): lib["rcal"].append(entry)   # the rear caliper (not its hose)
        if base == "Shock" and i in (12, 13) and len(CROWN_CENTERS) < 2: CROWN_CENTERS.append(((pos[:, :2].min(0) + pos[:, :2].max(0)) / 2))
        if node == "crank": lib["cranks"].append(entry)
        if base == "Derailleur" and node == "seatstay": lib["derail"].append(entry)
        if node == "steer" and base != "Shock": lib["cockpit"].append(entry)
        if base == "Brakes": lib["brakes"].append(entry)

print("nodes:", {k: sum(len(p[0]) // 3 for p in v) for k, v in parts.items()})

# ---------------------------------------------------------------- steer axis from the stanchions
sp = np.concatenate([a[0] for a in parts["steer"] if a[2] == "gold"])[:, :2]
cen = sp.mean(0); u, s, vt = np.linalg.svd(sp - cen, full_matrices=False)
axis = vt[0] if vt[0][1] > 0 else -vt[0]
axis = axis / np.linalg.norm(axis)
SP = cen + axis * np.dot(HEAD - cen, axis)       # steer pivot: on the axis, level with the head tube
print("steer axis", axis, "angle from vertical", math.degrees(math.atan2(-axis[0], axis[1])), "pivot", SP)

# ---------------------------------------------------------------- linkage check (as suspension.gd)
def solve(phi, prev):
    lCS = np.linalg.norm(C1 - G1); lR = np.linalg.norm(C2 - G2); lSS = np.linalg.norm(C2 - C1)
    c1 = G1 + lCS * np.array([math.cos(phi), math.sin(phi)])
    d = np.linalg.norm(c1 - G2)
    if d > lR + lSS or d < abs(lR - lSS): return None
    a = (lR * lR - lSS * lSS + d * d) / (2 * d); h = math.sqrt(max(0, lR * lR - a * a))
    e = (c1 - G2) / d; m = G2 + a * e
    s1 = m + h * np.array([-e[1], e[0]]); s2 = m - h * np.array([-e[1], e[0]])
    c2 = s1 if np.linalg.norm(s1 - prev) < np.linalg.norm(s2 - prev) else s2
    ss = math.atan2(*(c2 - c1)[::-1]); ss0 = math.atan2(*(C2 - C1)[::-1])
    rk = math.atan2(*(c2 - G2)[::-1]); rk0 = math.atan2(*(C2 - G2)[::-1])
    rot = lambda v, a: np.array([v[0] * math.cos(a) - v[1] * math.sin(a), v[0] * math.sin(a) + v[1] * math.cos(a)])
    return {"A": c1 + rot(A - C1, ss - ss0), "D": G2 + rot(D - G2, rk - rk0), "C2": c2}
phi0 = math.atan2(*(C1 - G1)[::-1]); L0 = np.linalg.norm(D - FE)
rows = []
for sgn in (-1, 1):
    prev = C2
    for k in range(0, 300):
        p = solve(phi0 + sgn * k * 0.002, prev)
        if p is None: break
        prev = p["C2"]; rows.append((p["A"][1] - A[1], L0 - np.linalg.norm(p["D"] - FE)))
rows.sort()
rise = np.array([r[0] for r in rows]); stroke = np.array([r[1] for r in rows])
print("linkage: axle rise %.3f..%.3f m, shock stroke %.3f..%.3f m (shock length %.3f)" % (rise.min(), rise.max(), stroke.min(), stroke.max(), L0))
up = stroke[np.argmin(abs(rise - 0.14))]; dn = stroke[np.argmin(abs(rise + 0.06))]
print("at the game's travel limits (rise +0.14 / -0.06): stroke %.3f / %.3f" % (up, dn))

z3 = lambda v: np.array([v[0], v[1], 0.0])
dirv = (D - FE) / np.linalg.norm(D - FE)
spr = np.concatenate([p[0] for p in parts["shock_spring"]])[:, :2]
proj = (spr - FE) @ dirv
seat0 = FE + dirv * proj.min(); spring_len = float(proj.max() - proj.min())
print("spring %.3f long, shock eye to eye %.3f" % (spring_len, np.linalg.norm(D - FE)))
PIV = {"frame": np.zeros(3), "steer": z3(SP), "fork_lower": z3(FAX), "wheel_front": z3(FAX), "swing": z3(G1),
       "seatstay": z3(C1), "wheel_rear": z3(A), "rocker": z3(G2), "shock_body": z3(FE), "shock_spring": z3(seat0), "shock_shaft": z3(D),
       "crank": z3(g2(*BBF)),   # the crank turns about the bottom bracket
       "pulley_1": z3(PUL1), "pulley_2": z3(PUL2)}   # derailleur pulleys: the chain path
PARENT = {"fork_lower": "steer", "wheel_front": "fork_lower", "wheel_rear": "seatstay", "pulley_1": "seatstay", "pulley_2": "seatstay",
          "shock_spring": "shock_body"}
tri = [(np.array([[0, 0, 0], [0.01, 0, 0], [0, 0.01, 0]], float), np.tile([0, 0, 1.0], (3, 1)), "chrome")]   # wheel placeholder
nodes = []
for name in ("frame", "steer", "fork_lower", "wheel_front", "swing", "seatstay", "wheel_rear", "pulley_1", "pulley_2", "rocker", "shock_body", "shock_spring", "shock_shaft", "crank"):
    par = PARENT.get(name)
    pp = PIV[par] if par else np.zeros(3)
    nd = {"name": name, "parent": par, "t": PIV[name] - pp, "origin": PIV[name], "local": name.startswith("wheel_"),
          "parts": (tri + ROTORS[name]) if name.startswith("wheel_") else parts.get(name, [])}
    if name == "shock_spring": nd["rotz"] = math.atan2(dirv[1], dirv[0]) - math.pi / 2
    nodes.append(nd)
rear = {"travel": 0.2, "sag": 0.3, "G1": G1.tolist(), "G2": G2.tolist(), "C1": C1.tolist(), "C2": C2.tolist(),
        "A": A.tolist(), "D": D.tolist(), "FE": FE.tolist(), "springLen": spring_len}
extras = {"steerAxis": [float(axis[0]), float(axis[1]), 0.0], "wheelRadius": float(FAX[1]), "wheelRadiusRear": float(A[1]),
          "wheelbase": float(FAX[0] - A[0]), "bbToRearAxle": float(0.0 - A[0]), "noBarMod": True, "noDecals": True,
          "chain": {"ring_r": 0.067, "ring_z": 0.0685, "cog_z": 0.055, "pulley_r": 0.024, "pulley_z": 0.09},
          "suspension": {"fork": {"travel": 0.2, "sag": 0.2}, "rear": rear}}
write_glb(os.path.join(OUT, "fuzz.glb"), nodes, extras)

# ---------------------------------------------------------------- reusable parts (their own origin)
def lib_glb(fname, key, origin, root, nodename):
    es = lib[key]
    if not es: return
    write_glb(os.path.join(OUT, "parts", fname), [{"name": nodename, "parent": None, "t": [0, 0, 0], "origin": origin,
              "parts": [(e[1], e[2], e[3]) for e in es]}], {"source": "NS Fuzz FBX", "origin": "bike coordinates, BB at 0"}, root)

# the fork alone (crown + stanchions, lowers + front caliper) for tools/make_forks.py, which fits it to the stock frame
crown_c = np.mean(CROWN_CENTERS, axis=0)
fork_nodes = [{"name": "fork_crown", "parent": None, "t": [0, 0, 0], "origin": z3(SP),
               "parts": [(e[1], e[2], e[3]) for e in lib["fork"] if e[0] == "steer"]},
              {"name": "fork_lower", "parent": None, "t": (z3(FAX) - z3(SP)).tolist(), "origin": z3(FAX),
               "parts": [(e[1], e[2], e[3]) for e in lib["fork"] if e[0] == "fork_lower"]}]
write_glb(os.path.join(OUT, "parts", "fuzz_fork.glb"), fork_nodes,
          {"steerAxis": [float(axis[0]), float(axis[1])], "crownMid": (crown_c - SP).tolist(), "axle": (FAX - SP).tolist()}, "fork")

lib_glb("fuzz_cranks.glb", "cranks", z3(g2(*BBF)), "cranks", "crank")
lib_glb("fuzz_cockpit.glb", "cockpit", z3(SP), "cockpit", "cockpit")


# the saddle alone (rails + cover), origin = under its middle at the rail bottom (where the post clamps) for tools/make_forks.py
if lib["saddle"]:
    sp = np.concatenate([e[1] for e in lib["saddle"]])
    org = np.array([(sp[:, 0].min() + sp[:, 0].max()) / 2, sp[:, 1].min() + 0.012, 0.0])
    write_glb(os.path.join(OUT, "parts", "fuzz_saddle.glb"), [{"name": "saddle", "parent": None, "t": [0, 0, 0], "origin": org,
              "parts": [(e[1], e[2], e[3]) for e in lib["saddle"]]}], None, "saddle")
# the rear brake caliper alone (relative to the rear axle) for tools/make_forks.py
if lib["rcal"]:
    main = max(lib["rcal"], key=lambda e: len(e[1]))
    mc = (main[1][:, :2].min(0) + main[1][:, :2].max(0)) / 2 - A
    write_glb(os.path.join(OUT, "parts", "fuzz_caliper_rear.glb"), [{"name": "caliper", "parent": None, "t": [0, 0, 0], "origin": z3(A),
              "parts": [(e[1], e[2], e[3]) for e in lib["rcal"]]}], {"center": mc.tolist()}, "caliper")
lib_glb("fuzz_derailleur.glb", "derail", z3(A), "derailleur", "derailleur")
lib_glb("fuzz_brakes.glb", "brakes", np.zeros(3), "brakes", "brakes")
