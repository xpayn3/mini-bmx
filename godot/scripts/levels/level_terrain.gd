class_name LevelTerrain
extends Terrain
## A level built in the Godot editor (the level builder: addons/level_builder, res://levels/*.tscn, BmxLevel +
## BmxTrail) in the ride's Terrain slot. Main starts it with --level=res://levels/<name>.tscn (the editor's
## "Ride this level" button does that). The scene is loaded, its BmxLevel makes the LevelField, which bakes the
## ground at 0.5 m: the physics reads that grid, the drawn ground is the same grid at 1 m. The base
## Terrain's field gets the level's trail as its TrailCourse (LevelField.to_course) and no route features.

var path := ""
var title := "Level"
var lf: LevelField
var _built := false
var baked := false             # loaded from the level's .bake (LevelBake): ground worked out, light baked
var baked_chunks := {}         # Vector2i -> LevelChunkData
var hour := 16.5               # the level's time of day (BmxLevel.hour)
var sun_turn := 0.0
var medals: Array = [0.0, 0.0, 0.0]   # gold, silver, bronze (s; 0 = none)
var practice_at := Vector2(INF, INF)   # --level-at=x,z (the editor's "Ride from selected"): start there, a practice run
const RT_SHADOW := 45.0        # m: on a baked level the real-time sun shadow only reaches this far (sharper, cheaper)
var _mat: ShaderMaterial


func _init(scene_path: String, seed_in := 12345) -> void:
	path = scene_path
	var t0 := Time.get_ticks_msec()
	var ps = load(scene_path) if ResourceLoader.exists(scene_path) else null
	var root: Node = ps.instantiate() if ps is PackedScene else null
	var lvl: BmxLevel = root if root is BmxLevel else null
	if lvl == null and root != null:
		for c in root.get_children():
			if c is BmxLevel: lvl = c; break
	if lvl == null:
		push_warning("LevelTerrain: no BmxLevel in '%s'" % scene_path)
		lf = LevelField.new()
	else:
		title = lvl.title
		hour = lvl.hour; sun_turn = lvl.sun_turn
		medals = [lvl.medal_gold, lvl.medal_silver, lvl.medal_bronze]
		var reg := LevelPublish.list()   # (the published medal times, worked out at Publish)
		for e in reg:
			if e.path == scene_path: medals = e.get("medals", medals)
		var bk := {} if Env.s("BMX_LEVEL_LIVE") != "" else LevelBake.load_bake(scene_path, LevelBake.signature(lvl))
		if not bk.is_empty():
			lf = LevelField.new()
			lf.load_state(bk.field)
			baked_chunks = bk.chunks
			baked = true
		else:
			lf = lvl.make_field()
	if root: root.free()
	if not baked: lf.bake(0.5)
	print("LEVEL ", scene_path, " from bake" if baked else " worked out live", " ms=", Time.get_ticks_msec() - t0, " grid=", lf.nx, "x", lf.nz, " | ", lf.summary())
	super(seed_in)


func _practice_arg() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--level-at="):
			var v := a.get_slice("=", 1).split(",")
			if v.size() == 2: practice_at = Vector2(float(v[0]), float(v[1]))


func set_seed(seed_in: int) -> void:
	_practice_arg()
	super(seed_in)
	field.course = lf.to_course()   # the level's own trail (demo AI, follow rider, trail camera, bend alerts)
	field.route_feats = lf.route   # its jumps / drops: the demo AI plans its speed for them, the HUD calls them out
	water_enabled = false
	if _water:   # (the world's sea level is -2.2 m; a level's ground is anywhere: no world water on it)
		_water.queue_free()
		_water = null
	cs_tyres = false   # its own ground: the drawn tyres sample it in GDScript


func update_stream(_px: float, _pz: float, _budget_ms: float = 4.0, _sync_r := -1) -> void:
	if _built: return
	_built = true
	var t0 := Time.get_ticks_msec()
	_mat = ShaderMaterial.new()
	_mat.shader = preload("res://shaders/playground_ground.gdshader")
	_mat.set_shader_parameter("line_1m", 0.0)
	_mat.set_shader_parameter("line_5m", 0.0)
	_mat.set_shader_parameter("contour", 0.0)
	var cover := _build_chunks()   # the world's ground shader + grass data, 48 m chunks over the level's grid
	_add_mesh(lf.far_mesh(1400.0, 14.0, cover), "FarLand")
	var pieces := Node3D.new()
	pieces.name = "Pieces"
	add_child(pieces)
	LevelVisuals.build(lf, pieces, true)
	chunk_serial += 1
	print("LEVEL ground built ms=", Time.get_ticks_msec() - t0)


