"""Brake rotors from the YT Tues and NS Fuzz FBX files for the garage's rotor choice.
  blender -b -P tools/export_rotors.py -- "YT _Tues.fbx" FuzzFBX.fbx
Writes godot/assets/forks/rotor_tues.glb / rotor_fuzz.glb: nodes "rotor_front" / "rotor_rear", the disc + its carrier (+ bolts),
relative to the axle (the game's wheel-local axes: x forward, y up, the axle along z), moved sideways onto the stock rotors' planes
(dh.glb: front z -0.0457, rear z -0.0561) so they sit on the generated hubs. BikeRig swaps them into the wheels' "rotor" meshes
(which keep their heat-glow shader).
"""
import bpy, sys, os, math
import numpy as np
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from bike_glb import extract, write_glb

TUES, FUZZ = sys.argv[-2], sys.argv[-1]
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "godot", "assets", "forks")
os.makedirs(OUT, exist_ok=True)
PLANE = {"front": -0.0457, "rear": -0.0561}   # the stock rotors' lateral planes (wheel-local z)
RATIO = 0.1                                     # the discs are 40-80k faces each: a tenth keeps their holes round enough


def split(names):
    for name in names:
        o = bpy.data.objects[name]
        bpy.context.view_layer.objects.active = o
        for ob in bpy.data.objects: ob.select_set(False)
        o.select_set(True)
        bpy.ops.object.mode_set(mode='EDIT'); bpy.ops.mesh.select_all(action='SELECT')
        bpy.ops.mesh.separate(type='LOOSE'); bpy.ops.object.mode_set(mode='OBJECT')


def world(o):
    V = np.empty(len(o.data.vertices) * 3); o.data.vertices.foreach_get("co", V); V = V.reshape(-1, 3)
    mw = np.array(o.matrix_world); return V @ mw[:3, :3].T + mw[:3, 3]


def collect(pick, axle_of):
    """pick(object, name, centre, extent) -> 'front' / 'rear' / None; returns {'front': [...], 'rear': [...]} parts relative to the axle"""
    out = {"front": [], "rear": []}
    for o in list(bpy.data.objects):
        if o.type != 'MESH' or len(o.data.polygons) == 0: continue
        W = world(o); c = (W.min(0) + W.max(0)) / 2; e = W.max(0) - W.min(0)
        side = pick(o.name, c, e, len(o.data.polygons))
        if side is None: continue
        P, L, N, mi, names = extract(o, RATIO if len(o.data.polygons) > 3000 else 1.0)
        n = len(mi); L = L.reshape(n, 3); N = N.reshape(n, 3, 3)
        ax = axle_of(side)                                   # (fy, fz) of this wheel's axle, plus the plate centre x
        shift = PLANE[side] - c_plate[side]
        pos = P[L].reshape(-1, 3); nrm = N.reshape(-1, 3)
        pos = np.stack([pos[:, 1] - ax[0], pos[:, 2] - ax[1], pos[:, 0] + shift], 1)
        nrm = np.stack([nrm[:, 1], nrm[:, 2], nrm[:, 0]], 1)
        out[side].append((pos, nrm, "chrome"))
    return out


def write(fid, parts):
    nodes = [{"name": "rotor_front", "parent": None, "t": [0, 0, 0], "origin": np.zeros(3), "parts": parts["front"]},
             {"name": "rotor_rear", "parent": None, "t": [0, 0, 0], "origin": np.zeros(3), "parts": parts["rear"]}]
    write_glb(os.path.join(OUT, "rotor_%s.glb" % fid), nodes, None, "rotors")


# ---- Tues: the discs are loose parts of the wheel meshes (thin along x, ~200 mm across, + the carrier spider of the same size class)
bpy.ops.wm.read_factory_settings(use_empty=True); bpy.ops.import_scene.fbx(filepath=TUES)
split(["Wheel_F", "Wheel_R"])
AX = {"front": (0.644, 0.361), "rear": (-0.629, 0.360)}
c_plate = {"front": -0.041, "rear": -0.065}
def pick_t(name, c, e, f):
    if not name.startswith("Wheel_") or e[0] > 0.006 or not (0.14 < e[1] < 0.22): return None
    if abs(c[1] - AX["front"][0]) < 0.02 and abs(c[2] - AX["front"][1]) < 0.02: return "front"
    if abs(c[1] - AX["rear"][0]) < 0.02 and abs(c[2] - AX["rear"][1]) < 0.02: return "rear"
write(("tues"), collect(pick_t, lambda s: AX[s]))

# ---- Fuzz: Brake_Discs holds both discs, their carriers and bolts
bpy.ops.wm.read_factory_settings(use_empty=True); bpy.ops.import_scene.fbx(filepath=FUZZ)
split(["Brake_Discs"])
AX = {"front": (0.629, 0.357), "rear": (-0.625, 0.365)}
c_plate = {"front": -0.056, "rear": -0.062}
def pick_f(name, c, e, f):
    if not name.startswith("Brake_Discs"): return None
    if abs(c[2] - 0.357) < 0.2 and abs(c[1] - AX["front"][0]) < 0.12 and c[1] > 0: return "front"
    if c[1] < 0 and abs(c[1] - AX["rear"][0]) < 0.12: return "rear"
write("fuzz", collect(pick_f, lambda s: AX[s]))
