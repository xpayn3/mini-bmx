class_name FX
extends Node3D
## Riding effects (port of src/fx.js): soft dust smoke and flying dirt/rock chunks. All pools are fixed-size ring
## buffers; nothing is allocated per frame (the tyre tracks are in the ground now: world/ruts.gd):
##  * dust: one MultiMeshInstance3D of camera-facing quads (shader: rotating, eroding, sun-lit puffs
##    from a 2x2 noise atlas); per-instance data in a PackedFloat32Array pushed with multimesh_set_buffer
##  * chunks: one MultiMeshInstance3D of flat-shaded tetrahedra that bounce on terrain.height()
##
## terrain: any object with height(x: float, z: float) -> float (null = flat ground at y 0).
## Colours are ordinary (sRGB) Godot Colors; they are converted to linear where three.js used linear.

const DUST_MAX := 700
const CHUNK_MAX := 180
const DUST_STRIDE := 20  # transform 12 + color 4 + custom 4
const CHUNK_STRIDE := 16 # transform 12 + color 4

const DUST_SHADER := """
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

uniform sampler2D smoke_tex : hint_default_white, filter_linear, repeat_disable;
uniform vec3 sun_col = vec3(1.6, 1.21, 0.77);   // 0xffe2b8 (linear) * 1.6
uniform vec3 sky_col = vec3(0.6, 0.79, 1.0);    // 0xcfe6ff (linear)
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;

varying vec4 v_custom;   // x: rotation, y: atlas cell, z: life 0..1
varying vec4 v_col;      // rgb: tint (linear), a: alpha

void vertex() {
	float sz = length(MODEL_MATRIX[0].xyz);
	// camera-facing, world size = instance scale (gl_PointSize = size * uScale / -z in three.js)
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0] * sz, INV_VIEW_MATRIX[1] * sz, INV_VIEW_MATRIX[2] * sz, MODEL_MATRIX[3]);
	MODELVIEW_NORMAL_MATRIX = mat3(1.0);
	v_custom = INSTANCE_CUSTOM;
	v_col = COLOR;
}

void fragment() {
	vec2 p = UV - 0.5;
	float c = cos(v_custom.x), s = sin(v_custom.x);
	vec2 q = vec2(c * p.x - s * p.y, s * p.x + c * p.y) + 0.5;
	if (q.x < 0.0 || q.y < 0.0 || q.x > 1.0 || q.y > 1.0) discard;
	vec2 cell = vec2(mod(v_custom.y, 2.0), floor(v_custom.y / 2.0));
	vec4 t = texture(smoke_tex, (q * 0.98 + 0.01 + cell) * 0.5);
	// density erodes from the thin parts first as the puff ages -> wisps that tear apart
	float er = v_custom.z * 0.75;
	float dens = t.r * smoothstep(er, er + 0.35, t.g);
	float a = dens * v_col.a;
	// soft particle: fade where the puff meets the ground, and right in front of the camera
	float zd = textureLod(depth_tex, SCREEN_UV, 0.0).r;
	vec4 sp = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, zd, 1.0);
	a *= clamp((VERTEX.z - sp.z / sp.w) / 0.5, 0.0, 1.0) * smoothstep(0.4, 1.6, -VERTEX.z);
	if (a < 0.003) discard;
	// cheap volume lighting: top of the puff faces the sun, underside is self-shadowed
	float up = 0.5 - UV.y;
	float light = clamp(0.55 + up * 0.9 + (t.b - 0.5) * 0.35, 0.0, 1.2);
	vec3 col = v_col.rgb * (sky_col * 0.55 + sun_col * light * 0.6);
	ALBEDO = clamp(col, vec3(0.0), vec3(4.0));
	ALPHA = clamp(a, 0.0, 1.0);
}
"""

var terrain = null
var t := 0.0

# ---- dust ----
var dust_mm: MultiMesh
var dust_mmi: MultiMeshInstance3D
var dust_mat: ShaderMaterial
var dust_buf := PackedFloat32Array()
var d_pos := PackedFloat32Array()
var d_vel := PackedFloat32Array()
var d_tint := PackedFloat32Array()
var d_age := PackedFloat32Array()
var d_life := PackedFloat32Array()
var d_s0 := PackedFloat32Array()
var d_a0 := PackedFloat32Array()
var d_ph := PackedFloat32Array()
var d_grow := PackedFloat32Array()
var d_spin := PackedFloat32Array()
var d_rot := PackedFloat32Array()
var d_cell := PackedFloat32Array()
var dust_next := 0

