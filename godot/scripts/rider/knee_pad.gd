class_name KneePad
extends Node3D
## Knee pads, built procedurally and ARTICULATED so they hold together at any bend. Every design is made of
## three rigid groups that never span the bend:
##  - the CAP sits on the bisector of the knee bend: it always faces out of the bend, halfway between thigh
##    and shin, and wraps the knee as a sphere shell round the joint
##  - the THIGH group (sleeve, band, plate / guard) is rigid to the thigh, the SHIN group to the shin
##  - a fabric ball closes the joint underneath, so any gap between the parts shows sleeve, never a hole
## Straight or folded tight, in a turn or in the ragdoll, nothing stretches, folds through itself or pokes out.
## DESIGNS (Kit > Knee pads, look.padStyle):
##   enduro - hard cap with a chevron on a foam bumper, quilted foam plates, hard shin insert
##   race   - hinged brace: big striped cap, ribbed hard thigh + shin guards, side bars + metal hinge discs
##   trail  - soft, low-profile: honeycomb foam cap, slim long sleeve with accent bands, small shin pad
##   none   - no pads (the rider shows the plain knee)
## Every design is held on by velcro straps round the back of the leg; their loose ends flap (StrapTail).
## Local frames: X = the front of the knee (out of the bend), Y = up the leg, Z = sideways (symmetric).

const SHADER := preload("res://shaders/knee_cap.gdshader")
const DESIGNS := ["enduro", "race", "trail", "none"]
const BALL_R := 0.079

## cap shapes: half width (rad round the knee), reach up / down (rad), outline power, edge radius, dome,
## centre spine, the foam's inside, shader mode
const CAPS := {
	enduro = {a = 1.12, up = 0.72, down = 0.98, p = 2.4, r = 0.097, dome = 0.022, ridge = 0.0035, inr = 0.081, mode = 0},
	race = {a = 1.02, up = 0.8, down = 1.0, p = 3.2, r = 0.1, dome = 0.027, ridge = 0.0, inr = 0.081, mode = 2},
	trail = {a = 0.98, up = 0.64, down = 0.84, p = 2.2, r = 0.0915, dome = 0.013, ridge = 0.0, inr = 0.081, mode = 4},
}

var design := ""
var cap: Node3D
var thigh_part: Node3D
var shin_part: Node3D
var _mats: Array[ShaderMaterial] = []    # shader materials of the current design (take the colours)
var _base_mats: Array[StandardMaterial3D] = []   # take the pad colour
var _accent_mats: Array[StandardMaterial3D] = []   # take the accent colour
var _base := Color("#1b1c20")
var _accent := Color("#ffd21f")
var front := Vector3.FORWARD   # last front of the knee (hint when the leg is straight)
var side := 1.0   # which way is the outside of this leg along the pad's Z (+1 = the rider's right leg)

## straps per design: [group, height on the bone, sleeve radius there]; the buckle sits on the outer back
const STRAPS := {
	enduro = [["thigh", 0.112, 0.0797], ["shin", -0.2, 0.0608]],
	race = [["thigh", 0.132, 0.0785], ["shin", -0.235, 0.0614]],
	trail = [["thigh", 0.15, 0.0756]],
}
const BUCKLE_A := 1.95   # rad round the leg from the front

## the brand printed on each design (made-up names, the same world as the trail banners) and where:
## [which shell: "cap" / "guard", rect (centre, half size in the shell's -1..1 space), vertical, colour:
## "white" / "accent" / "base"]
const LOGOS := {
	enduro = ["DIRTLAB", "cap", Vector4(0.0, 0.5, 0.33, 0.12), false, "white"],
	race = ["NITRO", "guard", Vector4(0.0, 0.02, 0.6, 0.17), true, "accent"],
	trail = ["TERRA", "cap", Vector4(0.0, 0.55, 0.34, 0.12), false, "base"],
}
static var _logo_tex := {}   # brand -> ImageTexture (baked once)
var _logo_mat: ShaderMaterial

