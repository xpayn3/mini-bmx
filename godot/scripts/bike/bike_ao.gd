class_name BikeAO
extends RefCounted
## Baked ambient occlusion for the bike: crevices, tube joins, the shock inside the frame, the hub under the
## spokes go darker, so the bike doesn't look flat / washed out in open light. Baked per vertex once a bike is
## built (C# AoBake, close range only) into the vertex colour; the materials multiply it into their albedo
## (BaseMaterial3D: vertex_color_use_as_albedo on a copy; the car paint + rotor shaders read COLOR). Free while
## riding. Three groups baked apart, as they move against each other: the front wheel, the rear wheel, the rest.
## Results are cached by mesh content in memory and on disk (user://cache/ao), so a garage click or the next
## launch only bakes what's new. BMX_NO_AO=1 = off, BMX_AO_PROBE=1 prints timings.

const RADIUS := 0.05      # m: how far a surface shades another (crevices, joins; not whole-bike shading)
const MAX_EDGE := 0.02   # m: longer edges are split before the bake
const CELL := 0.008       # m: the surface is merged into discs this big
const STRENGTH := 1.0     # 1 = a fully covered vertex goes black
const CACHE_DIR := "user://cache/ao"
const VER := 5            # bump when the bake changes
## Sharp convex edges (AoBake.Edges) baked beside the AO, into the vertex colour's alpha as 1 - edge (so a mesh
## without it reads "no edge"): the car paint shader rounds them off (a bevel catch-light).
## Curvature in 1 / m over EDGE_R: EDGE_K0 = none (tubes of ~2.5 cm radius and up), EDGE_K1 = full.
const EDGE_R := 0.012
const EDGE_K0 := 45.0
const EDGE_K1 := 160.0

static var _mem := {}     # content hash -> PackedFloat32Array
static var _mats := {}    # material instance id -> its AO copy
static var _cs: Object = null


static func available() -> bool:
	if Env.s("BMX_NO_AO") != "": return false
	if _cs == null: _cs = CrashLog.cs_new("res://scripts/bike/AoBake.cs")
	return _cs != null


## bakes + applies AO to every mesh under model (call before decals / camera / lights are added: those stay as they are)
static func apply(model: Node3D, wheel_f: Node3D, wheel_r: Node3D) -> void:
	if model == null or not available(): return
	var t0 := Time.get_ticks_usec()
	var groups: Array = [[], [], []]
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null or not (m.mesh is ArrayMesh) or m.material_override != null: continue
		var g := 2
		if wheel_f != null and (m == wheel_f or wheel_f.is_ancestor_of(m)): g = 0
		elif wheel_r != null and (m == wheel_r or wheel_r.is_ancestor_of(m)): g = 1
		groups[g].append(m)
	var baked := 0
	for g in groups:
		if not (g as Array).is_empty():
			baked += _group(model, g, g == groups[2])   # wheels: no splitting (long spokes, the rims are fine)
	if Env.s("BMX_AO_PROBE") != "":
		print("AO bike baked=%d verts total_ms=%.1f" % [baked, (Time.get_ticks_usec() - t0) / 1000.0])


static func _to_model(model: Node3D, n: Node3D) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var o: Node = n
	while o != null and o != model:
		if o is Node3D: xf = (o as Node3D).transform * xf
		o = o.get_parent()
	return xf


