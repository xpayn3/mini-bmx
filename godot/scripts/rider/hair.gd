class_name Hair
extends MeshInstance3D
## Hair for a rider without a helmet, done the way film hair is: a few dozen simulated GUIDE locks (Verlet chains
## that hang from the scalp, trail behind the head, flutter, rest on the head and shoulders) and a few hundred fine
## STRANDS that follow them. The strands are interpolated between the nearest three guides in the vertex shader
## (shaders/hair.gdshader reads the guide positions from a small texture), so the CPU only simulates the guides.
## Styles: "long" (flowing, ~45 cm) and "short" (ordinary short hair that still moves a little).

const G := 28                   # guide locks
const SEG := 9                 # points per lock after the root
const S := 260                  # strands drawn
const STEP := 1.0 / 60.0
const SHADER := "res://shaders/hair.gdshader"
## the skull the hair grows on and rests against, as an ellipsoid in head space (fitted to the custom head)
const HEAD_C := Vector3(0.006, -0.012, 0.0)
const HEAD_R := Vector3(0.12, 0.13, 0.11)
## hair presets: length (m), gravity, sway, bending stiffness, how strongly the scalp end keeps its shape (hold,
## over hold_n points), and short = lies close to the head / sweeps back instead of hanging
const STYLES := {
	"long":  {"label": "Long",  "len": 0.36, "grav": 9.0, "flutter": 0.4, "bend": 0.14, "hold": 0.3, "hold_n": 2, "short": false},
	"bob":   {"label": "Bob",   "len": 0.17, "grav": 8.0, "flutter": 0.3, "bend": 0.22, "hold": 0.5, "hold_n": 4, "short": false},
	"short": {"label": "Short", "len": 0.085, "grav": 4.5, "flutter": 0.2, "bend": 0.3, "hold": 1.0, "hold_n": 99, "short": true},
	"crop":  {"label": "Crop",  "len": 0.04, "grav": 3.0, "flutter": 0.1, "bend": 0.4, "hold": 1.0, "hold_n": 99, "short": true},
	# gathered at one tie point on the back of the head and hanging from it: a rope of locks that swings (it comes out under a helmet too)
	"ponytail": {"label": "Ponytail", "len": 0.3, "grav": 9.0, "flutter": 0.6, "bend": 0.1, "hold": 0.15, "hold_n": 2, "short": false, "tie": true},
}

var head: Node3D                # the rider's Head: roots and the shape of the hair follow it
var rider: Rider                # the body the hair rests on (spine, shoulders)
var style := "long"
var helmet_mode := false   # under a helmet: only a tuft from the nape, coming out under the back of the shell
var color := Color("#4a3022")

var _roots: Array[Vector3] = []
var _rest: Array[Vector3] = []
var _len := PackedFloat32Array()
var _ph := PackedFloat32Array()
var _P := PackedVector3Array()
var _Q := PackedVector3Array()
var _seg_len := 0.04
var _grav := 6.0
var _hold := 0.6               # how strongly the first points keep the hairstyle's shape
var _flutter := 1.4
var _bend := 0.14
var _hold_n := 2
var _tie := false   # ponytail: a part of the locks is gathered at the tie point
var _have := false
var _last := Vector3.ZERO
var _t := 0.0
var _acc := 0.0
var _img: Image
var _tex: ImageTexture
var _mat: ShaderMaterial


func _init() -> void:
	top_level = true
	process_priority = 100        # after the rider has been posed this frame
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mat = ShaderMaterial.new()
	_mat.shader = load(SHADER)
	_mat.set_meta("grime_pass", true)   # the bike's mud / wet overlay (bike/grime.gd) must leave the hair alone: its extra pass breaks the strands
	material_override = _mat
	_P.resize(G * (SEG + 1))
	_Q.resize(G * (SEG + 1))
	_ph.resize(G)
	_len.resize(G)
	set_style("long")


func set_color(c: Color) -> void:
	color = c
	_mat.set_shader_parameter("hair_col", Vector3(c.r, c.g, c.b))


func set_style(s: String, helmet := false) -> void:
	if not STYLES.has(s): s = "long"
	if s == style and helmet == helmet_mode and mesh != null and mesh.get_surface_count() > 0: return
	style = s
	helmet_mode = helmet
	var P: Dictionary = STYLES[style]
	var short: bool = P.short
	_seg_len = float(P.len) / SEG
	_grav = P.grav          # heavy: it hangs, it does not float
	_hold = P.hold
	_hold_n = mini(int(P.hold_n), SEG)
	_bend = P.bend
	_flutter = P.flutter     # a faint sway, not a flap
	_tie = bool(P.get("tie", false))
	_make_guides(short)
	_make_strands(short)
	_have = false


