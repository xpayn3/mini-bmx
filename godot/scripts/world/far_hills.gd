class_name FarHills
extends Node3D
## The distant landscape, title screen and ride: a coarse copy of the ground out to ~2.6 km (the same
## height field and colours) plus far trees, so the horizon is hills instead of the end of the world.
## The streamed chunks only reach ~170 m round the rider; this fills everything behind them.
##
## Built on a worker thread from a fork of the field, around a centre; rebuilt in the background once
## the rider is REBUILD m away from it. Two things follow the rider every frame on the GPU (follow()):
## - inside the streamed square it sits SINK m under the real ground, so it never shows through;
## - past ~450 m from the rider it rises into rolling ridges (stored per vertex), so every seed has a
##   skyline of hills, while near the rider it is the real ground the chunks will build.

const HALF := 2600.0      # half-size of the backdrop square
const STEP := 20.0        # ground grid (world aligned)
const TREE_CELL := 11.0   # at most one far tree per world cell
const TREE_R := 1900.0    # no far trees beyond this (fog)
const REBUILD := 900.0
const RIDGE_NEAR := 420.0
const RIDGE_FAR := 1500.0
const RIDGE_CLEAR_NEAR := 70.0    # no backdrop ridge within this of the trail, full ridge beyond ..FAR
const RIDGE_CLEAR_FAR := 200.0

const GROUND_SHADER := """
shader_type spatial;
render_mode world_vertex_coords, cull_back;
uniform vec3 rider;
uniform vec2 inner_c;
uniform float inner_half = 168.0;
uniform float sink = 5.0;
uniform float ridge_near = 420.0;
uniform float ridge_far = 1500.0;
void vertex() {
	float k = smoothstep(ridge_near, ridge_far, length(VERTEX.xz - rider.xz));
	VERTEX.y += k * CUSTOM0.w;
	NORMAL = normalize(mix(CUSTOM0.xyz, NORMAL, k));
	vec2 q = abs(VERTEX.xz - inner_c);
	float qm = max(q.x, q.y);
	// well inside the streamed square the real chunks are certainly there: go deep so no spike of the coarse
	// copy (a thin ridge / causeway / cliff sampled on a 20 m grid) can ever show through the real ground
	if (qm < inner_half) VERTEX.y -= sink + 60.0 * (1.0 - smoothstep(inner_half * 0.4, inner_half * 0.65, qm));
}
void fragment() {
	ALBEDO = COLOR.rgb;
	ROUGHNESS = 1.0;
}
"""

const TREE_SHADER := """
shader_type spatial;
render_mode world_vertex_coords, cull_back;
uniform vec3 rider;
uniform vec2 inner_c;
uniform float inner_half = 168.0;
uniform float ridge_near = 420.0;
uniform float ridge_far = 1500.0;
uniform vec3 albedo : source_color;
void vertex() {
	vec3 o = MODEL_MATRIX[3].xyz;   // the tree's base (instance origin)
	float k = smoothstep(ridge_near, ridge_far, length(o.xz - rider.xz));
	VERTEX.y += k * INSTANCE_CUSTOM.x;
	vec2 q = abs(o.xz - inner_c);
	if (max(q.x, q.y) < inner_half + 4.0) VERTEX = o - vec3(0.0, 50.0, 0.0);   // the real trees are there
}
void fragment() {
	ALBEDO = albedo * COLOR.rgb;
	ROUGHNESS = 1.0;
}
"""

static var _ground_sh: Shader
static var _tree_sh: Shader

var _terrain
var _seed := 0
var _ridge := FastNoiseLite.new()
var _roll := FastNoiseLite.new()
var _task := -1
var _job := {}            # the build in flight: {f, cx, cz, out}
var _center := Vector2(INF, INF)
var _parts: Array = []    # nodes of the current build
var _mats: Array = []
var _last := Vector3.ZERO

