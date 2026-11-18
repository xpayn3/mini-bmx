class_name RiderGear
extends RefCounted
## Port of src/gear.js: moto goggles, flat-pedal shoes, gloved hands and the lofted jersey torso.
## Frames as in the JS: +X forward, +Y up, +Z the rider's right.

const G := preload("res://scripts/rider/rider_geo.gd")


static func _add(parent: Node3D, g: Dictionary, m: Material) -> MeshInstance3D:
	var mi := G.inst(g, m)
	parent.add_child(mi)
	return mi


## three.js Euler 'XYZ' (Rx * Ry * Rz)
static func euler_xyz(x: float, y: float, z: float) -> Basis:
	return Basis(Vector3.RIGHT, x) * Basis(Vector3.UP, y) * Basis(Vector3.BACK, z)


# ---------------- goggles ----------------

static func _bez(out: PackedVector2Array, p0: Vector2, c1: Vector2, c2: Vector2, p3: Vector2, n: int) -> void:
	for k in range(1, n + 1):
		var t := float(k) / n
		var u := 1.0 - t
		out.append(p0 * u * u * u + c1 * 3.0 * u * u * t + c2 * 3.0 * u * t * t + p3 * t * t * t)


## The goggle outline (u across, v up), sampled with n points per curve (same count for every inset,
## so an inset outline's points pair up with the outer one's).
static func goggle_outline(w: float, h: float, inset := 0.0, n := 10) -> PackedVector2Array:
	var W := w / 2 - inset
	var H := h / 2 - inset
	var nose := 0.022 - inset * 0.5
	var nw := 0.024 + inset * 0.3
	var s := PackedVector2Array()
	var p := Vector2(-nw, -H)
	s.append(p)
	_bez(s, p, Vector2(-W * 0.6, -H - 0.004), Vector2(-W, -H * 0.7), Vector2(-W, -H * 0.05), n)
	_bez(s, s[s.size() - 1], Vector2(-W, H * 0.85), Vector2(-W * 0.8, H), Vector2(-W * 0.55, H), n)
	s.append(Vector2(W * 0.55, H))
	_bez(s, s[s.size() - 1], Vector2(W * 0.8, H), Vector2(W, H * 0.85), Vector2(W, -H * 0.05), n)
	_bez(s, s[s.size() - 1], Vector2(W, -H * 0.7), Vector2(W * 0.6, -H - 0.004), Vector2(nw, -H), n)
	_bez(s, s[s.size() - 1], Vector2(nw * 0.7, -H + nose), Vector2(-nw * 0.7, -H + nose), Vector2(-nw, -H), n)
	s.remove_at(s.size() - 1)   # closes back onto the start
	return s