static func _group(model: Node3D, mis: Array, split: bool) -> int:
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var idx := PackedInt32Array()
	var surf := []   # [mi, surface, arrays, first vertex, count]
	for mi in mis:
		var xf := _to_model(model, mi)
		var nb := xf.basis.inverse().transposed()
		var mesh: ArrayMesh = mi.mesh
		for s in mesh.get_surface_count():
			if mesh.surface_get_primitive_type(s) != Mesh.PRIMITIVE_TRIANGLES: continue
			var a := mesh.surface_get_arrays(s)
			if a[Mesh.ARRAY_NORMAL] == null or (a[Mesh.ARRAY_VERTEX] as PackedVector3Array).is_empty(): continue
			if split: a = _split(a)
			var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
			var n: PackedVector3Array = a[Mesh.ARRAY_NORMAL]
			var base := verts.size()
			for i in v.size():
				verts.append(xf * v[i])
				norms.append((nb * n[i]).normalized())
			if a[Mesh.ARRAY_INDEX] != null:
				var ix: PackedInt32Array = a[Mesh.ARRAY_INDEX]
				for i in ix.size(): idx.append(ix[i] + base)
			else:
				for i in v.size(): idx.append(i + base)
			surf.append([mi, s, a, base, v.size()])
	if verts.is_empty(): return 0
	var key := "%d_%d_%d_%d" % [VER, hash(verts), hash(idx), verts.size()]
	var nv := verts.size()
	var ao: PackedFloat32Array = _mem.get(key, PackedFloat32Array())   # AO (nv) then edges (nv)
	if ao.size() != nv * 2:
		ao = _load(key, nv * 2)
		if ao.size() != nv * 2:
			var t0 := Time.get_ticks_usec()
			ao = PackedFloat32Array(_cs.call("Bake", verts, norms, idx, RADIUS, CELL, STRENGTH))
			var t1 := Time.get_ticks_usec()
			ao.append_array(PackedFloat32Array(_cs.call("Edges", verts, norms, EDGE_R, EDGE_K0, EDGE_K1)))
			if Env.s("BMX_AO_PROBE") != "": print("AO group verts=%d tris=%d bake_ms=%.1f edges_ms=%.1f" % [nv, idx.size() / 3, (t1 - t0) / 1000.0, (Time.get_ticks_usec() - t1) / 1000.0])
			_save(key, ao)
		_mem[key] = ao
	if Env.s("BMX_AO_PROBE") != "":
		var hist := [0, 0, 0, 0, 0]
		var ehist := [0, 0, 0, 0, 0]
		for i in nv:
			hist[clampi(int((1.0 - ao[i]) * 10.0), 0, 4)] += 1
			ehist[clampi(int(ao[nv + i] * 5.0), 0, 4)] += 1
		print("AO edges (0-.2, -.4, -.6, -.8, -1) %s" % [ehist])
		print("AO hist (1.0-0.9, -0.8, -0.7, -0.6, darker) %s of %d  first=%s" % [hist, ao.size(), (mis[0] as Node).name])
	# rebuild each mesh with the AO in its vertex colour
	var by_mi := {}
	for e in surf:
		if not by_mi.has(e[0]): by_mi[e[0]] = []
		by_mi[e[0]].append(e)
	for mi in by_mi:
		_apply_mesh(mi, by_mi[mi], ao, nv)
	return verts.size()


## long edges split (AoBake.Subdivide) so the AO has points to land on: a low-poly tube is one long face,
## and its two end vertices would smear a joint's darkness half way along it
static func _split(a: Array) -> Array:
	var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
	var ix: PackedInt32Array = a[Mesh.ARRAY_INDEX] if a[Mesh.ARRAY_INDEX] != null else PackedInt32Array(range(v.size()))
	if int(_cs.call("LongEdges", v, ix, MAX_EDGE)) == 0: return a
	var n: PackedVector3Array = a[Mesh.ARRAY_NORMAL]
	var tg = a[Mesh.ARRAY_TANGENT]
	var uv = a[Mesh.ARRAY_TEX_UV]
	var uv2 = a[Mesh.ARRAY_TEX_UV2]
	var col = a[Mesh.ARRAY_COLOR]
	var stride := 6 + (4 if tg != null else 0) + (2 if uv != null else 0) + (2 if uv2 != null else 0) + (4 if col != null else 0)
	var f := PackedFloat32Array()
	f.resize(v.size() * stride)
	var k := 0
	for i in v.size():
		f[k] = v[i].x; f[k + 1] = v[i].y; f[k + 2] = v[i].z
		f[k + 3] = n[i].x; f[k + 4] = n[i].y; f[k + 5] = n[i].z
		k += 6
		if tg != null:
			for j in 4: f[k + j] = tg[i * 4 + j]
			k += 4
		if uv != null: f[k] = uv[i].x; f[k + 1] = uv[i].y; k += 2
		if uv2 != null: f[k] = uv2[i].x; f[k + 1] = uv2[i].y; k += 2
		if col != null:
			var c: Color = col[i]
			f[k] = c.r; f[k + 1] = c.g; f[k + 2] = c.b; f[k + 3] = c.a; k += 4
	var r: Array = _cs.call("Subdivide", f, stride, ix, MAX_EDGE, 6)
	var F := PackedFloat32Array(r[0])
	var nv := F.size() / stride
	var V := PackedVector3Array(); V.resize(nv)
	var N := PackedVector3Array(); N.resize(nv)
	var TG := PackedFloat32Array(); if tg != null: TG.resize(nv * 4)
	var UV := PackedVector2Array(); if uv != null: UV.resize(nv)
	var UV2 := PackedVector2Array(); if uv2 != null: UV2.resize(nv)
	var C := PackedColorArray(); if col != null: C.resize(nv)
	k = 0
	for i in nv:
		V[i] = Vector3(F[k], F[k + 1], F[k + 2])
		N[i] = Vector3(F[k + 3], F[k + 4], F[k + 5]).normalized()
		k += 6
		if tg != null:
			var t := Vector3(F[k], F[k + 1], F[k + 2]).normalized()
			TG[i * 4] = t.x; TG[i * 4 + 1] = t.y; TG[i * 4 + 2] = t.z; TG[i * 4 + 3] = 1.0 if F[k + 3] >= 0.0 else -1.0
			k += 4
		if uv != null: UV[i] = Vector2(F[k], F[k + 1]); k += 2
		if uv2 != null: UV2[i] = Vector2(F[k], F[k + 1]); k += 2
		if col != null: C[i] = Color(F[k], F[k + 1], F[k + 2], F[k + 3]); k += 4
	var out := []
	out.resize(Mesh.ARRAY_MAX)
	out[Mesh.ARRAY_VERTEX] = V
	out[Mesh.ARRAY_NORMAL] = N
	if tg != null: out[Mesh.ARRAY_TANGENT] = TG
	if uv != null: out[Mesh.ARRAY_TEX_UV] = UV
	if uv2 != null: out[Mesh.ARRAY_TEX_UV2] = UV2
	if col != null: out[Mesh.ARRAY_COLOR] = C
	out[Mesh.ARRAY_INDEX] = PackedInt32Array(r[1])
	return out


