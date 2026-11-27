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
	var model: Mesh = m.get("model_mesh")
	if model:   # the ski-goggle model in place of the built frame / foam / lens (fit: SKI_FIT)
		var gm := MeshInstance3D.new()
		gm.name = "SkiGoggle"
		gm.mesh = model
		gm.material_override = m.model_mat
		var sk: float = fit.get("model_scale", 0.0082)
		var front: Vector3 = fit.get("model_front", Vector3(0.0, 3.8, 0.34))   # model point that goes to g's origin
		# model: +z forward, +x to its right -> head: +X forward (turned a quarter round Y)
		gm.basis = Basis(Vector3.UP, PI * 0.5).scaled(Vector3.ONE * sk)
		gm.position = -(gm.basis * front) + Vector3(fit.get("model_dx", 0.0), 0, 0)
		g.add_child(gm)
	else:
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
		o.visible = model == null   # (the model has its own side pieces: only the strap's attach point is used)
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
	_add_strap_edges(root, pts, S.cx, hw)
	if m.has("logo"):
		_add_strap_logo(root, pts, S.cx, hw, m.logo)
	# where the loose flapping tail hangs off the strap (outer side of the right clip, goggles-root space)
	root.set_meta("flap_anchor", Vector3(ends[1].x - 0.004, yS, ends[1].z + 0.014))
	return root


static var _edge_mat: StandardMaterial3D

## a thin white line along the top and bottom edge of the strap's outside, the whole way round (like a real
## goggle strap's woven border): two narrow ribbons 1 mm off the strap
static func _add_strap_edges(root: Node3D, pts: PackedVector3Array, cx: float, hw: float) -> void:
	if _edge_mat == null:
		_edge_mat = StandardMaterial3D.new()
		_edge_mat.albedo_color = Color(0.96, 0.96, 0.94)
		_edge_mat.roughness = 0.7
		_edge_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var lw := 0.0024                 # line width
	var inset := 0.0018              # from the strap's edge
	var v3 := PackedVector3Array()
	var nr := PackedVector3Array()
	var idx := PackedInt32Array()
	for side in [-1.0, 1.0]:
		var yc: float = side * (hw - inset - lw * 0.5)
		var base := v3.size()
		for i in pts.size():
			var p := pts[i]
			var out := Vector3(p.x - cx, 0, p.z).normalized()
			var q := p + out * 0.0012
			v3.append(Vector3(q.x, q.y + yc - lw * 0.5, q.z))
			v3.append(Vector3(q.x, q.y + yc + lw * 0.5, q.z))
			nr.append(out); nr.append(out)
			if i > 0:
				var k := base + i * 2
				idx.append_array([k - 2, k - 1, k, k - 1, k + 1, k])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = v3
	arr[Mesh.ARRAY_NORMAL] = nr
	arr[Mesh.ARRAY_INDEX] = idx
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	var mi := MeshInstance3D.new()
	mi.name = "StrapEdges"
	mi.mesh = am
	mi.material_override = _edge_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)


## a brand wordmark printed along the middle of the strap's back: a thin overlay ribbon floating 2 mm off the
## strap, UV running along the strap (left to right seen from behind) and across it
static func _add_strap_logo(root: Node3D, pts: PackedVector3Array, cx: float, hw: float, mat: Material, length := 0.27) -> void:
	var s := PackedFloat32Array()
	s.resize(pts.size())
	for i in range(1, pts.size()):
		s[i] = s[i - 1] + pts[i].distance_to(pts[i - 1])
	var mid := s[pts.size() - 1] * 0.5
	var v3 := PackedVector3Array()
	var uv := PackedVector2Array()
	var nr := PackedVector3Array()
	var idx := PackedInt32Array()
	for i in pts.size():
		if absf(s[i] - mid) > length * 0.5:
			continue
		var p := pts[i]
		var out := Vector3(p.x - cx, 0, p.z).normalized()
		var u := (s[i] - (mid - length * 0.5)) / length
		var q := p + out * 0.0022
		v3.append(Vector3(q.x, q.y - hw * 0.92, q.z))
		uv.append(Vector2(u, 1.0))
		v3.append(Vector3(q.x, q.y + hw * 0.92, q.z))
		uv.append(Vector2(u, 0.0))
		nr.append(out)
		nr.append(out)
		var k := v3.size() - 2
		if k >= 2:
			idx.append_array([k - 2, k - 1, k, k - 1, k + 1, k])
	if idx.is_empty():
		return
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = v3
	arr[Mesh.ARRAY_NORMAL] = nr
	arr[Mesh.ARRAY_TEX_UV] = uv
	arr[Mesh.ARRAY_INDEX] = idx
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	var mi := MeshInstance3D.new()
	mi.name = "StrapLogo"
	mi.mesh = am
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)


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
		# the fan only covers the arch: close the bottom too (centre to the two sole corners) - the heel
		# had a triangular hole you could see the trouser leg through
		var k0 := ci * row
		var km := ci * row + m
		if cap[1]:
			idx.append_array([c, km, k0])
		else:
			idx.append_array([c, k0, km])
	return {pos = pos, idx = idx}