## m: {frame, foam, lens, strap} materials. fit: Rider.GOGGLE_FIT. hug: Callable(x, y, dx, dz) -> float
## distance to the shell's outside (or null / invalid Callable: plain ellipse).
static func build_goggles(m: Dictionary, fit: Dictionary, hug: Callable) -> Node3D:
	var x: float = fit.get("x", 0.15)
	var y: float = fit.get("y", 0.025)
	var tilt: float = fit.get("tilt", 0.25)
	var w: float = fit.get("w", 0.2)
	var h: float = fit.get("h", 0.075)
	var R: float = fit.get("R", 0.12)
	var S: Dictionary = fit.get("strap", {cx = 0.01, ra = 0.236, rc = 0.162})
	var root := Node3D.new()
	root.name = "Goggles"
	var g := Node3D.new()
	g.position = Vector3(x, y, 0)
	g.basis = Basis(Vector3.BACK, tilt)
	root.add_child(g)
	# (u, v, depth) -> bent onto a vertical cylinder of radius R (flips handedness)
	var bend := func(p: Vector3) -> Vector3:
		var a := p.x / R
		var r := R + p.z
		return Vector3(r * cos(a) - R, p.y, r * sin(a))
	_add(g, G.prism(goggle_outline(w, h), goggle_outline(w, h, 0.01), -0.012, -0.002, bend, true), m.frame)
	_add(g, G.prism(goggle_outline(w, h, 0.002), PackedVector2Array(), -0.022, -0.014, bend, true), m.foam)
	_add(g, G.sheet(goggle_outline(w, h, 0.005, 12), -0.004, bend, true), m.lens)
	# outriggers where the strap clips on
	var ends: Array[Vector3] = []
	for s in [-1.0, 1.0]:
		var a: float = s * (w / 2) / R
		var r := R - 0.008
		var o := _add(g, G.box(0.028, 0.032, 0.012), m.frame)
		o.position = Vector3(r * cos(a) - R - 0.006, 0, r * sin(a) + s * 0.004)
		o.basis = Basis(Vector3.UP, -a)
		ends.append(Transform3D(Basis(Vector3.BACK, tilt), g.position) * o.position)
	# strap: outrigger -> round the back of the shell -> other outrigger
	var yS := y - 0.004
	var pts := PackedVector3Array()
	var ca := clampf((ends[0].x - 0.02 - S.cx) / S.ra, -0.98, 0.98)
	var a0 := acos(ca)
	pts.append(Vector3(ends[0].x, yS, ends[0].z))
	var seg := 40
	for i in seg + 1:
		var a := -a0 - (PI * 2 - 2 * a0) * (float(i) / seg)
		var dx := cos(a)
		var dz := sin(a)
		var r = hug.call(S.cx, yS, dx, dz) if hug.is_valid() else null
		if r != null and r != 0.0:
			pts.append(Vector3(S.cx + dx * (r + 0.004), yS, dz * (r + 0.004)))
		else:
			pts.append(Vector3(S.cx + S.ra * dx, yS, S.rc * dz))
	pts.append(Vector3(ends[1].x, yS, ends[1].z))
	var pos := PackedVector3Array()
	var idx := PackedInt32Array()
	var hw := 0.021
	for i in pts.size():
		var p := pts[i]
		pos.append(Vector3(p.x, p.y - hw, p.z))
		pos.append(Vector3(p.x, p.y + hw, p.z))
		if i < pts.size() - 1:
			var k := i * 2
			idx.append_array([k, k + 1, k + 2, k + 1, k + 3, k + 2])
	_add(root, {pos = pos, idx = idx}, m.strap)
	return root


# ---------------- shoes ----------------
const X0 := -0.115
const X1 := 0.175
const LEN := X1 - X0


static func half_width(x: float) -> float:
	var t := (x - X0) / LEN
	var base := 0.042 + 0.016 * sin(minf(1.0, t / 0.72) * PI * 0.5)
	var toe := sqrt(maxf(0.0, 1.0 - pow((t - 0.72) / 0.28, 2))) if t > 0.72 else 1.0
	var heel := sqrt(maxf(0.0, 1.0 - pow((0.12 - t) / 0.12, 2))) if t < 0.12 else 1.0
	return base * minf(toe, heel) + 0.002


static func upper_h(x: float) -> float:
	var t := (x - X0) / LEN
	if t > 0.62:
		return 0.05 + 0.04 * pow(1.0 - (t - 0.62) / 0.38, 1.5)
	if t > 0.25:
		return 0.09 + 0.005 * sin((t - 0.25) / 0.37 * PI)
	return 0.09 + 0.015 * (0.25 - t) / 0.25


static func _sole_geo(inset: float, y0: float, y1: float, n := 28) -> Dictionary:
	var side := PackedVector2Array()
	for i in n + 1:
		var x := X0 + LEN * (float(i) / n)
		side.append(Vector2(x, half_width(x) - inset))
	var loop := side.duplicate()
	for i in range(n - 1, 0, -1):
		loop.append(Vector2(side[i].x, -side[i].y))
	# (x, z) outline, extruded along y: (a, b, c) -> (a, c, b) flips handedness
	var map := func(p: Vector3) -> Vector3: return Vector3(p.x, p.z, p.y)
	return G.prism(loop, PackedVector2Array(), y0, y1, map, true)


