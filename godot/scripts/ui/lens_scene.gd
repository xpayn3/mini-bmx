extends SubViewportContainer
## The ride setup's RACE step preview: a made-up vista seen from riding height on a ridge-top trail: the trail drops
## into a huge valley (switchbacks, a lake, forests), ridge after ridge beyond and peaks ~3 km away; built to show what
## the time of day and each goggle lens do. Dirt with ruts and roots (contrast lenses read them), dappled tree shade across
## the trail (shade vs sun), a dark forest edge and an open meadow, a puddle mirroring the sky (glare), white rocks
## (brightness), hazy hills far off (haze / low light) and the game's own sky. Uses the game's tree / rock / grass meshes and
## shaders (backlit leaves, dappled shadows), its sky shader and the same light formulas as the ride (Game._apply_light,
## condensed), graded by the lens LUT. Its own small World3D; only drawn while it's on screen.
## No class_name (preloaded by main.gd): a new class_name needs a re-import.

const GoggleLens = preload("res://scripts/rider/goggle_lens.gd")

var vp := SubViewport.new()
var env := Environment.new()
var sky_mat := ShaderMaterial.new()
var sun := DirectionalLight3D.new()
var lamp := SpotLight3D.new()     # the bike lamp at night
var cam := Camera3D.new()
var hour := 19.33
var lens := "neutral"
var _t := 0.0
var _root := Node3D.new()
var cam_attr := CameraAttributesPractical.new()
static var _data := {}      # the computed land + props, kept for the session (RACE opens instantly the next time)
static var _task := -1
var _made := false



func _init() -> void:
	stretch = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_2X
	vp.positional_shadow_atlas_size = 1024
	vp.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	add_child(vp)
	vp.add_child(_root)
	TerrainGeo.ensure()
	TerrainChunkBuilder.ensure_static()
	_build_env()
	# the land + its trees are worked out on a worker thread once per session (~0.8 s of maths), then made here
	prewarm()
	if not _data.is_empty() and _task < 0: _make(_data)
	cam.fov = 62.0
	cam.far = 9000.0
	cam.current = true
	_root.add_child(cam)
	set_hour(hour)


func _exit_tree() -> void:
	join()

## never leave the worker task running (quitting with one crashed the game before); main.gd calls it on quit too
static func join() -> void:
	if _task >= 0:
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1

## start working out the land in the background (main.gd calls this while the boot intro plays)
static func prewarm() -> void:
	if _data.is_empty() and _task < 0:
		_task = WorkerThreadPool.add_task(_compute_all)

static func _compute_all() -> void:
	var t0 := Time.get_ticks_msec()
	var d := {"ground": _compute_ground(), "props": _compute_props()}
	d["ms"] = Time.get_ticks_msec() - t0
	_data = d

## the nodes from the computed data (main thread, a few ms); the picture fades in
func _make(d: Dictionary) -> void:
	_made = true
	var m0 := Time.get_ticks_usec()
	var mi := MeshInstance3D.new()
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, d.ground)
	mi.mesh = am
	mi.material_override = _ground_mat()
	_root.add_child(mi)
	_make_water()
	var P: Dictionary = d.props
	for k in P:
		var e: Dictionary = P[k]
		_mm(e.mesh, e.mat, e.buf, int(e.count), e.cast)
	if Env.s("BMX_SETUP_PROBE") != "": print("LENSSCENE build_ms=%d (worker) make_ms=%.1f (main thread)" % [int(d.get("ms", 0)), (Time.get_ticks_usec() - m0) / 1000.0])
	modulate.a = 0.0
	create_tween().tween_property(self, "modulate:a", 1.0, 0.5)

func set_hour(h: float) -> void:
	hour = h
	_apply_light(h)

func set_lens(id: String) -> void:
	lens = id
	env.adjustment_color_correction = GoggleLens.lut(id) if id != "" else null


