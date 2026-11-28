"""Megascans downloads (Fab, the user's claimed library: Fab Standard licence, may ship inside the game, the files may
NOT be redistributed: the output is gitignored) -> game-ready near / far meshes for Godot.

    blender -b --factory-startup -P tools/make_scan_plants.py -- <dir of unzipped downloads> <godot/assets/plants_scan>
then  python tools/pack_scan_plant_textures.py <same dir> <godot/assets/plants_scan>   (textures; system Python + PIL)
then  import in Godot (BC7 + mipmaps: compress/mode=2, see ScanPlants).

One sub-folder per download, any of the forms Fab gives:
  * FBX per LOD: <Name>_<id>_<Q>_<id>_Var<X>_LOD<n>.fbx (+ <Name>_<id>_<Q>_<2K>_<Map>.jpg)
  * one FBX (a scanned rock / cactus)
  * glTF "UE" package: <id>_tier_N.gltf (+ standard/<id>_tier_N_nonUE.gltf) with nodes SM_<id>_Var<X>[_LOD<n>]
  * glTF / glb of one scanned mesh (rocks, stumps), textures beside it or embedded (saved out as src/img_<map>.png)
Per variant: <out>/<id>/<X>_near.glb and <X>_far.glb (y up, metres, base at y = 0, no materials / vertex colours).
Leafy plants: near = the finest LOD under NEAR_MAX triangles (else LOD2 decimated to it), far = Megascans' own billboard
(LOD3, `bb`; `flat` = a single card: the game turns it to the camera) or, without one, a decimated LOD. Solid scans: near /
far decimated from the finest mesh, re-centred on their footprint. <out>/<id>/info.json lists kind, variants, sizes, maps.
"""
import bpy, glob, json, os, re, sys

NEAR_MAX = 5000
FAR_MAX = 700
SOLID_NEAR = 3000
SOLID_FAR = 450

args = sys.argv[sys.argv.index("--") + 1:]
SRC, OUT = os.path.abspath(args[0]), os.path.abspath(args[1])
ONLY = args[2] if len(args) > 2 else ""


def plant_id(folder):
    n = os.path.basename(folder).lower()
    n = re.sub(r" \(\d+\)$", "", n)
    n = n.replace("grass_clumps_rbojr", "grass_clumps_b_x")   # (two downloads of the same name)
    n = re.sub(r"_(ue|gltf)?_?(low|mid|high|2k|4k)$", "", n)
    n = re.sub(r"_(ue|gltf)$", "", n)
    n = re.sub(r"_[a-z0-9]{5,10}$", "", n) if not n.endswith("_x") else n[:-2]   # the Megascans id
    return n


def tris(o):
    o.data.calc_loop_triangles()
    return len(o.data.loop_triangles)


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def import_file(path):
    before = set(bpy.data.objects)
    if path.lower().endswith(".fbx"):
        bpy.ops.import_scene.fbx(filepath=path)
    else:
        bpy.ops.import_scene.gltf(filepath=path)
    return [o for o in bpy.data.objects if o not in before and o.type == 'MESH']


def baked_copy(objs):
    """one new object: the given meshes joined, transforms applied"""
    copies = []
    for o in objs:
        c = o.copy()
        c.data = o.data.copy()
        c.parent = None
        c.matrix_world = o.matrix_world.copy()
        bpy.context.scene.collection.objects.link(c)
        copies.append(c)
    bpy.ops.object.select_all(action='DESELECT')
    for c in copies:
        c.select_set(True)
    bpy.context.view_layer.objects.active = copies[0]
    if len(copies) > 1:
        bpy.ops.object.join()
    o = bpy.context.view_layer.objects.active
    o.select_set(True)
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    return o


def decimate(o, target):
    t = tris(o)
    if t <= target:
        return
    m = o.modifiers.new("dec", 'DECIMATE')
    m.decimate_type = 'COLLAPSE'
    m.ratio = max(target / t, 0.0005)
    m.use_collapse_triangulate = True
    m.delimit = {'UV'}
    bpy.context.view_layer.objects.active = o
    bpy.ops.object.modifier_apply(modifier=m.name)


def export(o, path, shift):
    me = o.data
    while me.color_attributes:
        me.color_attributes.remove(me.color_attributes[0])
    while len(me.uv_layers) > 1:   # (UE packages carry a lightmap UV: only the first is used)
        me.uv_layers.remove(me.uv_layers[-1])
    me.materials.clear()
    for v in me.vertices:
        v.co.x -= shift[0]; v.co.y -= shift[1]; v.co.z -= shift[2]
    bpy.ops.object.select_all(action='DESELECT')
    o.select_set(True)
    bpy.ops.export_scene.gltf(filepath=path, export_format='GLB', use_selection=True, export_materials='NONE',
                              export_yup=True, export_apply=True)
    n = tris(o)
    bpy.data.objects.remove(o, do_unlink=True)
    return n


def bbox(o):
    vs = [o.matrix_world @ v.co for v in o.data.vertices]
    lo = [min(v[i] for v in vs) for i in range(3)]
    hi = [max(v[i] for v in vs) for i in range(3)]
    return lo, hi


