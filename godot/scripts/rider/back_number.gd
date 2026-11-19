class_name BackNumber
extends MeshInstance3D
## Race number paper pinned to the rider's back (safety pins at the four corners, like a real bib). A small
## Verlet cloth (same idea as TapeSim): light paper, big drag, pulled towards the air velocity, so it lies
## flat when slow and billows, rattles and flaps its middle and edges as the rider speeds up.
## Drawn in world space, nothing on the jersey changes.

const NUMBER := "27"
const C := 5                    # points across (sideways)
const R := 4                    # points down
const W := 0.21                 # paper size, m
const H := 0.165
const T_TOP := 0.72             # on the spine: 0 hips .. 1 collar
const T_BOT := 0.40
const SUB := 2
const ITER := 5
const DRAG := 5.0
const SAG := 1.05               # paper a bit bigger than the pin spacing: it can bulge

var _imesh := ImmediateMesh.new()
var _P := PackedVector3Array()
var _Q := PackedVector3Array()
var _ph := PackedFloat32Array()
var _have := false
var _last := Vector3.ZERO
var _vs := Vector3.ZERO
var _t := 0.0


func _init() -> void:
	mesh = _imesh
	top_level = true
	process_priority = 100        # after the rider has been posed this frame
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	extra_cull_margin = 16384.0
	var m := StandardMaterial3D.new()
	m.albedo_texture = _make_texture()
	m.roughness = 0.85
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	material_override = m
	for i in C * R:
		_ph.append(randf() * 6.28)


## white paper, a coloured band on top, the number in black (seven-segment digits drawn into an image)
static func _make_texture() -> ImageTexture:
	var w := 168
	var h := 132
	var img := Image.create(w, h, false, Image.FORMAT_RGB8)
	img.fill(Color("#f4f2ea"))
	img.fill_rect(Rect2i(0, 0, w, 26), Color("#d8232a"))
	img.fill_rect(Rect2i(0, h - 5, w, 5), Color("#d8232a"))
	# segments a..g: top, top-right, bottom-right, bottom, bottom-left, top-left, middle
	var seg := {"0": "abcdef", "1": "bc", "2": "abged", "3": "abgcd", "4": "fgbc", "5": "afgcd",
		"6": "afgedc", "7": "abc", "8": "abcdefg", "9": "abcdfg"}
	var dw := 56
	var dh := 82
	var th := 13
	var gap := 12
	var total := NUMBER.length() * dw + (NUMBER.length() - 1) * gap
	var x0 := (w - total) / 2
	var y0 := 36
	for n in NUMBER.length():
		var x := x0 + n * (dw + gap)
		for s in seg[NUMBER[n]]:
			var r: Rect2i
			match s:
				"a": r = Rect2i(x, y0, dw, th)
				"b": r = Rect2i(x + dw - th, y0, th, dh / 2 + th / 2)
				"c": r = Rect2i(x + dw - th, y0 + dh / 2 - th / 2, th, dh / 2 + th / 2)
				"d": r = Rect2i(x, y0 + dh - th, dw, th)
				"e": r = Rect2i(x, y0 + dh / 2 - th / 2, th, dh / 2 + th / 2)
				"f": r = Rect2i(x, y0, th, dh / 2 + th / 2)
				_: r = Rect2i(x, y0 + dh / 2 - th / 2, dw, th)
			img.fill_rect(r, Color("#14161a"))
	return ImageTexture.create_from_image(img)


func _anchors(rider: Rider) -> PackedVector3Array:
	# the four pinned corners, world space: top-left, top-right, bottom-left, bottom-right
	var out := PackedVector3Array()
	for tz in [[T_TOP, -W / 2], [T_TOP, W / 2], [T_BOT, -W / 2], [T_BOT, W / 2]]:
		out.append(rider.global_transform * rider.back_point(tz[0], tz[1], 0.004))
	return out


func _reset(A: PackedVector3Array) -> void:
	_P.resize(C * R)
	_Q.resize(C * R)
	for r in R:
		for c in C:
			var u := float(c) / (C - 1)
			var v := float(r) / (R - 1)
			var p := A[0].lerp(A[1], u).lerp(A[2].lerp(A[3], u), v)
			_P[r * C + c] = p
			_Q[r * C + c] = p
	_vs = Vector3.ZERO
	_last = A[0]
	_have = true


