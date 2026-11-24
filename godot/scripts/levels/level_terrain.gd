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
		lf = lvl.make_field()
		title = lvl.title
	if root: root.free()
	lf.bake(0.5)
	print("LEVEL ", scene_path, " baked ms=", Time.get_ticks_msec() - t0, " grid=", lf.nx, "x", lf.nz, " | ", lf.summary())
	super(seed_in)


func set_seed(seed_in: int) -> void:
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
	return 1 if lf.surface_at(x, z) > 0 else 0

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
	return lf.start_stand()

## the bail tap: back on the nearest point of the trail, a few metres up it, facing down it
func level_reset(x: float, z: float) -> Vector3:
	var i := lf.nearest(x, z)
	return lf.stand_at(maxi(2, i - 8)) if i >= 0 else level_spawn()


# ---- chunks: the level's ground drawn like the world's ------------------------------------------------------
## 48 m chunks (Terrain.SIZE) covering the level's grid, each with the textures the world's chunks bake
## (TerrainChunkBuilder): land / dirt colour + trail weight + rock weight, the trail's own frame (across, along),
## built jumps, air, corner load, so world/ground.gdshader draws worn lines, tyre prints and grit on the level's trail;
## and grass_img / grass_h, so the grass carpet (GrassField) grows on the level. Returns the rectangle covered.
const NV := 97   # texels per chunk side (0.5 m), as the world's (GrassField.SEG + 1)

func _build_chunks() -> Rect2:
	var gx1 := lf.x0 + (lf.nx - 1) * lf.step; var gz1 := lf.z0 + (lf.nz - 1) * lf.step
	var kx0 := int(ceil((lf.x0 + SIZE * 0.5) / SIZE)); var kx1 := int(floor((gx1 - SIZE * 0.5) / SIZE))
	var kz0 := int(ceil((lf.z0 + SIZE * 0.5) / SIZE)); var kz1 := int(floor((gz1 - SIZE * 0.5) / SIZE))
	var shader := load("res://scripts/world/ground.gdshader")
	var scans := trail_textures()
	for kz in range(kz0, kz1 + 1):
		for kx in range(kx0, kx1 + 1):
			_chunk(Vector2i(kx, kz), shader, scans)
	return Rect2(kx0 * SIZE - SIZE * 0.5, kz0 * SIZE - SIZE * 0.5, (kx1 - kx0 + 1) * SIZE, (kz1 - kz0 + 1) * SIZE)


static func _enc(v: float) -> int:
	return TerrainChunkBuilder._enc(v)


