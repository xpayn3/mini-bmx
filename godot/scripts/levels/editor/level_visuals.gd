@tool
class_name LevelVisuals
extends RefCounted
## What a level's pieces look like, built from a baked LevelField under `parent`: structures (jumps / drops) as their
## own fine meshes, rocks (the world's rock meshes in the ride; plain stones in the editor), race gates (two posts,
## a banner). The editor preview (BmxLevel) and the ride (LevelTerrain) both use it.

const GATE_COL := {"start": Color(0.2, 0.85, 0.3), "checkpoint": Color(1.0, 0.75, 0.15), "finish": Color(0.95, 0.95, 0.95)}


static func build(f: LevelField, parent: Node3D, in_game: bool, internal := false) -> void:
	var smat := StandardMaterial3D.new()
	smat.vertex_color_use_as_albedo = true
	smat.roughness = 0.9
	smat.cull_mode = BaseMaterial3D.CULL_DISABLED
	for st in f.structs:
		var mi := MeshInstance3D.new()
		mi.name = "Struct_" + str(st.name)
		mi.mesh = f.struct_mesh(st)
		mi.material_override = smat
		if in_game: mi.layers = 1 | Terrain.GROUND_LAYER
		_add(parent, mi, internal)
	_rocks(f, parent, in_game, internal)
	_trees(f, parent, internal)
	for g in f.gates: _gate(f, g, parent, internal)


static func _add(parent: Node, n: Node, internal: bool) -> void:
	if internal: parent.add_child(n, false, Node.INTERNAL_MODE_BACK)
	else: parent.add_child(n)


static func _rocks(f: LevelField, parent: Node3D, in_game: bool, internal: bool) -> void:
	if f.rocks.is_empty(): return
	var mesh: Mesh
	var mat: Material
	if in_game:
		TerrainGeo.ensure()
		mesh = TerrainGeo.MESH["rock"]
		mat = TerrainGeo.MAT["rock"]
	else:
		var sm := SphereMesh.new(); sm.radius = 1.0; sm.height = 2.0; sm.radial_segments = 10; sm.rings = 6
		mesh = sm
		var m := StandardMaterial3D.new(); m.albedo_color = Color(0.55, 0.53, 0.5); m.roughness = 0.95
		mat = m
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = in_game   # (the world's deco material tints each instance by its custom data: white = as is)
	mm.mesh = mesh
	mm.instance_count = f.rocks.size()
	for i in f.rocks.size():
		if in_game: mm.set_instance_custom_data(i, Color(1, 1, 1, 1))
		var c: Dictionary = f.rocks[i]
		var s := Vector3(c.sx, c.sy, c.sc) if in_game else Vector3(c.sx, c.sy, c.sc) * 0.9
		mm.set_instance_transform(i, Transform3D(Basis(Vector3.UP, c.yaw).scaled_local(s), Vector3(c.x, float(c.base) - c.sc * 0.3, c.z)))
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Rocks"
	mmi.multimesh = mm
	mmi.material_override = mat
	_add(parent, mmi, internal)