# ---- chunks ----
var chunk_mm: MultiMesh
var chunk_mmi: MultiMeshInstance3D
var chunk_buf := PackedFloat32Array()
var c_pos := PackedFloat32Array()
var c_vel := PackedFloat32Array()
var c_rot := PackedFloat32Array()
var c_w := PackedFloat32Array()
var c_s := PackedFloat32Array()
var c_age := PackedFloat32Array()
var c_life := PackedFloat32Array()
var c_rest := PackedByteArray()
var chunk_next := 0

static var _smoke_tex: ImageTexture


func _init(p_terrain = null) -> void:
	name = "FX"
	terrain = p_terrain
	_build_dust()
	_build_chunks()


func setup(p_terrain) -> void:
	terrain = p_terrain


func _ground(x: float, z: float) -> float:
	return terrain.height(x, z) if terrain != null else 0.0


# ======================================================================= build

static func smoke_texture() -> ImageTexture:
	# 2x2 atlas of soft noise puffs: R = density, G = erosion noise, B = lighting detail
	if _smoke_tex != null:
		return _smoke_tex
	var N := 128
	var W := N * 2
	var data := PackedByteArray()
	data.resize(W * W * 4)
	for cell in 4:
		var off := cell * 7.3
		var warp_n := _noise(cell * 3 + 1, 1.0 / 22.0, 3, off)
		var n1_n := _noise(cell * 3 + 2, 1.0 / 14.0, 5, off * 2.0)
		var n2_n := _noise(cell * 3 + 3, 1.0 / 7.0, 4, off + 3.1)
		var warp_d := warp_n.get_image(N, N).get_data()
		var n1_d := n1_n.get_image(N, N).get_data()
		var n2_d := n2_n.get_image(N, N).get_data()
		var ox := (cell % 2) * N
		var oy := (cell / 2) * N
		for y in N:
			for x in N:
				var j := y * N + x
				# normalised noise 0..1 -> roughly the range of the three.js value-noise fbm
				var warp := 0.15 + warp_d[j] / 255.0 * 0.7
				var n1 := 0.15 + n1_d[j] / 255.0 * 0.7
				var n2 := 0.15 + n2_d[j] / 255.0 * 0.7
				var u := float(x) / N - 0.5
				var v := float(y) / N - 0.5
				# warp the radius with noise so edges are billowy, not round
				var r := sqrt(u * u + v * v) * 2.0 * (0.75 + warp * 0.5)
				var fall := maxf(0.0, 1.0 - r)
				var soft := fall * fall * (3.0 - 2.0 * fall)
				var k := ((oy + y) * W + ox + x) * 4
				data[k] = roundi(255.0 * minf(1.0, soft * (0.45 + n1 * 0.9)))
				data[k + 1] = roundi(255.0 * minf(1.0, n2 * 0.6 + soft * 0.55))
				data[k + 2] = roundi(255.0 * n1)
				data[k + 3] = 255
	var img := Image.create_from_data(W, W, false, Image.FORMAT_RGBA8, data)
	_smoke_tex = ImageTexture.create_from_image(img)
	return _smoke_tex


static func _noise(seed: int, freq: float, octaves: int, off: float) -> FastNoiseLite:
	var n := FastNoiseLite.new()
	n.noise_type = FastNoiseLite.TYPE_VALUE_CUBIC
	n.seed = seed
	n.frequency = freq
	n.fractal_type = FastNoiseLite.FRACTAL_FBM
	n.fractal_octaves = octaves
	n.offset = Vector3(off * 10.0, off * 10.0, 0.0)
	return n


