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
## the finer middle ring (2026-11-25): the same ground at 8 m (the chunks' own coarsest LOD) from where the real ground
## dissolves out (shaders/ground ground_fade) to MID_BAND_OUT, where the 20 m backdrop takes over, again dithered.
const MID_HALF := 880.0           # >= MID_BAND_OUT + MID_REBUILD + what the rider covers while it builds
const MID_STEP := 8.0
const MID_REBUILD := 200.0
const MID_BAND_IN := 560.0
const MID_BAND_OUT := 620.0
const RM_STEP := 20.0             # grid of the "no backdrop ridge over the trail" map (shared by both rings)
const WATER_COL := Color(0.10, 0.22, 0.28)   # lakes continue past the chunks: flat, 0.3 m under the water sheet's level

const GROUND_SHADER := """
shader_type spatial;
render_mode world_vertex_coords, cull_back;
uniform vec3 rider;
uniform vec2 inner_c;
uniform float inner_half = 168.0;
uniform float sink = 5.0;
uniform float ridge_near = 420.0;
uniform float ridge_far = 1500.0;
uniform float ring = 0.0;          // 0 the 20 m backdrop, 1 the finer middle ring
uniform float mid_ready = 0.0;     // 1 once the middle ring is built (until then the backdrop draws its part too)
uniform vec2 mid_band = vec2(560.0, 620.0);
global uniform vec4 ground_fade;   // xy rider xz, z = real ground full until, w = gone by (w <= 0: off, the old hard square)
varying vec3 wp;
void vertex() {
	float k = smoothstep(ridge_near, ridge_far, length(VERTEX.xz - rider.xz));
	VERTEX.y += k * CUSTOM0.w;
	NORMAL = normalize(mix(CUSTOM0.xyz, NORMAL, k));
	wp = VERTEX;
	if (ground_fade.w <= 0.0) {
		vec2 q = abs(VERTEX.xz - inner_c);
		float qm = max(q.x, q.y);
		// well inside the streamed square the real chunks are certainly there: go deep so no spike of the coarse
		// copy (a thin ridge / causeway / cliff sampled on a 20 m grid) can ever show through the real ground
		if (qm < inner_half) VERTEX.y -= sink + 60.0 * (1.0 - smoothstep(inner_half * 0.4, inner_half * 0.65, qm));
	}
	// (crossfade mode: no sink. Every pixel is drawn by exactly one of the real ground, the middle ring and the backdrop,
	// and none of them casts a shadow, so nothing can show through)
}
void fragment() {
	if (ground_fade.w > 0.0) {
		if (PROJECTION_MATRIX[3][3] < 0.5) {
			float d = distance(wp.xz, ground_fade.xy);
			float gk = 1.0 - smoothstep(ground_fade.z, ground_fade.w, d);
			float n1 = fract(52.9829189 * fract(dot(FRAGCOORD.xy, vec2(0.06711056, 0.00583715))));
			if (n1 < gk) discard;   // the real ground (shaders/ground) draws exactly these pixels
			float km = mid_ready * (1.0 - smoothstep(mid_band.x, mid_band.y, d));
			float n2 = fract(52.9829189 * fract(dot(FRAGCOORD.xy, vec2(0.00583715, 0.06711056))) + 0.37);
			if (ring > 0.5) { if (n2 >= km) discard; }   // the middle ring: inside its band
			else { if (n2 < km) discard; }               // the backdrop: what the middle ring leaves
		}
	} else if (ring > 0.5) {
		discard;
	}
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
#include "res://shaders/deco_fade.gdshaderinc"
varying flat vec3 v_origin;
void vertex() {
	vec3 o = MODEL_MATRIX[3].xyz;   // the tree's base (instance origin)
	v_origin = o;
	float k = smoothstep(ridge_near, ridge_far, length(o.xz - rider.xz));
	VERTEX.y += k * INSTANCE_CUSTOM.x;
	if (deco_fade.w > 0.0) {
		// the real trees fade out over deco_fade's band round the rider and these fade in over it (fragment):
		// a smooth circle instead of the streamed chunk square, which jumped 48 m at every chunk line
		if (distance(o.xz, deco_fade.xy) < deco_fade.z - 1.0) VERTEX = o - vec3(0.0, 50.0, 0.0);
	} else {
		vec2 q = abs(o.xz - inner_c);
		if (max(q.x, q.y) < inner_half + 4.0) VERTEX = o - vec3(0.0, 50.0, 0.0);   // the real trees are there
	}
}
void fragment() {
	if (deco_cut(v_origin, -1.0, FRAGCOORD.xy, false)) discard;
	ALBEDO = albedo * COLOR.rgb;
	ROUGHNESS = 1.0;
}
"""