static func _gate(f: LevelField, g: Dictionary, parent: Node3D, internal: bool) -> void:
	var root := Node3D.new()
	root.name = "Gate_" + str(g.gate)
	var pos: Vector2 = g.pos; var dir: Vector2 = g.dir
	var sd := LevelField._side(dir)
	var col: Color = GATE_COL.get(g.gate, Color.WHITE)
	var m := StandardMaterial3D.new(); m.albedo_color = col; m.roughness = 0.6
	var half := float(g.span) * 0.5
	var hgt := 3.6
	var y0 := f.height(pos.x, pos.y)
	for sgn: float in [-1.0, 1.0]:
		var p := pos + sd * (sgn * half)
		var post := MeshInstance3D.new()
		var bm := BoxMesh.new(); bm.size = Vector3(0.18, hgt + 1.0, 0.18); bm.material = m
		post.mesh = bm
		post.position = Vector3(p.x, f.height(p.x, p.y) + (hgt + 1.0) * 0.5 - 0.5, p.y)
		root.add_child(post)
	var ban := MeshInstance3D.new()
	var bb := BoxMesh.new(); bb.size = Vector3(0.08, 0.7, float(g.span)); bb.material = m
	ban.mesh = bb
	ban.transform = Transform3D(Basis(Vector3.UP, atan2(-dir.y, dir.x)), Vector3(pos.x, y0 + hgt, pos.y))
	root.add_child(ban)
	var lbl := Label3D.new()
	lbl.text = str(g.gate).to_upper()
	lbl.font_size = 96
	lbl.pixel_size = 0.006
	lbl.outline_size = 12
	lbl.transform = Transform3D(Basis(Vector3.UP, atan2(-dir.y, dir.x) + PI * 0.5), Vector3(pos.x, y0 + hgt, pos.y) - Vector3(dir.x, 0, dir.y) * 0.06)
	lbl.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	lbl.double_sided = true
	root.add_child(lbl)
	_add(parent, root, internal)


const PINE_COLS := [0x2f6e45, 0x3b7d4b, 0x2a5f44]
const LEAF_COLS := [0x4f9a3a, 0x6cb544, 0x3f8a3f]
const BUSH_COLS := [0x3f7f33, 0x4c8c38, 0x5a8f3a]


static func _lin(h: int) -> Color:
	return Color.hex((h << 8) | 0xff).srgb_to_linear()


## the trees, as the world draws them (TerrainGeo's trunk / pine / blob / bush meshes + deco materials, the colour in
## each instance's custom data)
static func _trees(f: LevelField, parent: Node3D, internal: bool) -> void:
	if f.tree_list.is_empty(): return
	TerrainGeo.ensure()
	var lists := {"trunk": [], "pine": [], "blob": [], "bush": []}
	for t in f.tree_list:
		var sc: float = t.sc
		var h: float = t.h
		var yaw: float = t.yaw
		var p := Vector3(t.x, 0, t.z)
		match str(t.kind):
			"pine", "leafy":   # real-size trees (CardTree.dims, varied by place)
				var dm := CardTree.dims_at(str(t.kind), t.x, t.z)   # (a whole grown tree from the ground)
				var base := p + Vector3(0, h - 0.1, 0)
				if t.kind == "pine":
					lists.pine.append([base, dm.scale, yaw, _lin(PINE_COLS[t.ci])])
				else:
					lists.blob.append([base, dm.scale, yaw, _lin(LEAF_COLS[t.ci])])
			_:
				lists.bush.append([p + Vector3(0, h - 0.08, 0), Vector3(sc * 0.9, sc * 0.6, sc * 0.9), yaw, _lin(BUSH_COLS[t.ci])])
	var spec := {"trunk": ["trunk", "trunk"], "pine": ["pine", "leaf"], "blob": ["blob", "leafSoft"], "bush": ["bush", "leafCard"]}
	for nm in lists:
		var arr: Array = lists[nm]
		if arr.is_empty(): continue
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true
		mm.mesh = TerrainGeo.MESH[spec[nm][0]]
		mm.instance_count = arr.size()
		for i in arr.size():
			var e: Array = arr[i]
			mm.set_instance_transform(i, Transform3D(Basis(Vector3.UP, e[2]).scaled_local(e[1]), e[0]))
			mm.set_instance_custom_data(i, e[3])
		var mi := MultiMeshInstance3D.new()
		mi.name = "Trees_" + nm
		mi.multimesh = mm
		mi.material_override = TerrainGeo.MAT[spec[nm][1]]
		_add(parent, mi, internal)
		mi.set_instance_shader_parameter("fade_mode", 1.0)
		if not internal:   # (the editor preview has no fade band: LOD1 cards only, nothing extra saved into the scene)
			CardTree.add_twin(mi, spec[nm][0])   # (full leaf cards near the rider: card_tree.gd)
		elif nm == "pine" or nm == "blob":
			CardTree.add_spire(mi, nm, true)   # (its wood, LOD1)