## a random spot on the scalp (head space) that is allowed to grow hair for this style, and which way it falls.
## The hairline runs over the forehead (high at the centre, low at the temples); hair never grows on the face or under the jaw.
func _spot(rng: RandomNumberGenerator, short: bool, tail := false) -> Array:
	if tail:   # the ponytail: every lock leaves the tie point on the back of the head (lower, under the shell, when a helmet is on)
		var tie := Vector3(-0.108, -0.035 if helmet_mode else 0.025, 0.0)
		var p := tie + Vector3(rng.randf_range(-0.004, 0.004), rng.randf_range(-0.03, 0.03), rng.randf_range(-0.036, 0.036))
		return [p, Vector3(-0.6, -1.0, 0.0).normalized()]
	for tries in 400:
		var ct := rng.randf_range(-0.3, 1.0)
		var st := sqrt(maxf(0.0, 1.0 - ct * ct))
		var phi := rng.randf_range(0.0, TAU)
		var d := Vector3(st * cos(phi), ct, st * sin(phi))
		var p := HEAD_C + Vector3(d.x * HEAD_R.x, d.y * HEAD_R.y, d.z * HEAD_R.z) * 1.03
		var hairline := 0.056 - clampf(absf(p.z) / 0.095, 0.0, 1.0) * 0.07
		if p.x > 0.0 and p.y < hairline: continue          # not on the face: below the hairline
		if ct < 0.0 and p.x > -0.03: continue               # nothing under the jaw / in front of the ears at neck height
		if helmet_mode and not (p.x < -0.03 and p.y < 0.0 and p.y > -0.1): continue   # under a helmet: only the nape, below the shell
		var front := clampf(p.x / 0.06, 0.0, 1.0)           # 1 at the hairline, 0 from the crown backwards
		# a lock leaves the scalp OUTWARD and then falls over the head under gravity (so it never starts inside it);
		# the front is swept back and a little to the side, over the head, not down over the eyes
		var out := ((d * 0.9 + Vector3(-0.25, -0.1, 0.0)) if not short else (d * 0.95 + Vector3(-0.1, -0.2, 0.0))).normalized()
		var swept := (d * 0.3 + Vector3(-0.9, 0.25, signf(p.z) * 0.35)).normalized()
		if helmet_mode: out = (d * 0.25 + Vector3(-0.25, -1.0, 0.0)).normalized()   # straight down over the neck / back
		return [p, out.lerp(swept, front).normalized()]
	return [Vector3(-0.08, 0.02, 0), Vector3(-0.6, -1.0, 0).normalized()]


func _make_guides(short: bool) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	_roots.clear()
	_rest.clear()
	for i in G:
		var tail := _tie and (helmet_mode or i < G * 6 / 10)   # a ponytail: 60 % of the guides are the tail, the rest hold the hair on the head
		var sp := _spot(rng, short or _tie, tail)
		_roots.append(sp[0])
		_rest.append(sp[1])
		_len[i] = rng.randf_range(0.85, 1.15) * (1.0 if (tail or not _tie) else 0.2)
		_ph[i] = rng.randf() * TAU
	_img = Image.create(SEG + 1, G, false, Image.FORMAT_RGBF)
	_tex = ImageTexture.create_from_image(_img)
	_mat.set_shader_parameter("guides", _tex)
	_mat.set_shader_parameter("seg", SEG)