func _process(dt: float) -> void:
	if not _made and _task >= 0 and WorkerThreadPool.is_task_completed(_task):
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1
		_make(_data)
	elif not _made and _task < 0 and not _data.is_empty():
		_make(_data)
	if not is_visible_in_tree(): return
	_t += dt
	# on the ridge top, at riding height, a slow look round over the valley + a little handheld sway
	var z := -sin(_t * 0.1) * 1.2
	var x := _cx(z) - 0.15 + sin(_t * 0.37) * 0.05
	cam.position = Vector3(x, G(x, z) + 1.62 + sin(_t * 0.9) * 0.015, z)
	var yaw := sin(_t * 0.05) * 0.09
	var ahead := Vector3(sin(yaw) * 700.0, -125.0, -cos(yaw) * 700.0)
	cam.look_at(ahead, Vector3.UP)
	cam.rotate_object_local(Vector3(0, 0, 1), sin(_t * 0.23) * 0.01)


# ---------------------------------------------------------------- the place: a ridge top over a huge valley
## the trail: wiggles along the ridge top near the camera, then switchbacks down the slope into the valley
static func _cx(z: float) -> float:
	var d := -z
	var near := 2.6 * sin(z * 0.045) + 1.2 * sin(z * 0.11 + 1.0)
	var far := 55.0 * sin(d * 0.013 + 0.4) * smoothstep(40.0, 200.0, d) + 0.04 * maxf(d - 100.0, 0.0)
	return near + far

static func _fbm(x: float, z: float) -> float:
	var s := 0.0
	var a := 1.0
	var f := 1.0 / 420.0
	for i in 5:
		s += a * (sin(x * f * 1.7 + i * 1.3) * cos(z * f * 1.3 - i * 0.7) + 0.5 * sin((x + z) * f * 2.3 + i))
		a *= 0.5
		f *= 2.07
	return s * 0.5

## ground height everywhere: a gentle ridge top round the camera, the land falling ~95 m into a valley floor (a lake
## lies in it), valley walls rising both sides, ridge after ridge beyond and big peaks 2-3 km away
static func G(x: float, z: float) -> float:
	var d := -z
	var ax := absf(x)
	var y := z * 0.05
	y -= 260.0 * (1.0 - exp(-maxf(d - 16.0, 0.0) / 260.0))
	y += smoothstep(150.0, 1600.0, ax) * 260.0 * (1.0 - 0.3 * smoothstep(1500.0, 4000.0, d))
	y += smoothstep(1300.0, 4500.0, d) * 380.0
	var rough := 4.0 + 70.0 * smoothstep(40.0, 900.0, maxf(d, ax))
	y += _fbm(x, z) * rough
	var r := 1.0 - absf(sin(x * 0.0021 + 0.7) * cos(z * 0.0017 - 0.3))
	y += pow(r, 3.0) * 460.0 * smoothstep(2500.0, 4800.0, d)   # sharp peaks far off
	# near the trail: a bank either side, ruts in the dirt
	var off := x - _cx(z)
	var od := absf(off)
	if d < 220.0:
		var k := 1.0 - smoothstep(120.0, 220.0, d)
		y += k * (smoothstep(2.0, 14.0, od) * 0.35 + (sin(x * 0.21 + 1.3) * 0.3 + sin(z * 0.17) * 0.35) * smoothstep(1.0, 6.0, od))
		if od < 1.3:
			y -= k * 0.06 * (exp(-pow((off - 0.38) / 0.12, 2.0)) + exp(-pow((off + 0.38) / 0.12, 2.0)))
	return y

const LAKE_Y := -262.0

static func _hash(x: float, z: float) -> float:
	return fposmod(sin(x * 127.1 + z * 311.7) * 43758.5453, 1.0)