static var _meshes := {}   # design -> {part name: Mesh}
static var _alive := 0     # pads in existence: the caches are let go with the last one (no leaks at quit)


func _init(sd := 1.0) -> void:
	name = "KneePad"
	_alive += 1
	side = signf(sd) if sd != 0.0 else 1.0
	set_design("enduro")


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		_alive -= 1
		if _alive <= 0:
			_meshes.clear()
			_logo_tex.clear()


## swap to another design (DESIGNS); "none" hides the pad
func set_design(d: String) -> void:
	if not d in DESIGNS:
		d = "enduro"
	if d == design:
		return
	design = d
	for c in get_children():
		remove_child(c)
		c.free()
	_mats.clear(); _base_mats.clear(); _accent_mats.clear()
	_logo_mat = null
	cap = Node3D.new(); cap.name = "Cap"; add_child(cap)
	thigh_part = Node3D.new(); thigh_part.name = "Thigh"; add_child(thigh_part)
	shin_part = Node3D.new(); shin_part.name = "Shin"; add_child(shin_part)
	visible = d != "none"
	if d == "none":
		return
	var M: Dictionary = _design_meshes(d)
	var fabric := _mat("#141518", 0.97)
	var foam := _mat("#34373e", 0.92)
	var cap_mat := _shader(int(CAPS[d].mode), float(CAPS[d].p))
	_logo_mat = cap_mat
	_add(cap, M.shell, cap_mat)
	_add(cap, M.cap_foam, foam)
	_add(thigh_part, M.thigh_sleeve, fabric)
	_add(shin_part, M.shin_sleeve, fabric)
	var ball := SphereMesh.new()
	ball.radius = BALL_R; ball.height = 2 * BALL_R; ball.radial_segments = 20; ball.rings = 12
	_add(thigh_part, ball, fabric)
	var band := _mat("#1b1c20", 0.55)
	if d == "trail":
		_accent_mats.append(band)
	else:
		_base_mats.append(band)
	_add(thigh_part, M.thigh_band, band)
	_add(shin_part, M.shin_band, band)
	match d:
		"enduro":
			_add(thigh_part, M.thigh_plate, foam)
			_add(shin_part, M.shin_plate, foam)
			var ins := _shader(1, 4.0)
			ins.set_shader_parameter("gloss", 0.0)
			_add(shin_part, M.shin_insert, ins)
		"race":
			var guard := _shader(3, 4.0)
			guard.set_shader_parameter("gloss", 0.0)
			_logo_mat = guard
			_add(thigh_part, M.thigh_guard, guard)
			_add(shin_part, M.shin_guard, guard)
			var bar := _mat("#1b1c20", 0.8)
			_base_mats.append(bar)
			var metal := _mat("#b9bcc2", 0.25)
			metal.metallic = 1.0
			var dark := _mat("#18191c", 0.6)
			for sd in [-1.0, 1.0]:
				# the brace: a bar down each side of the thigh and the shin, joined by a hinge on the knee's axis
				# (both groups turn round their Z = the bend axis, so the hinge stays put and the bars swing)
				_add(thigh_part, M.bar_thigh, bar, Vector3(0, 0, sd * 0.088))
				_add(shin_part, M.bar_shin, bar, Vector3(0, 0, sd * 0.099))
				_add(shin_part, M.hinge, dark, Vector3(0, 0, sd * 0.107), sd)
				_add(shin_part, M.hinge_cap, metal, Vector3(0, 0, sd * 0.113), sd)
		"trail":
			_add(shin_part, M.shin_plate, foam)
	# velcro straps round the back of the leg, a buckle tab on the outer back, the loose end flapping
	var strap := _mat("#ffd21f", 0.8)   # the straps in the accent colour (like the goggle strap)
	strap.cull_mode = BaseMaterial3D.CULL_DISABLED
	_accent_mats.append(strap)
	var tab := _mat("#2a2c31", 0.6)
	for st in STRAPS[d]:
		var grp: Node3D = thigh_part if st[0] == "thigh" else shin_part
		var y: float = st[1]
		var r: float = st[2]
		_add(grp, _strap_mesh(r, 0.0, side), strap, Vector3(0, y, 0))
		_add(grp, _strap_mesh(r, 1.0, side), tab, Vector3(0, y, 0))
		var tail := StrapTail.new()
		tail.part = grp
		tail.anchor_local = Vector3(cos(BUCKLE_A) * (r + 0.008), y, side * sin(BUCKLE_A) * (r + 0.008))
		tail.clear_r = r + 0.006
		tail.material_override = strap
		grp.add_child(tail)
	# the brand
	var lg: Array = LOGOS[d]
	_logo_mat.set_shader_parameter("logo_rect", lg[2])
	_logo_mat.set_shader_parameter("logo_vertical", lg[3])
	if _logo_tex.has(lg[0]):
		_logo_mat.set_shader_parameter("logo_tex", _logo_tex[lg[0]])
		_logo_mat.set_shader_parameter("logo_on", 1.0)
	else:
		var bk := LogoBaker.new()
		bk.text = lg[0]
		bk.done = func(tex: Texture2D) -> void:
			_logo_tex[lg[0]] = tex
			if is_instance_valid(_logo_mat) and design == d:
				_logo_mat.set_shader_parameter("logo_tex", tex)
				_logo_mat.set_shader_parameter("logo_on", 1.0)
		add_child(bk)
	set_colors(_base, _accent)


