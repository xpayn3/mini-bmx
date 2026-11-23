extends RefCounted
## Bakes rigid groups of small meshes (action cams, the bike lamp, pivot bolts) into ONE MeshInstance3D, so each
## group costs one or a few draw calls instead of one per piece (BMX_RENDER_PROBE: the helmet cam alone was 22).
##
## merge(parent, sources): every MeshInstance3D in `sources` (and under them, but not under a node in `skip`) goes
## into one new MeshInstance3D "Merged" under `parent`, in parent space. Surfaces are grouped by material:
## - flat = true: plain opaque StandardMaterial3Ds without emission (and not in `keep`) become ONE surface with the
##   part's colour baked into the vertices, one shared material (roughness / metal averaged by area): parts this
##   small don't show their own textures. Everything else keeps its material, one surface per material.
## - ShaderMaterials (blinking LED, halo quads, fur shells: their shaders may billboard or read the part's own
##   space) are never merged: those nodes stay as they are.
## Merged pieces are freed (or keep their node with no mesh when they have children). Returns the new mesh, or null.
## BMX_NO_MERGE=1 = leave everything as built (A/B).

static var OFF := OS.get_environment("BMX_NO_MERGE") != ""
const SHADOW_MIN := 0.1   # = Game.SMALL_SHADOW

static func merge(parent: Node3D, sources: Array, flat := true, keep: Array = [], skip: Array = []) -> MeshInstance3D:
	if OFF or parent == null: return null
	var parts: Array = []   # [MeshInstance3D, transform in parent space]
	for s in sources:
		_collect(s, parent, parts, skip)
	if parts.size() < 2: return null
	# groups: material -> arrays; the flat group under the key "flat"
	var groups := {}
	var order: Array = []
	var area := 0.0; var rough := 0.0; var metal := 0.0
	var used: Array = []
	for pr in parts:
		var mi: MeshInstance3D = pr[0]
		var xf: Transform3D = pr[1]
		var mesh := mi.mesh
		var any := false
		for si in mesh.get_surface_count():
			var mat: Material = mi.material_override
			if mat == null: mat = mi.get_surface_override_material(si)
			if mat == null: mat = mesh.surface_get_material(si)
			if mat is ShaderMaterial or mat == null: continue
			if mesh is ArrayMesh and (mesh as ArrayMesh).surface_get_primitive_type(si) != Mesh.PRIMITIVE_TRIANGLES: continue   # primitives are triangles
			var is_flat: bool = flat and mat is StandardMaterial3D and not keep.has(mat) \
				and (mat as BaseMaterial3D).transparency == BaseMaterial3D.TRANSPARENCY_DISABLED \
				and not (mat as BaseMaterial3D).emission_enabled
			var key = "flat" if is_flat else mat
			if not groups.has(key):
				groups[key] = {"v": PackedVector3Array(), "n": PackedVector3Array(), "uv": PackedVector2Array(),
					"c": PackedColorArray(), "i": PackedInt32Array(), "mat": mat}
				order.append(key)
			var a := _append(groups[key], mesh.surface_get_arrays(si), xf,
				(mat as BaseMaterial3D).albedo_color if is_flat else Color.WHITE)
			if is_flat:
				area += a; rough += a * (mat as BaseMaterial3D).roughness; metal += a * (mat as BaseMaterial3D).metallic
			any = true
		if any: used.append(mi)
	if used.size() < 2: return null
	var am := ArrayMesh.new()
	for key in order:
		var g: Dictionary = groups[key]
		if g.i.is_empty(): continue
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = g.v
		arr[Mesh.ARRAY_NORMAL] = g.n
		arr[Mesh.ARRAY_TEX_UV] = g.uv
		if key is String: arr[Mesh.ARRAY_COLOR] = g.c
		arr[Mesh.ARRAY_INDEX] = g.i
		am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		var m: Material = g.mat
		if key is String:
			var fm := StandardMaterial3D.new()
			fm.vertex_color_use_as_albedo = true
			fm.vertex_color_is_srgb = true
			fm.roughness = rough / maxf(area, 1e-9)
			fm.metallic = metal / maxf(area, 1e-9)
			m = fm
		am.surface_set_material(am.get_surface_count() - 1, m)
	var out := MeshInstance3D.new()
	out.name = "Merged"
	out.mesh = am
	# a sun shadow only if one of the pieces was big enough to cast one on its own (Game._shadow_size: under
	# SHADOW_MIN across = none): a merged group is bigger than its pieces, and the shadow pass would grow
	var cs := GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for pr in parts:
		var pm: MeshInstance3D = pr[0]
		if used.has(pm) and pm.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF \
				and ((pr[1] as Transform3D) * pm.mesh.get_aabb()).size.length() >= SHADOW_MIN:
			cs = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	out.cast_shadow = cs
	out.set_meta("shadow_sized", true)   # decided here: Game._shadow_size leaves it
	parent.add_child(out)
	for mi in used:
		if (mi as Node).get_child_count() > 0:
			(mi as MeshInstance3D).mesh = null
		else:
			(mi as Node).get_parent().remove_child(mi)
			(mi as Node).queue_free()
	return out

## MeshInstance3Ds under n (n included), with their transform relative to `parent` (from the local transforms:
## works before the tree is in the scene)
static func _collect(n: Node, parent: Node3D, out: Array, skip: Array) -> void:
	if skip.has(n): return
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null and (n as Node3D).visible:
		out.append([n, _rel(n as Node3D, parent)])
	for c in n.get_children():
		_collect(c, parent, out, skip)

static func _rel(n: Node3D, parent: Node3D) -> Transform3D:
	var t := Transform3D()
	var o: Node = n
	while o != null and o != parent:
		if o is Node3D: t = (o as Node3D).transform * t
		o = o.get_parent()
	return t

## one surface's triangles into a group, moved by xf; returns its area (for the averaged material)
static func _append(g: Dictionary, a: Array, xf: Transform3D, col: Color) -> float:
	var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
	var n = a[Mesh.ARRAY_NORMAL]
	var uv = a[Mesh.ARRAY_TEX_UV]
	var idx = a[Mesh.ARRAY_INDEX]
	var base: int = g.v.size()
	var nb := xf.basis.inverse().transposed()
	for k in v.size():
		g.v.append(xf * v[k])
		g.n.append((nb * (n[k] as Vector3)).normalized() if n != null and k < n.size() else Vector3.UP)
		g.uv.append(uv[k] if uv != null and k < uv.size() else Vector2.ZERO)
		g.c.append(col)
	var area := 0.0
	var flip := xf.basis.determinant() < 0.0
	if idx == null or (idx as PackedInt32Array).is_empty():
		idx = PackedInt32Array(range(v.size()))
	var ii: PackedInt32Array = idx
	for k in range(0, ii.size() - 2, 3):
		var i0 := ii[k]
		var i1 := ii[k + 2] if flip else ii[k + 1]   # a mirrored part: keep its faces turned out
		var i2 := ii[k + 1] if flip else ii[k + 2]
		g.i.append(base + i0); g.i.append(base + i1); g.i.append(base + i2)
		area += 0.5 * (g.v[base + i1] - g.v[base + i0]).cross(g.v[base + i2] - g.v[base + i0]).length()
	return area
