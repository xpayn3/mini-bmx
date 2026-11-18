class_name RiderGeo
extends RefCounted
## Geometry helpers for the procedural rider: ports of the three.js geometries rider.js / gear.js use.
## Every builder works in three.js conventions (counter-clockwise front faces, normals the way
## BufferGeometry.computeVertexNormals makes them); mesh_from() converts to Godot's clockwise winding.


## pos + idx (three.js CCW triangles) -> ArrayMesh. Normals: given, or smooth area-weighted (indexed)
## like computeVertexNormals (a non-indexed triangle soup therefore comes out flat).
static func mesh_from(pos: PackedVector3Array, idx: PackedInt32Array, normals := PackedVector3Array(), mesh: ArrayMesh = null) -> ArrayMesh:
	if idx.is_empty():
		idx.resize(pos.size())
		for i in pos.size():
			idx[i] = i
	if normals.size() != pos.size():
		normals = PackedVector3Array()
		normals.resize(pos.size())
		for t in range(0, idx.size(), 3):
			var a := pos[idx[t]]
			var b := pos[idx[t + 1]]
			var c := pos[idx[t + 2]]
			var n := (c - b).cross(a - b)
			normals[idx[t]] += n
			normals[idx[t + 1]] += n
			normals[idx[t + 2]] += n
		for i in normals.size():
			var l := normals[i].length()
			normals[i] = normals[i] / l if l > 1e-12 else Vector3.UP
	var gi := PackedInt32Array()
	gi.resize(idx.size())
	for t in range(0, idx.size(), 3):   # CCW (three) -> CW (Godot)
		gi[t] = idx[t]
		gi[t + 1] = idx[t + 2]
		gi[t + 2] = idx[t + 1]
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = pos
	arr[Mesh.ARRAY_NORMAL] = normals
	arr[Mesh.ARRAY_INDEX] = gi
	if mesh == null:
		mesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return mesh


## Merge several {pos, idx} parts (offsetting indices).
static func merge(parts: Array) -> Dictionary:
	var pos := PackedVector3Array()
	var idx := PackedInt32Array()
	for p in parts:
		var o := pos.size()
		pos.append_array(p.pos)
		for i in p.idx:
			idx.append(i + o)
	return {pos = pos, idx = idx}


static func xform(g: Dictionary, t: Transform3D) -> Dictionary:
	var pos: PackedVector3Array = g.pos.duplicate()
	for i in pos.size():
		pos[i] = t * pos[i]
	var idx: PackedInt32Array = g.idx.duplicate()
	if t.basis.determinant() < 0.0:
		for k in range(0, idx.size(), 3):
			var s := idx[k + 1]
			idx[k + 1] = idx[k + 2]
			idx[k + 2] = s
	return {pos = pos, idx = idx}


## THREE.SphereGeometry(r, ws, hs, phiStart, phiLength, thetaStart, thetaLength)
static func sphere(r: float, ws: int, hs: int, phi0 := 0.0, phi_len := TAU, th0 := 0.0, th_len := PI) -> Dictionary:
	var th_end := minf(th0 + th_len, PI)
	var pos := PackedVector3Array()
	var grid := []
	for iy in hs + 1:
		var row := []
		var v := float(iy) / hs
		for ix in ws + 1:
			var u := float(ix) / ws
			pos.append(Vector3(-r * cos(phi0 + u * phi_len) * sin(th0 + v * th_len),
				r * cos(th0 + v * th_len),
				r * sin(phi0 + u * phi_len) * sin(th0 + v * th_len)))
			row.append(pos.size() - 1)
		grid.append(row)
	var idx := PackedInt32Array()
	for iy in hs:
		for ix in ws:
			var a: int = grid[iy][ix + 1]
			var b: int = grid[iy][ix]
			var c: int = grid[iy + 1][ix]
			var d: int = grid[iy + 1][ix + 1]
			if iy != 0 or th0 > 0.0:
				idx.append_array([a, b, d])
			if iy != hs - 1 or th_end < PI:
				idx.append_array([b, c, d])
	return {pos = pos, idx = idx}