## the ground at a point for vista_ground.gdshader: [land colour (linear), trail dirt weight, rut, rock-face weight]
## land = grass / dry grass, forest floor, bare rock high up, snow on the peaks, sand at the lake
static func _ground_attr(x: float, z: float, y: float, slope: float) -> Array:
	var d := -z
	var forest := smoothstep(0.1, 0.45, _fbm(x * 2.3 + 900.0, z * 2.3 - 400.0))
	var c := Color(0.3, 0.5, 0.18).lerp(Color(0.52, 0.56, 0.26), smoothstep(0.35, 0.9, _fbm(x * 3.0, z * 3.0) + 0.3) * 0.7)
	c = c.lerp(Color(0.2, 0.32, 0.15), forest * (1.0 - smoothstep(140.0, 200.0, y)))
	var rock := smoothstep(0.55, 0.85, slope)
	c = c.lerp(Color(0.5, 0.48, 0.44), rock)
	c = c.lerp(Color(0.52, 0.5, 0.46), smoothstep(200.0, 270.0, y))
	c = c.lerp(Color(0.95, 0.96, 0.98), smoothstep(330.0, 370.0, y + _fbm(x * 4.0, z * 4.0) * 35.0))
	c = c.lerp(Color(0.72, 0.64, 0.46), (1.0 - smoothstep(LAKE_Y + 0.5, LAKE_Y + 3.0, y)))   # sandy shore
	var off := absf(x - _cx(z))
	var tw := lerpf(1.2, 3.5, smoothstep(30.0, 600.0, d))   # the trail stays visible further away
	var trail := 1.0 - smoothstep(tw * 0.85, tw * 1.35, off)
	var rut := exp(-pow((off - 0.38) / 0.14, 2.0)) * (1.0 - smoothstep(1.0, 1.3, off)) * (1.0 - smoothstep(40.0, 80.0, d))
	return [c.srgb_to_linear(), trail, rut, maxf(rock, smoothstep(200.0, 270.0, y)) * 0.8]

static func _compute_ground() -> Array:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# near: fine (0.6 m) round the camera
	var rows := []
	var step := 0.6
	for j in int(66.0 / step) + 1:
		var z := 8.0 - j * step
		var row := []
		for i in int(64.0 / step) + 1:
			var x := -32.0 + i * step
			row.append(Vector3(x, G(x, z), z))
		rows.append(row)
	_grid(st, rows)
	# far: rows further apart the further they are, columns spread across a wider span, out to 3.4 km
	var frows := []
	var d := 54.0
	while d < 6200.0:
		var hw := clampf(d * 1.25 + 100.0, 140.0, 5200.0)
		var row := []
		var n := 130
		for i in n + 1:
			var t := float(i) / n * 2.0 - 1.0
			var x := hw * signf(t) * pow(absf(t), 1.35)
			row.append(Vector3(x, G(x, -d) - 0.12, -d))
		frows.append(row)
		d += maxf(3.0, d * 0.024)
	_grid(st, frows)
	st.generate_normals()
	return st.commit_to_arrays()

static func _ground_mat() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/vista_ground.gdshader")
	m.set_shader_parameter("dirt_col", Color(0.5, 0.36, 0.24))
	return m

func _make_water() -> void:
	# the lake on the valley floor: a still mirror of the sky (glare: what a dark / mirrored lens calms)
	var lake := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(5000, 5000)
	lake.mesh = pm
	lake.position = Vector3(0, LAKE_Y, -2000)
	var wm := StandardMaterial3D.new()
	wm.albedo_color = Color(0.03, 0.06, 0.07)
	wm.roughness = 0.04
	wm.metallic_specular = 1.0
	lake.material_override = wm
	lake.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_root.add_child(lake)
	# a puddle in the trail on the ridge
	var pz := -13.5
	var pd := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 1.0; cyl.bottom_radius = 1.0; cyl.height = 0.02; cyl.radial_segments = 32
	pd.mesh = cyl
	pd.scale = Vector3(0.55, 1.0, 1.6)
	pd.position = Vector3(_cx(pz) + 0.3, G(_cx(pz) + 0.3, pz) + 0.004, pz)
	var pm2 := StandardMaterial3D.new()
	pm2.albedo_color = Color(0.06, 0.05, 0.035)
	pm2.roughness = 0.06
	pd.material_override = pm2
	pd.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_root.add_child(pd)