def save_embedded(dst):
    """images packed in a glb: written out, named by what the material uses them for"""
    use = {}
    for m in bpy.data.materials:
        if not m.use_nodes:
            continue
        for n in m.node_tree.nodes:
            if n.type != 'TEX_IMAGE' or not n.image:
                continue
            kind = "base"
            for l in n.outputs[0].links:
                to = l.to_node
                if to.type == 'NORMAL_MAP':
                    kind = "normal"
                elif to.type == 'SEPRGB' or to.type == 'SEPARATE_COLOR':
                    kind = "orm"
                elif to.type == 'BSDF_PRINCIPLED' and l.to_socket.name in ('Roughness', 'Metallic'):
                    kind = "orm"
            use[n.image.name] = kind
    out = {}
    os.makedirs(os.path.join(dst, "src"), exist_ok=True)
    open(os.path.join(dst, "src", ".gdignore"), "w").close()   # (packer inputs only: Godot must not import them)
    for im in bpy.data.images:
        if im.name not in use or use[im.name] in out:
            continue
        p = os.path.join(dst, "src", "img_%s.png" % use[im.name])
        im.filepath_raw = p
        im.file_format = 'PNG'
        im.save()
        out[use[im.name]] = os.path.basename(p)
    return out


def handle(folder):
    pid = plant_id(folder)
    dst = os.path.join(OUT, pid)
    os.makedirs(dst, exist_ok=True)
    reset()
    files = sorted(glob.glob(os.path.join(folder, "*.fbx")))
    gl = sorted(glob.glob(os.path.join(folder, "standard", "*_nonUE.gltf"))) or \
        sorted(glob.glob(os.path.join(folder, "*.gltf")) + glob.glob(os.path.join(folder, "*.glb")))
    leaf = bool(glob.glob(os.path.join(folder, "*Opacity*")) or glob.glob(os.path.join(folder, "Textures", "*B-O*")))
    groups = {}   # var -> {lod: [objects]}
    maps = {}
    if files:
        for f in files:
            m = re.search(r"_Var([A-Z])_LOD(\d)\.fbx$", f)
            objs = import_file(f)
            if m:
                groups.setdefault(m.group(1), {})[int(m.group(2))] = objs
            else:
                groups.setdefault("A", {})[0] = objs
    elif gl:
        objs = import_file(gl[0])
        for o in objs:
            m = re.search(r"Var([A-Z])(?:_LOD(\d))?", o.name)
            if m:
                groups.setdefault(m.group(1), {}).setdefault(int(m.group(2) or 0), []).append(o)
            else:
                lm = re.search(r"LOD(\d)", o.name)
                groups.setdefault("A", {}).setdefault(int(lm.group(1)) if lm else 0, []).append(o)
        if gl[0].endswith(".glb"):
            maps = save_embedded(dst)
    else:
        return
    info = {"plant": pid, "kind": "leaf" if leaf else "solid", "variants": {}, "maps": maps,
            "ue": bool(glob.glob(os.path.join(folder, "Textures", "T_*")))}
    for var, lods in sorted(groups.items()):
        ref = baked_copy(lods[min(lods)])
        lo0, hi0 = bbox(ref)
        bpy.data.objects.remove(ref, do_unlink=True)
        shift = ((lo0[0] + hi0[0]) / 2, (lo0[1] + hi0[1]) / 2, lo0[2]) if not leaf else (0.0, 0.0, lo0[2])
        rec = {"size": [round(hi0[0] - lo0[0], 3), round(hi0[2] - lo0[2], 3), round(hi0[1] - lo0[1], 3)]}
        if leaf:
            pick = None
            ks = sorted(l for l in lods if l <= 2)
            for i, k in enumerate(ks):
                o = baked_copy(lods[k])
                t = tris(o)
                if t <= NEAR_MAX:
                    if t < NEAR_MAX / 8 and i > 0:   # (a far-coarser LOD under the budget: decimate the finer one instead)
                        bpy.data.objects.remove(o, do_unlink=True)
                        o = baked_copy(lods[ks[i - 1]])
                        decimate(o, NEAR_MAX)
                    pick = o
                    break
                bpy.data.objects.remove(o, do_unlink=True)
            if pick is None:
                pick = baked_copy(lods[ks[-1]])
                decimate(pick, NEAR_MAX)
            rec["near"] = export(pick, os.path.join(dst, "%s_near.glb" % var), shift)
            if 3 in lods:
                o = baked_copy(lods[3])
                lo, hi = bbox(o)
                w = max(hi[0] - lo[0], hi[1] - lo[1])
                rec["bb"] = True
                rec["flat"] = min(hi[0] - lo[0], hi[1] - lo[1]) < 0.02 * max(w, 0.01)
                rec["far"] = export(o, os.path.join(dst, "%s_far.glb" % var), shift)
            else:
                o = baked_copy(lods[max(l for l in lods if l <= 2)])
                decimate(o, FAR_MAX)
                rec["far"] = export(o, os.path.join(dst, "%s_far.glb" % var), shift)
        else:
            for tag, tgt in (("near", SOLID_NEAR), ("far", SOLID_FAR)):
                o = baked_copy(lods[min(lods)])
                decimate(o, tgt)
                rec[tag] = export(o, os.path.join(dst, "%s_%s.glb" % (var, tag)), shift)
        info["variants"][var] = rec
        print("PLANT", pid, var, rec)
    with open(os.path.join(dst, "info.json"), "w") as fh:
        json.dump(info, fh, indent=1)


for folder in sorted(glob.glob(os.path.join(SRC, "*"))):
    if os.path.isdir(folder) and (not ONLY or ONLY in os.path.basename(folder)):
        handle(folder)
print("DONE")