## Far trees as impostors (2026-11-26, user: "a PNG of our trees for the furthest view"): each far tree is a quad turned
## to the camera about its upright axis, showing one cell of assets/textures/tree_cards/impostors.png (our card trees
## rendered side-on by tools/bake_tree_impostors.tscn; cells 0-1 pines, 2-3 leafy trees, picked per tree by a hash of
## its place). Lit with a rounded normal (out of the quad's middle, toward the camera, a little up) so it shades like
## a volume. The cut-out's alpha is raised in the small mips (no thinning out with distance). Without the atlas, or
## BMX_OLD_TREES=1: the old cones and balls.
const IMPOSTOR_PNG := "res://assets/textures/tree_cards/impostors.png"
const IMPOSTOR_SHADER := """
shader_type spatial;
render_mode world_vertex_coords, cull_disabled, diffuse_burley, specular_schlick_ggx;
uniform vec3 rider;
uniform vec2 inner_c;
uniform float inner_half = 168.0;
uniform float ridge_near = 420.0;
uniform float ridge_far = 1500.0;
uniform vec3 albedo : source_color;
uniform sampler2D atlas : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform float cells = 4.0;
uniform float cell0 = 0.0;     // this kind's first cell
uniform float variants = 2.0;  // cells of this kind
uniform float fill = 1.0;      // how much of a cell's height the tree covers (the quad grows by 1 / fill)
#include "res://shaders/deco_fade.gdshaderinc"
varying flat vec3 v_origin;
varying flat float v_cell;
varying vec3 v_right;
varying vec3 v_fwd;
void vertex() {
	vec3 o = MODEL_MATRIX[3].xyz;   // the tree's base
	v_origin = o;
	float h = length(MODEL_MATRIX[1].xyz) / fill;
	vec3 to = CAMERA_POSITION_WORLD - o;
	to.y = 0.0;
	vec3 f = normalize(to + vec3(1e-4, 0.0, 0.0));
	vec3 r = vec3(f.z, 0.0, -f.x);
	VERTEX = o + r * (UV.x - 0.5) * h * 0.5 + vec3(0.0, (1.0 - UV.y) * h, 0.0);
	NORMAL = f;
	v_right = r;
	v_fwd = f;
	v_cell = cell0 + min(floor(fract(sin(dot(o.xz, vec2(12.9898, 78.233))) * 43758.5453) * variants), variants - 1.0);
	float k = smoothstep(ridge_near, ridge_far, length(o.xz - rider.xz));
	VERTEX.y += k * INSTANCE_CUSTOM.x;
	if (deco_fade.w > 0.0) {
		if (distance(o.xz, deco_fade.xy) < deco_fade.z - 1.0) VERTEX = o - vec3(0.0, 50.0, 0.0);
	} else {
		vec2 q = abs(o.xz - inner_c);
		if (max(q.x, q.y) < inner_half + 4.0) VERTEX = o - vec3(0.0, 50.0, 0.0);   // the real trees are there
	}
}
void fragment() {
	if (deco_cut(v_origin, -1.0, FRAGCOORD.xy, false)) discard;
	vec2 uv = vec2((v_cell + clamp(UV.x, 0.002, 0.998)) / cells, UV.y);
	vec4 t = texture(atlas, uv);
	float lod = textureQueryLod(atlas, uv).x;
	ALPHA = clamp(t.a * (1.0 + max(lod, 0.0) * 0.3), 0.0, 1.0);
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	ALBEDO = t.rgb * COLOR.rgb;
	vec3 nw = normalize(v_right * (UV.x - 0.5) * 1.6 + v_fwd * 0.75 + vec3(0.0, 0.3, 0.0));
	NORMAL = normalize((VIEW_MATRIX * vec4(nw, 0.0)).xyz);
	ROUGHNESS = 1.0;
	SPECULAR = 0.1;
}
"""
static var _imp_sh: Shader
static var _imp_tex: Texture2D
static var _imp_meta := {}
static var _imp_quad: ArrayMesh

static var ground_crossfade := false   # Game: the ground crossfade (global ground_fade) is on, so the middle ring is used
static var _ground_sh: Shader
static var _tree_sh: Shader

