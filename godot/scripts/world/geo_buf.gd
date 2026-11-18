class_name GeoBuf
extends RefCounted
## Tiny triangle-soup builder mirroring the three.js geometry calls the JS uses
## (CCW front faces like three.js; to_mesh() flips them to Godot's clockwise order).

var pos := PackedVector3Array()
var col := PackedColorArray()
var tint := PackedFloat32Array()


static func of(p: PackedVector3Array) -> GeoBuf:
	var g := GeoBuf.new()
	g.pos = p
	g.col.resize(p.size())
	g.col.fill(Color(1, 1, 1))
	g.tint.resize(p.size())
	return g


func copy() -> GeoBuf:
	var g := GeoBuf.new()
	g.pos = pos.duplicate(); g.col = col.duplicate(); g.tint = tint.duplicate()
	return g


func xform(b: Basis, o: Vector3 = Vector3.ZERO) -> GeoBuf:
	for i in pos.size():
		pos[i] = b * pos[i] + o
	return self


func translate(x: float, y: float, z: float) -> GeoBuf:
	var o := Vector3(x, y, z)
	for i in pos.size():
		pos[i] += o
	return self


func scale(x: float, y: float, z: float) -> GeoBuf:
	var s := Vector3(x, y, z)
	for i in pos.size():
		pos[i] *= s
	return self


func rot_x(a: float) -> GeoBuf:
	return xform(Basis(Vector3.RIGHT, a))


func rot_y(a: float) -> GeoBuf:
	return xform(Basis(Vector3.UP, a))


func rot_z(a: float) -> GeoBuf:
	return xform(Basis(Vector3.BACK, a))


func paint(c: Color, t: float = 0.0) -> GeoBuf:
	col.fill(c)
	tint.fill(t)
	return self


func append(g: GeoBuf) -> GeoBuf:
	pos.append_array(g.pos); col.append_array(g.col); tint.append_array(g.tint)
	return self


static func merge(list: Array) -> GeoBuf:
	var g := GeoBuf.new()
	for p in list:
		g.append(p)
	return g


func center() -> GeoBuf:
	var a := AABB(pos[0], Vector3.ZERO)
	for p in pos:
		a = a.expand(p)
	var c := a.get_center()
	return translate(-c.x, -c.y, -c.z)


func face_normals() -> PackedVector3Array:
	var nr := PackedVector3Array()
	nr.resize(pos.size())
	for i in range(0, pos.size(), 3):
		var n := (pos[i + 1] - pos[i]).cross(pos[i + 2] - pos[i])
		n = n.normalized() if n.length_squared() > 1e-20 else Vector3.UP
		nr[i] = n; nr[i + 1] = n; nr[i + 2] = n
	return nr


## smooth normals: area-weighted face normals summed over vertices that share a position
func smooth_normals() -> PackedVector3Array:
	var acc := {}
	var keys := []
	keys.resize(pos.size())
	for i in range(0, pos.size(), 3):
		var n := (pos[i + 1] - pos[i]).cross(pos[i + 2] - pos[i])
		for k in 3:
			var p := pos[i + k]
			var key := Vector3i(roundi(p.x * 10000), roundi(p.y * 10000), roundi(p.z * 10000))
			keys[i + k] = key
			acc[key] = acc.get(key, Vector3.ZERO) + n
	var nr := PackedVector3Array()
	nr.resize(pos.size())
	for i in pos.size():
		var v: Vector3 = acc[keys[i]]
		nr[i] = v.normalized() if v.length_squared() > 1e-20 else Vector3.UP
	return nr


func to_mesh(smooth: bool = false, normals: PackedVector3Array = PackedVector3Array()) -> ArrayMesh:
	var nr := normals
	if nr.is_empty():
		nr = smooth_normals() if smooth else face_normals()
	# CCW (three.js) -> CW (Godot): swap the 2nd and 3rd vertex of every triangle
	var p := pos.duplicate()
	var c := col.duplicate()
	var t := tint
	var uv := PackedVector2Array()
	uv.resize(p.size())
	for i in range(0, p.size(), 3):
		var tmp := p[i + 1]; p[i + 1] = p[i + 2]; p[i + 2] = tmp
		var tn := nr[i + 1]; nr[i + 1] = nr[i + 2]; nr[i + 2] = tn
		var tc := c[i + 1]; c[i + 1] = c[i + 2]; c[i + 2] = tc
		uv[i] = Vector2(t[i], 0); uv[i + 1] = Vector2(t[i + 2], 0); uv[i + 2] = Vector2(t[i + 1], 0)
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = p
	arr[Mesh.ARRAY_NORMAL] = nr
	arr[Mesh.ARRAY_COLOR] = c
	arr[Mesh.ARRAY_TEX_UV] = uv
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m