## triangles over rows of points (each row the same number of points), coloured by _ground_attr
static func _grid(st: SurfaceTool, rows: Array) -> void:
	# a colour per point (slope from the height field), triangles share points: smooth shading
	var base := 0
	var cols := []
	for row: Array in rows:
		var cr := []
		for v: Vector3 in row:
			var e := 1.5
			var gx := (G(v.x + e, v.z) - G(v.x - e, v.z)) / (2.0 * e)
			var gz := (G(v.x, v.z + e) - G(v.x, v.z - e)) / (2.0 * e)
			cr.append(_ground_attr(v.x, v.z, v.y, sqrt(gx * gx + gz * gz) * 1.3))
		cols.append(cr)
	var verts := 0
	for j in rows.size():
		var row: Array = rows[j]
		for i in row.size():
			var ga: Array = cols[j][i]
			var lc: Color = ga[0]
			st.set_color(Color(lc.r, lc.g, lc.b, float(ga[1])))
			st.set_uv(Vector2(float(ga[2]), float(ga[3])))
			st.add_vertex(row[i])
	# (the vertex index of the first point of this grid = what was added before it)
	base = st.get_meta(&"count", 0) if st.has_meta(&"count") else 0
	var w: int = (rows[0] as Array).size()
	for j in rows.size() - 1:
		for i in w - 1:
			var a := base + j * w + i
			st.add_index(a); st.add_index(a + w); st.add_index(a + 1)
			st.add_index(a + 1); st.add_index(a + w); st.add_index(a + w + 1)
	st.set_meta(&"count", base + rows.size() * w)


## MultiMesh of a TerrainGeo mesh with per-instance colours (the deco / flower shaders read INSTANCE_CUSTOM)
func _mm(mesh_name: String, mat_name: String, buf: PackedFloat32Array, count: int, cast := true) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = TerrainGeo.MESH[mesh_name]
	mm.instance_count = count
	if count > 0: mm.buffer = buf
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = TerrainGeo.MAT[mat_name]
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if cast else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_root.add_child(mmi)
	if mesh_name.ends_with("Billboard"):
		mmi.set_instance_shader_parameter("fade_mode", 0.0)   # (no LOD band here: always the billboard)

## [transform, colour] items -> a MultiMesh buffer (3x4 basis+origin rows, then the custom colour): 16 floats each
static func _pack(items: Array) -> PackedFloat32Array:
	var b := PackedFloat32Array()
	b.resize(items.size() * 16)
	var o := 0
	for it in items:
		var t: Transform3D = it[0]
		var c: Color = it[1]
		b[o] = t.basis.x.x; b[o + 1] = t.basis.y.x; b[o + 2] = t.basis.z.x; b[o + 3] = t.origin.x
		b[o + 4] = t.basis.x.y; b[o + 5] = t.basis.y.y; b[o + 6] = t.basis.z.y; b[o + 7] = t.origin.y
		b[o + 8] = t.basis.x.z; b[o + 9] = t.basis.y.z; b[o + 10] = t.basis.z.z; b[o + 11] = t.origin.z
		b[o + 12] = c.r; b[o + 13] = c.g; b[o + 14] = c.b; b[o + 15] = c.a
		o += 16
	return b

## the ground mesh is ready as arrays; the ArrayMesh is made here
static func _xf(p: Vector3, s: Vector3, yaw: float) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, yaw).scaled(s), p)