var _terrain
var _seed := 0
var ridge_gain := 1.0   # the title screen raises the backdrop ridges into real mountains (set before setup)
var _ridge := FastNoiseLite.new()
var _roll := FastNoiseLite.new()
var _last := Vector3.ZERO
# the two grids: [0] the 20 m backdrop (out to HALF, with the far trees), [1] the finer middle ring
var _rings: Array = [
	{"half": HALF, "step": STEP, "rebuild": REBUILD, "trees": true, "task": -1, "job": {}, "center": Vector2(INF, INF), "parts": [], "mats": []},
	{"half": MID_HALF, "step": MID_STEP, "rebuild": MID_REBUILD, "trees": false, "task": -1, "job": {}, "center": Vector2(INF, INF), "parts": [], "mats": []},
]

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
	var mid_ready := 1.0 if (_rings[1].center as Vector2).x != INF else 0.0
	for r in _rings:
		for m in r.mats:
			m.set_shader_parameter("rider", p)
			m.set_shader_parameter("inner_c", inner)
			m.set_shader_parameter("inner_half", half - 4.0)
			m.set_shader_parameter("mid_ready", mid_ready)
	var fade_on := ground_crossfade
	for i in _rings.size():
		var r: Dictionary = _rings[i]
		if i == 1 and not fade_on:
			continue   # the middle ring only exists in the crossfade mode
		if r.task < 0 and Vector2(p.x, p.z).distance_to(r.center) > r.rebuild:
			_start(i, p.x, p.z)

func _process(_dt: float) -> void:
	for i in _rings.size():
		var r: Dictionary = _rings[i]
		if r.task >= 0 and WorkerThreadPool.is_task_completed(r.task):
			WorkerThreadPool.wait_for_task_completion(r.task)
			r.task = -1
			_swap(i)

func _exit_tree() -> void:
	for r in _rings:
		if r.task >= 0:
			WorkerThreadPool.wait_for_task_completion(r.task)
			r.task = -1

func _start(i: int, x: float, z: float) -> void:
	var r: Dictionary = _rings[i]
	var sn: float = r.step * 11.0
	r.job = {"f": _terrain.query_field().fork(), "cx": snappedf(x, sn), "cz": snappedf(z, sn),
		"half": r.half, "step": r.step, "trees": r.trees, "ring": i}
	r.task = WorkerThreadPool.add_task(_run.bind(r.job), false, "far hills %d" % i)

## extra height of the backdrop ridges at full strength (the shaders fade it in with rider distance)
func _ridge_h(x: float, z: float) -> float:
	return ((_ridge.get_noise_2d(x, z) * 0.5 + 0.5) * 150.0 + (_roll.get_noise_2d(x, z) * 0.5 + 0.5) * 45.0) * ridge_gain

## the drawn backdrop surface at (x, z) seen from `from` (ground + the ridge faded in with distance): for placing things on the skyline
func surface_h(x: float, z: float, from: Vector2) -> float:
	var d := Vector2(x, z).distance_to(from)
	return _terrain.height(x, z) + _ridge_h(x, z) * smoothstep(RIDGE_NEAR, RIDGE_FAR, d)

static func _cell_rand(ix: int, iz: int, k: int) -> float:
	var h := (ix * 73856093) ^ (iz * 19349663) ^ (k * 83492791)
	h = (h ^ (h >> 13)) * 1274126177
	h ^= h >> 16
	return float(h & 0xffffff) / 16777215.0

## bilinear read of the ridge-clear map (grid coordinates)
static func _rm_at(rm: PackedFloat32Array, nr: int, gx: float, gz: float) -> float:
	gx = clampf(gx, 0.0, nr - 1.0)
	gz = clampf(gz, 0.0, nr - 1.0)
	var ix := mini(int(gx), nr - 2)
	var iz := mini(int(gz), nr - 2)
	var fx := gx - ix
	var fz := gz - iz
	var i := iz * nr + ix
	return lerpf(lerpf(rm[i], rm[i + 1], fx), lerpf(rm[i + nr], rm[i + nr + 1], fx), fz)