# ---------------- shoe v2 (2026-11-27, user: "a better shoe, not a low poly chunk") ----------------
## a flat-pedal shoe: thick gum outsole with a raised rim and a little toe spring, white midsole stripe, a boxy rounded
## upper (superellipse sections), rubber toe bumper + heel counter in the accent colour, a padded collar round the ankle
## point (shoe (-0.04, 0.09): the shin always ends inside it), tongue, crossed laces. Same frame as the old one (+X toe,
## sole bottom y 0, x X0..X1). BMX_OLD_SHOE=1 = the old shoe
static var _OLD_SHOE := OS.get_environment("BMX_OLD_SHOE") != ""

## v2 plan outline: slim road-shoe last, narrow heel, pointed toe
static func _hw2(x: float) -> float:
	var t := clampf((x - X0) / LEN, 0.0, 1.0)
	var base := 0.043 + 0.009 * sin(minf(1.0, t / 0.66) * PI * 0.5)
	var toe := pow(maxf(0.0, 1.0 - pow((t - 0.66) / 0.34, 2.0)), 0.62) if t > 0.66 else 1.0
	var heel := sqrt(maxf(0.0, 1.0 - pow((0.1 - t) / 0.1, 2))) if t < 0.1 else 1.0
	return base * minf(toe, heel) + 0.0015

## toe spring: the sole's bottom rises toward the toe tip (past the ball: the pedal sits at x ~0.08)
static func _spring(x: float) -> float:
	var t := clampf((x - 0.12) / (X1 - 0.12), 0.0, 1.0)
	return 0.02 * t * t

## the upper's top line v2: low rounded toe box, the instep rising to the collar, a high padded heel
## the top line (user's sketch, 2026-11-27): a high heel tab, a slight dip behind the ankle, a peak just in front of the
## opening, then one long smooth curve over the instep down to the toe tip. Catmull-Rom through (t along the last, m)
const TOP2 := [[-0.1, 0.104], [0.0, 0.106], [0.14, 0.099], [0.24, 0.097], [0.35, 0.102], [0.48, 0.091], [0.6, 0.078],
	[0.72, 0.064], [0.84, 0.05], [0.93, 0.037], [1.0, 0.02], [1.1, 0.0]]
static func _top2(x: float) -> float:
	var t := clampf((x - X0) / LEN, 0.0, 1.0)
	var i := 1
	while i < TOP2.size() - 3 and float(TOP2[i + 1][0]) < t: i += 1
	var p0: Array = TOP2[i - 1]; var p1: Array = TOP2[i]; var p2: Array = TOP2[i + 1]; var p3: Array = TOP2[i + 2]
	var u := clampf((t - float(p1[0])) / (float(p2[0]) - float(p1[0])), 0.0, 1.0)
	var u2 := u * u
	var u3 := u2 * u
	return 0.5 * (2.0 * p1[1] + (-p0[1] + p2[1]) * u + (2.0 * p0[1] - 5.0 * p1[1] + 4.0 * p2[1] - p3[1]) * u2 		+ (-p0[1] + 3.0 * p1[1] - 3.0 * p2[1] + p3[1]) * u3)

