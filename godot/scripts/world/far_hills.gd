class_name FarHills
extends Node3D
## Title-screen backdrop: a coarse copy of the landscape out to ~1.6 km (the same height field and
## ground colours), plus far trees as two MultiMeshes. The streamed chunks only reach ~170 m round the
## rider; this fills the vista behind them. Built on a worker thread from a fork of the field; inside
## the streamed square it sits a few metres under the real ground so it never shows through.
## Past ~450 m it rises into rolling ridges (title screen only), so every world gets a skyline of hills.

const HALF := 2600.0      # half-size of the backdrop square
const STEP := 20.0        # ground grid
const TREE_CELL := 11.0   # at most one far tree per cell
const INNER := 164.0      # half-size of the streamed square (7 chunks x 48 m = 336 m)
const SINK := 5.0

var _f
var _cx := 0.0
var _cz := 0.0
var _task := -1
var _out := {}
var _ridge := FastNoiseLite.new()
var _roll := FastNoiseLite.new()

func build(terrain, x: float, z: float) -> void:
	_f = terrain.query_field().fork()
	_ridge.seed = terrain.seed_value
	_ridge.frequency = 1.0 / 900.0
	_ridge.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	_ridge.fractal_octaves = 4
	_roll.seed = terrain.seed_value + 7
	_roll.frequency = 1.0 / 420.0
	_roll.fractal_octaves = 3
	# the streamed square is centred on the rider's chunk
	_cx = roundf(x / Terrain.SIZE) * Terrain.SIZE
	_cz = roundf(z / Terrain.SIZE) * Terrain.SIZE
	_task = WorkerThreadPool.add_task(_run, false, "far hills")

func _process(_dt: float) -> void:
	if _task >= 0 and WorkerThreadPool.is_task_completed(_task):
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1
		_make()

func _exit_tree() -> void:
	if _task >= 0:
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1

func _inside(x: float, z: float, pad: float) -> bool:
	return absf(x - _cx) < INNER - pad and absf(z - _cz) < INNER - pad

## ground height + the backdrop ridges, which grow in with distance from the rider
func _h(f, x: float, z: float) -> float:
	var k := smoothstep(420.0, 1500.0, Vector2(x - _cx, z - _cz).length())
	if k <= 0.0:
		return f.ground(x, z)
	var r := (_ridge.get_noise_2d(x, z) * 0.5 + 0.5) * 150.0 + (_roll.get_noise_2d(x, z) * 0.5 + 0.5) * 45.0
	return f.ground(x, z) + k * r

func _run() -> void:
	var f = _f
	var n := int(HALF * 2.0 / STEP) + 1
	var x0 := _cx - HALF
	var z0 := _cz - HALF
	var hs := PackedFloat32Array(); hs.resize(n * n)
	for iz in n:
		for ix in n:
			hs[iz * n + ix] = _h(f, x0 + ix * STEP, z0 + iz * STEP)
	var verts := PackedVector3Array(); verts.resize(n * n)
	var norms := PackedVector3Array(); norms.resize(n * n)
	var cols := PackedColorArray(); cols.resize(n * n)
	for iz in n:
		for ix in n:
			var i := iz * n + ix
			var x := x0 + ix * STEP
			var z := z0 + iz * STEP
			var h := hs[i]
			var hl := hs[iz * n + maxi(ix - 1, 0)]
			var hr := hs[iz * n + mini(ix + 1, n - 1)]
			var hd := hs[maxi(iz - 1, 0) * n + ix]
			var hu := hs[mini(iz + 1, n - 1) * n + ix]
			var nrm := Vector3(hl - hr, STEP * 2.0, hd - hu).normalized()
			norms[i] = nrm
			# coloured as the unraised ground (the ridges would otherwise read as snow and scree)
			cols[i] = f.color(x, z, f.ground(x, z), maxf(nrm.y, 0.82))
			verts[i] = Vector3(x, h - (SINK if _inside(x, z, -STEP) else 0.0), z)
	var idx := PackedInt32Array()
	for iz in n - 1:
		for ix in n - 1:
			var a := iz * n + ix
			idx.append_array([a, a + 1, a + n, a + 1, a + n + 1, a + n])
	# far trees: same forest noise as the chunk builder, thinned to one per cell
	var pines := PackedFloat32Array()
	var blobs := PackedFloat32Array()
	var rng := RandomNumberGenerator.new()
	rng.seed = 91731
	var m := int(HALF * 2.0 / TREE_CELL)
	for iz in m:
		for ix in m:
			var x := x0 + (ix + rng.randf()) * TREE_CELL
			var z := z0 + (iz + rng.randf()) * TREE_CELL
			var r := rng.randf()
			var r2 := rng.randf()
			var sc := 1.0 + rng.randf() * 0.9
			if _inside(x, z, 0.0) or Vector2(x - _cx, z - _cz).length() > 1900.0:
				continue
			var forest: float = f.n(x + 400, z, TerrainField.I38)
			if r > smoothstep(-0.25, 0.25, forest) * 0.9 + 0.05:
				continue
			f.biome(x, z)
			if r2 < float(f.b_dry):
				continue
			var h: float = _h(f, x, z)
			if h < Terrain.WATER + 0.4 or f.trail(x, z) > 0.02:
				continue
			var pine := h > 4.0 or r2 < 0.3 + float(f.b_rug) * 0.6
			var shade := 0.75 + rng.randf() * 0.35
			var buf := pines if pine else blobs
			var w := sc * (1.5 if pine else 2.1)
			var ht := sc * (6.5 if pine else 4.2)
			# Transform3D rows (basis scaled, no yaw needed for round shapes) + colour
			buf.append_array([w, 0, 0, x, 0, ht, 0, h + ht * (0.5 if pine else 0.75), 0, 0, w, z,
				shade, shade, shade, 1.0])
	_out = {"verts": verts, "norms": norms, "cols": cols, "idx": idx, "pines": pines, "blobs": blobs}

func _make() -> void:
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = _out.verts
	arr[Mesh.ARRAY_NORMAL] = _out.norms
	arr[Mesh.ARRAY_COLOR] = _out.cols
	arr[Mesh.ARRAY_INDEX] = _out.idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 1.0
	var gi := MeshInstance3D.new()
	gi.mesh = mesh
	gi.material_override = mat
	gi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(gi)
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0; cone.bottom_radius = 0.5; cone.height = 1.0
	cone.radial_segments = 6; cone.rings = 0; cone.cap_bottom = false
	var ball := SphereMesh.new()
	ball.radius = 0.5; ball.height = 1.0; ball.radial_segments = 7; ball.rings = 3
	_trees(cone, _out.pines, Color("2f6247"))
	_trees(ball, _out.blobs, Color("4f7d34"))
	_out = {}

func _trees(mesh: Mesh, buf: PackedFloat32Array, col: Color) -> void:
	var count := buf.size() / 16
	if count == 0: return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = count
	mm.buffer = buf
	var mat := StandardMaterial3D.new()
	mat.albedo_color = col
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 1.0
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