func _build_dust() -> void:
	d_age.resize(DUST_MAX); d_life.resize(DUST_MAX); d_s0.resize(DUST_MAX); d_a0.resize(DUST_MAX)
	d_ph.resize(DUST_MAX); d_grow.resize(DUST_MAX); d_spin.resize(DUST_MAX); d_rot.resize(DUST_MAX); d_cell.resize(DUST_MAX)
	d_pos.resize(DUST_MAX * 3); d_vel.resize(DUST_MAX * 3); d_tint.resize(DUST_MAX * 3)
	d_age.fill(1.0); d_life.fill(1.0)
	dust_buf.resize(DUST_MAX * DUST_STRIDE)   # zeros: scale 0, alpha 0 -> invisible
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	var sh := Shader.new()
	sh.code = DUST_SHADER
	dust_mat = ShaderMaterial.new()
	dust_mat.shader = sh
	dust_mat.set_shader_parameter("smoke_tex", smoke_texture())
	dust_mat.render_priority = 2
	quad.material = dust_mat
	dust_mm = MultiMesh.new()
	dust_mm.transform_format = MultiMesh.TRANSFORM_3D
	dust_mm.use_colors = true
	dust_mm.use_custom_data = true
	dust_mm.mesh = quad
	dust_mm.instance_count = DUST_MAX
	dust_mm.custom_aabb = AABB(Vector3(-1e5, -1e5, -1e5), Vector3(2e5, 2e5, 2e5))
	dust_mmi = MultiMeshInstance3D.new()
	dust_mmi.name = "dust"
	dust_mmi.multimesh = dust_mm
	dust_mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(dust_mmi)
	RenderingServer.multimesh_set_buffer(dust_mm.get_rid(), dust_buf)


func _build_chunks() -> void:
	c_s.resize(CHUNK_MAX); c_age.resize(CHUNK_MAX); c_life.resize(CHUNK_MAX)
	c_pos.resize(CHUNK_MAX * 3); c_vel.resize(CHUNK_MAX * 3); c_rot.resize(CHUNK_MAX * 3); c_w.resize(CHUNK_MAX * 3)
	c_rest.resize(CHUNK_MAX)
	c_age.fill(9.0); c_life.fill(1.0)
	chunk_buf.resize(CHUNK_MAX * CHUNK_STRIDE)
	# TetrahedronGeometry(1, 0), flat shaded; Godot's front faces wind clockwise
	var vs := [Vector3(1, 1, 1).normalized(), Vector3(-1, -1, 1).normalized(), Vector3(-1, 1, -1).normalized(), Vector3(1, -1, -1).normalized()]
	var faces := [[2, 1, 0], [0, 3, 2], [1, 3, 0], [2, 3, 1]]
	var P := PackedVector3Array()
	var Nn := PackedVector3Array()
	for f in faces:
		var a: Vector3 = vs[f[0]]
		var b: Vector3 = vs[f[1]]
		var c: Vector3 = vs[f[2]]
		var n := ((a + b + c) / 3.0).normalized()   # outward
		if (b - a).cross(c - a).dot(n) > 0.0:
			var tmp := b; b = c; c = tmp
		P.append_array([a, b, c])
		Nn.append_array([n, n, n])
	var arrs := []
	arrs.resize(Mesh.ARRAY_MAX)
	arrs[Mesh.ARRAY_VERTEX] = P
	arrs[Mesh.ARRAY_NORMAL] = Nn
	var tet := ArrayMesh.new()
	tet.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrs)
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = true
	mat.roughness = 0.9
	tet.surface_set_material(0, mat)
	chunk_mm = MultiMesh.new()
	chunk_mm.transform_format = MultiMesh.TRANSFORM_3D
	chunk_mm.use_colors = true
	chunk_mm.mesh = tet
	chunk_mm.instance_count = CHUNK_MAX
	chunk_mm.custom_aabb = AABB(Vector3(-1e5, -1e5, -1e5), Vector3(2e5, 2e5, 2e5))
	chunk_mmi = MultiMeshInstance3D.new()
	chunk_mmi.name = "chunks"
	chunk_mmi.multimesh = chunk_mm
	chunk_mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(chunk_mmi)
	RenderingServer.multimesh_set_buffer(chunk_mm.get_rid(), chunk_buf)


# ======================================================================= emitters