static func _apply_mesh(mi: MeshInstance3D, entries: Array, ao: PackedFloat32Array, nv: int) -> void:
	var src: ArrayMesh = mi.mesh
	var done := {}
	for e in entries: done[e[1]] = e
	var out := ArrayMesh.new()
	out.resource_name = src.resource_name
	var overrides := []
	for s in src.get_surface_count():
		var ov := mi.get_surface_override_material(s)
		var mat: Material = ov if ov else src.surface_get_material(s)
		var a: Array = done[s][2] if done.has(s) else src.surface_get_arrays(s)
		if done.has(s):
			var base: int = done[s][3]
			var cnt: int = done[s][4]
			var old = a[Mesh.ARRAY_COLOR]
			var col := PackedColorArray()
			col.resize(cnt)
			var bm := mat as BaseMaterial3D
			var keep: bool = old != null and bm != null and bm.vertex_color_use_as_albedo
			var srgb: bool = keep and bm.vertex_color_is_srgb
			var see_through: bool = bm != null and bm.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED
			for i in cnt:
				var k := ao[base + i]
				if keep:
					var c: Color = old[i]
					var m := pow(k, 1.0 / 2.2) if srgb else k
					col[i] = Color(c.r * m, c.g * m, c.b * m, c.a)
				else:
					col[i] = Color(k, k, k, 1.0 if see_through else 1.0 - ao[nv + base + i])
			a[Mesh.ARRAY_COLOR] = col
			if bm != null and not keep:
				mat = _ao_mat(bm)
		out.add_surface_from_arrays(src.surface_get_primitive_type(s), a)
		out.surface_set_name(s, src.surface_get_name(s))
		# an override stays an override (paint etc. are found there), the mesh keeps its own material under it
		out.surface_set_material(s, src.surface_get_material(s) if ov != null else mat)
		overrides.append(mat if ov != null else null)
	out.custom_aabb = src.custom_aabb
	mi.mesh = out
	for s in overrides.size():
		mi.set_surface_override_material(s, overrides[s])
	if Env.s("BMX_AO_SHOW") != "":   # tests: the AO alone, unlit
		var dbg := StandardMaterial3D.new()
		dbg.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		dbg.vertex_color_use_as_albedo = true
		dbg.albedo_color = Color(0.22, 0.22, 0.22)   # under the exposure + tonemap (white clips)
		mi.material_override = dbg


## a copy of a material that multiplies the vertex colour (the AO) into its albedo; the original's
## resource_name stays (paint / chrome / metal finishes are found by it)
static func _ao_mat(m: BaseMaterial3D) -> BaseMaterial3D:
	if m.vertex_color_use_as_albedo: return m
	var id := m.get_instance_id()
	if _mats.has(id) and is_instance_valid(_mats[id]): return _mats[id]
	var d: BaseMaterial3D = m.duplicate()
	d.vertex_color_use_as_albedo = true
	d.vertex_color_is_srgb = false
	_mats[id] = d
	return d


static func _load(key: String, n: int) -> PackedFloat32Array:
	var p := "%s/%s.bin" % [CACHE_DIR, key]
	if not FileAccess.file_exists(p): return PackedFloat32Array()
	var f := FileAccess.open(p, FileAccess.READ)
	if f == null: return PackedFloat32Array()
	var b := f.get_buffer(n * 4)
	return b.to_float32_array()


static func _save(key: String, ao: PackedFloat32Array) -> void:
	DirAccess.make_dir_recursive_absolute(CACHE_DIR)
	var f := FileAccess.open("%s/%s.bin" % [CACHE_DIR, key], FileAccess.WRITE)
	if f != null: f.store_buffer(ao.to_byte_array())
