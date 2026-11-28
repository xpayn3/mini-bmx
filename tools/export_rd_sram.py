"""Export the SRAM Force eTap AXS rear derailleur model from the bike HDA (bike_skeleton.hda, section
model_rdmech.bgeo.sc) as rigid groups for the game's drivetrain sim, plus its measured kinematics.

The HDA poses this model with three degrees of freedom (its rderail_pose wrangle) and the generator's derailleur
solve (B-tension set once on the biggest cog, slant-parallelogram angle per cog plane, fixed-length chain, cage
angle solved to close it). The game does the same solve itself every frame (unity: Game/Bike/RearDerailleur.cs),
so any cassette / chainring works: nothing here is baked per gear.

Groups (the model's own FBX hierarchy, as the HDA reads it):
  fixed    Mount, Nut                          bolted to the hanger, never moves
  body     Tob__part_ (+ battery, pin bosses)  the B-knuckle: turns on the B-bolt (model z axis through the origin)
  link_top upper_arm (+ its bolt)              parallelogram arm, turns on its pin on the body
  link_bot lower_arm (+ its bolt)
  knuckle  egine_and_pivot (+ motor)           the P-knuckle: TRANSLATES (true parallelogram)
  cage     Jockey_hanger (+ bolt)              turns on the top jockey's axle
The model's jockey wheels are left out (14.5k polygons each): the game draws light 12T pulleys on the same centres,
as the HDA does.

Output (model frame = the bike's axes, +x forward, +y up, +z outboard, METRES; each group node sits at its pivot):
  godot/assets/parts/rd_sram.glb       (Godot's copy, for later)
  unity/Assets/Runout/Art/Models/Bikes/rd_sram.glb + rd_sram.extras.txt

Run with Houdini 21 hython, from the repo root:
  & "C:\\Program Files\\Side Effects Software\\Houdini 21.0.440\\bin\\hython.exe" tools\\export_rd_sram.py
"""
import os, sys, shutil
import numpy as np
import hou

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)
sys.path.insert(0, HERE)
from bike_glb import write_glb

HDA = os.path.expanduser(r"~\Documents\houdini21.0\otls\bike_skeleton.hda")
OUT_G = os.path.join(REPO, "godot", "assets", "parts", "rd_sram.glb")
OUT_U = os.path.join(REPO, "unity", "Assets", "Runout", "Art", "Models", "Bikes")
MM = 0.001

# ---- the model's kinematics, as the HDA measured them off the file (bike_skeleton: rd_axis() ... rd_mount_in()), mm
AXIS = np.array([0.0, -0.731, 0.682]); AXIS /= np.linalg.norm(AXIS)
PIN_TOP = np.array([-18.13, -54.31, 25.88])
PIN_BOT = np.array([-22.54, -62.32, 9.54])
LINK = np.array([43.59, 15.43, 5.70])
U0 = np.array([35.07, -51.90, -26.30])          # top jockey, as exported
CAGE_LEN = 70.01                                # jockey to jockey
CAGE_REST = 252.17                              # deg, top -> bottom jockey as exported
MOUNT_IN = -9.0                                 # the Mount's inboard face, model z
JOCKEY_T = 12                                   # SRAM's X-Sync pulleys, top and bottom
# ---- the DH frame's numbers, from cooking the bike HDA (detail attributes; tools/export_dh.py's frame)
REAR = (-442.29403, 355.09002)                  # rear axle, bike frame mm (= dh.glb)
HANGER_LEN, HANGER_ANG = 32.0, 255.0            # axle -> B-bolt
ORIGIN_Z = 77.5                                 # rd_zw0: the model origin's z (mount on the hanger), mm
DERAIL_GAP = 11.0                               # chain gap to the top pulley, set on the biggest cog
CAGE_MIN, CAGE_MAX = 190.0, 320.0               # the cage's swing, deg
CHAIN_SLACK = 2                                 # links added to the big-big sizing (HDA chain_slack default)
COG_Z0, COG_PITCH = 63.22, 3.74                 # the hub's smallest-cog plane and the 11-speed pitch the HDA uses
RING_Z = 52.0
SEATSTAY = (-416.694, 340.59)                   # dh.glb's seatstay node (the dropout the hanger is on)

GROUP_OF = [  # path component -> group (first match from the deepest)
    ("Jockey_hanger", "cage"), ("egine_and_pivot", "knuckle"), ("upper_arm", "link_top"),
    ("lower_arm", "link_bot"), ("Tob__part_", "body"), ("Mount", "fixed"), ("Nut", "fixed")]
PIVOT = {"fixed": np.zeros(3), "body": np.zeros(3), "link_top": PIN_TOP, "link_bot": PIN_BOT,
         "knuckle": np.zeros(3), "cage": U0}
# materials (the game's names: BikeMaterialSet dresses them): the HDA's colours by part
def material(path):
    if "Battery" in path or "Твердое_тело" in path: return "plastic"      # battery, motor housing
    if "Bolt" in path or "Nut" in path: return "chrome"
    if path.endswith("/Mount") or "Jockey_hanger" in path: return "black"   # mount + cage plates: dark metal
    return "chrome"                                                         # the body + arms: silver