func _make_strands(short: bool) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var verts := PackedVector3Array()
	var cols := PackedColorArray()
	var uvs := PackedVector2Array()
	var c0 := PackedFloat32Array()
	var c1 := PackedFloat32Array()
	var idx := PackedInt32Array()
	for s in S:
		var tail := _tie and (helmet_mode or s % 5 < 3)
		var sp := _spot(rng, short or _tie, tail)
		var root: Vector3 = sp[0]
		# the three nearest guide roots, weighted by distance
		var best := [[1e9, 0], [1e9, 0], [1e9, 0]]
		for g in G:
			var d := root.distance_squared_to(_roots[g])
			for slot in 3:
				if d < best[slot][0]:
					for m in range(2, slot, -1): best[m] = best[m - 1]
					best[slot] = [d, g]
					break
		var ws := []
		var tot := 0.0
		for slot in 3:
			var w: float = 1.0 / (best[slot][0] + 0.0004)
			ws.append(w); tot += w
		var avg_root := Vector3.ZERO
		for slot in 3:
			ws[slot] /= tot
			avg_root += (_roots[best[slot][1]] as Vector3) * ws[slot]
		var off := root - avg_root          # where this strand starts relative to the blend of its guides
		var lf := rng.randf_range(0.82, 1.0)
		var shade := rng.randf_range(0.82, 1.14)
		var width := rng.randf_range(0.0065, 0.0105) * (1.5 if tail else 1.0)   # a ponytail is a thick bundle
		var ph := rng.randf() * TAU
		for k in SEG + 1:
			var f := float(k) / SEG
			for side in [-1.0, 1.0]:
				verts.append(Vector3(best[0][1], best[1][1], best[2][1]))
				c0.append_array([ws[0], ws[1], ws[2], ph])
				c1.append_array([off.x, off.y, off.z, width])
				uvs.append(Vector2(side, f))
				cols.append(Color(shade, shade, shade, lf))
		for k in SEG:
			var a := (s * (SEG + 1) + k) * 2
			idx.append_array([a, a + 1, a + 2, a + 1, a + 3, a + 2])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_COLOR] = cols
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_CUSTOM0] = c0
	arr[Mesh.ARRAY_CUSTOM1] = c1
	arr[Mesh.ARRAY_INDEX] = idx
	var flags := (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT) | (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM1_SHIFT)
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr, [], {}, flags)
	mesh = am


func _reset(ht: Transform3D) -> void:
	for i in G:
		var b := i * (SEG + 1)
		var root := ht * _roots[i]
		var dir := ht.basis * _rest[i]
		for j in SEG + 1:
			_P[b + j] = root + dir * (_seg_len * _len[i] * j)
			_Q[b + j] = _P[b + j]
	_have = true


func _process(dt: float) -> void:
	if head == null or not is_visible_in_tree() or dt <= 0.0:
		return
	global_transform = Transform3D.IDENTITY
	dt = minf(dt, 1.0 / 30.0)
	var ht := head.global_transform
	if not _have or ht.origin.distance_to(_last) > 3.0:
		_reset(ht)
	_last = ht.origin
	# the strands are placed by the shader, so the mesh itself has no real extent: tell the engine where the hair is
	# (a box round the head, in world space - the node sits at the origin), or it is culled whenever the rider is far from the origin
	custom_aabb = AABB(ht.origin - Vector3(1.5, 1.5, 1.5), Vector3(3, 3, 3))
	_t += dt
	_acc += dt
	var solids := _solids(ht)
	var steps := 0
	while _acc >= STEP and steps < 2:
		_step(ht, solids)
		_acc -= STEP
		steps += 1
	if steps == 2: _acc = 0.0
	# the guides go to the shader as a float texture, the head's transform with them
	_img.set_data(SEG + 1, G, false, Image.FORMAT_RGBF, _P.to_byte_array())
	_tex.update(_img)
	_mat.set_shader_parameter("head_xf", ht)


## the solid things hair rests on, as [world centre, radius]: the neck, spheres down the spine (back, chest, hips)
## and the shoulders. Taken from the posed rider, so they follow a hunched, leaning or tumbling body.
func _solids(ht: Transform3D) -> Array:
	var out: Array = [[ht * Vector3(-0.01, -0.17, 0), 0.055]]   # the neck
	if rider != null and rider.spine_skel != null:
		var xf := rider.global_transform
		for t in [0.95, 0.75, 0.55, 0.35]:
			out.append([xf * rider.back_point(t, 0.0, -0.09), 0.10])                # the middle of the body
			out.append([xf * rider.back_point(t, -0.115, -0.06), 0.065])           # and its two sides
			out.append([xf * rider.back_point(t, 0.115, -0.06), 0.065])
		for sp in rider.shoulder_sph:
			if sp != null: out.append([sp.global_position, 0.078])
		for ua in rider.upper_arm:
			if ua != null: out.append([ua.global_position, 0.055])
	else:
		out.append([ht * Vector3(-0.02, -0.2, 0), 0.15])
		out.append([ht * Vector3(-0.1, -0.32, 0), 0.17])
	return out