static func _compute_props() -> Dictionary:
	var pines := []; var trunks := []; var blobs := []; var bushes := []; var rocks := []; var grass := []; var roots := []
	var far_pines := []; var far_trunks := []
	var rng := RandomNumberGenerator.new(); rng.seed = 7
	var P: Array = TerrainChunkBuilder.PINES
	var L: Array = TerrainChunkBuilder.LEAVES
	var B: Array = TerrainChunkBuilder.BUSHES
	# near the ridge top: a few pines and round trees beside the trail (shade across it), bushes, grass, rocks, roots
	for i in 14:
		var z := 4.0 - rng.randf() * 22.0
		var side := -1.0 if i % 4 != 0 else 1.0
		var x := _cx(z) + side * (11.0 + rng.randf() * 10.0)
		if absf(x - _cx(z)) < 9.0 + maxf(-z - 10.0, 0.0) * 0.3: continue   # the trees frame the view, they don't block it
		var y := G(x, z)
		# a whole grown tree from the ground (CardTree.dims: real size)
		var dm := CardTree.dims("pine", 0.5, rng.randf(), rng.randf(), rng.randf())
		pines.append([_xf(Vector3(x, y - 0.1, z), dm.scale, rng.randf() * TAU), P[i % P.size()]])
	for spot in []:
		var z: float = spot[1]
		var x := _cx(z) + float(spot[0])
		var y := G(x, z)
		var sc := 2.4 + rng.randf() * 0.6
		var th := 2.4
		trunks.append([_xf(Vector3(x, y - 0.1, z), Vector3(sc, th + 0.3, sc), 0.0), Color(1, 1, 1)])
		blobs.append([_xf(Vector3(x, y + th + sc * 0.7, z), Vector3(sc * 1.25, sc * 1.05, sc * 1.25), rng.randf() * TAU), L[rng.randi() % 4]])
		blobs.append([_xf(Vector3(x + 0.8, y + th + sc * 1.35, z - 0.5), Vector3(sc * 0.8, sc * 0.75, sc * 0.8), rng.randf() * TAU), L[rng.randi() % 4]])
	for i in 16:
		var z := 2.0 - rng.randf() * 26.0
		var x := _cx(z) + (2.4 + rng.randf() * 9.0) * (1.0 if rng.randf() < 0.5 else -1.0)
		var sc := 0.6 + rng.randf() * 0.9
		bushes.append([_xf(Vector3(x, G(x, z) - 0.08, z), Vector3(sc, sc * 0.8, sc), rng.randf() * TAU), B[i % B.size()]])
	for i in 2400:
		var z := 4.0 - rng.randf() * 55.0
		var side := 1.0 if rng.randf() < 0.6 else -1.0
		var x := _cx(z) + side * (1.6 + pow(rng.randf(), 1.6) * 22.0)
		var sc := 0.5 + rng.randf() * 0.7
		grass.append([_xf(Vector3(x, G(x, z) - 0.02, z), Vector3(sc, sc * (0.8 + rng.randf() * 0.6), sc), rng.randf() * TAU), TerrainGeo.lin([0x5f9a38, 0x7aa83e, 0x4f8a34, 0x9aa848][rng.randi() % 4]) * (0.85 + rng.randf() * 0.3)])
	for i in 24:
		var z := 3.0 - rng.randf() * 55.0
		var x := _cx(z) + (1.4 + rng.randf() * 3.0) * (1.0 if rng.randf() < 0.5 else -1.0)
		var sc := 0.25 + rng.randf() * 0.6
		var white := i % 5 == 0
		rocks.append([_xf(Vector3(x, G(x, z) - sc * 0.25, z), Vector3(sc * 1.2, sc * 0.8, sc), rng.randf() * TAU), Color(1.35, 1.33, 1.28) if white else Color(0.85, 0.83, 0.8)])
	for rz in [-7.0, -11.5, -19.0, -27.5, -38.0]:
		var x0 := _cx(rz)
		var ang := 0.35 * sin(rz * 1.7)
		roots.append([Transform3D(Basis(Vector3.UP, ang).scaled(Vector3(2.9, 0.22, 0.26)), Vector3(x0, G(x0, rz) - 0.015, rz)), Color(0.5, 0.38, 0.27)])
	# the forests below: thousands of pines over the valley slopes, big enough to read kilometres away
	var tries := 0
	while far_pines.size() < 9000 and tries < 80000:
		tries += 1
		var d := 70.0 + pow(rng.randf(), 1.3) * 3800.0
		var hw := clampf(d * 1.2 + 100.0, 150.0, 3800.0)
		var x := (rng.randf() * 2.0 - 1.0) * hw
		var z := -d
		if _fbm(x * 2.3 + 900.0, z * 2.3 - 400.0) < 0.12: continue   # forest patches, clearings between
		var y := G(x, z)
		if y < LAKE_Y + 2.0 or y > 190.0: continue
		var s2 := absf(G(x + 6.0, z) - y) + absf(G(x, z + 6.0) - y)
		if s2 > 9.0: continue
		if absf(x - _cx(z)) < 6.0: continue
		if d < 420.0 and absf(x) < d * 0.55: continue   # keep the view down into the valley open
		var sc := (2.2 + rng.randf() * 2.0) * (1.0 + d / 1500.0)   # far trees a bit bigger so the forests read
		# (billboards of our grown pine: a whole tree from the ground, ~6 x sc tall)
		var hh := sc * (5.5 + rng.randf() * 1.8)
		far_pines.append([_xf(Vector3(x, y - 0.1, z), Vector3(hh * 0.9, hh, hh * 0.9), rng.randf() * TAU), P[rng.randi() % P.size()]])
	var out := {}
	for e in [["trunks", "trunk", "trunk", trunks, true], ["pines", "pine", "leaf", pines, true], ["blobs", "blob", "leafSoft", blobs, true],
			["bushes", "bush", "leafCard", bushes, true], ["rocks", "rock", "rock", rocks, true], ["grass", "grass", "flower", grass, false],
			["roots", "log", "trunk", roots, true], ["far_pines", "pineBillboard", "pineBillboard", far_pines, false],
			["far_trunks", "trunk", "trunk", far_trunks, false],
			["wood", "pineWood0", "wood_pine", pines, false], ["limbs", "leafyWood0", "wood_leafy", blobs, false]]:   # (grown trees' wood)
		out[e[0]] = {"mesh": e[1], "mat": e[2], "buf": _pack(e[3]), "count": (e[3] as Array).size(), "cast": e[4]}
	return out