func setup(terrain) -> void:
	_terrain = terrain
	_seed = terrain.seed_value
	_ridge.seed = _seed
	_ridge.frequency = 1.0 / 900.0
	_ridge.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	_ridge.fractal_octaves = 4
	_roll.seed = _seed + 7
	_roll.frequency = 1.0 / 420.0
	_roll.fractal_octaves = 3
	if _ground_sh == null:
		_ground_sh = Shader.new(); _ground_sh.code = GROUND_SHADER
		_tree_sh = Shader.new(); _tree_sh.code = TREE_SHADER

## every frame: the rider's position (ridges, rebuilds) and the centre of the streamed chunk square
func follow(p: Vector3) -> void:
	_last = p
	var inner := Vector2(floorf(p.x / Terrain.SIZE + 0.5), floorf(p.z / Terrain.SIZE + 0.5)) * Terrain.SIZE
	var half := (Terrain.RADIUS + 0.5) * Terrain.SIZE
	for m in _mats:
		m.set_shader_parameter("rider", p)
		m.set_shader_parameter("inner_c", inner)
		m.set_shader_parameter("inner_half", half - 4.0)
	if _task < 0 and Vector2(p.x, p.z).distance_to(_center) > REBUILD:
		_start(p.x, p.z)

func _process(_dt: float) -> void:
	if _task >= 0 and WorkerThreadPool.is_task_completed(_task):
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1
		_swap()

func _exit_tree() -> void:
	if _task >= 0:
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1

func _start(x: float, z: float) -> void:
	_job = {"f": _terrain.query_field().fork(), "cx": snappedf(x, STEP * 11.0), "cz": snappedf(z, STEP * 11.0)}
	_task = WorkerThreadPool.add_task(_run, false, "far hills")

## extra height of the backdrop ridges at full strength (the shaders fade it in with rider distance)
func _ridge_h(x: float, z: float) -> float:
	return (_ridge.get_noise_2d(x, z) * 0.5 + 0.5) * 150.0 + (_roll.get_noise_2d(x, z) * 0.5 + 0.5) * 45.0

static func _cell_rand(ix: int, iz: int, k: int) -> float:
	var h := (ix * 73856093) ^ (iz * 19349663) ^ (k * 83492791)
	h = (h ^ (h >> 13)) * 1274126177
	h ^= h >> 16
	return float(h & 0xffffff) / 16777215.0

