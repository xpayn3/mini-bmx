class_name KneePad
extends Node3D
## A downhill knee pad, built procedurally and ARTICULATED so it holds together at any bend:
##  - the hard CAP (shell over a foam bumper) sits on the bisector of the knee bend: it always faces out
##    of the bend, halfway between thigh and shin, and wraps the knee as a sphere shell round the joint
##  - a quilted foam plate + fabric sleeve rigid to the THIGH, another (with a hard insert) to the SHIN
##  - a fabric ball closes the joint underneath, so any gap between the parts shows sleeve, never a hole
## No piece ever has to span the bend, so nothing stretches, folds through itself or pokes out, straight or
## folded tight, in a turn or in the ragdoll. pose() every frame from hip, knee and ankle.
## Local frames: X = the front of the knee (out of the bend), Y = up the leg, Z = sideways (symmetric).

const SHADER := preload("res://shaders/knee_cap.gdshader")

## the cap: half width (rad round the knee), how far up / down it reaches (rad), outline power
const CAP_A := 1.12
const CAP_UP := 0.72
const CAP_DOWN := 0.98
const CAP_P := 2.4
const CAP_R := 0.097      # shell radius at the edge (from the knee centre)
const CAP_DOME := 0.022   # extra bulge in the middle
const CAP_IN := 0.081     # the foam's inside (just over the joint ball)
const BALL_R := 0.079

var cap: Node3D
var thigh_part: Node3D
var shin_part: Node3D
var cap_mat: ShaderMaterial
var insert_mat: ShaderMaterial
var band_mat: StandardMaterial3D
var front := Vector3.FORWARD   # last front of the knee (hint when the leg is straight)

static var _meshes := {}


func _init() -> void:
	name = "KneePad"
	_build_meshes()
	cap_mat = ShaderMaterial.new()
	cap_mat.shader = SHADER
	cap_mat.set_shader_parameter("sp", CAP_P)
	insert_mat = ShaderMaterial.new()
	insert_mat.shader = SHADER
	insert_mat.set_shader_parameter("mode", 1)
	insert_mat.set_shader_parameter("sp", 4.0)
	var foam := _mat("#34373e", 0.92)
	var fabric := _mat("#141518", 0.97)
	band_mat = _mat("#1b1c20", 0.55)
	cap = Node3D.new()
	cap.name = "Cap"
	add_child(cap)
	_add(cap, _meshes.shell, cap_mat)
	_add(cap, _meshes.cap_foam, foam)
	thigh_part = Node3D.new()
	thigh_part.name = "Thigh"
	add_child(thigh_part)
	_add(thigh_part, _meshes.thigh_sleeve, fabric)
	_add(thigh_part, _meshes.thigh_band, band_mat)
	_add(thigh_part, _meshes.thigh_plate, foam)
	var ball := SphereMesh.new()
	ball.radius = BALL_R
	ball.height = 2 * BALL_R
	ball.radial_segments = 20
	ball.rings = 12
	_add(thigh_part, ball, fabric)
	shin_part = Node3D.new()
	shin_part.name = "Shin"
	add_child(shin_part)
	_add(shin_part, _meshes.shin_sleeve, fabric)
	_add(shin_part, _meshes.shin_band, band_mat)
	_add(shin_part, _meshes.shin_plate, foam)
	_add(shin_part, _meshes.shin_insert, insert_mat)
	set_colors(Color("#1b1c20"), Color("#ffd21f"))


func _add(parent: Node3D, m: Mesh, mt: Material) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.material_override = mt
	parent.add_child(mi)


## shell colour + accent (chevron, stripe)
func set_colors(base: Color, accent: Color) -> void:
	for m in [cap_mat, insert_mat]:
		m.set_shader_parameter("base_col", base)
		m.set_shader_parameter("accent", accent)
	band_mat.albedo_color = base


## Place the pad. hip -> knee_t is the thigh, knee_s -> ankle the shin (knee_t != knee_s: the shin was torn
## off at the knee, the cap goes). hint: the knee's front when the leg is straight (the IK pole), or ZERO
## to keep the last one. All points in the parent's space.
func pose(hip: Vector3, knee_t: Vector3, knee_s: Vector3, ankle: Vector3, hint := Vector3.ZERO) -> void:
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


## a point on the cap's sphere round the knee: s across, t up the leg (both -1..1 on the outline)
static func _cap_dir(s: float, t: float) -> Vector3:
	var a := s * CAP_A * (1.0 - 0.2 * maxf(0.0, -t))   # a little narrower toward the shin (a shield)
	var e := t * (CAP_UP if t > 0.0 else CAP_DOWN)
	return Vector3(cos(e) * cos(a), sin(e), cos(e) * sin(a))