func _run(job: Dictionary) -> void:
	var f = job.f
	var cx: float = job.cx
	var cz: float = job.cz
	var half: float = job.half
	var step: float = job.step
	var n := int(half * 2.0 / step) + 1
	var x0 := cx - half
	var z0 := cz - half
	var hg := PackedFloat32Array(); hg.resize(n * n)   # real ground
	var hr := PackedFloat32Array(); hr.resize(n * n)   # ridge on top
	# no backdrop ridges over the trail: how far each cell of a 20 m map is from the course (capped), then a fade
	# (both rings read this one map, bilinear)
	var nr := int(half * 2.0 / RM_STEP) + 1
	var rm := PackedFloat32Array(); rm.resize(nr * nr)
	rm.fill(RIDGE_CLEAR_FAR)
	var C = f.course
	var rr := int(ceil(RIDGE_CLEAR_FAR / RM_STEP))
	for ci in range(0, C.n, 3):
		var px: float = C.X[ci]
		var pz: float = C.Z[ci]
		var gx := int(roundf((px - x0) / RM_STEP))
		var gz := int(roundf((pz - z0) / RM_STEP))
		if gx < -rr or gz < -rr or gx > nr + rr or gz > nr + rr:
			continue
		for jz in range(maxi(0, gz - rr), mini(nr - 1, gz + rr) + 1):
			for jx in range(maxi(0, gx - rr), mini(nr - 1, gx + rr) + 1):
				var d := Vector2(x0 + jx * RM_STEP - px, z0 + jz * RM_STEP - pz).length()
				if d < rm[jz * nr + jx]:
					rm[jz * nr + jx] = d
	for k in nr * nr:
		rm[k] = smoothstep(RIDGE_CLEAR_NEAR, RIDGE_CLEAR_FAR, rm[k])
	var batched: bool = f.has_method("far_ground")   # C#: the whole grid in one call (per-point calls from a worker
	if batched:                                     # left engine objects for the GC; HANDOFF "never call per point")
		hg = f.far_ground(x0, z0, step, n)
	for iz in n:
		for ix in n:
			var x := x0 + ix * step
			var z := z0 + iz * step
			if not batched: hg[iz * n + ix] = f.ground(x, z)
			hr[iz * n + ix] = _ridge_h(x, z) * _rm_at(rm, nr, (x - x0) / RM_STEP, (z - z0) / RM_STEP)
	# despike: a lone sample far above all four neighbours (a thin raised trail on a coarse grid) would be a
	# tower in the mesh
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
			var x := x0 + ix * step
			var z := z0 + iz * step
			var il := iz * n + maxi(ix - 1, 0)
			var ir := iz * n + mini(ix + 1, n - 1)
			var id := maxi(iz - 1, 0) * n + ix
			var iu := mini(iz + 1, n - 1) * n + ix
			var ng := Vector3(hg[il] - hg[ir], step * 2.0, hg[id] - hg[iu]).normalized()
			var nf := Vector3(hg[il] + hr[il] - hg[ir] - hr[ir], step * 2.0, hg[id] + hr[id] - hg[iu] - hr[iu]).normalized()
			verts[i] = Vector3(x, hg[i], z)
			norms[i] = nf   # with the ridges at full height; CUSTOM0 = the plain ground's normal + ridge height
			cust[i * 4] = ng.x; cust[i * 4 + 1] = ng.y; cust[i * 4 + 2] = ng.z; cust[i * 4 + 3] = hr[i]
			# coloured as the plain ground (the ridges would otherwise read as snow and scree)
			slope[i] = maxf(minf(ng.y, nf.y), 0.82)
			if not batched: cols[i] = f.color(x, z, hg[i], slope[i])
	if batched:
		cols = f.far_colors(x0, z0, step, n, hg, slope)
	# lakes: flat water-coloured cells, 0.3 m under the water sheet (which only exists inside the loaded chunks), no ridge
	for i in n * n:
		if hg[i] < Terrain.WATER:
			verts[i].y = Terrain.WATER - 0.3
			norms[i] = Vector3.UP
			cust[i * 4] = 0.0; cust[i * 4 + 1] = 1.0; cust[i * 4 + 2] = 0.0; cust[i * 4 + 3] = 0.0
			cols[i] = WATER_COL
	var idx := PackedInt32Array(); idx.resize((n - 1) * (n - 1) * 6)
	var w := 0
	for iz in n - 1:
		for ix in n - 1:
			var a := iz * n + ix
			idx[w] = a; idx[w + 1] = a + 1; idx[w + 2] = a + n
			idx[w + 3] = a + 1; idx[w + 4] = a + n + 1; idx[w + 5] = a + n
			w += 6
	# far trees (the backdrop only): the chunk builder's forest noise, one chance per world cell (same trees after a rebuild)
	var pines := PackedFloat32Array()
	var blobs := PackedFloat32Array()
	if job.trees:
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
				var rmv := rm[clampi(int(roundf((z - z0) / RM_STEP)), 0, nr - 1) * nr + clampi(int(roundf((x - x0) / RM_STEP)), 0, nr - 1)]
				var rec := PackedFloat32Array([tw, 0, 0, x, 0, ht, 0, h, 0, 0, tw, z,
					shade, shade, shade, 1.0, _ridge_h(x, z) * rmv, 0, 0, 0])
				if pine: pines.append_array(rec)
				else: blobs.append_array(rec)
	job.out = {"verts": verts, "norms": norms, "cols": cols, "cust": cust, "idx": idx,
		"pines": pines, "blobs": blobs, "cx": cx, "cz": cz}
	job.f = null