func _run() -> void:
	var f = _job.f
	var cx: float = _job.cx
	var cz: float = _job.cz
	var n := int(HALF * 2.0 / STEP) + 1
	var x0 := cx - HALF
	var z0 := cz - HALF
	var hg := PackedFloat32Array(); hg.resize(n * n)   # real ground
	var hr := PackedFloat32Array(); hr.resize(n * n)   # ridge on top
	# no backdrop ridges over the trail: how far each cell is from the course (capped), then a fade
	var rm := PackedFloat32Array(); rm.resize(n * n)
	rm.fill(RIDGE_CLEAR_FAR)
	var C = f.course
	var rr := int(ceil(RIDGE_CLEAR_FAR / STEP))
	for ci in range(0, C.n, 3):
		var px: float = C.X[ci]
		var pz: float = C.Z[ci]
		var gx := int(roundf((px - x0) / STEP))
		var gz := int(roundf((pz - z0) / STEP))
		if gx < -rr or gz < -rr or gx > n + rr or gz > n + rr:
			continue
		for jz in range(maxi(0, gz - rr), mini(n - 1, gz + rr) + 1):
			for jx in range(maxi(0, gx - rr), mini(n - 1, gx + rr) + 1):
				var d := Vector2(x0 + jx * STEP - px, z0 + jz * STEP - pz).length()
				if d < rm[jz * n + jx]:
					rm[jz * n + jx] = d
	for k in n * n:
		rm[k] = smoothstep(RIDGE_CLEAR_NEAR, RIDGE_CLEAR_FAR, rm[k])
	var batched: bool = f.has_method("far_ground")   # C#: the whole grid in one call (per-point calls from a worker
	if batched:                                     # left engine objects for the GC; HANDOFF "never call per point")
		hg = f.far_ground(x0, z0, STEP, n)
	for iz in n:
		for ix in n:
			var x := x0 + ix * STEP
			var z := z0 + iz * STEP
			if not batched: hg[iz * n + ix] = f.ground(x, z)
			hr[iz * n + ix] = _ridge_h(x, z) * rm[iz * n + ix]
	# despike: a lone sample far above all four neighbours (a thin raised trail on a 20 m grid) would be a
	# tower in the coarse mesh
	var hs := hg.duplicate()
	for iz in range(1, n - 1):
		for ix in range(1, n - 1):
			var i0 := iz * n + ix
			var top := maxf(maxf(hs[i0 - 1], hs[i0 + 1]), maxf(hs[i0 - n], hs[i0 + n]))
			if hs[i0] > top + 4.0:
				hg[i0] = top + 4.0
	var verts := PackedVector3Array(); verts.resize(n * n)
	var norms := PackedVector3Array(); norms.resize(n * n)
	var cols := PackedColorArray(); cols.resize(n * n)
	var cust := PackedFloat32Array(); cust.resize(n * n * 4)
	var slope := PackedFloat32Array(); slope.resize(n * n)
	for iz in n:
		for ix in n:
			var i := iz * n + ix
			var x := x0 + ix * STEP
			var z := z0 + iz * STEP
			var il := iz * n + maxi(ix - 1, 0)
			var ir := iz * n + mini(ix + 1, n - 1)
			var id := maxi(iz - 1, 0) * n + ix
			var iu := mini(iz + 1, n - 1) * n + ix
			var ng := Vector3(hg[il] - hg[ir], STEP * 2.0, hg[id] - hg[iu]).normalized()
			var nf := Vector3(hg[il] + hr[il] - hg[ir] - hr[ir], STEP * 2.0, hg[id] + hr[id] - hg[iu] - hr[iu]).normalized()
			verts[i] = Vector3(x, hg[i], z)
			norms[i] = nf   # with the ridges at full height; CUSTOM0 = the plain ground's normal + ridge height
			cust[i * 4] = ng.x; cust[i * 4 + 1] = ng.y; cust[i * 4 + 2] = ng.z; cust[i * 4 + 3] = hr[i]
			# coloured as the plain ground (the ridges would otherwise read as snow and scree)
			slope[i] = maxf(minf(ng.y, nf.y), 0.82)
			if not batched: cols[i] = f.color(x, z, hg[i], slope[i])
	if batched:
		cols = f.far_colors(x0, z0, STEP, n, hg, slope)
	var idx := PackedInt32Array(); idx.resize((n - 1) * (n - 1) * 6)
	var w := 0
	for iz in n - 1:
		for ix in n - 1:
			var a := iz * n + ix
			idx[w] = a; idx[w + 1] = a + 1; idx[w + 2] = a + n
			idx[w + 3] = a + 1; idx[w + 4] = a + n + 1; idx[w + 5] = a + n
			w += 6
	# far trees: the chunk builder's forest noise, one chance per world cell (same trees after a rebuild)
	var pines := PackedFloat32Array()
	var blobs := PackedFloat32Array()
	var c0x := int(floorf((cx - TREE_R) / TREE_CELL))
	var c0z := int(floorf((cz - TREE_R) / TREE_CELL))
	var m := int(TREE_R * 2.0 / TREE_CELL)
	for jz in m:
		for jx in m:
			var gx := c0x + jx
			var gz := c0z + jz
			var x := (gx + _cell_rand(gx, gz, 1)) * TREE_CELL
			var z := (gz + _cell_rand(gx, gz, 2)) * TREE_CELL
			if Vector2(x - cx, z - cz).length() > TREE_R:
				continue
			var r := _cell_rand(gx, gz, 3)
			var r2 := _cell_rand(gx, gz, 4)
			var forest: float = f.n(x + 400, z, TerrainField.I38)
			if r > smoothstep(-0.25, 0.25, forest) * 0.9 + 0.05:
				continue
			f.biome(x, z)
			if r2 < float(f.b_dry):
				continue
			var h: float = f.ground(x, z)
			if h < Terrain.WATER + 0.4 or f.trail(x, z) > 0.02:
				continue
			var sc := 1.0 + _cell_rand(gx, gz, 5) * 0.9
			var pine := h > 4.0 or r2 < 0.3 + float(f.b_rug) * 0.6
			var shade := 0.75 + _cell_rand(gx, gz, 6) * 0.35
			var tw := sc * (1.5 if pine else 2.1)
			var ht := sc * (6.5 if pine else 4.2)
			# Transform3D rows (round shapes: no yaw), colour, custom (x = ridge height under the tree).
			# The origin is the base; the mesh is lifted inside the transform so it stands on it.
			var rec := PackedFloat32Array([tw, 0, 0, x, 0, ht, 0, h, 0, 0, tw, z,
				shade, shade, shade, 1.0, _ridge_h(x, z) * rm[clampi(int(roundf((z - z0) / STEP)), 0, n - 1) * n + clampi(int(roundf((x - x0) / STEP)), 0, n - 1)], 0, 0, 0])
			if pine: pines.append_array(rec)
			else: blobs.append_array(rec)
	_job.out = {"verts": verts, "norms": norms, "cols": cols, "cust": cust, "idx": idx,
		"pines": pines, "blobs": blobs, "cx": cx, "cz": cz}
	_job.f = null