func _add_mesh(m: ArrayMesh, nm: String) -> void:
	var mi := MeshInstance3D.new()
	mi.name = nm
	mi.mesh = m
	mi.material_override = _mat
	mi.layers = 1 | GROUND_LAYER
	add_child(mi)


func stream_complete() -> bool:
	return _built

func _update_ropes() -> void:
	pass

func update_water(_px: float, _pz: float, _t: float) -> void:
	pass

func water_near(_px: float, _pz: float, _reach: float) -> bool:
	return false


# ---- physics queries -------------------------------------------------------------------------------------
func _height0(x: float, z: float) -> float:
	return lf.height(x, z)

func height(x: float, z: float) -> float:
	return lf.height_rocks(x, z) - rut_at(x, z)   # (domes over the rocks, as in the world)

func deck_height(x: float, z: float) -> float:
	return lf.height(x, z) - rut_at(x, z)

func mesh_height(x: float, z: float) -> float:
	return lf.height(x, z)

func top_height(x: float, z: float) -> float:
	return lf.height_rocks(x, z) - rut_at(x, z)

func grid_height(x: float, z: float) -> float:
	return lf.height(x, z)

## trail + berm faces = dirt (1), the land = grass (0)
func surface(x: float, z: float) -> int:
	var sf := lf.surface_at(x, z)
	return 3 if sf == 3 else (1 if sf > 0 else 0)   # (painted sand rides as the world's sand)

func jump(x: float, z: float) -> Array:
	return [lf.height(x, z), lf.jump_mask(x, z), 0.0, 0.0, null]

func jump_mask(x: float, z: float) -> float:
	return lf.jump_mask(x, z)

func biome_name(_x: float, _z: float) -> String:
	return title

func ground_color(x: float, z: float, _ny: float = 1.0) -> Color:
	var sf := lf.surface_at(x, z)
	if sf == 1: return LevelField.DIRT
	if sf == 2: return LevelField.CLAY
	return LevelField.GRASS

func trail(x: float, z: float) -> float:
	return 1.0 if lf.surface_at(x, z) == 1 else 0.0

func colliders_near(x: float, z: float) -> Array:
	return lf.rocks_near(x, z)

func take_pack(_x: float, _y: float, _z: float, _r: float = 1.6):
	return null

## the start: the trail's first point, facing down it ((x, heading, z) as Game.respawn takes it)
func level_spawn() -> Vector3:
	if practice_at.x != INF:   # (the editor's "Ride from selected": 30 m up the trail from that piece)
		var i := lf.nearest(practice_at.x, practice_at.y)
		if i >= 0: return lf.stand_at(maxi(0, i - 30))
		return Vector3(practice_at.x - 25.0, 0.0, practice_at.y)
	return lf.start_stand()

## the bail tap: back on the nearest point of the trail, a few metres up it, facing down it
func level_reset(x: float, z: float) -> Vector3:
	var i := lf.nearest(x, z)
	return lf.stand_at(maxi(2, i - 8)) if i >= 0 else level_spawn()


# ---- chunks: the level's ground drawn like the world's ------------------------------------------------------
## 48 m chunks over the level's grid with the world chunk textures (LevelChunkData: from the level's .bake, or worked
## out now), drawn by world/ground.gdshader; grass_img / grass_h in chunks[k] for the grass carpet. With a bake the
## shader also gets the baked sun + sky light (`bake_tex`): far off, past the short real-time shadow, the ground's
## shadows are the baked ones. Returns the rectangle covered.
func _build_chunks() -> Rect2:
	var cv := LevelChunkData.cover(lf)
	var shader := load("res://scripts/world/ground.gdshader")
	var scans := trail_textures()
	for k in cv[0]:
		var data: Dictionary = baked_chunks.get(k, {})
		if data.is_empty(): data = LevelChunkData.build(lf, k)
		_chunk_nodes(k, data, shader, scans)
	return cv[1]