func puff(pos: Vector3, vel: Vector3, color: Color, size := 0.35, life := 1.4, alpha := 0.5) -> void:
	var i := dust_next
	dust_next = (i + 1) % DUST_MAX
	d_age[i] = 0.0
	d_life[i] = life * (0.8 + randf() * 0.4)
	_dust_busy = true
	d_s0[i] = size * (0.8 + randf() * 0.4)
	d_a0[i] = alpha
	d_vel[i * 3] = vel.x; d_vel[i * 3 + 1] = vel.y; d_vel[i * 3 + 2] = vel.z
	d_ph[i] = randf() * 100.0
	d_grow[i] = 2.6 + randf() * 1.6
	d_spin[i] = (randf() - 0.5) * 1.2
	d_rot[i] = randf() * 6.283
	d_cell[i] = float(randi() % 4)
	d_pos[i * 3] = pos.x + (randf() - 0.5) * 0.1
	d_pos[i * 3 + 1] = pos.y
	d_pos[i * 3 + 2] = pos.z + (randf() - 0.5) * 0.1
	var lin := color.srgb_to_linear()
	var k := 0.9 + randf() * 0.2
	d_tint[i * 3] = lin.r * k; d_tint[i * 3 + 1] = lin.g * k; d_tint[i * 3 + 2] = lin.b * k


func chunk(pos: Vector3, vel: Vector3, color: Color, size := 0.03, life := 2.2) -> void:
	var i := chunk_next
	chunk_next = (i + 1) % CHUNK_MAX
	c_age[i] = 0.0
	c_life[i] = life * (0.7 + randf() * 0.6)
	_chunk_busy = true
	c_rest[i] = 0
	c_pos[i * 3] = pos.x; c_pos[i * 3 + 1] = pos.y; c_pos[i * 3 + 2] = pos.z
	c_vel[i * 3] = vel.x; c_vel[i * 3 + 1] = vel.y; c_vel[i * 3 + 2] = vel.z
	for j in 3:
		c_rot[i * 3 + j] = randf() * 6.0
		c_w[i * 3 + j] = (randf() - 0.5) * 25.0
	c_s[i] = size * (0.6 + randf() * 0.9)
	var m := 0.75 + randf() * 0.4
	var o := i * CHUNK_STRIDE + 12
	chunk_buf[o] = color.r * m; chunk_buf[o + 1] = color.g * m; chunk_buf[o + 2] = color.b * m; chunk_buf[o + 3] = 1.0


# ======================================================================= simulation

## camera is unused (the dust shader faces the quads to whatever camera draws them); kept for parity
var _dust_busy := false    # any puff alive (or one just died, so its slot still needs zeroing) -> loop + upload
var _chunk_busy := false

func update(dt: float, _camera: Camera3D = null) -> void:
	t += dt
	if _dust_busy: _update_dust(dt)
	if _chunk_busy: _update_chunks(dt)

## dust: drift, slow down, rise a little, grow and fade
func _update_dust(dt: float) -> void:
	var alive := false
	var damp := exp(-dt * 1.8)
	for i in DUST_MAX:
		var o := i * DUST_STRIDE
		if d_age[i] >= d_life[i]:
			if dust_buf[o] != 0.0 or dust_buf[o + 15] != 0.0:
				dust_buf[o] = 0.0; dust_buf[o + 5] = 0.0; dust_buf[o + 10] = 0.0; dust_buf[o + 15] = 0.0
			continue
		alive = true
		d_age[i] += dt
		var k := minf(1.0, d_age[i] / d_life[i])
		var j := i * 3
		var vx := d_vel[j] * damp
		var vy := d_vel[j + 1] * damp
		var vz := d_vel[j + 2] * damp
		# turbulence: slow rolling swirl per puff, plus a light breeze; warm dust lifts then hangs
		var sw := t * 0.9 + d_ph[i]
		var px := d_pos[j]
		var pz := d_pos[j + 2]
		vx += (sin(sw + pz * 1.3) * 0.55 + 0.12) * dt
		vz += cos(sw * 1.1 + px * 1.3) * 0.55 * dt
		vy += (0.22 + 0.12 * sin(sw * 0.7)) * dt * (1.0 - k)
		d_vel[j] = vx; d_vel[j + 1] = vy; d_vel[j + 2] = vz
		px += vx * dt
		var py := d_pos[j + 1] + vy * dt
		pz += vz * dt
		d_pos[j] = px; d_pos[j + 1] = py; d_pos[j + 2] = pz
		d_rot[i] += d_spin[i] * dt * (1.0 - k * 0.7)
		var s := d_s0[i] * (1.0 + d_grow[i] * (1.0 - pow(1.0 - k, 1.8)))   # expands quickly, then slowly
		var al := d_a0[i] * minf(1.0, d_age[i] * 6.0) * pow(1.0 - k, 0.9)
		dust_buf[o] = s; dust_buf[o + 1] = 0.0; dust_buf[o + 2] = 0.0; dust_buf[o + 3] = px
		dust_buf[o + 4] = 0.0; dust_buf[o + 5] = s; dust_buf[o + 6] = 0.0; dust_buf[o + 7] = py
		dust_buf[o + 8] = 0.0; dust_buf[o + 9] = 0.0; dust_buf[o + 10] = s; dust_buf[o + 11] = pz
		dust_buf[o + 12] = d_tint[j]; dust_buf[o + 13] = d_tint[j + 1]; dust_buf[o + 14] = d_tint[j + 2]; dust_buf[o + 15] = al
		dust_buf[o + 16] = d_rot[i]; dust_buf[o + 17] = d_cell[i]; dust_buf[o + 18] = k; dust_buf[o + 19] = 0.0
	RenderingServer.multimesh_set_buffer(dust_mm.get_rid(), dust_buf)
	_dust_busy = alive   # one more pass after the last puff died has zeroed its slot