func _chunk(k: Vector2i, shader: Shader, scans: Array) -> void:
	var ox := k.x * SIZE; var oz := k.y * SIZE
	var gs := lf.step
	var hw := lf.trail_width * 0.5
	var pG := PackedByteArray(); pG.resize(NV * NV * 4)
	var pD := PackedByteArray(); pD.resize(NV * NV * 4)
	var TR := PackedFloat32Array(); TR.resize(NV * NV * 4)
	var pT2 := PackedByteArray(); pT2.resize(NV * NV * 4)
	var pA := PackedByteArray(); pA.resize(NV * NV * 2)
	var pK := PackedByteArray(); pK.resize(NV * NV * 4)
	var gh := PackedFloat32Array(); gh.resize(NV * NV)
	var dirt := LevelField.DIRT.srgb_to_linear(); var clay := LevelField.CLAY.srgb_to_linear()
	for j in NV:
		for i in NV:
			var o := j * NV + i
			var x := ox - SIZE * 0.5 + i * 0.5; var z := oz - SIZE * 0.5 + j * 0.5
			var gi := clampi(int(round((x - lf.x0) / gs)), 1, lf.nx - 2); var gj := clampi(int(round((z - lf.z0) / gs)), 1, lf.nz - 2)
			var idx := gj * lf.nx + gi
			var h := lf.H[idx]
			gh[o] = h
			var ny := Vector3(-(lf.H[idx + 1] - lf.H[idx - 1]) / (2.0 * gs), 1.0, -(lf.H[idx + lf.nx] - lf.H[idx - lf.nx]) / (2.0 * gs)).normalized().y
			var sf := lf.S[idx]
			var dt := lf.DT[idx]
			var tw := 0.0
			if sf == 1: tw = 1.0
			elif sf == 2: tw = 0.75
			elif dt < INF: tw = 1.0 - smoothstep(hw, hw + 0.9, dt)
			var rockw := 0.0 if sf != 0 else smoothstep(0.80, 0.68, ny)
			var g := lf._land_color(x, z, ny).srgb_to_linear()
			var dc := clay if sf == 2 else dirt
			pG[o * 4] = _enc(g.r); pG[o * 4 + 1] = _enc(g.g); pG[o * 4 + 2] = _enc(g.b); pG[o * 4 + 3] = roundi(clampf(tw, 0, 1) * 255)
			pD[o * 4] = _enc(dc.r); pD[o * 4 + 1] = _enc(dc.g); pD[o * 4 + 2] = _enc(dc.b); pD[o * 4 + 3] = roundi(clampf(rockw, 0, 1) * 255)
			if dt < INF:
				TR[o * 4] = lf.TSA[idx]; TR[o * 4 + 1] = 0.0; TR[o * 4 + 2] = lf.TAL[idx]; TR[o * 4 + 3] = 0.0
			var jmk := lf.JM[idx] == 1
			pT2[o * 4 + 2] = 255 if jmk else 0
			var air := 0.0
			if jmk: air = _air_at(x, z)
			pA[o * 2] = roundi(air * 255)
			pA[o * 2 + 1] = roundi(smoothstep(1.0 / 80.0, 1.0 / 12.0, absf(lf.TKC[idx])) * 255)
			var den := (1.0 - smoothstep(0.04, 0.4, tw)) * (1.0 - smoothstep(0.1, 0.6, rockw)) * (0.0 if jmk else 1.0)
			if den > 0.0:
				for c in lf.rocks_near(x, z):
					if c.has("top") and Vector2(c.x - x, c.z - z).length() < float(c.r) + 0.15: den = 0.0
			pK[o * 4] = pG[o * 4]; pK[o * 4 + 1] = pG[o * 4 + 1]; pK[o * 4 + 2] = pG[o * 4 + 2]; pK[o * 4 + 3] = roundi(clampf(den, 0, 1) * 255)
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
	var img_g := Image.create_from_data(NV, NV, false, Image.FORMAT_RGBA8, pG); img_g.generate_mipmaps()
	var img_d := Image.create_from_data(NV, NV, false, Image.FORMAT_RGBA8, pD); img_d.generate_mipmaps()
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("land_tex", ImageTexture.create_from_image(img_g))
	mat.set_shader_parameter("dirt_tex", ImageTexture.create_from_image(img_d))
	for q in scans.size(): mat.set_shader_parameter("tr_nr%d" % q, scans[q])
	mat.set_shader_parameter("trail_tex", ImageTexture.create_from_image(Image.create_from_data(NV, NV, false, Image.FORMAT_RGBAF, TR.to_byte_array())))
	mat.set_shader_parameter("trail2_tex", ImageTexture.create_from_image(Image.create_from_data(NV, NV, false, Image.FORMAT_RGBA8, pT2)))
	mat.set_shader_parameter("trail3_tex", ImageTexture.create_from_image(Image.create_from_data(NV, NV, false, Image.FORMAT_RG8, pA)))
	mat.set_shader_parameter("trail_fx", 1.0)
	var node := Node3D.new()
	node.name = "Chunk_%d_%d" % [k.x, k.y]
	add_child(node)
	var gi3 := MeshInstance3D.new()
	gi3.mesh = mesh
	gi3.material_override = mat
	gi3.layers = 1 | GROUND_LAYER
	gi3.position = Vector3(ox, 0, oz)
	node.add_child(gi3)
	chunks[k] = {"node": node, "grass_img": Image.create_from_data(NV, NV, false, Image.FORMAT_RGBA8, pK),
		"grass_h": Image.create_from_data(NV, NV, false, Image.FORMAT_RF, gh.to_byte_array()), "pud": PackedFloat32Array()}


## a jump's air (riders fly over it, the worn lines stop): from the lip to where the design speed lands
func _air_at(x: float, z: float) -> float:
	for st in lf.structs:
		if not st.has("d") or not (st.rect as Rect2).has_point(Vector2(x, z)): continue
		var l: Vector2 = lf._local(st, x, z)
		var d: Dictionary = st.d
		var u_end: float = float(d.lip_u) + float(st.flights[1].dist) if is_finite(float(st.flights[1].dist)) else float(d.land1)
		return smoothstep(float(d.lip_u) - 0.3, float(d.lip_u) + 0.5, l.x) * (1.0 - smoothstep(u_end - 2.0, u_end + 0.5, l.x))
	return 0.0