## a lofted shell from xa to xb: sections with bottom yb(x), top ht(x) * frac, half width hw(x) - inset, superellipse
## exponents (ey up the side, ez across); closed at both ends with a fan
static func _loft2(xa: float, xb: float, n: int, m: int, inset: float, frac: float, y_base: float, ey := 0.5, ez := 0.7, frac_b := -1.0, caps := true) -> Dictionary:
	var pos := PackedVector3Array()
	var idx := PackedInt32Array()
	for i in n + 1:
		var tt := float(i) / n
		# sections packed toward both ends (cosine spacing): the round heel and toe in plan need them, evenly every 7 mm
		# the heel came out as a vertical crease
		var x := xa + (xb - xa) * (0.5 - 0.5 * cos(PI * tt))
		var hw := maxf(0.0015, _hw2(x) - inset)
		var y0 := y_base + _spring(x)
		var fr := frac if frac_b < 0.0 else lerpf(frac, frac_b, smoothstep(0.0, 1.0, tt))
		var h := y0 + (_top2(x) + _spring(x) * 0.6 - y0) * fr + inset * 0.3
		# the back third is boxier (walls straight up, a flat top): the ankle opening, the shin stays inside it
		var bx := 1.0 - smoothstep(0.24, 0.44, (x - X0) / LEN)
		var eyx := lerpf(ey, 0.2, bx)
		var ezx := lerpf(ez, 0.95, bx)
		for j in m + 1:
			var a := PI * float(j) / m
			var ca := cos(a)
			var z := signf(ca) * pow(absf(ca), ezx) * hw
			pos.append(Vector3(x, y0 + pow(sin(a), eyx) * (h - y0), z))
	var row := m + 1
	for i in n:
		for j in m:
			var k := i * row + j
			idx.append_array([k, k + row, k + 1, k + 1, k + row, k + row + 1])
	for cap in ([[0, false], [n, true]] if caps else []):
		var ci: int = cap[0]
		var c := pos.size()
		var cx := pos[ci * row].x
		pos.append(Vector3(cx, pos[ci * row].y + (pos[ci * row + m / 2].y - pos[ci * row].y) * 0.5, 0))
		for j in m:
			var k := ci * row + j
			if cap[1]: idx.append_array([c, k, k + 1])
			else: idx.append_array([c, k + 1, k])
		var k0 := ci * row
		var km := ci * row + m
		if cap[1]: idx.append_array([c, km, k0])
		else: idx.append_array([c, k0, km])
	return {pos = pos, idx = idx}

## the outsole: the outline (half_width) extruded from y0 to y1 with the toe spring, edges rounded by a ring of bevel rows
static func _sole2(inset: float, y0: float, y1: float, n := 48) -> Dictionary:
	var pos := PackedVector3Array()
	var idx := PackedInt32Array()
	var loop := []
	for i in n + 1:
		var x := X0 + LEN * (float(i) / n)
		loop.append(Vector2(x, _hw2(x) - inset))
	for i in range(n - 1, 0, -1):
		loop.append(Vector2((loop[i] as Vector2).x, -(loop[i] as Vector2).y))
	var L := loop.size()
	# rows: bottom (pulled in 2 mm), bottom edge, top edge, top (pulled in 1.5 mm)
	var rows := [[y0, -0.002], [y0 + 0.003, 0.0], [y1 - 0.002, 0.0], [y1, -0.0015]]
	for r in rows:
		for q in loop:
			var v: Vector2 = q
			var sz := signf(v.y) if absf(v.y) > 1e-5 else 1.0
			var inn: float = r[1]
			pos.append(Vector3(v.x + (inn if v.x < 0.0 else -inn) * 0.3, float(r[0]) + _spring(v.x), v.y + sz * inn))
	for r in 3:
		for k in L:
			var a := r * L + k
			var b2 := r * L + (k + 1) % L
			idx.append_array([a, a + L, b2, b2, a + L, b2 + L])
	# bottom and top caps: fans from the middle line
	for cap in [[0, true], [3, false]]:
		var base: int = cap[0] * L
		var c := pos.size()
		pos.append(Vector3((X0 + X1) * 0.5, pos[base].y, 0.0))
		for k in L:
			var a2 := base + k
			var b3 := base + (k + 1) % L
			if cap[1]: idx.append_array([c, b3, a2])
			else: idx.append_array([c, a2, b3])
	return {pos = pos, idx = idx}