static func _upper_geo(n := 22, m := 12) -> Dictionary:
	var pos := PackedVector3Array()
	var idx := PackedInt32Array()
	for i in n + 1:
		var x := X0 + 0.004 + (LEN - 0.012) * (float(i) / n)
		var hw := half_width(x) - 0.003
		var h := upper_h(x)
		for j in m + 1:
			var a := PI * (float(j) / m)
			pos.append(Vector3(x, 0.022 + pow(sin(a), 0.7) * (h - 0.022), cos(a) * hw))
	var row := m + 1
	for i in n:
		for j in m:
			var k := i * row + j
			idx.append_array([k, k + row, k + 1, k + 1, k + row, k + row + 1])
	for cap in [[0, false], [n, true]]:
		var ci: int = cap[0]
		var c := pos.size()
		var x := pos[ci * row].x
		pos.append(Vector3(x, 0.022 + (upper_h(x) - 0.022) * 0.5, 0))
		for j in m:
			var k := ci * row + j
			if cap[1]:
				idx.append_array([c, k, k + 1])
			else:
				idx.append_array([c, k + 1, k])
	return {pos = pos, idx = idx}


## m: {upper, accent, sole, mid, laces}
static func build_shoe(m: Dictionary) -> Node3D:
	var s := Node3D.new()
	s.name = "Shoe"
	_add(s, _sole_geo(0, 0, 0.022), m.sole)
	_add(s, _sole_geo(-0.001, 0.019, 0.025), m.mid)
	_add(s, _upper_geo(), m.upper)
	var collar := _add(s, G.torus(0.043, 0.011, 5, 12), m.accent)
	collar.transform = Transform3D(euler_xyz(PI / 2, 0, -0.18).scaled_local(Vector3(1.25, 1, 1)), Vector3(-0.055, 0.1, 0))
	var tab := _add(s, G.box(0.012, 0.035, 0.03), m.accent)
	tab.transform = Transform3D(Basis(Vector3.BACK, 0.15), Vector3(-0.111, 0.095, 0))
	# toe cap: the front 22% of the loft, puffed out a touch
	var toe := _upper_geo(6, 10)
	var tp: PackedVector3Array = toe.pos
	for i in tp.size():
		var x := tp[i].x
		var t := (x - X0) / LEN
		var nx := X0 + LEN * (0.78 + 0.22 * t) - 0.004
		var hw := half_width(nx) - 0.001
		var h := upper_h(nx) + 0.003
		var z := tp[i].z
		var yy := tp[i].y
		var hw0 := half_width(x) - 0.003
		var h0 := upper_h(x)
		tp[i] = Vector3(nx, 0.02 + (yy - 0.022) / maxf(h0 - 0.022, 1e-3) * (h - 0.02), z / maxf(hw0, 1e-3) * hw)
	toe.pos = tp
	_add(s, toe, m.accent)
	var laces := []
	for i in 4:
		var x := 0.045 + i * 0.022
		laces.append(G.xform(G.box(0.008, 0.005, 0.048), Transform3D(Basis(), Vector3(x, upper_h(x) + 0.001, 0))))
	_add(s, G.merge(laces), m.laces)
	return s


# ---------------- gloved hands ----------------

static func _capsule(radius: float, length: float, m: Material) -> MeshInstance3D:
	var c := CapsuleMesh.new()
	c.radius = radius
	c.height = length + 2 * radius
	c.radial_segments = 10
	c.rings = 4
	var mi := MeshInstance3D.new()
	mi.mesh = c
	mi.material_override = m
	return mi