## chunks: ballistic, spin, bounce on the terrain, then settle and shrink away
func _update_chunks(dt: float) -> void:
	var alive := false
	for i in CHUNK_MAX:
		var o := i * CHUNK_STRIDE
		if c_age[i] >= c_life[i]:
			continue
		alive = true
		c_age[i] += dt
		var j := i * 3
		var s0 := c_s[i]
		if c_rest[i] == 0:
			c_vel[j + 1] -= 9.81 * dt
			c_pos[j] += c_vel[j] * dt; c_pos[j + 1] += c_vel[j + 1] * dt; c_pos[j + 2] += c_vel[j + 2] * dt
			c_rot[j] += c_w[j] * dt; c_rot[j + 1] += c_w[j + 1] * dt; c_rot[j + 2] += c_w[j + 2] * dt
			var g := _ground(c_pos[j], c_pos[j + 2]) + s0 * 0.5
			if c_pos[j + 1] < g:
				c_pos[j + 1] = g
				if absf(c_vel[j + 1]) < 0.6:
					c_rest[i] = 1
				c_vel[j + 1] *= -0.35; c_vel[j] *= 0.55; c_vel[j + 2] *= 0.55
				c_w[j] *= 0.5; c_w[j + 1] *= 0.5; c_w[j + 2] *= 0.5
		var fade := maxf(0.0, (c_life[i] - c_age[i]) / 0.4) if c_age[i] > c_life[i] - 0.4 else 1.0
		var s := s0 * fade
		if c_age[i] >= c_life[i]:
			s = 0.0
		var b := Basis.from_euler(Vector3(c_rot[j], c_rot[j + 1], c_rot[j + 2]), EULER_ORDER_XYZ)
		var bx := b.x * s
		var by := b.y * (s * 0.8)
		var bz := b.z * s
		chunk_buf[o] = bx.x; chunk_buf[o + 1] = by.x; chunk_buf[o + 2] = bz.x; chunk_buf[o + 3] = c_pos[j]
		chunk_buf[o + 4] = bx.y; chunk_buf[o + 5] = by.y; chunk_buf[o + 6] = bz.y; chunk_buf[o + 7] = c_pos[j + 1]
		chunk_buf[o + 8] = bx.z; chunk_buf[o + 9] = by.z; chunk_buf[o + 10] = bz.z; chunk_buf[o + 11] = c_pos[j + 2]
	RenderingServer.multimesh_set_buffer(chunk_mm.get_rid(), chunk_buf)
	_chunk_busy = alive   # a chunk on its last frame wrote scale 0 above


## number of live dust puffs / chunks (debug / tests)
func live_counts() -> Vector2i:
	var nd := 0
	var nc := 0
	for i in DUST_MAX:
		if d_age[i] < d_life[i]: nd += 1
	for i in CHUNK_MAX:
		if c_age[i] < c_life[i]: nc += 1
	return Vector2i(nd, nc)