static func _build_shoe2(m: Dictionary, side := 1.0) -> Node3D:
	var s := Node3D.new()
	s.name = "Shoe"
	_add(s, _sole2(0.0, 0.0, 0.011), m.sole)
	_add(s, _sole2(0.001, 0.0105, 0.016), m.mid)
	_add(s, _loft2(X0 + 0.0015, X1 - 0.002, 36, 20, 0.003, 1.0, 0.015), m.upper)
	# rubber toe bumper: an open shell over the front, low at its back edge rising round the toe, a touch proud
	_add(s, _loft2(X0 + LEN * 0.72, X1 + 0.0015, 14, 20, -0.0012, 0.12, 0.014, 0.5, 0.7, 0.5, false), m.accent)
	# heel counter: an open shell round the heel, high at the back sweeping down toward the arch
	_add(s, _loft2(X0 - 0.0025, X0 + LEN * 0.34, 18, 20, -0.0012, 0.85, 0.014, 0.5, 0.7, 0.12, true), m.accent)
	# two BOA dials on the outer side of the instep (side = which foot: +1 right, -1 left, so they sit outside), each
	# with a thin cable over the top to a guide on the inner side
	var bits := []
	var cab := []
	for dx in [0.03, 0.082]:
		var hw := _hw2(dx) - 0.003
		var zo: float = side * hw * 0.78
		var dp := _upper_pt(dx, zo, 0.0)
		var y0 := 0.015 + _spring(dx)
		var nrm := Vector3(0.0, (dp.y - y0) / maxf(_top2(dx) - y0, 1e-3) * 0.6, zo / maxf(hw, 1e-3)).normalized()
		var bas := Basis(Quaternion(Vector3.UP, nrm))
		var dm := MeshInstance3D.new()
		var cy := CylinderMesh.new()
		cy.top_radius = 0.0135; cy.bottom_radius = 0.0145; cy.height = 0.008; cy.radial_segments = 18; cy.rings = 1
		dm.mesh = cy
		dm.material_override = m.sole
		dm.transform = Transform3D(bas, dp + nrm * 0.004)
		s.add_child(dm)
		var cp := MeshInstance3D.new()
		var cc := CylinderMesh.new()
		cc.top_radius = 0.009; cc.bottom_radius = 0.0105; cc.height = 0.003; cc.radial_segments = 18; cc.rings = 1
		cp.mesh = cc
		cp.material_override = m.accent
		cp.transform = Transform3D(bas, dp + nrm * 0.009)
		s.add_child(cp)
		# cable: dial -> over the top -> a guide on the inner side, and back a little further forward
		var g_in := Vector2(dx + 0.012, -side * (_hw2(dx + 0.012) - 0.003) * 0.7)
		bits.append(G.xform(G.rounded_box(0.012, 0.004, 0.009, 1, 0.002), Transform3D(Basis(), _upper_pt(g_in.x, g_in.y, 0.002))))
		cab.append_array(_cable(Vector2(dx - 0.004, zo * 0.8), g_in))
		cab.append_array(_cable(g_in, Vector2(dx + 0.006, zo * 0.8)))
	_add(s, G.merge(bits), m.sole)
	_add(s, G.merge(cab), m.laces)
	return s

## a point on the v2 upper's surface at (x, z), lifted off it by `lift`
static func _upper_pt(x: float, z: float, lift: float) -> Vector3:
	var hw := maxf(0.0015, _hw2(x) - 0.003)
	var y0 := 0.015 + _spring(x)
	var h := y0 + (_top2(x) + _spring(x) * 0.6 - y0)
	var c := pow(clampf(absf(z) / hw, 0.0, 1.0), 1.0 / 0.7)
	var sn := sqrt(maxf(0.0, 1.0 - c * c))
	return Vector3(x, y0 + pow(sn, 0.5) * (h - y0) + lift, z)

## a BOA cable from (x, z) a to b over the upper's curve: short rods between points on its surface
static func _cable(a: Vector2, b: Vector2) -> Array:
	var out := []
	var n := 6
	var p0 := _upper_pt(a.x, a.y, 0.0022)
	for k in range(1, n + 1):
		var q := a.lerp(b, float(k) / n)
		var p1 := _upper_pt(q.x, q.y, 0.0022)
		out.append(_rod(p0, p1, 0.0014))
		p0 = p1
	return out