func _shader(mode: int, sp: float) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = SHADER
	m.set_shader_parameter("mode", mode)
	m.set_shader_parameter("sp", sp)
	_mats.append(m)
	return m


## a part; side != 0: a disc standing on the Z axis, facing out to that side
func _add(parent: Node3D, m: Mesh, mt: Material, at := Vector3.ZERO, side := 0.0) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.material_override = mt
	mi.position = at
	if side != 0.0:
		mi.rotation.x = side * PI * 0.5
	parent.add_child(mi)


## pad colour + accent (chevron, stripes, trail bands)
func set_colors(base: Color, accent: Color) -> void:
	_base = base
	_accent = accent
	for m in _mats:
		m.set_shader_parameter("base_col", base)
		m.set_shader_parameter("accent", accent)
	for m in _base_mats:
		m.albedo_color = base
	if _logo_mat != null and LOGOS.has(design):
		var lc: String = LOGOS[design][4]
		var c := Color(0.95, 0.95, 0.95) if lc == "white" else (accent if lc == "accent" else base)
		if lc == "white" and base.get_luminance() > 0.6: c = Color(0.08, 0.08, 0.09)   # white pads: dark print
		_logo_mat.set_shader_parameter("logo_col", c)
	for m in _accent_mats:
		m.albedo_color = accent


## Place the pad. hip -> knee_t is the thigh, knee_s -> ankle the shin (knee_t != knee_s: the shin was torn
## off at the knee, the cap goes). hint: the knee's front when the leg is straight (the IK pole), or ZERO
## to keep the last one. All points in the parent's space.
func pose(hip: Vector3, knee_t: Vector3, knee_s: Vector3, ankle: Vector3, hint := Vector3.ZERO) -> void:
	if not visible:
		return
	var t := knee_t - hip
	t = t.normalized() if t.length() > 1e-4 else Vector3.DOWN
	var s := ankle - knee_s
	s = s.normalized() if s.length() > 1e-4 else t
	var axis := t + s
	axis = axis.normalized() if axis.length() > 1e-3 else t
	# the hint, square to the leg (falls back to the last front if it lines up with the leg)
	var h := hint - axis * hint.dot(axis)
	if h.length() < 0.3:
		h = front - axis * front.dot(axis)
	if h.length() < 1e-3:
		h = axis.cross(Vector3.RIGHT if absf(axis.x) < 0.9 else Vector3.UP)
	h = h.normalized()
	# out of the bend = (thigh dir - shin dir); kept on the anatomical front (the hint's side), and near
	# straight it eases onto the hint, so the cap never spins round the leg
	var b := t - s
	if b.dot(h) < 0.0:
		b = -b
	var f := b + h * maxf(0.0, 0.3 - b.length())
	f = f.normalized() if f.length() > 1e-4 else h
	front = f
	var cut := knee_t.distance_squared_to(knee_s) > 1e-6
	cap.visible = not cut
	if not cut:
		var u := -(t + s)
		u = u - f * u.dot(f)
		u = u.normalized() if u.length() > 1e-4 else -t
		cap.transform = Transform3D(Basis(f, u, f.cross(u)), knee_t)
	thigh_part.transform = Transform3D(_seg_basis(-t, f), knee_t)
	shin_part.transform = Transform3D(_seg_basis(-s, f), knee_s)