# ---------------- primitives (three.js conventions) ----------------
static func _tri_list(verts: Array, idx: Array) -> PackedVector3Array:
	var p := PackedVector3Array()
	for i in idx:
		p.append(verts[i])
	return p


static func cylinder(rt: float, rb: float, h: float, seg: int, hseg: int = 1) -> GeoBuf:
	var grid := []
	for iy in hseg + 1:
		var v := float(iy) / hseg
		var r := v * (rb - rt) + rt
		var row := []
		for ix in seg + 1:
			var th := float(ix) / seg * TAU
			row.append(Vector3(r * sin(th), -v * h + h / 2, r * cos(th)))
		grid.append(row)
	var p := PackedVector3Array()
	for ix in seg:
		for iy in hseg:
			var a: Vector3 = grid[iy][ix]
			var b: Vector3 = grid[iy + 1][ix]
			var c: Vector3 = grid[iy + 1][ix + 1]
			var d: Vector3 = grid[iy][ix + 1]
			if rt > 0 or iy != 0:
				p.append(a); p.append(b); p.append(d)
			if rb > 0 or iy != hseg - 1:
				p.append(b); p.append(c); p.append(d)
	for top in [true, false]:
		var r := rt if top else rb
		if r <= 0:
			continue
		var sgn := 1.0 if top else -1.0
		var cen := Vector3(0, h / 2 * sgn, 0)
		for ix in seg:
			var t0 := float(ix) / seg * TAU
			var t1 := float(ix + 1) / seg * TAU
			var v0 := Vector3(r * sin(t0), h / 2 * sgn, r * cos(t0))
			var v1 := Vector3(r * sin(t1), h / 2 * sgn, r * cos(t1))
			if top:
				p.append(v0); p.append(v1); p.append(cen)
			else:
				p.append(v1); p.append(v0); p.append(cen)
	return of(p)


static func cone(r: float, h: float, seg: int) -> GeoBuf:
	return cylinder(0.0, r, h, seg)


static func box(w: float, h: float, d: float) -> GeoBuf:
	var x := w / 2; var y := h / 2; var z := d / 2
	var v := [Vector3(-x, -y, -z), Vector3(x, -y, -z), Vector3(x, y, -z), Vector3(-x, y, -z),
		Vector3(-x, -y, z), Vector3(x, -y, z), Vector3(x, y, z), Vector3(-x, y, z)]
	# CCW seen from outside
	var idx := [4, 5, 6, 4, 6, 7,   1, 0, 3, 1, 3, 2,   5, 1, 2, 5, 2, 6,   0, 4, 7, 0, 7, 3,   7, 6, 2, 7, 2, 3,   0, 1, 5, 0, 5, 4]
	return of(_tri_list(v, idx))


static func _subdivide(verts: Array, idx: Array, detail: int, radius: float) -> GeoBuf:
	var p := PackedVector3Array()
	var cols := detail + 1
	for f in range(0, idx.size(), 3):
		var a: Vector3 = verts[idx[f]]
		var b: Vector3 = verts[idx[f + 1]]
		var c: Vector3 = verts[idx[f + 2]]
		var vv := []
		for i in cols + 1:
			var aj := a.lerp(c, float(i) / cols)
			var bj := b.lerp(c, float(i) / cols)
			var rows := cols - i
			var row := []
			for j in rows + 1:
				row.append(aj if (j == 0 and rows == 0) else aj.lerp(bj, float(j) / maxi(rows, 1)))
			vv.append(row)
		for i in cols:
			for j in 2 * (cols - i) - 1:
				var k := j / 2
				if j % 2 == 0:
					p.append(vv[i][k + 1]); p.append(vv[i + 1][k]); p.append(vv[i][k])
				else:
					p.append(vv[i][k + 1]); p.append(vv[i + 1][k + 1]); p.append(vv[i + 1][k])
	for i in p.size():
		p[i] = p[i].normalized() * radius
	return of(p)


