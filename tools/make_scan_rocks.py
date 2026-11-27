"""Makes godot/assets/rocks_scan/<id>_lod0.glb / <id>_lod1.glb (+ textures): light game rocks from Poly Haven rock scans (CC0).
Run inside Blender (5.x):
  blender --background --python tools/make_scan_rocks.py -- <dir with the downloaded glTF folders> <out dir>
Each scan mesh: transforms applied, centred on its footprint, scaled so its horizontal radius is 1 (the generated rocks'
convention: rock_gen.gd, colliders / domes fit), its lowest point at y = -0.12 (the foot sits in the ground), decimated to
LOD0 (~TRIS0 triangles) and LOD1 (~TRIS1), UVs kept (the scan's own textures map on). Textures are packed separately by
tools/make_scan_rock_textures.py (plain Python + PIL).
"""
import os
import sys
import bpy
import bmesh
from mathutils import Vector

TRIS0 = 1600
TRIS1 = 360
# asset -> list of (object name in the glTF, out id)
ASSETS = {
    "boulder_01": [("boulder_01", "boulder01")],
    "namaqualand_boulder_02": [("boulder_02", "nboulder02")],
    "rock_09": [("rock_09_LOD0", "rock09")],
    "namaqualand_stones_01": [("namaqualand_stones_01_" + c, "nstone_" + c) for c in "abcde"],
}

argv = sys.argv[sys.argv.index("--") + 1:]
SRC, OUT = argv[0], argv[1]
os.makedirs(OUT, exist_ok=True)


def clear():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def tri_count(ob):
    return sum(len(p.vertices) - 2 for p in ob.data.polygons)


def decimated_copy(ob, target):
    c = ob.copy()
    c.data = ob.data.copy()
    bpy.context.collection.objects.link(c)
    # weld split vertices first (some scans come with every triangle's corners apart: the collapse can't merge them)
    bm = bmesh.new()
    bm.from_mesh(c.data)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
    bm.to_mesh(c.data)
    bm.free()
    for _ in range(4):   # passes: a collapse can stop short on seams
        n = tri_count(c)
        if n <= target * 1.1:
            break
        m = c.modifiers.new("dec", "DECIMATE")
        m.decimate_type = "COLLAPSE"
        m.ratio = target / n
        m.use_collapse_triangulate = True
        bpy.context.view_layer.objects.active = c
        bpy.ops.object.modifier_apply(modifier="dec")
    return c


def export(ob, path):
    bpy.ops.object.select_all(action="DESELECT")
    ob.select_set(True)
    bpy.context.view_layer.objects.active = ob
    ob.data.materials.clear()
    bpy.ops.export_scene.gltf(filepath=path, use_selection=True, export_format="GLB", export_materials="NONE",
                              export_normals=True, export_texcoords=True, export_apply=True)


for asset, parts in ASSETS.items():
    clear()
    bpy.ops.import_scene.gltf(filepath=os.path.join(SRC, asset, asset + ".gltf"))
    for name, oid in parts:
        ob = bpy.data.objects.get(name)
        if ob is None:
            print("MISSING", asset, name, [o.name for o in bpy.data.objects])
            continue
        # bake the object's (and its parents') transforms into the mesh, then normalise
        ob.data = ob.data.copy()
        ob.data.transform(ob.matrix_world)
        ob.parent = None
        ob.matrix_world.identity()
        vs = [v.co for v in ob.data.vertices]
        minx = min(v.x for v in vs); maxx = max(v.x for v in vs)
        miny = min(v.y for v in vs); maxy = max(v.y for v in vs)
        minz = min(v.z for v in vs); maxz = max(v.z for v in vs)
        # Blender is Z up; the glTF exporter turns it back to Y up
        cx, cy = (minx + maxx) / 2, (miny + maxy) / 2
        r = max(((v.x - cx) ** 2 + (v.y - cy) ** 2) ** 0.5 for v in vs)
        s = 1.0 / r
        for v in ob.data.vertices:
            v.co = Vector(((v.co.x - cx) * s, (v.co.y - cy) * s, (v.co.z - minz) * s - 0.12))
        ob.data.update()
        h = (maxz - minz) * s
        for lod, target in ((0, TRIS0), (1, TRIS1)):
            c = decimated_copy(ob, target)
            bpy.ops.object.select_all(action="DESELECT")
            c.select_set(True)
            bpy.context.view_layer.objects.active = c
            bpy.ops.object.shade_smooth()
            export(c, os.path.join(OUT, "%s_lod%d.glb" % (oid, lod)))
            print("ROCK %s lod%d tris=%d height=%.2f (src %d tris)" % (oid, lod, tri_count(c), h, tri_count(ob)))
            bpy.data.objects.remove(c)