## Y = up (along a bone), X = the front squared to it
static func _seg_basis(up: Vector3, fwd: Vector3) -> Basis:
	var x := fwd - up * fwd.dot(up)
	if x.length() < 1e-4:
		x = up.cross(Vector3.FORWARD if absf(up.z) < 0.9 else Vector3.RIGHT)
	x = x.normalized()
	return Basis(x, up, x.cross(up))


# ---------------------------------------------------------------- geometry (built once, shared)

## indexed triangles + uv; tri() orients each triangle to face `want` (three-style CCW = front)
class Mb:
	var pos := PackedVector3Array()
	var uv := PackedVector2Array()
	var idx := PackedInt32Array()

	func v(p: Vector3, t := Vector2.ZERO) -> int:
		pos.append(p)
		uv.append(t)
		return pos.size() - 1

	func tri(a: int, b: int, c: int, want: Vector3) -> void:
		if (pos[b] - pos[a]).cross(pos[c] - pos[a]).dot(want) < 0.0:
			idx.append_array([a, c, b])
		else:
			idx.append_array([a, b, c])

	func mesh() -> ArrayMesh:
		var nrm := PackedVector3Array()
		nrm.resize(pos.size())
		for k in range(0, idx.size(), 3):
			var n := (pos[idx[k + 1]] - pos[idx[k]]).cross(pos[idx[k + 2]] - pos[idx[k]])
			for j in 3:
				nrm[idx[k + j]] += n
		for i in nrm.size():
			nrm[i] = nrm[i].normalized() if nrm[i].length() > 1e-12 else Vector3.UP
		var gi := PackedInt32Array()
		gi.resize(idx.size())
		for k in range(0, idx.size(), 3):   # CCW -> Godot's CW
			gi[k] = idx[k]
			gi[k + 1] = idx[k + 2]
			gi[k + 2] = idx[k + 1]
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = pos
		arr[Mesh.ARRAY_NORMAL] = nrm
		arr[Mesh.ARRAY_TEX_UV] = uv
		arr[Mesh.ARRAY_INDEX] = gi
		var m := ArrayMesh.new()
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		return m

	## a patch over the superellipse |s|^p + |t|^p <= 1: an n x n grid of the square squeezed onto it.
	## f(s, t, rho) -> point; want(point) -> the side to face. Returns the edge loop [[id, s, t], ...].
	func patch(n: int, p: float, f: Callable, want: Callable) -> Array:
		var ids := PackedInt32Array()
		for j in n + 1:
			for i in n + 1:
				var q := Vector2(-1.0 + 2.0 * i / n, -1.0 + 2.0 * j / n)
				var m := maxf(absf(q.x), absf(q.y))
				if m > 0.0:
					q *= m / pow(pow(absf(q.x), p) + pow(absf(q.y), p), 1.0 / p)
				ids.append(v(f.call(q.x, q.y, m), q * 0.5 + Vector2(0.5, 0.5)))
		for j in n:
			for i in n:
				var a := ids[j * (n + 1) + i]
				var b := ids[j * (n + 1) + i + 1]
				var c := ids[(j + 1) * (n + 1) + i + 1]
				var d := ids[(j + 1) * (n + 1) + i]
				var w: Vector3 = want.call((pos[a] + pos[c]) * 0.5)
				tri(a, b, c, w)
				tri(a, c, d, w)
		var loop := []
		var at := func(i: int, j: int) -> void:
			var k := ids[j * (n + 1) + i]
			loop.append([k, uv[k].x * 2.0 - 1.0, uv[k].y * 2.0 - 1.0])
		for i in n: at.call(i, 0)
		for j in n: at.call(n, j)
		for i in range(n, 0, -1): at.call(i, n)
		for j in range(n, 0, -1): at.call(0, j)
		return loop

	## a new ring of points g(s, t) along an edge loop; joined to it, facing want(point)
	func ring(loop: Array, g: Callable, want: Callable) -> Array:
		var out := []
		for e in loop:
			out.append([v(g.call(e[1], e[2]), Vector2(e[1], e[2]) * 0.5 + Vector2(0.5, 0.5)), e[1], e[2]])
		join(loop, out, want)
		return out

	func join(l0: Array, l1: Array, want: Callable) -> void:
		var n := l0.size()
		for k in n:
			var a: int = l0[k][0]
			var b: int = l0[(k + 1) % n][0]
			var c: int = l1[(k + 1) % n][0]
			var d: int = l1[k][0]
			var w: Vector3 = want.call((pos[a] + pos[c]) * 0.5)
			tri(a, b, c, w)
			tri(a, c, d, w)

	## an open tube round Y through rings [[y, r], ...], facing out
	func tube(rings: Array, seg: int) -> void:
		var prev := []
		for rr in rings:
			var cur := []
			for k in seg:
				var a := TAU * k / seg
				cur.append([v(Vector3(cos(a) * rr[1], rr[0], sin(a) * rr[1])), 0.0, 0.0])
			if not prev.is_empty():
				join(prev, cur, func(pt: Vector3) -> Vector3: return Vector3(pt.x, 0.0, pt.z))
			prev = cur