static func _cap_r(s: float, t: float) -> float:
	var rho := minf(pow(pow(absf(s), CAP_P) + pow(absf(t), CAP_P), 1.0 / CAP_P), 1.0)
	var dome := CAP_DOME * pow(1.0 - rho * rho, 1.3)
	var ridge := 0.0035 * exp(-pow(s / 0.09, 2.0)) * (1.0 - pow(rho, 4.0))   # a spine down the middle
	return CAP_R + dome + ridge


## quilted foam: n_q pillows up the plate, grooves between them, rounded off at the edge
static func _pillow(t: float, rho: float, n_q: float) -> float:
	var u := (t + 1.0) * 0.5 * n_q
	var fu := u - floorf(u)
	return sqrt(maxf(sin(PI * fu), 0.0)) * (1.0 - pow(minf(rho, 1.0), 8.0))


static func _build_meshes() -> void:
	if not _meshes.is_empty():
		return
	var out_c := func(pt: Vector3) -> Vector3: return pt   # away from the knee centre
	var in_c := func(pt: Vector3) -> Vector3: return -pt
	var out_axis := func(pt: Vector3) -> Vector3: return Vector3(pt.x, 0.0, pt.z)

	# --- cap: shell (outer face + a rolled lip) and the foam bumper under it
	var sh := Mb.new()
	var edge := sh.patch(18, CAP_P, func(s, t, _r): return _cap_dir(s, t) * _cap_r(s, t), out_c)
	sh.ring(edge, func(s, t): return _cap_dir(s, t) * (_cap_r(s, t) - 0.0045), func(pt: Vector3) -> Vector3: return pt - Vector3(0.09, 0, 0))
	var fm := Mb.new()
	var f0 := []
	for e in edge:   # the foam starts just under the shell's lip
		f0.append([fm.v(_cap_dir(e[1], e[2]) * (_cap_r(e[1], e[2]) - 0.004)), e[1], e[2]])
	var bump := func(pt: Vector3) -> Vector3: return pt - Vector3(0.085, 0, 0)
	var f1 := fm.ring(f0, func(s, t): return _cap_dir(s * 1.07, t * 1.07) * (CAP_R - 0.002), bump)
	var f2 := fm.ring(f1, func(s, t): return _cap_dir(s * 1.04, t * 1.04) * (CAP_IN + 0.004), bump)
	var inner := fm.patch(18, CAP_P, func(s, t, _r): return _cap_dir(s, t) * CAP_IN, in_c)
	fm.join(f2, inner, bump)

	# --- thigh: sleeve from the knee up, an elastic band at the top, a quilted plate on the front
	var ts := Mb.new()
	ts.tube([[0.0, 0.0772], [0.025, 0.0802], [0.08, 0.0795], [0.16, 0.0778], [0.166, 0.0745]], 28)
	var tb := Mb.new()
	tb.tube([[0.15, 0.0765], [0.153, 0.0812], [0.178, 0.0806], [0.183, 0.0735]], 28)
	var tp := _plate(0.068, 0.148, 1.0, 0.0805, 0.0795, 2.0)

	# --- shin: sleeve down to mid-shin, band, a long quilted plate and a hard insert on it
	var ss := Mb.new()
	ss.tube([[0.0, 0.0745], [-0.025, 0.0735], [-0.07, 0.066], [-0.15, 0.0615], [-0.255, 0.0595], [-0.26, 0.056]], 28)
	var sb := Mb.new()
	sb.tube([[-0.238, 0.0598], [-0.242, 0.0642], [-0.266, 0.0632], [-0.27, 0.0565]], 28)
	var sp := _plate(-0.235, -0.088, 1.08, 0.0598, 0.0645, 3.0)
	var si := Mb.new()
	var ins_r := func(y: float) -> float: return lerpf(0.0598, 0.0645, inverse_lerp(-0.235, -0.088, y)) + 0.0175
	var ins_pt := func(s, t, _r) -> Vector3:
		var y: float = lerpf(-0.2, -0.13, (t + 1.0) * 0.5)
		var a: float = s * 0.5
		var r: float = ins_r.call(y) + 0.0025 * (1.0 - pow(minf(_r, 1.0), 6.0))
		return Vector3(cos(a) * r, y, sin(a) * r)
	var ins_edge := func(s, t) -> Vector3:
		var y: float = lerpf(-0.2, -0.13, (t + 1.0) * 0.5)
		var r: float = ins_r.call(y) - 0.006
		return Vector3(cos(s * 0.5) * r, y, sin(s * 0.5) * r)
	var ie := si.patch(10, 4.0, ins_pt, out_axis)
	si.ring(ie, ins_edge, func(pt: Vector3) -> Vector3: return pt - Vector3(0.06, -0.165, 0))

	_meshes = {shell = sh.mesh(), cap_foam = fm.mesh(), thigh_sleeve = ts.mesh(), thigh_band = tb.mesh(),
		thigh_plate = tp.mesh(), shin_sleeve = ss.mesh(), shin_band = sb.mesh(), shin_plate = sp.mesh(),
		shin_insert = si.mesh()}


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
	return m