# ---------------------------------------------------------------- light (condensed from Game._build_env / _apply_light)
func _build_env() -> void:
	var we := WorldEnvironment.new()
	sky_mat.shader = load("res://shaders/sky_hdri.gdshader")
	var sky := Sky.new()
	sky.sky_material = sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_128
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_agx_contrast = Game.AGX_CONTRAST
	env.tonemap_agx_white = 12.0
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_depth_curve = 1.6
	env.fog_depth_begin = 200.0
	env.fog_depth_end = 7500.0
	env.fog_sky_affect = 0.0
	# the ride's own look (Game._build_env): AO, indirect light, bloom levels, sun shafts through the haze
	env.ssao_enabled = true
	env.ssao_radius = 0.6
	env.ssao_intensity = 2.0
	env.ssao_power = 1.5
	env.ssao_detail = 0.5
	env.ssao_horizon = 0.06
	env.ssao_light_affect = 0.15
	env.ssil_enabled = true
	env.ssil_radius = 4.0
	env.ssil_intensity = 0.7
	env.glow_enabled = true
	env.glow_intensity = 0.25
	env.glow_strength = 0.9
	env.glow_bloom = 0.02
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	env.set_glow_level(0, 0.0); env.set_glow_level(1, 0.6); env.set_glow_level(2, 1.0)
	env.set_glow_level(3, 0.6); env.set_glow_level(4, 0.3)
	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = Game.VOL_DENSITY
	env.volumetric_fog_anisotropy = 0.78
	env.volumetric_fog_length = 90.0
	env.volumetric_fog_detail_spread = 1.6
	env.volumetric_fog_sky_affect = 0.0
	env.volumetric_fog_temporal_reprojection_enabled = true
	env.volumetric_fog_temporal_reprojection_amount = 0.9
	env.adjustment_enabled = true
	we.environment = env
	# the eye adapting, as in the ride (off at night)
	cam_attr.auto_exposure_enabled = true
	cam_attr.auto_exposure_scale = 0.4
	cam_attr.auto_exposure_speed = 0.7
	cam_attr.auto_exposure_min_sensitivity = 80.0
	cam_attr.auto_exposure_max_sensitivity = 140.0
	we.camera_attributes = cam_attr
	_root.add_child(we)
	# the ride's colour grade (split tone + vignette, shaders/grade.gdshader) over this view too
	var cl := CanvasLayer.new()
	cl.layer = -1
	var gr := ColorRect.new()
	gr.set_anchors_preset(Control.PRESET_FULL_RECT)
	gr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var gm := ShaderMaterial.new()
	gm.shader = load("res://shaders/grade.gdshader")
	gm.set_shader_parameter("grade_amt", 1.0 if Settings.get_v("grade") else 0.0)
	gr.material = gm
	cl.add_child(gr)
	vp.add_child(cl)
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 70.0
	sun.shadow_bias = 0.04
	sun.shadow_normal_bias = 1.5
	_root.add_child(sun)
	lamp.light_color = Color(1.0, 0.97, 0.9)
	lamp.light_energy = 3.0
	lamp.spot_range = 34.0
	lamp.spot_angle = 26.0
	lamp.spot_angle_attenuation = 1.4
	lamp.light_volumetric_fog_energy = 0.5
	lamp.shadow_enabled = true
	lamp.visible = false
	cam.add_child(lamp)
	lamp.position = Vector3(0, -0.45, -0.3)
	lamp.rotation = Vector3(-0.09, 0, 0)

