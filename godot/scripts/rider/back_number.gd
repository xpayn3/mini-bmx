class_name BackNumber
extends MeshInstance3D
## Race number paper pinned to the rider's back, like a real bib. A small Verlet cloth (same idea as TapeSim):
## light paper, big drag, pulled towards the air velocity. The top corners are safety-pinned; the bottom corners
## are only loosely held, so at speed the lower half lifts, pumps and flaps. Drawn in world space; nothing on
## the jersey changes. The paper's face (header, number, sponsors) is drawn once into a small SubViewport.

const NUMBER := "27"
const CLASS_LINE := "ELITE  DOWNHILL"
const C := 6                    # points across (sideways)
const R := 5                    # points down
const W := 0.24                 # paper size, m
const H := 0.19
const T_TOP := 0.68             # on the spine: 0 hips .. 1 collar
const T_BOT := 0.30
const STAND := 0.009            # the paper floats this far off the jersey (the torso mesh is faceted)
const MAX_STAND := 0.055        # nothing billows further off the jersey than this
const TETHER := 0.06            # how far a bottom corner can lift off its pin spot
const SUB := 2
const ITER := 5
const DRAG := 5.0
const SAG := 1.06               # paper a bit bigger than the pin spacing: it can bulge
const PX_W := 384
const PX_H := 304

var _imesh := ImmediateMesh.new()
var _vp: SubViewport
var _vp_frames := 0
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
	for i in C * R:
		_ph.append(randf() * 6.28)


func _ready() -> void:
	_vp = _build_face()
	add_child(_vp)
	var m := StandardMaterial3D.new()
	m.albedo_texture = _vp.get_texture()
	m.roughness = 0.85
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	material_override = m


# ---------------- the printed paper ----------------

static func _label(parent: Control, text: String, rect: Rect2, size: int, color: Color, black := true) -> Label:
	var l := Label.new()
	var ls := LabelSettings.new()
	ls.font = UITheme.font(black)
	ls.font_size = size
	ls.font_color = color
	l.label_settings = ls
	l.text = text
	l.position = rect.position
	l.size = rect.size
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	parent.add_child(l)
	return l


static func _box(parent: Control, rect: Rect2, bg: Color, border: Color, bw: int, radius: int) -> Panel:
	var p := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(bw)
	sb.set_corner_radius_all(radius)
	p.add_theme_stylebox_override("panel", sb)
	p.position = rect.position
	p.size = rect.size
	parent.add_child(p)
	return p


func _build_face() -> SubViewport:
	var vp := SubViewport.new()
	vp.size = Vector2i(PX_W, PX_H)
	vp.disable_3d = true
	vp.transparent_bg = false
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var root := Control.new()
	root.size = Vector2(PX_W, PX_H)
	vp.add_child(root)
	var ink := Color("#14161a")
	var red := Color("#d8232a")
	_box(root, Rect2(0, 0, PX_W, PX_H), Color("#f6f4ec"), ink, 5, 10)
	# header band
	_box(root, Rect2(5, 5, PX_W - 10, 50), red, red, 0, 6)
	_label(root, "MINI BMX  •  DOWNHILL CUP", Rect2(5, 5, PX_W - 10, 50), 25, Color.WHITE)
	# the number: a soft grey offset behind it, then the black digits
	_label(root, NUMBER, Rect2(6, 54, PX_W, 166), 178, Color(0, 0, 0, 0.16))
	_label(root, NUMBER, Rect2(0, 50, PX_W, 166), 178, ink)
	_label(root, CLASS_LINE, Rect2(0, 212, PX_W, 24), 17, Color("#3a3d44"))
	# sponsor row
	_box(root, Rect2(12, 240, PX_W - 24, 2), ink, ink, 0, 0)
	var sx := [12.0, 102.0, 192.0, 282.0]
	var logos := [
		["GLORY", Color("#d8232a"), Color.WHITE, Color("#d8232a"), 24],
		["FOX", Color.WHITE, ink, ink, 36],
		["MAXXIS", ink, Color.WHITE, ink, 21],
		["CINELLI", Color.WHITE, red, red, 20],
	]
	for i in 4:
		var L: Array = logos[i]
		var r := Rect2(sx[i], 250, 90.0 if i < 3 else 90.0, 44)
		_box(root, r, L[1], L[3], 3, 6)
		_label(root, L[0], r, L[4], L[2])
	# the FOX mark gets an orange underline
	_box(root, Rect2(sx[1] + 18, 282, 54, 5), Color("#ff7a1a"), Color("#ff7a1a"), 0, 2)
	# safety-pin holes at the corners
	var holes := Control.new()
	holes.size = Vector2(PX_W, PX_H)
	root.add_child(holes)
	holes.draw.connect(func() -> void:
		for p in [Vector2(20, 22), Vector2(PX_W - 20, 22), Vector2(20, PX_H - 22), Vector2(PX_W - 20, PX_H - 22)]:
			holes.draw_circle(p, 8, Color("#14161a"))
			holes.draw_circle(p, 5.5, Color("#b9b7ae")))
	return vp