static func ico(radius: float, detail: int) -> GeoBuf:
	var t := (1.0 + sqrt(5.0)) / 2.0
	var v := [Vector3(-1, t, 0), Vector3(1, t, 0), Vector3(-1, -t, 0), Vector3(1, -t, 0), Vector3(0, -1, t), Vector3(0, 1, t),
		Vector3(0, -1, -t), Vector3(0, 1, -t), Vector3(t, 0, -1), Vector3(t, 0, 1), Vector3(-t, 0, -1), Vector3(-t, 0, 1)]
	var idx := [0, 11, 5, 0, 5, 1, 0, 1, 7, 0, 7, 10, 0, 10, 11, 1, 5, 9, 5, 11, 4, 11, 10, 2, 10, 7, 6, 7, 1, 8,
		3, 9, 4, 3, 4, 2, 3, 2, 6, 3, 6, 8, 3, 8, 9, 4, 9, 5, 2, 4, 11, 6, 2, 10, 8, 6, 7, 9, 8, 1]
	return _subdivide(v, idx, detail, radius)


static func octa(radius: float) -> GeoBuf:
	var v := [Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 1, 0), Vector3(0, -1, 0), Vector3(0, 0, 1), Vector3(0, 0, -1)]
	var idx := [0, 2, 4, 0, 4, 3, 0, 3, 5, 0, 5, 2, 1, 2, 5, 1, 5, 3, 1, 3, 4, 1, 4, 2]
	return _subdivide(v, idx, 0, radius)


static func sphere(r: float, ws: int, hs: int, phi0: float, phil: float, th0: float, thl: float) -> GeoBuf:
	var grid := []
	for iy in hs + 1:
		var v := float(iy) / hs
		var row := []
		for ix in ws + 1:
			var u := float(ix) / ws
			row.append(Vector3(-r * cos(phi0 + u * phil) * sin(th0 + v * thl), r * cos(th0 + v * thl), r * sin(phi0 + u * phil) * sin(th0 + v * thl)))
		grid.append(row)
	var p := PackedVector3Array()
	var th_end := minf(th0 + thl, PI)
	for iy in hs:
		for ix in ws:
			var a: Vector3 = grid[iy][ix + 1]
			var b: Vector3 = grid[iy][ix]
			var c: Vector3 = grid[iy + 1][ix]
			var d: Vector3 = grid[iy + 1][ix + 1]
			if iy != 0 or th0 > 0:
				p.append(a); p.append(b); p.append(d)
			if iy != hs - 1 or th_end < PI:
				p.append(b); p.append(c); p.append(d)
	return of(p)


## closed prism: triangle pts in the (a, y) plane swept along +z from `from` to `to` (axis z), or (axis x) a -> z, sweep -> -x
static func prism(pts: Array, from: float, to: float, axis: String) -> GeoBuf:
	var p := PackedVector3Array()
	var a: Vector2 = pts[0]
	var b: Vector2 = pts[1]
	var c: Vector2 = pts[2]
	# make the outline CCW in (a, y)
	if (b - a).cross(c - a) < 0:
		var t := b; b = c; c = t
	var P := func(v: Vector2, zz: float) -> Vector3: return Vector3(v.x, v.y, zz)
	# back cap (z = from) faces -z, front cap faces +z
	p.append(P.call(a, to)); p.append(P.call(b, to)); p.append(P.call(c, to))
	p.append(P.call(a, from)); p.append(P.call(c, from)); p.append(P.call(b, from))
	var ring := [a, b, c, a]
	for i in 3:
		var u: Vector2 = ring[i]
		var w: Vector2 = ring[i + 1]
		p.append(P.call(u, from)); p.append(P.call(w, from)); p.append(P.call(w, to))
		p.append(P.call(u, from)); p.append(P.call(w, to)); p.append(P.call(u, to))
	var g := of(p)
	if axis == "x":
		g.rot_y(-PI / 2)
	return g