## THREE.TorusGeometry(radius, tube, radialSegments, tubularSegments, arc)
static func torus(radius: float, tube: float, radial: int, tubular: int, arc := TAU) -> Dictionary:
	var pos := PackedVector3Array()
	for j in radial + 1:
		for i in tubular + 1:
			var u := float(i) / tubular * arc
			var v := float(j) / radial * TAU
			pos.append(Vector3((radius + tube * cos(v)) * cos(u), (radius + tube * cos(v)) * sin(u), tube * sin(v)))
	var idx := PackedInt32Array()
	for j in range(1, radial + 1):
		for i in range(1, tubular + 1):
			var a := (tubular + 1) * j + i - 1
			var b := (tubular + 1) * (j - 1) + i - 1
			var c := (tubular + 1) * (j - 1) + i
			var d := (tubular + 1) * j + i
			idx.append_array([a, b, d, b, c, d])
	return {pos = pos, idx = idx}


## THREE.BoxGeometry(w, h, d), 1 segment each way (flat faces)
static func box(w: float, h: float, d: float) -> Dictionary:
	return rounded_box(w, h, d, 0, 0.0)


## Rounded box (like three's RoundedBoxGeometry): a box whose vertices are pushed onto a sphere of
## `radius` round the inner box. segments = steps across each rounded edge.
static func rounded_box(w: float, h: float, d: float, segments: int, radius: float) -> Dictionary:
	var half := Vector3(w, h, d) * 0.5
	radius = minf(radius, minf(half.x, minf(half.y, half.z)))
	var inner := half - Vector3.ONE * radius
	var coords := func(hl: float, il: float) -> PackedFloat32Array:
		var c := PackedFloat32Array()
		if segments <= 0 or radius <= 0.0:
			c.append(-hl)
			c.append(hl)
			return c
		for k in segments + 1:
			c.append(-hl + (hl - il) * float(k) / segments)
		for k in segments + 1:
			c.append(il + (hl - il) * float(k) / segments)
		return c
	var cs := [coords.call(half.x, inner.x), coords.call(half.y, inner.y), coords.call(half.z, inner.z)]
	var pos := PackedVector3Array()
	var nrm := PackedVector3Array()
	var idx := PackedInt32Array()
	for axis in 3:
		for sgn in [-1.0, 1.0]:
			var ua := (axis + 1) % 3
			var va := (axis + 2) % 3
			var cu: PackedFloat32Array = cs[ua]
			var cv: PackedFloat32Array = cs[va]
			var base := pos.size()
			for j in cv.size():
				for i in cu.size():
					var p := Vector3.ZERO
					p[axis] = sgn * half[axis]
					p[ua] = cu[i]
					p[va] = cv[j]
					var c := p.clamp(-inner, inner)
					var n := p - c
					var fn := Vector3.ZERO
					fn[axis] = sgn
					if radius > 0.0 and n.length() > 1e-9:
						n = n.normalized()
						p = c + n * radius
					else:
						n = fn
					pos.append(p)
					nrm.append(n)
			var fnv := Vector3.ZERO
			fnv[axis] = sgn
			for j in cv.size() - 1:
				for i in cu.size() - 1:
					var a := base + j * cu.size() + i
					var b := a + 1
					var c2 := a + cu.size()
					var e := c2 + 1
					# orient so the face looks outward (three CCW)
					var tri1 := [a, b, e]
					var tri2 := [a, e, c2]
					for tri in [tri1, tri2]:
						var gn: Vector3 = (pos[tri[1]] - pos[tri[0]]).cross(pos[tri[2]] - pos[tri[0]])
						if gn.dot(fnv) < 0.0:
							idx.append_array([tri[0], tri[2], tri[1]])
						else:
							idx.append_array(tri)
	return {pos = pos, idx = idx, nrm = nrm}