# ---------------- the cloth ----------------

func _anchors(rider: Rider) -> PackedVector3Array:
	# the four corners on the jersey, world space: top-left, top-right, bottom-left, bottom-right
	var out := PackedVector3Array()
	for tz in [[T_TOP, -W / 2], [T_TOP, W / 2], [T_BOT, -W / 2], [T_BOT, W / 2]]:
		out.append(rider.global_transform * rider.back_point(tz[0], tz[1], STAND))
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
	if _vp != null and _vp_frames >= 0:   # the face is drawn once (a few frames for fonts / layout), then frozen
		_vp_frames += 1
		if _vp_frames > 4:
			_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
			_vp_frames = -1
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
	# outward normal of the paper's plane (the back faces -x of the torso)
	var ctr := (A[0] + A[1] + A[2] + A[3]) * 0.25
	var nrm := (A[1] - A[0]).cross(A[2] - A[0]).normalized()
	if nrm.dot(ctr - (rider.global_transform * rider.back_point(0.55, 0.0, -0.1))) < 0.0:
		nrm = -nrm
	var S := PackedVector3Array()   # the jersey surface under every paper point
	S.resize(C * R)
	for r in R:
		for c in C:
			S[r * C + c] = rider.global_transform * rider.back_point(
				lerpf(T_TOP, T_BOT, float(r) / (R - 1)), lerpf(-W / 2, W / 2, float(c) / (C - 1)))
	var cw := (A[1] - A[0]).length() / (C - 1) * SAG
	var ch := (A[2] - A[0]).length() / (R - 1) * SAG
	var dg := sqrt(cw * cw + ch * ch)
	var side := nrm.cross(Vector3.UP).normalized()
	var h := dt / SUB
	var gust := clampf(speed / 6.0, 0.0, 1.0)   # nothing much at a walk, full flap from ~20 km/h
	for sub in SUB:
		for r in R:
			var low := 0.25 + 0.75 * float(r) / (R - 1)   # the loose lower half flaps most
			for c in C:
				var i := r * C + c
				if i == 0 or i == C - 1:
					continue
				var tu := _t * 19.0 + _ph[i] + r * 0.9 + c * 1.3
				# air in the rider's wake travels with him; the paper is pumped in and out and rattled sideways
				var pump := 0.25 + 0.6 * sin(tu) + 0.35 * sin(tu * 1.9 + 2.0) + 0.2 * sin(_t * 52.0 + _ph[i] * 3.0)
				var w := _vs * 0.4 + nrm * (speed * pump * low * gust) + side * (sin(tu * 1.4 + 1.0) * speed * 0.12 * low * gust)
				w += Vector3.UP * (sin(tu * 1.1 + 0.5) * speed * 0.18 * low * gust)
				var p := _P[i]
				var v := (p - _Q[i]) / h
				var acc := (w - v) * DRAG + Vector3(0, -9.81 * 0.5, 0)
				_Q[i] = p
				_P[i] = p + v * h + acc * (h * h)
		for it in ITER:
			_P[0] = A[0]
			_P[C - 1] = A[1]
			for r in R:
				for c in C:
					var i := r * C + c
					if c < C - 1:
						_link(i, i + 1, cw)
					if r < R - 1:
						_link(i, i + C, ch)
						if c < C - 1:
							_link(i, i + C + 1, dg)
						if c > 0:
							_link(i, i + C - 1, dg)
		_P[0] = A[0]
		_P[C - 1] = A[1]
		# the bottom corners are only loosely pinned
		for k in [[(R - 1) * C, 2], [R * C - 1, 3]]:
			var d: Vector3 = _P[k[0]] - A[k[1]]
			if d.length() > TETHER:
				_P[k[0]] = A[k[1]] + d.normalized() * TETHER
		for i in C * R:   # never through the body: stay outside the (curved) back surface under each point
			var d := (_P[i] - S[i]).dot(nrm)
			if d < STAND:
				_P[i] += nrm * (STAND - d)
			elif d > MAX_STAND:
				_P[i] -= nrm * (d - MAX_STAND)
	_draw(nrm)


func _link(a: int, b: int, rest: float) -> void:
	var d := _P[b] - _P[a]
	var l := maxf(d.length(), 1e-6)
	var diff := (l - rest) / l
	var pin_a := a == 0 or a == C - 1
	var pin_b := b == 0 or b == C - 1
	var wa := 0.0 if pin_a else (1.0 if pin_b else 0.5)
	var wb := 0.0 if pin_b else (1.0 if pin_a else 0.5)
	_P[a] += d * (diff * wa)
	_P[b] -= d * (diff * wb)


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
