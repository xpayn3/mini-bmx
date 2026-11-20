class_name NeonText
extends RefCounted
## Lettering bent from glass tube, like a real neon sign: a small stroke font (each glyph = centre lines in
## a 1-high box, curves as sampled arcs), every stroke smoothed (glass is bent, not cut) and swept with a
## round tube; where a tube ends it turns back into the sign behind a dark electrode cap.
##
## NeonText.build(text, height, tube_r) -> {mesh: ArrayMesh (the glowing glass), caps: ArrayMesh (the dark
## electrodes), width: float}. Text lies in local XY (baseline y = 0, left x = 0), facing +Z.

const SIDES := 10

static func _arc(cx: float, cy: float, rx: float, ry: float, a0: float, a1: float, n := 0) -> Array:
	var pts := []
	if n <= 0: n = maxi(6, int(absf(a1 - a0) / 12.0))
	for i in n + 1:
		var a := deg_to_rad(lerpf(a0, a1, float(i) / n))
		pts.append(Vector2(cx + cos(a) * rx, cy + sin(a) * ry))
	return pts

static func _p(a: Array) -> Array:   # [x, y] pairs -> Vector2s
	var out := []
	for q in a: out.append(Vector2(q[0], q[1]))
	return out

## glyph -> [advance width, [stroke, ...]] (a stroke is a list of Vector2; a single point = a dot)
static func _glyph(ch: String) -> Array:
	match ch:
		"G": return [0.74, [_arc(0.36, 0.5, 0.36, 0.5, 42, 360) + _p([[0.4, 0.5]])]]
		"N": return [0.7, [_p([[0, 0], [0, 1], [0.66, 0], [0.66, 1]])]]
		"A": return [0.74, [_p([[0, 0], [0.36, 1], [0.72, 0]]), _p([[0.16, 0.38], [0.56, 0.38]])]]
		"R": return [0.7, [_p([[0, 0], [0, 1], [0.4, 1]]) + _arc(0.4, 0.75, 0.25, 0.25, 90, -90) + _p([[0, 0.5]]),
			_p([[0.3, 0.5], [0.66, 0]])]]
		"W": return [0.92, [_p([[0, 1], [0.21, 0], [0.45, 0.66], [0.69, 0], [0.9, 1]])]]
		"H": return [0.7, [_p([[0, 0], [0, 1]]), _p([[0.66, 0], [0.66, 1]]), _p([[0, 0.5], [0.66, 0.5]])]]
		"L": return [0.6, [_p([[0, 1], [0, 0], [0.56, 0]])]]
		"c": return [0.52, [_arc(0.26, 0.28, 0.25, 0.28, 45, 315)]]
		"y": return [0.56, [_p([[0, 0.56], [0.26, 0.04]]), _p([[0.52, 0.56], [0.2, -0.3]]) + _arc(0.08, -0.3, 0.12, 0.1, 0, -150)]]
		"l": return [0.22, [_p([[0.06, 1.0], [0.06, 0.08]]) + _arc(0.16, 0.08, 0.1, 0.08, 180, 300)]]
		"e": return [0.54, [_p([[0.02, 0.28], [0.5, 0.28]]) + _arc(0.26, 0.28, 0.24, 0.28, 0, 320)]]
		"s": return [0.48, [_arc(0.22, 0.42, 0.2, 0.14, 25, 270) + _arc(0.22, 0.14, 0.2, 0.14, 90, -150)]]
		"t": return [0.36, [_p([[0.12, 0.86], [0.12, 0.08]]) + _arc(0.22, 0.08, 0.1, 0.08, 180, 300), _p([[0, 0.56], [0.3, 0.56]])]]
		".": return [0.2, [_p([[0.06, 0.04]])]]
		"·": return [0.3, [_p([[0.12, 0.3]])]]
		"2": return [0.58, [_arc(0.27, 0.72, 0.26, 0.28, 160, -35) + _p([[0, 0], [0.54, 0]])]]
		"0": return [0.56, [_arc(0.27, 0.5, 0.26, 0.5, 90, 450, 36)]]
		"6": return [0.58, [_p([[0.46, 0.92], [0.3, 1.0]]) + _arc(0.3, 0.5, 0.28, 0.5, 90, 180) + _arc(0.28, 0.27, 0.26, 0.27, 180, 540, 30)]]
	return [0.32, []]   # space / unknown