func _apply_light(h: float) -> void:
	var L: Dictionary = LightSettings.current
	var el := Game.sun_elev_deg(h)
	var g := 1.0 - smoothstep(8.0, 30.0, el)
	var n := 1.0 - smoothstep(-11.0, -3.5, el)
	var day := 1.0 - n
	var gw := clampf(g * day * float(L.get("warmth", 1.0)), 0.0, 1.0)
	var tw := smoothstep(1.0, -4.0, el) * day
	var low := 1.0 - smoothstep(1.0, 12.0, el)
	# the sun sweeps across the view: rising front-right, high behind at noon, setting front-left (backlit trail)
	var u := clampf((h - 6.0) / 14.0, 0.0, 1.0)
	var yaw := lerpf(-PI * 0.5 + 0.32, -PI * 0.5 - 0.32 + TAU, u) if el > -3.0 else 0.0   # 0 = +X; -PI/2 = ahead (-Z)
	var dirv: Vector3
	var sun_e: float
	if el > -3.0:
		var e := deg_to_rad(maxf(el, 2.5))
		dirv = Vector3(cos(yaw) * cos(e), sin(e), sin(yaw) * cos(e))
		sun.light_color = Color(1.0, 0.95, 0.87).lerp(Color(1.0, 0.62, 0.36), gw).lerp(Color(1.0, 0.5, 0.26), low * gw)
		sun_e = lerpf(Game.RIDE_SUN, 2.2, g) * smoothstep(-3.0, 5.0, el)
	else:
		var e := deg_to_rad(15.0)
		dirv = Vector3(cos(-PI * 0.5 + 0.7), sin(e), sin(-PI * 0.5 + 0.7)).normalized()   # the moon ahead-right
		sun.light_color = Color(0.55, 0.66, 0.95)
		sun_e = 0.3 * smoothstep(-3.0, -10.0, el)
	sun.light_energy = sun_e * float(L.get("sun", 1.0)) if el > -3.0 else sun_e * float(L.get("moon", 1.0))
	sun.look_at_from_position(dirv, Vector3.ZERO, Vector3.UP)
	sun.shadow_blur = lerpf(lerpf(1.0, 2.0, g), 2.6, n)
	sun.light_volumetric_fog_energy = lerpf(lerpf(2.0, 2.4, gw), 0.12, n)
	# sky: the photo for this sun height, golden / twilight / night modes, the true sun
	var hd: Array = Game.HDRI_DAY[0] if el >= 14.0 else (Game.HDRI_LOW[0] if el >= -6.0 else Game.HDRI_NIGHT)
	sky_mat.set_shader_parameter("hdri", load(Game.HDRI_DIR + String(hd[0])))
	sky_mat.set_shader_parameter("rotation", atan2(dirv.x, -dirv.z) - (float(hd[1]) - 0.5) * TAU)
	sky_mat.set_shader_parameter("mix_b", 0.0)
	sky_mat.set_shader_parameter("golden", gw)
	var se := deg_to_rad(el)
	sky_mat.set_shader_parameter("sun_vec", Vector3(cos(yaw) * cos(se), sin(se), sin(yaw) * cos(se)) if el > -3.0 else Vector3.ZERO)
	sky_mat.set_shader_parameter("sunny", day * (1.0 - gw))
	sky_mat.set_shader_parameter("night", n)
	sky_mat.set_shader_parameter("energy", lerpf(1.0, 0.55, n))
	sky_mat.set_shader_parameter("light_energy", lerpf(lerpf(0.55, 0.85, g), 0.2, n))
	env.ambient_light_sky_contribution = lerpf(0.8, 0.5, n)
	env.ambient_light_energy = 0.36 * float(L.get("sky", 1.0)) * lerpf(1.0, 0.3, n) * (1.0 + 0.6 * tw)
	env.ambient_light_color = Color(0.55, 0.68, 0.9).lerp(Color(0.62, 0.55, 0.78), gw * 0.6).lerp(Color(0.55, 0.45, 0.72), tw).lerp(Color(0.16, 0.22, 0.42), n)
	env.fog_density = 0.6 * lerpf(1.0, 1.35, n) * lerpf(1.0, 0.6, gw)
	env.fog_light_color = Game.RIDE_FOG.lerp(Color(0.95, 0.64, 0.46), g * day).lerp(Color(0.4, 0.3, 0.46), tw).lerp(Color(0.012, 0.016, 0.03), n)
	env.fog_aerial_perspective = 0.75 * (1.0 - n)
	env.fog_sun_scatter = 0.1 * gw * (1.0 - tw) * (1.0 - 0.6 * low)
	env.volumetric_fog_albedo = Color(0.86, 0.9, 0.95).lerp(Color(1.0, 0.8, 0.6), g * day).lerp(Color(0.7, 0.75, 0.85), n)
	env.volumetric_fog_density = Game.VOL_DENSITY * lerpf(1.0, 0.25, g * day) * lerpf(1.0, 2.2, n)
	env.volumetric_fog_ambient_inject = lerpf(lerpf(0.12, 0.03, gw), 0.0, n)
	env.tonemap_exposure = lerpf(lerpf(Game.AGX_EXP_DAY, Game.AGX_EXP_GOLD, g) + 0.75 * tw, Game.AGX_EXP_NIGHT, n) * float(L.get("exposure", 1.0))
	env.adjustment_saturation = float(L.get("saturation", 1.22)) * lerpf(1.0, 1.06, gw) * lerpf(1.0, 0.42, n)
	env.adjustment_contrast = float(L.get("contrast", 1.12)) * lerpf(1.0, 1.07, gw) * lerpf(1.0, 1.08, n)
	cam_attr.auto_exposure_enabled = n < 0.5
	cam_attr.auto_exposure_min_sensitivity = lerpf(80.0, 40.0, gw)
	cam_attr.auto_exposure_max_sensitivity = lerpf(140.0, 95.0, gw)
	env.adjustment_brightness = lerpf(1.0, 0.94, n)
	env.glow_hdr_threshold = lerpf(lerpf(0.92, 0.85, gw), 0.7, n)
	lamp.visible = n > 0.35
	# the ride's glare guard (Game._glare_guard): this view always faces a low sun, so the same easing applies
	var k := (1.0 - smoothstep(20.0, 40.0, el)) * smoothstep(-6.0, 0.0, el)
	sun.light_volumetric_fog_energy *= 1.0 - 0.8 * k
	env.fog_sun_scatter *= 1.0 - k
	env.glow_intensity = 0.25 * (1.0 - 0.65 * k)
	sky_mat.set_shader_parameter("energy", lerpf(1.0, 0.55, n) * (1.0 - 0.38 * k))