func _swap() -> void:
	var o: Dictionary = _job.out
	_job = {}
	for p in _parts: p.queue_free()
	_parts.clear()
	_mats.clear()
	_center = Vector2(o.cx, o.cz)
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = o.verts
	arr[Mesh.ARRAY_NORMAL] = o.norms
	arr[Mesh.ARRAY_COLOR] = o.cols
	arr[Mesh.ARRAY_CUSTOM0] = o.cust
	arr[Mesh.ARRAY_INDEX] = o.idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr, [], {},
		Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT)
	var mat := ShaderMaterial.new()
	mat.shader = _ground_sh
	_mats.append(mat)
	var gi := MeshInstance3D.new()
	gi.mesh = mesh
	gi.material_override = mat
	gi.extra_cull_margin = 220.0   # the ridges are raised in the shader
	gi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(gi)
	_parts.append(gi)
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0; cone.bottom_radius = 0.5; cone.height = 1.0
	cone.radial_segments = 6; cone.rings = 0; cone.cap_bottom = false
	var ball := SphereMesh.new()
	ball.radius = 0.5; ball.height = 1.0; ball.radial_segments = 7; ball.rings = 3
	_trees(_lifted(cone, 0.5), o.pines, Color("2f6247"))
	_trees(_lifted(ball, 0.75), o.blobs, Color("4f7d34"))
	follow(_last)

## the mesh with its base at the origin (y + lift), so the instance origin is where it meets the ground
func _lifted(src: PrimitiveMesh, lift: float) -> ArrayMesh:
	var a := src.get_mesh_arrays()
	var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
	for i in v.size(): v[i].y += lift
	a[Mesh.ARRAY_VERTEX] = v
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a)
	return m

func _trees(mesh: Mesh, buf: PackedFloat32Array, col: Color) -> void:
	var count := buf.size() / 20
	if count == 0: return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = mesh
	mm.instance_count = count
	mm.buffer = buf
	var mat := ShaderMaterial.new()
	mat.shader = _tree_sh
	mat.set_shader_parameter("albedo", col)
	_mats.append(mat)
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.material_override = mat
	mi.extra_cull_margin = 220.0
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	_parts.append(mi)