## m: {glove, knuckle, palm, cuff}; side -1 left, +1 right
static func build_hand(m: Dictionary, side: int) -> Node3D:
	var h := Node3D.new()
	h.name = "Hand"
	var inner := -side
	var fist := _add(h, G.rounded_box(0.095, 0.078, 0.098, 4, 0.03), m.glove)
	fist.position = Vector3(0.008, 0.004, 0)
	var zs := [-0.034, -0.0115, 0.0115, 0.034]
	for k in 4:
		var f := _capsule(0.0155, 0.036, m.glove)
		var edge := k == 0 or k == 3
		var sc := 0.92 if edge else 1.0
		f.transform = Transform3D(Basis(Vector3.BACK, 0.18).scaled_local(Vector3.ONE * sc),
			Vector3(0.05 - (0.004 if edge else 0.0), -0.002 + (0.003 if edge else 0.0), zs[k]))
		h.add_child(f)
	var th := _capsule(0.016, 0.045, m.glove)
	th.transform = Transform3D(Basis(Vector3.BACK, PI / 2 + 0.35), Vector3(0.012, -0.03, inner * 0.04))
	h.add_child(th)
	var pad := _add(h, G.rounded_box(0.06, 0.016, 0.08, 2, 0.007), m.knuckle)
	pad.transform = Transform3D(Basis(Vector3.BACK, -0.15), Vector3(0.012, 0.043, 0))
	var palm := _add(h, G.rounded_box(0.07, 0.014, 0.084, 2, 0.006), m.palm)
	palm.position = Vector3(-0.004, -0.036, 0)
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.052
	cyl.bottom_radius = 0.05
	cyl.height = 0.05
	cyl.radial_segments = 18
	var cuff := MeshInstance3D.new()
	cuff.mesh = cyl
	cuff.material_override = m.cuff
	cuff.transform = Transform3D(Basis(Vector3.BACK, PI / 2), Vector3(-0.058, 0.002, 0))
	h.add_child(cuff)
	return h


# ---------------- torso ----------------
## Unit height (y -0.5 hips .. +0.5 collar), lofted through rounded-rectangle sections.
static func torso_geometry() -> Dictionary:
	var S := [
		[0.00, 0.150, 0.105, -0.005],
		[0.12, 0.148, 0.102, 0.000],
		[0.30, 0.138, 0.098, 0.006],
		[0.50, 0.150, 0.108, 0.010],
		[0.68, 0.172, 0.118, 0.012],
		[0.82, 0.186, 0.114, 0.006],
		[0.92, 0.180, 0.098, -0.004],
		[0.97, 0.140, 0.080, -0.010],
		[1.00, 0.075, 0.060, -0.012],
	]
	var seg := 28
	var rows := 36
	var at := func(t: float) -> Array:
		var i := 0
		while i < S.size() - 2 and S[i + 1][0] < t:
			i += 1
		var a: Array = S[i]
		var b: Array = S[i + 1]
		var u: float = (t - a[0]) / (b[0] - a[0])
		var s := u * u * (3 - 2 * u)
		return [a[1] + (b[1] - a[1]) * s, a[2] + (b[2] - a[2]) * s, a[3] + (b[3] - a[3]) * s]
	var pos := PackedVector3Array()
	var idx := PackedInt32Array()
	var k := 2.0 / 2.6
	for r in rows + 1:
		var t := float(r) / rows
		var wdf: Array = at.call(t)
		for j in seg:
			var a := float(j) / seg * TAU
			var c := cos(a)
			var s := sin(a)
			var x: float = signf(c) * pow(absf(c), k) * wdf[1] + wdf[2]
			var z: float = signf(s) * pow(absf(s), k) * wdf[0]
			pos.append(Vector3(x, t - 0.5, z))
	for r in rows:
		for j in seg:
			var a := r * seg + j
			var b := r * seg + (j + 1) % seg
			var c := a + seg
			var e := b + seg
			idx.append_array([a, c, b, b, c, e])
	for cap in [[0, false], [rows, true]]:
		var r: int = cap[0]
		var ctr := pos.size()
		var wdf: Array = at.call(float(r) / rows)
		pos.append(Vector3(wdf[2], float(r) / rows - 0.5, 0))
		for j in seg:
			var a := r * seg + j
			var b := r * seg + (j + 1) % seg
			if cap[1]:
				idx.append_array([ctr, a, b])
			else:
				idx.append_array([ctr, b, a])
	return {pos = pos, idx = idx}