## round the corners off a stroke (Chaikin), as a glassblower bends the tube
static func _smooth(pts: Array, it := 2) -> Array:
	for _k in it:
		if pts.size() < 3: return pts
		var out := [pts[0]]
		for i in pts.size() - 1:
			var a: Vector2 = pts[i]; var b: Vector2 = pts[i + 1]
			out.append(a.lerp(b, 0.25)); out.append(a.lerp(b, 0.75))
		out.append(pts[-1])
		pts = out
	return pts

static func build(text: String, height: float, tube_r: float, track := 0.12) -> Dictionary:
	var glass := SurfaceTool.new(); glass.begin(Mesh.PRIMITIVE_TRIANGLES)
	var caps := SurfaceTool.new(); caps.begin(Mesh.PRIMITIVE_TRIANGLES)
	var x := 0.0
	for ch in text:
		var g := _glyph(ch)
		for stroke in g[1]:
			var pts := []
			for q in stroke: pts.append(Vector3(x + q.x * height, q.y * height, 0.0))
			if pts.size() == 1:
				_ball(glass, pts[0], tube_r * 1.4)
				continue
			var p2 := []
			for p in pts: p2.append(Vector2(p.x, p.y))
			p2 = _smooth(p2)
			var path := []
			for p in p2: path.append(Vector3(p.x, p.y, 0.0))
			_sweep(glass, path, tube_r)
			# the ends turn back into the sign: a short bend, then a dark electrode cap
			for e in [path[0], path[-1]]:
				_ball(glass, e, tube_r)
				_tube_z(caps, e, tube_r * 1.25, -0.045, -0.005)
		x += (g[0] + track) * height
	return {"mesh": glass.commit(), "caps": caps.commit(), "width": x - track * height}

static func _sweep(st: SurfaceTool, path: Array, r: float) -> void:
	var n := path.size()
	var rings := []
	for i in n:
		var t: Vector3 = (path[mini(i + 1, n - 1)] - path[maxi(i - 1, 0)]).normalized()
		var side := t.cross(Vector3.BACK).normalized()
		var ring := []
		for k in SIDES:
			var a := TAU * k / SIDES
			var nrm := side * cos(a) + Vector3.BACK * sin(a)
			ring.append([path[i] + nrm * r, nrm])
		rings.append(ring)
	for i in n - 1:
		for k in SIDES:
			var k2 := (k + 1) % SIDES
			var a: Array = rings[i][k]; var b: Array = rings[i][k2]
			var c: Array = rings[i + 1][k]; var d: Array = rings[i + 1][k2]
			for v in [a, c, b, b, c, d]:
				st.set_normal(v[1]); st.add_vertex(v[0])

static func _ball(st: SurfaceTool, c: Vector3, r: float) -> void:
	var la := 6; var lo := SIDES
	for i in la:
		for j in lo:
			var q := []
			for di in [0, 1]:
				for dj in [0, 1]:
					var th := PI * float(i + di) / la
					var ph := TAU * float(j + dj) / lo
					q.append(Vector3(sin(th) * cos(ph), cos(th), sin(th) * sin(ph)))
			for v in [q[0], q[2], q[1], q[1], q[2], q[3]]:
				st.set_normal(v); st.add_vertex(c + v * r)

static func _tube_z(st: SurfaceTool, c: Vector3, r: float, z0: float, z1: float) -> void:
	for k in SIDES:
		var a0 := TAU * k / SIDES; var a1 := TAU * (k + 1) / SIDES
		var n0 := Vector3(cos(a0), sin(a0), 0); var n1 := Vector3(cos(a1), sin(a1), 0)
		var v := [[c + n0 * r + Vector3(0, 0, z0), n0], [c + n1 * r + Vector3(0, 0, z0), n1],
			[c + n0 * r + Vector3(0, 0, z1), n0], [c + n1 * r + Vector3(0, 0, z1), n1]]
		for w in [v[0], v[1], v[2], v[2], v[1], v[3]]:
			st.set_normal(w[1]); st.add_vertex(w[0])