## quilted foam: n_q pillows up the plate, grooves between them, rounded off at the edge
static func _pillow(t: float, rho: float, n_q: float) -> float:
	var u := (t + 1.0) * 0.5 * n_q
	var fu := u - floorf(u)
	return sqrt(maxf(sin(PI * fu), 0.0)) * (1.0 - pow(minf(rho, 1.0), 8.0))



## a quilted foam plate wrapped round the bone axis: y0..y1 up the bone, half width a (rad), sitting on a
## sleeve of radius r0 (at y0) .. r1 (at y1), n_q pillows
static func _plate(y0: float, y1: float, a: float, r0: float, r1: float, n_q: float) -> Mb:
	var m := Mb.new()
	var base := func(y: float) -> float: return lerpf(r0, r1, inverse_lerp(y0, y1, y))
	var surf := func(s, t, rho) -> Vector3:
		var y: float = lerpf(y0, y1, (t + 1.0) * 0.5)
		var r: float = base.call(y) + 0.004 + 0.0095 * _pillow(t, rho, n_q)
		return Vector3(cos(s * a) * r, y, sin(s * a) * r)
	var mid := (y0 + y1) * 0.5
	var away := func(pt: Vector3) -> Vector3: return Vector3(0, pt.y - mid, 0) + Vector3(0, 0, pt.z) * 1.5
	var edge := func(s, t) -> Vector3:
		var y: float = lerpf(y0, y1, (t * 1.015 + 1.0) * 0.5)
		var r: float = base.call(y) + 0.0015
		return Vector3(cos(s * a * 1.015) * r, y, sin(s * a * 1.015) * r)
	var e := m.patch(26, 4.0, surf, func(pt: Vector3) -> Vector3: return Vector3(pt.x, 0.0, pt.z))
	m.ring(e, edge, away)
	return m