## Closed prism from a 2D polygon (outer, optional same-length inner = hole) between c0 and c1 along the
## third axis, then mapped through `map(Vector3(a, b, c)) -> Vector3`. Flat triangle soup (three CCW).
## flip: reverse winding (when the map flips handedness).
static func prism(outer: PackedVector2Array, inner: PackedVector2Array, c0: float, c1: float, map: Callable, flip: bool) -> Dictionary:
	if _area(outer) < 0.0:
		outer = _reversed(outer)
		if not inner.is_empty():
			inner = _reversed(inner)
	var tris := PackedVector3Array()
	var add := func(a: Vector3, b: Vector3, c: Vector3, want: Vector3) -> void:
		if (b - a).cross(c - a).dot(want) < 0.0:
			tris.append_array([a, c, b])
		else:
			tris.append_array([a, b, c])
	var n := outer.size()
	if inner.is_empty():
		var tri := Geometry2D.triangulate_polygon(outer)
		for k in range(0, tri.size(), 3):
			for cz in [[c1, 1.0], [c0, -1.0]]:
				add.call(_v3(outer[tri[k]], cz[0]), _v3(outer[tri[k + 1]], cz[0]), _v3(outer[tri[k + 2]], cz[0]), Vector3(0, 0, cz[1]))
	else:
		for i in n:
			var j := (i + 1) % n
			for cz in [[c1, 1.0], [c0, -1.0]]:
				var want := Vector3(0, 0, cz[1])
				add.call(_v3(outer[i], cz[0]), _v3(outer[j], cz[0]), _v3(inner[j], cz[0]), want)
				add.call(_v3(outer[i], cz[0]), _v3(inner[j], cz[0]), _v3(inner[i], cz[0]), want)
	var walls := [[outer, 1.0]]
	if not inner.is_empty():
		walls.append([inner, -1.0])
	for wl in walls:
		var poly: PackedVector2Array = wl[0]
		for i in n:
			var j := (i + 1) % n
			var e := poly[j] - poly[i]
			var want: Vector3 = Vector3(e.y, -e.x, 0.0) * float(wl[1])
			add.call(_v3(poly[i], c0), _v3(poly[j], c0), _v3(poly[j], c1), want)
			add.call(_v3(poly[i], c0), _v3(poly[j], c1), _v3(poly[i], c1), want)
	for i in tris.size():
		tris[i] = map.call(tris[i])
	if flip:
		for k in range(0, tris.size(), 3):
			var s := tris[k + 1]
			tris[k + 1] = tris[k + 2]
			tris[k + 2] = s
	return {pos = tris, idx = PackedInt32Array()}


## Flat single-sided sheet of a polygon at c (facing +c), mapped like prism().
static func sheet(poly: PackedVector2Array, c: float, map: Callable, flip: bool) -> Dictionary:
	var tris := PackedVector3Array()
	var tri := Geometry2D.triangulate_polygon(poly)
	for k in range(0, tri.size(), 3):
		var a := _v3(poly[tri[k]], c)
		var b := _v3(poly[tri[k + 1]], c)
		var cc := _v3(poly[tri[k + 2]], c)
		if (b - a).cross(cc - a).z < 0.0:
			tris.append_array([a, cc, b])
		else:
			tris.append_array([a, b, cc])
	for i in tris.size():
		tris[i] = map.call(tris[i])
	if flip:
		for k in range(0, tris.size(), 3):
			var s := tris[k + 1]
			tris[k + 1] = tris[k + 2]
			tris[k + 2] = s
	return {pos = tris, idx = PackedInt32Array()}


static func _v3(p: Vector2, c: float) -> Vector3:
	return Vector3(p.x, p.y, c)


static func _area(p: PackedVector2Array) -> float:
	var a := 0.0
	for i in p.size():
		var j := (i + 1) % p.size()
		a += p[i].x * p[j].y - p[j].x * p[i].y
	return a * 0.5


static func _reversed(p: PackedVector2Array) -> PackedVector2Array:
	var r := PackedVector2Array()
	for i in range(p.size() - 1, -1, -1):
		r.append(p[i])
	return r


## A MeshInstance3D for a {pos, idx[, nrm]} part.
static func inst(g: Dictionary, m: Material, smooth := true) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var nrm: PackedVector3Array = g.get("nrm", PackedVector3Array())
	var idx: PackedInt32Array = g.idx
	mi.mesh = mesh_from(g.pos, idx, nrm)
	mi.material_override = m
	return mi
