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
	mm.mesh = mesh
	mm.instance_count = f.rocks.size()
	for i in f.rocks.size():
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