func _step(ht: Transform3D, spheres: Array) -> void:
	var h2 := STEP * STEP
	var hinv := ht.affine_inverse()
	for i in G:
		var b := i * (SEG + 1)
		var root := ht * _roots[i]
		_P[b] = root
		_Q[b] = root
		var L := _seg_len * _len[i]
		for j in range(1, SEG + 1):
			var k := b + j
			var v := (_P[k] - _Q[k]) * 0.978
			_Q[k] = _P[k]
			var f := float(j) / SEG
			# slow breathing sway through the whole length (a wave that travels down the lock), not a twitch
			var sway := Vector3(sin(_t * 1.7 + _ph[i] * 0.5 - j * 0.45), sin(_t * 1.3 + _ph[i] - j * 0.35) * 0.4,
				cos(_t * 1.5 + _ph[i] * 0.8 - j * 0.4)) * sqrt(f)
			_P[k] += v + (Vector3(0, -_grav, 0) + sway * _flutter * 2.0) * h2
		# the first points keep the hairstyle's shape (volume at the scalp)
		for j in range(1, _hold_n + 1):
			var target := root + ht.basis * _rest[i] * (L * j)
			var moved := _P[b + j].lerp(target, minf(1.0, _hold / j))
			_Q[b + j] += moved - _P[b + j]
			_P[b + j] = moved
		for it in 2:
			for j in range(1, SEG + 1):
				var a := _P[b + j - 1]
				var d := _P[b + j] - a
				var l := d.length()
				if l > 1e-6: _P[b + j] = a + d * (L / l)
		for j in range(1, SEG + 1):
			var lp := hinv * _P[b + j] - HEAD_C                       # head space, centred on the head
			var q := Vector3(lp.x / HEAD_R.x, lp.y / HEAD_R.y, lp.z / HEAD_R.z)
			var ql := q.length()
			if ql < 1.07 and ql > 1e-4:                                # push out to just above the scalp
				q *= 1.07 / ql
				_P[b + j] = ht * (Vector3(q.x * HEAD_R.x, q.y * HEAD_R.y, q.z * HEAD_R.z) + HEAD_C)
				_Q[b + j] = _Q[b + j].lerp(_P[b + j], 0.7)             # sliding on the scalp: speed is lost, nothing is kicked out
			elif _P[b + j].y < ht.origin.y - 0.1:                       # below the head: the body
				for s in spheres:
					var dd: Vector3 = _P[b + j] - (s[0] as Vector3)
					var r: float = float(s[1]) + 0.006
					var l2 := dd.length_squared()
					if l2 < r * r and l2 > 1e-9:
						_P[b + j] = (s[0] as Vector3) + dd / sqrt(l2) * r
						_Q[b + j] = _Q[b + j].lerp(_P[b + j], 0.7)
		for j in range(2, SEG + 1):                                     # bending stiffness: a lock curves, it does not kink or flap
			var dir := (_P[b + j - 1] - _P[b + j - 2]).normalized()
			var moved := _P[b + j].lerp(_P[b + j - 1] + dir * L, _bend)
			_Q[b + j] += moved - _P[b + j]
			_P[b + j] = moved
		for j in range(1, SEG + 1):                                     # last: keep the lengths
			var a := _P[b + j - 1]
			var d := _P[b + j] - a
			var l := d.length()
			if l > 1e-6: _P[b + j] = a + d * (L / l)


## The hair-coloured cap under the strands: from the crown down to the hairline (high on the forehead, low at the
## temples and the nape), with a soft edge (the vertex alpha fades out over the last ring) so there is no hard line.
static func scalp_mesh() -> ArrayMesh:
	const P := 40
	const R := 12
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	for k in P:
		var phi := TAU * float(k) / P
		var cp := cos(phi)
		var sp := absf(sin(phi))
		var side := 0.056 - sp * 0.07                       # hairline height at the front / temples
		var t := clampf(-cp, 0.0, 1.0)                      # towards the back of the head
		var yb := side * (1.0 - t) + (-0.085) * t          # ... down to the nape
		var ctb := clampf((yb - HEAD_C.y) / HEAD_R.y, -0.7, 0.99)
		for i in R + 1:
			var ct := lerpf(1.0, ctb, float(i) / R)
			var st := sqrt(maxf(0.0, 1.0 - ct * ct))
			var d := Vector3(st * cos(phi), ct, st * sin(phi))
			verts.append(HEAD_C + Vector3(d.x * HEAD_R.x, d.y * HEAD_R.y, d.z * HEAD_R.z) * 1.02)
			norms.append(Vector3(d.x / HEAD_R.x, d.y / HEAD_R.y, d.z / HEAD_R.z).normalized())
			var a := 1.0 if i < R - 2 else (0.7 if i == R - 2 else (0.35 if i == R - 1 else 0.0))
			cols.append(Color(1, 1, 1, a))
	for k in P:
		var k2 := (k + 1) % P
		for i in R:
			var a := k * (R + 1) + i
			var b := k2 * (R + 1) + i
			idx.append_array([a, b, a + 1, b, b + 1, a + 1])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_COLOR] = cols
	arr[Mesh.ARRAY_INDEX] = idx
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return am