def main():
    d = hou.hda.definitionsInFile(HDA)[0]
    tmp = os.path.join(os.environ.get("TEMP", "."), "rdmech_export.bgeo.sc")
    open(tmp, "wb").write(d.sections()["model_rdmech.bgeo.sc"].binaryContents())
    # triangulate (the file has polygons up to n-gons)
    sop = hou.node("/obj").createNode("geo", "rd_export")
    f = sop.createNode("file"); f.parm("file").set(tmp)
    blast = sop.createNode("blast"); blast.setInput(0, f)
    blast.parm("group").set('@name="*Jockey_gear*"'); blast.parm("grouptype").set("prims")
    div = sop.createNode("divide"); div.setInput(0, blast); div.parm("convex").set(1); div.parm("numsides").set(3)
    # light: decimated like the old drivetrain export (RD_REDUCE_PCT, default 14 % of the triangles), smooth normals
    # rebuilt with a cusp (the edges of the machined parts stay sharp)
    red = sop.createNode("polyreduce::2.0"); red.setInput(0, div)
    red.parm("percentage").set(float(os.environ.get("RD_REDUCE_PCT", "14")))
    nrm = sop.createNode("normal"); nrm.setInput(0, red)
    nrm.parm("type").set(0)            # vertex normals
    nrm.parm("cuspangle").set(40.0)
    nrm.cook(force=True)
    g = nrm.geometry()
    P = np.array(g.pointFloatAttribValues("P"), np.float64).reshape(-1, 3)
    has_n = g.findVertexAttrib("N") is not None
    parts = {}
    for pr in g.prims():
        vs = pr.vertices()
        if len(vs) != 3: continue
        path = pr.attribValue("name")
        comps = path.split("/")
        grp = None
        for key, gname in GROUP_OF:
            if key in comps: grp = gname; break
        if grp is None: continue
        mat = material(path)
        tri = np.array([P[v.point().number()] for v in vs])
        if has_n: nrm = np.array([v.attribValue("N") for v in vs], np.float64)
        else:
            n = np.cross(tri[1] - tri[0], tri[2] - tri[0]); n /= max(np.linalg.norm(n), 1e-12); nrm = np.array([n, n, n])
        parts.setdefault(grp, {}).setdefault(mat, ([], []))
        parts[grp][mat][0].append(tri); parts[grp][mat][1].append(nrm)
    nodes = []
    for grp in ("fixed", "body", "link_top", "link_bot", "knuckle", "cage"):
        piv = PIVOT[grp] * MM
        nd = {"name": grp, "parent": None, "t": piv, "origin": piv, "parts": []}
        for mat, (tris, nrms) in parts.get(grp, {}).items():
            pos = np.concatenate(tris) * MM
            nr = np.concatenate(nrms)
            # Houdini winds clockwise seen from the front; glTF wants counter-clockwise: swap two corners
            pos = pos.reshape(-1, 3, 3)[:, [0, 2, 1]].reshape(-1, 3)
            nr = nr.reshape(-1, 3, 3)[:, [0, 2, 1]].reshape(-1, 3)
            nd["parts"].append((pos, nr, mat))
        print(grp, sum(len(p[0]) // 3 for p in nd["parts"]), "tris")
        nodes.append(nd)
    os.makedirs(os.path.dirname(OUT_G), exist_ok=True)
    write_glb(OUT_G, nodes, root="rd_sram")
    shutil.copyfile(OUT_G, os.path.join(OUT_U, "rd_sram.glb"))
    # the kinematics + this frame's numbers, for the game's solve (metres)
    bk = (REAR[0] + np.cos(np.radians(HANGER_ANG)) * HANGER_LEN, REAR[1] + np.sin(np.radians(HANGER_ANG)) * HANGER_LEN)
    L = []
    def v(k, a): L.append(k + "=" + ",".join("%.6f" % x for x in np.atleast_1d(a)))
    v("axis", AXIS); v("pinTop", PIN_TOP * MM); v("pinBot", PIN_BOT * MM); v("link", LINK * MM); v("u0", U0 * MM)
    v("cageLen", CAGE_LEN * MM); v("cageRestDeg", CAGE_REST); v("jockeyTeeth", JOCKEY_T)
    v("origin", [bk[0] * MM, bk[1] * MM, ORIGIN_Z * MM])
    v("originSeatstay", [(bk[0] - SEATSTAY[0]) * MM, (bk[1] - SEATSTAY[1]) * MM, ORIGIN_Z * MM])
    v("gap", DERAIL_GAP * MM); v("cageMinDeg", CAGE_MIN); v("cageMaxDeg", CAGE_MAX); v("chainSlack", CHAIN_SLACK)
    v("cogZ0", COG_Z0 * MM); v("cogPitch", COG_PITCH * MM); v("ringZ", RING_Z * MM)
    open(os.path.join(OUT_U, "rd_sram.extras.txt"), "w").write("\n".join(L) + "\n")
    print("wrote rd_sram.extras.txt")


main()