func _process(dt: float) -> void:
	var rider := get_parent() as Rider
	if rider == null or rider.spine_skel == null or not rider.is_visible_in_tree() or dt <= 0.0:
		return
	dt = minf(dt, 1.0 / 30.0)
	_t += dt
	var A := _anchors(rider)
	if not _have or A[0].distance_to(_last) > 4.0:
		_reset(A)
	var vi := (A[0] - _last) / dt
	_last = A[0]
	_vs += (vi - _vs) * (1.0 - exp(-dt / 0.12))
	var speed := _vs.length()
	# the paper's plane: centre, outward normal (the back faces -x of the torso)
	var ctr := (A[0] + A[1] + A[2] + A[3]) * 0.25
	var nrm := (A[1] - A[0]).cross(A[2] - A[0]).normalized()
	if nrm.dot(ctr - (rider.global_transform * rider.back_point(0.55, 0.0, -0.1))) < 0.0:
		nrm = -nrm   # make it point away from the body
	var S := PackedVector3Array()   # the jersey surface under every paper point
	S.resize(C * R)
	for r in R:
		for c in C:
			S[r * C + c] = rider.global_transform * rider.back_point(
				lerpf(T_TOP, T_BOT, float(r) / (R - 1)), lerpf(-W / 2, W / 2, float(c) / (C - 1)))
	var cw := (A[1] - A[0]).length() / (C - 1) * SAG
	var ch := (A[2] - A[0]).length() / (R - 1) * SAG
	var h := dt / SUB
	for sub in SUB:
		for r in R:
			for c in C:
				var i := r * C + c
				if (r == 0 or r == R - 1) and (c == 0 or c == C - 1):
					continue
				var p := _P[i]
				var tu := _t * 17.0 + _ph[i] + r * 0.8 + c * 1.1
				# air in the rider's wake travels with him; on top of that a gusty in / out pumping of the paper
				var w := _vs * 0.4 + nrm * (speed * (0.22 + 0.45 * sin(tu) + 0.25 * sin(tu * 1.7 + 2.0)))
				w += nrm.cross(Vector3.UP) * (sin(tu * 1.3 + 1.0) * speed * 0.12)
				var v := (p - _Q[i]) / h
				var acc := (w - v) * DRAG + Vector3(0, -9.81 * 0.5, 0)
				_Q[i] = p
				_P[i] = p + v * h + acc * (h * h)
		for it in ITER:
			_P[0] = A[0]
			_P[C - 1] = A[1]
			_P[(R - 1) * C] = A[2]
			_P[R * C - 1] = A[3]
			for r in R:
				for c in C:
					var i := r * C + c
					if c < C - 1:
						_link(i, i + 1, cw)
					if r < R - 1:
						_link(i, i + C, ch)
						if c < C - 1:
							_link(i, i + C + 1, sqrt(cw * cw + ch * ch))
						if c > 0:
							_link(i, i + C - 1, sqrt(cw * cw + ch * ch))
		_P[0] = A[0]
		_P[C - 1] = A[1]
		_P[(R - 1) * C] = A[2]
		_P[R * C - 1] = A[3]
		for i in C * R:   # never through the body: stay outside the (curved) back surface under each point
			var d := (_P[i] - S[i]).dot(nrm)
			if d < 0.004:
				_P[i] += nrm * (0.004 - d)
	_draw(nrm)


func _link(a: int, b: int, rest: float) -> void:
	var d := _P[b] - _P[a]
	var l := maxf(d.length(), 1e-6)
	var diff := (l - rest) / l
	var pin_a := _is_pin(a)
	var pin_b := _is_pin(b)
	var wa := 0.0 if pin_a else (1.0 if pin_b else 0.5)
	var wb := 0.0 if pin_b else (1.0 if pin_a else 0.5)
	_P[a] += d * (diff * wa)
	_P[b] -= d * (diff * wb)


func _is_pin(i: int) -> bool:
	return i == 0 or i == C - 1 or i == (R - 1) * C or i == R * C - 1


func _draw(nrm: Vector3) -> void:
	_imesh.clear_surfaces()
	var N := PackedVector3Array()
	N.resize(C * R)
	for r in R:
		for c in C:
			var l := _P[r * C + maxi(c - 1, 0)]
			var rt := _P[r * C + mini(c + 1, C - 1)]
			var up := _P[maxi(r - 1, 0) * C + c]
			var dn := _P[mini(r + 1, R - 1) * C + c]
			var n := (rt - l).cross(dn - up).normalized()
			if n.dot(nrm) < 0.0:
				n = -n
			N[r * C + c] = n
	_imesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for r in R - 1:
		for c in C - 1:
			var i0 := r * C + c
			for k in [i0, i0 + 1, i0 + C, i0 + 1, i0 + C + 1, i0 + C]:
				_imesh.surface_set_normal(N[k])
				_imesh.surface_set_uv(Vector2(float(k % C) / (C - 1), float(k / C) / (R - 1)))
				_imesh.surface_add_vertex(_P[k])
	_imesh.surface_end()