static func _mat(color: String, roughness: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(color)
	m.roughness = roughness
	if roughness >= 0.5:   # sleeves, foam, bands, straps: matte; only the kneecap shell shines
		m.roughness = maxf(roughness, 0.92)
		m.metallic_specular = 0.15
	m.cull_mode = BaseMaterial3D.CULL_DISABLED   # double sided: sleeves, plates and lips are open shells
	return m


const G := preload("res://scripts/rider/rider_geo.gd")


## a point on a cap's sphere round the knee: s across, t up the leg (both -1..1 on the outline)
static func _cap_dir(c: Dictionary, s: float, t: float) -> Vector3:
	var a: float = s * float(c.a) * (1.0 - 0.2 * maxf(0.0, -t))   # a little narrower toward the shin (a shield)
	var e: float = t * float(c.up if t > 0.0 else c.down)
	return Vector3(cos(e) * cos(a), sin(e), cos(e) * sin(a))


static func _cap_r(c: Dictionary, s: float, t: float) -> float:
	var p: float = c.p
	var rho := minf(pow(pow(absf(s), p) + pow(absf(t), p), 1.0 / p), 1.0)
	var dome: float = float(c.dome) * pow(1.0 - rho * rho, 1.3)
	var ridge: float = float(c.ridge) * exp(-pow(s / 0.09, 2.0)) * (1.0 - pow(rho, 4.0))   # a spine down the middle
	return float(c.r) + dome + ridge


## the cap: shell (outer face + a rolled lip) and the foam bumper under it
static func _cap_meshes(c: Dictionary) -> Array:
	var p: float = c.p
	var sh := Mb.new()
	var edge := sh.patch(18, p, func(s, t, _r): return _cap_dir(c, s, t) * _cap_r(c, s, t), func(pt: Vector3) -> Vector3: return pt)
	sh.ring(edge, func(s, t): return _cap_dir(c, s, t) * (_cap_r(c, s, t) - 0.0045), func(pt: Vector3) -> Vector3: return pt - Vector3(0.09, 0, 0))
	var fm := Mb.new()
	var f0 := []
	for e in edge:   # the foam starts just under the shell's lip
		f0.append([fm.v(_cap_dir(c, e[1], e[2]) * (_cap_r(c, e[1], e[2]) - 0.004)), e[1], e[2]])
	var bump := func(pt: Vector3) -> Vector3: return pt - Vector3(0.085, 0, 0)
	var f1 := fm.ring(f0, func(s, t): return _cap_dir(c, s * 1.07, t * 1.07) * (float(c.r) - 0.002), bump)
	var f2 := fm.ring(f1, func(s, t): return _cap_dir(c, s * 1.04, t * 1.04) * (float(c.inr) + 0.004), bump)
	var inner := fm.patch(18, p, func(s, t, _r): return _cap_dir(c, s, t) * float(c.inr), func(pt: Vector3) -> Vector3: return -pt)
	fm.join(f2, inner, bump)
	return [sh.mesh(), fm.mesh()]


## a hard plate wrapped round the bone axis (UV for the shader): y0..y1, half width a (rad), standing `off`
## over a sleeve of radius r0 (at y0) .. r1 (at y1), domed by `bulge`, with a lip down to the sleeve
static func _guard(y0: float, y1: float, a: float, r0: float, r1: float, off: float, bulge: float) -> ArrayMesh:
	var m := Mb.new()
	var base := func(y: float) -> float: return lerpf(r0, r1, inverse_lerp(y0, y1, y))
	var surf := func(s, t, rho) -> Vector3:
		var y: float = lerpf(y0, y1, (t + 1.0) * 0.5)
		var r: float = base.call(y) + off + bulge * (1.0 - pow(minf(rho, 1.0), 2.0))
		return Vector3(cos(s * a) * r, y, sin(s * a) * r)
	var lip := func(s, t) -> Vector3:
		var y: float = lerpf(y0, y1, (t + 1.0) * 0.5)
		var r: float = base.call(y) + 0.0015
		return Vector3(cos(s * a) * r, y, sin(s * a) * r)
	var mid := Vector3(0.0, (y0 + y1) * 0.5, 0.0)
	var e := m.patch(16, 4.0, surf, func(pt: Vector3) -> Vector3: return Vector3(pt.x, 0.0, pt.z))
	m.ring(e, lip, func(pt: Vector3) -> Vector3: return Vector3(0, pt.y - mid.y, 0) + Vector3(0, 0, pt.z) * 1.5)
	return m.mesh()


static func _tube(rings: Array) -> ArrayMesh:
	var m := Mb.new()
	m.tube(rings, 28)
	return m.mesh()


static func _bar(y0: float, y1: float) -> ArrayMesh:
	var g := G.rounded_box(0.026, y1 - y0, 0.009, 2, 0.004)
	g = G.xform(g, Transform3D(Basis(), Vector3(0, (y0 + y1) * 0.5, 0)))
	return G.mesh_from(g.pos, g.idx)


static func _disc(r: float, h: float) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = r
	c.bottom_radius = r
	c.height = h
	c.radial_segments = 24
	c.rings = 1
	return c


## a strap: kind 0 = the band round the back of the leg (from under the front plate's edge, both sides), kind
## 1 = the buckle tab on the outer back (`sd` side). Rectangular section, local y = 0 at the strap's middle.
static func _strap_mesh(r: float, kind: float, sd: float) -> ArrayMesh:
	var key := "strap_%.4f_%d_%d" % [r, int(kind), int(sd)]
	if _meshes.has(key):
		return _meshes[key]
	var w := 0.0125 if kind == 0.0 else 0.017
	var t := 0.0035 if kind == 0.0 else 0.0075
	var a0 := 0.9 if kind == 0.0 else BUCKLE_A - 0.17
	var a1 := TAU - 0.9 if kind == 0.0 else BUCKLE_A + 0.17
	var m := Mb.new()
	var prof := [[-w, r - 0.001], [-w, r + t], [w, r + t], [w, r - 0.001]]
	var rows := []
	var n := 40 if kind == 0.0 else 6
	for k in n + 1:
		var a := lerpf(a0, a1, float(k) / n) * (sd if kind == 1.0 else 1.0)
		var row := []
		for pp in prof:
			row.append(m.v(Vector3(cos(a) * pp[1], pp[0], sin(a) * pp[1])))
		rows.append(row)
	var want := func(pt: Vector3) -> Vector3: return Vector3(pt.x, pt.y * 3.0, pt.z)
	for k in n:
		for j in 3:
			var a: int = rows[k][j]
			var b: int = rows[k + 1][j]
			var c: int = rows[k + 1][j + 1]
			var e: int = rows[k][j + 1]
			var wv: Vector3 = want.call((m.pos[a] + m.pos[c]) * 0.5)
			m.tri(a, b, c, wv)
			m.tri(a, c, e, wv)
	if kind == 1.0:   # close the tab's ends
		for row in [rows[0], rows[n]]:
			var cen: Vector3 = (m.pos[row[0]] + m.pos[row[2]]) * 0.5
			var wv: Vector3 = cen - Vector3(cos(BUCKLE_A) * r, 0, sd * sin(BUCKLE_A) * r)
			m.tri(row[0], row[1], row[2], wv)
			m.tri(row[0], row[2], row[3], wv)
	var mesh := m.mesh()
	_meshes[key] = mesh
	return mesh


static func _design_meshes(d: String) -> Dictionary:
	if _meshes.has(d):
		return _meshes[d]
	var cm := _cap_meshes(CAPS[d])
	var M := {shell = cm[0], cap_foam = cm[1]}
	match d:
		"enduro":
			M.thigh_sleeve = _tube([[0.0, 0.0772], [0.025, 0.0802], [0.08, 0.0795], [0.16, 0.0778], [0.166, 0.0745]])
			M.thigh_band = _tube([[0.15, 0.0765], [0.153, 0.0812], [0.178, 0.0806], [0.183, 0.0735]])
			M.thigh_plate = _plate(0.068, 0.148, 1.0, 0.0805, 0.0795, 2.0).mesh()
			M.shin_sleeve = _tube([[0.0, 0.0745], [-0.025, 0.0735], [-0.07, 0.066], [-0.15, 0.0615], [-0.255, 0.0595], [-0.26, 0.056]])
			M.shin_band = _tube([[-0.238, 0.0598], [-0.242, 0.0642], [-0.266, 0.0632], [-0.27, 0.0565]])
			M.shin_plate = _plate(-0.235, -0.088, 1.08, 0.0598, 0.0645, 3.0).mesh()
			M.shin_insert = _guard(-0.2, -0.13, 0.5, 0.0724, 0.0747, 0.006, 0.0025)
		"race":
			M.thigh_sleeve = _tube([[0.0, 0.0772], [0.025, 0.0802], [0.1, 0.0792], [0.2, 0.0768], [0.206, 0.0738]])
			M.thigh_band = _tube([[0.19, 0.0758], [0.193, 0.0806], [0.218, 0.08], [0.223, 0.0728]])
			M.thigh_guard = _guard(0.078, 0.186, 0.98, 0.0796, 0.077, 0.006, 0.006)
			M.shin_sleeve = _tube([[0.0, 0.0745], [-0.025, 0.0735], [-0.07, 0.066], [-0.15, 0.0618], [-0.3, 0.0612], [-0.305, 0.0585]])
			M.shin_band = _tube([[-0.283, 0.0614], [-0.287, 0.0656], [-0.311, 0.0648], [-0.315, 0.058]])
			M.shin_guard = _guard(-0.28, -0.098, 1.12, 0.0612, 0.0645, 0.006, 0.008)
			M.bar_thigh = _bar(-0.012, 0.19)
			M.bar_shin = _bar(-0.27, 0.012)
			M.hinge = _disc(0.026, 0.012)
			M.hinge_cap = _disc(0.012, 0.006)
		"trail":
			M.thigh_sleeve = _tube([[0.0, 0.0768], [0.025, 0.0792], [0.1, 0.0778], [0.2, 0.0755], [0.205, 0.0728]])
			M.thigh_band = _tube([[0.186, 0.0752], [0.189, 0.0786], [0.207, 0.0781], [0.211, 0.0722]])
			M.shin_sleeve = _tube([[0.0, 0.0735], [-0.025, 0.072], [-0.07, 0.0645], [-0.15, 0.0602], [-0.28, 0.0598], [-0.285, 0.057]])
			M.shin_band = _tube([[-0.262, 0.06], [-0.266, 0.0634], [-0.286, 0.0628], [-0.29, 0.0565]])
			M.shin_plate = _plate(-0.19, -0.082, 1.0, 0.0601, 0.0635, 2.0).mesh()
	_meshes[d] = M
	return M


## bakes a wordmark (white on clear) once with a throw-away SubViewport, like StrapLogo; then done(texture)
class LogoBaker extends Node:
	const W := 512
	const H := 128
	var text := ""
	var done: Callable
	var _vp: SubViewport
	var _frames := 0

	func _ready() -> void:
		_vp = SubViewport.new()
		_vp.size = Vector2i(W, H)
		_vp.disable_3d = true
		_vp.transparent_bg = true
		_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		var fv := FontVariation.new()
		fv.base_font = ThemeDB.fallback_font
		fv.variation_embolden = 1.2
		fv.spacing_glyph = 6
		var ls := LabelSettings.new()
		ls.font = fv
		ls.font_size = 104
		ls.font_color = Color.WHITE
		var l := Label.new()
		l.label_settings = ls
		l.text = text
		l.size = Vector2(W, H)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_vp.add_child(l)
		add_child(_vp)

	func _process(_dt: float) -> void:
		_frames += 1
		if _frames < 4:
			return
		var img := _vp.get_texture().get_image()
		if img != null and not img.is_empty():
			img.generate_mipmaps()
			done.call(ImageTexture.create_from_image(img))
		queue_free()