## a thin round rod from a to b (a box would do at 1 mm, but a rod catches the light)
static func _rod(a: Vector3, b: Vector3, r: float) -> Dictionary:
	var d := b - a
	var l := d.length()
	var g := G.rounded_box(r * 2.0, l, r * 2.0, 1, r * 0.9)
	var bas := Basis(Quaternion(Vector3.UP, d / maxf(l, 1e-5)))
	return G.xform(g, Transform3D(bas, (a + b) * 0.5))


## m: {upper, accent, sole, mid, laces}
static func build_shoe(m: Dictionary, side := 1.0) -> Node3D:
	if not _OLD_SHOE: return _build_shoe2(m, side)
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


## The back of the gloved hand: palm block from the wrist to the knuckles, knuckle guard, cuff. The fingers are a
## skinned mesh on the skeleton's finger bones (GloveFingers), posed in this node's space.
## m: {glove, knuckle, palm, cuff}; side -1 left, +1 right
static func build_hand(m: Dictionary, side: int) -> Node3D:
	var h := Node3D.new()
	h.name = "Hand"
	var inner := -side
	# the palm rises from the wrist (on the forearm's line) to sit on top of the grip at the knuckles
	var tilt := Basis(Vector3.BACK, 0.30)
	var palm_blk := _add(h, G.rounded_box(0.098, 0.038, 0.094, 1, 0.010), m.glove)
	palm_blk.transform = Transform3D(tilt, Vector3(-0.026, 0.023, 0))
	# the heel of the thumb (the thenar pad) bulging on the inside
	var heel := _add(h, G.rounded_box(0.05, 0.03, 0.026, 1, 0.009), m.glove)
	heel.transform = Transform3D(Basis(Vector3.UP, inner * 0.35) * tilt, Vector3(-0.040, 0.010, inner * 0.030))
	# knuckle guard: a moulded strip across the knuckles
	var pad := _add(h, G.rounded_box(0.022, 0.010, 0.078, 1, 0.004), m.knuckle)
	pad.transform = Transform3D(Basis(Vector3.BACK, 0.6), Vector3(0.014, 0.046, 0))
	var palm := _add(h, G.rounded_box(0.06, 0.008, 0.07, 1, 0.003), m.palm)
	palm.transform = Transform3D(tilt, Vector3(-0.032, 0.002, 0))
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.054   # an octagon round the forearm tube's end (0.04-0.047): clear of it, no z-fighting
	cyl.bottom_radius = 0.052
	cyl.height = 0.05
	cyl.radial_segments = 8
	cyl.rings = 1
	var cuff := MeshInstance3D.new()
	cuff.mesh = cyl
	cuff.material_override = m.cuff
	cuff.transform = Transform3D(Basis(Vector3.BACK, PI / 2), Vector3(-0.078, 0.004, 0))
	h.add_child(cuff)
	return h


# ---------------- torso ----------------
## Unit height (y -0.5 hips .. +0.5 collar), lofted through rounded-rectangle sections.
## sections: [t, half-width (z), half-depth (x), x offset]
const TORSO_S := [
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


## the torso section at t (0 hips .. 1 collar): [half-width, half-depth, x offset]
static func torso_profile(t: float) -> Array:
	var S := TORSO_S
	var i := 0
	while i < S.size() - 2 and S[i + 1][0] < t:
		i += 1
	var a: Array = S[i]
	var b: Array = S[i + 1]
	var u: float = (t - a[0]) / (b[0] - a[0])
	var s := u * u * (3 - 2 * u)
	return [a[1] + (b[1] - a[1]) * s, a[2] + (b[2] - a[2]) * s, a[3] + (b[3] - a[3]) * s]


## how far behind the torso axis (mesh -x) the back surface is, at height t and sideways offset z
static func torso_back_x(t: float, z: float) -> float:
	var p := torso_profile(t)
	var k := 2.0 / 2.6
	var s := clampf(absf(z) / p[0], 0.0, 0.999)
	var sa := pow(s, 1.0 / k)
	var c := sqrt(1.0 - sa * sa)
	return pow(c, k) * p[1] - p[2]


static func torso_geometry() -> Dictionary:
	var seg := 28
	var rows := 36
	var at := torso_profile
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
			# wound to face OUT (top cap up, bottom down): the top one used to face in, was culled and left a
			# hole round the neck you could see into the torso through
			if cap[1]:
				idx.append_array([ctr, b, a])
			else:
				idx.append_array([ctr, a, b])
	return {pos = pos, idx = idx}