func _swap(i: int) -> void:
	var r: Dictionary = _rings[i]
	var o: Dictionary = r.job.out
	r.job = {}
	for p in r.parts: p.queue_free()
	r.parts.clear()
	r.mats.clear()
	r.center = Vector2(o.cx, o.cz)
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
	mat.set_shader_parameter("ring", float(i))
	mat.set_shader_parameter("mid_band", Vector2(MID_BAND_IN, MID_BAND_OUT))
	r.mats.append(mat)
	var gi := MeshInstance3D.new()
	gi.mesh = mesh
	gi.material_override = mat
	gi.extra_cull_margin = 220.0   # the ridges are raised in the shader
	gi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(gi)
	r.parts.append(gi)
	if r.trees:
		var cone := CylinderMesh.new()
		cone.top_radius = 0.0; cone.bottom_radius = 0.5; cone.height = 1.0
		cone.radial_segments = 6; cone.rings = 0; cone.cap_bottom = false
		var ball := SphereMesh.new()
		ball.radius = 0.5; ball.height = 1.0; ball.radial_segments = 7; ball.rings = 3
		if _impostors():
			_trees(r, _imp_quad, o.pines, Color("2f6247"), "pine")
			_trees(r, _imp_quad, o.blobs, Color("4f7d34"), "leafy")
		else:
			_trees(r, _lifted(cone, 0.5), o.pines, Color("2f6247"))
			_trees(r, _lifted(ball, 0.75), o.blobs, Color("4f7d34"))
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

## the impostor atlas + its cells (impostors.json), loaded once; false = draw the old cones / balls
static func _impostors() -> bool:
	if OS.get_environment("BMX_OLD_TREES") == "1" or not ResourceLoader.exists(IMPOSTOR_PNG):
		return false
	if _imp_sh == null:
		_imp_sh = Shader.new(); _imp_sh.code = IMPOSTOR_SHADER
		_imp_tex = load(IMPOSTOR_PNG)
		var j = JSON.parse_string(FileAccess.get_file_as_string(IMPOSTOR_PNG.get_basename() + ".json"))
		_imp_meta = j if j is Dictionary else {"cells": 4, "trees": []}
		# a quad of UVs (the shader places it); its box covers a tree for culling (+ extra_cull_margin)
		var a := []
		a.resize(Mesh.ARRAY_MAX)
		a[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3(-0.6, 0, 0), Vector3(0.6, 0, 0), Vector3(0.6, 2.0, 0), Vector3(-0.6, 2.0, 0)])
		a[Mesh.ARRAY_TEX_UV] = PackedVector2Array([Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)])
		a[Mesh.ARRAY_NORMAL] = PackedVector3Array([Vector3.BACK, Vector3.BACK, Vector3.BACK, Vector3.BACK])
		a[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 2, 1, 0, 3, 2])
		_imp_quad = ArrayMesh.new()
		_imp_quad.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a)
	return true

func _trees(r: Dictionary, mesh: Mesh, buf: PackedFloat32Array, col: Color, imp_kind := "") -> void:
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
	if imp_kind != "":
		mat.shader = _imp_sh
		mat.set_shader_parameter("atlas", _imp_tex)
		var cells: Array = _imp_meta.get("trees", [])
		var first := -1
		var n := 0
		var fill := 0.0
		for i in cells.size():
			if cells[i].kind == imp_kind:
				if first < 0: first = i
				n += 1
				fill += float(cells[i].fill)
		mat.set_shader_parameter("cells", float(_imp_meta.get("cells", 4)))
		mat.set_shader_parameter("cell0", float(maxi(first, 0)))
		mat.set_shader_parameter("variants", float(maxi(n, 1)))
		mat.set_shader_parameter("fill", fill / maxi(n, 1) if n > 0 else 1.0)
	r.mats.append(mat)
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.material_override = mat
	mi.extra_cull_margin = 220.0
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	r.parts.append(mi)