func _chunk_nodes(k: Vector2i, data: Dictionary, shader: Shader, scans: Array) -> void:
	var NV := LevelChunkData.NV
	var ox := k.x * SIZE; var oz := k.y * SIZE
	var gs := lf.step
	# the mesh: 1 m, the grid's heights (tucked under a structure's own mesh), UVs on the texel centres
	var M := 49
	var V := PackedVector3Array(); V.resize(M * M)
	var N := PackedVector3Array(); N.resize(M * M)
	var UV := PackedVector2Array(); UV.resize(M * M)
	for j in M:
		for i in M:
			var x := ox - SIZE * 0.5 + i; var z := oz - SIZE * 0.5 + j
			var gi := clampi(int(round((x - lf.x0) / gs)), 1, lf.nx - 2); var gj := clampi(int(round((z - lf.z0) / gs)), 1, lf.nz - 2)
			var idx := gj * lf.nx + gi
			V[j * M + i] = Vector3(i - SIZE * 0.5, lf.H[idx] - (0.14 if lf.JM[idx] == 1 else 0.0), j - SIZE * 0.5)
			N[j * M + i] = Vector3(-(lf.H[idx + 1] - lf.H[idx - 1]) / (2.0 * gs), 1.0, -(lf.H[idx + lf.nx] - lf.H[idx - lf.nx]) / (2.0 * gs)).normalized()
			UV[j * M + i] = Vector2((i * 2 + 0.5) / NV, (j * 2 + 0.5) / NV)
	var I := PackedInt32Array(); I.resize((M - 1) * (M - 1) * 6)
	var p := 0
	for j in M - 1:
		for i in M - 1:
			var a := j * M + i
			I[p] = a; I[p + 1] = a + 1; I[p + 2] = a + M; I[p + 3] = a + 1; I[p + 4] = a + M + 1; I[p + 5] = a + M
			p += 6
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = V; arr[Mesh.ARRAY_NORMAL] = N; arr[Mesh.ARRAY_TEX_UV] = UV; arr[Mesh.ARRAY_INDEX] = I
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	var img_g := Image.create_from_data(NV, NV, false, Image.FORMAT_RGBA8, data.land); img_g.generate_mipmaps()
	var img_d := Image.create_from_data(NV, NV, false, Image.FORMAT_RGBA8, data.dirt); img_d.generate_mipmaps()
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("land_tex", ImageTexture.create_from_image(img_g))
	mat.set_shader_parameter("dirt_tex", ImageTexture.create_from_image(img_d))
	for q in scans.size(): mat.set_shader_parameter("tr_nr%d" % q, scans[q])
	set_trail_scans(mat)
	var tr: PackedFloat32Array = data.tr
	mat.set_shader_parameter("trail_tex", ImageTexture.create_from_image(Image.create_from_data(NV, NV, false, Image.FORMAT_RGBAF, tr.to_byte_array())))
	mat.set_shader_parameter("trail2_tex", ImageTexture.create_from_image(Image.create_from_data(NV, NV, false, Image.FORMAT_RGBA8, data.tr2)))
	mat.set_shader_parameter("trail3_tex", ImageTexture.create_from_image(Image.create_from_data(NV, NV, false, Image.FORMAT_RG8, data.tr3)))
	mat.set_shader_parameter("trail_fx", 1.0)
	var pl: PackedByteArray = data.get("light", PackedByteArray())
	if not pl.is_empty():
		mat.set_shader_parameter("bake_tex", ImageTexture.create_from_image(Image.create_from_data(NV, NV, false, Image.FORMAT_RG8, pl)))
		mat.set_shader_parameter("bake_on", 1.0)
		mat.set_shader_parameter("bake_near", RT_SHADOW)
	var node := Node3D.new()
	node.name = "Chunk_%d_%d" % [k.x, k.y]
	add_child(node)
	var gi3 := MeshInstance3D.new()
	gi3.mesh = mesh
	gi3.material_override = mat
	gi3.layers = 1 | GROUND_LAYER
	gi3.position = Vector3(ox, 0, oz)
	node.add_child(gi3)
	var gh: PackedFloat32Array = data.gh
	chunks[k] = {"node": node, "grass_img": Image.create_from_data(NV, NV, false, Image.FORMAT_RGBA8, data.grass),
		"grass_h": Image.create_from_data(NV, NV, false, Image.FORMAT_RF, gh.to_byte_array()), "pud": PackedFloat32Array(), "mat": mat}
