class_name BikeDecals
extends RefCounted
## Bike decals (port of src/decals.js): artwork / lettering projected onto the model's own surface
## (a CPU port of three's DecalGeometry: the surface's triangles clipped to the projector box), so it
## follows the tube's curve and the tyre's bulge. Each decal is a MeshInstance3D child of the mesh it
## sits on, so it moves with it (the tyre lettering spins with the wheel).
##
## In Godot each part is ONE mesh with a surface per material, where three.js had a child mesh per
## material ("frame_1" = the frame's 1st primitive). Labels therefore name the node AND the surface
## (by material name, or index); three.js style names like "frame_1" are still understood.
##
## Lettering ("GLORY", "MAXXIS" round the tyres) is drawn by a 2D node into a SubViewport that renders
## once; its ViewportTexture is the decal's albedo. The SubViewports are parented under the bike.

## the `decals` block of BIKES.dh in src/main.js
const DH_DECALS := {
	"labels": [
		# down tube
		{"mesh": "frame", "surface": "paint", "from": [0.168, 0.486], "to": [0.404, 0.809],
			"image": "res://assets/decals/cinelli.png", "length": 0.2, "height": 0.0627},
		# top tube: model name
		{"mesh": "frame", "surface": "paint", "from": [0.05, 0.74], "to": [0.30, 0.86],
			"text": "GLORY", "length": 0.19, "height": 0.032},
		# chainstays
		{"mesh": "swing", "surface": "paint", "from": [-0.44, -0.025], "to": [-0.25, 0.03],
			"image": "res://assets/decals/cinelli.png", "length": 0.09, "height": 0.0282, "z": 0.075, "depth": 0.06},
		# both fork legs: the Fox stickers
		{"mesh": "fork_lower", "surface": "black", "from": [-0.03, 0.07], "to": [-0.165, 0.335], "upright": true,
			"length": 0.062, "height": 0.1, "z": 0.085, "depth": 0.05,
			"image": "res://assets/decals/fox_right.png", "imageMinus": "res://assets/decals/fox_left.png"},
	],
	"tyres": {"text": "MAXXIS", "meshes": [["wheel_front", "rubber"], ["wheel_rear", "rubber"]]},
}

const SURFACE_LIFT := 0.0006   # decal pushed out along the normal (stands in for polygonOffset)

static var _tex_cache := {}
static var _pending := {}   # ViewportTexture instance id -> TextArt still drawing it
static var _bolt_mat: StandardMaterial3D
static var _socket_mat: StandardMaterial3D


# ---------------------------------------------------------------- lettering textures

## Draws straight or ring lettering into its SubViewport (canvas: y down, like the HTML canvas).
class TextArt:
	extends Node2D
	var mode := "word"          # "word" | "ring"
	var text := ""
	var size := Vector2i(1024, 128)
	var fill := Color(1, 1, 1)
	var stroke := Color(20 / 255.0, 20 / 255.0, 24 / 255.0, 0.85)
	var italic := true
	var R := 0.3
	var r0 := 0.2
	var r1 := 0.25

	# Godot's built-in font, emboldened (and slanted for italic) to stand in for "Arial Black":
	# system fonts are not used, they render as solid boxes in this Godot build and vary per machine
	func _font(_px: int) -> Font:
		var f := FontVariation.new()
		f.base_font = ThemeDB.fallback_font
		f.variation_embolden = 1.2
		if italic and mode == "word":
			f.variation_transform = Transform2D(Vector2(1.0, 0.2), Vector2(0.0, 1.0), Vector2.ZERO)
		return f

	var materials: Array = []   # decal materials showing this texture (re-pointed when baked)
	var _frames := 0

	# render for a few frames (the glyph atlas fills on the first draw), then bake the result into a
	# mipmapped ImageTexture (viewport textures have no mipmaps: minified text would sample garbage)
	# and free the SubViewport
	func _process(_dt: float) -> void:
		_frames += 1
		if _frames < 4:
			return
		set_process(false)
		var vp := get_parent() as SubViewport
		if vp == null:
			return
		var img := vp.get_texture().get_image()
		if img == null or img.is_empty():   # no real renderer (headless): keep the live viewport
			vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
			return
		img.generate_mipmaps()
		var tex := ImageTexture.create_from_image(img)
		for m in materials:
			(m as StandardMaterial3D).albedo_texture = tex
		BikeDecals._pending.erase(vp.get_texture().get_instance_id())
		vp.queue_free()

	func _draw() -> void:
		if mode == "ring":
			_draw_ring()
		else:
			_draw_word()

	func _draw_word() -> void:
		var W := size.x
		var H := size.y
		var px := H * 0.86
		var font := _font(int(px))
		var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, int(px)).x
		if w > W * 0.94:
			px *= W * 0.94 / w
			w = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, int(px)).x
		var ip := int(px)
		var base_y := H / 2.0 + px * 0.04 + (font.get_ascent(ip) - font.get_descent(ip)) / 2.0
		var pos := Vector2((W - w) / 2.0, base_y)
		draw_string_outline(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, ip, maxi(1, int(px * 0.1)), stroke)
		draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, ip, fill)

	# lettering bent round a circle (a tyre sidewall). The canvas spans [-R, R] of the tyre; the letters
	# sit between radii r0 and r1, centred at the top and again at the bottom.
	func _draw_ring() -> void:
		var S := float(size.x)
		var k := S / (2.0 * R)
		var r_mid := (r0 + r1) / 2.0 * k
		var px := (r1 - r0) * k * 0.95
		var ip := int(px)
		var font := _font(ip)
		var track := px * 0.08   # a little letter spacing
		var widths: Array[float] = []
		var total := 0.0
		for ch in text:
			var cw := font.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, ip).x + track
			widths.append(cw)
			total += cw
		var arc := total / r_mid
		var mid_y := (font.get_ascent(ip) - font.get_descent(ip)) / 2.0
		for mid in [-PI / 2.0, PI / 2.0]:   # top, then bottom (upside down, like a real tyre)
			var th: float = mid - arc / 2.0
			for i in text.length():
				var a: float = th + widths[i] / 2.0 / r_mid
				var o := Vector2(S / 2.0, S / 2.0) + Vector2(cos(a), sin(a)) * r_mid
				draw_set_transform(o, a + PI / 2.0, Vector2.ONE)
				var cw := widths[i] - track
				draw_string(font, Vector2(-cw / 2.0, mid_y), text[i], HORIZONTAL_ALIGNMENT_LEFT, -1, ip, fill)
				th += widths[i] / r_mid
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


static func _text_texture(host: Node, art: TextArt) -> Texture2D:
	var vp := SubViewport.new()
	vp.name = "decal_text"
	vp.size = art.size
	vp.transparent_bg = true
	vp.disable_3d = true
	vp.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS   # TextArt freezes it after a few frames
	vp.add_child(art)
	host.add_child(vp)
	var tex := vp.get_texture()
	_pending[tex.get_instance_id()] = art
	return tex


static func _bind_text(tex: Texture2D, mat: Material) -> void:
	var art = _pending.get(tex.get_instance_id())
	if art != null:
		art.materials.append(mat)


static func word_texture(host: Node, text: String, aspect: float, opts: Dictionary = {}) -> Texture2D:
	var art := TextArt.new()
	art.mode = "word"
	art.text = text
	art.size = Vector2i(1024, maxi(8, roundi(1024.0 / aspect)))
	if opts.has("fill"): art.fill = opts["fill"]
	if opts.has("stroke"): art.stroke = opts["stroke"]
	art.italic = opts.get("italic", true)
	return _text_texture(host, art)


static func ring_texture(host: Node, text: String, R: float, r0: float, r1: float, fill := Color8(0xf4, 0xf4, 0xf0)) -> Texture2D:
	var art := TextArt.new()
	art.mode = "ring"
	art.text = text
	art.size = Vector2i(2048, 2048)
	art.R = R; art.r0 = r0; art.r1 = r1
	art.fill = fill
	return _text_texture(host, art)


static func image_texture(path: String) -> Texture2D:
	if not _tex_cache.has(path):
		if path.begins_with("res://"):
			_tex_cache[path] = load(path)
		else:   # a logo the player imported (user:// or a file on disk)
			var img := Image.load_from_file(path)
			if img == null or img.is_empty():
				return null
			img.generate_mipmaps()
			_tex_cache[path] = ImageTexture.create_from_image(img)
	return _tex_cache[path]


static func decal_material(tex: Texture2D, roughness: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = tex
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	m.roughness = roughness
	m.metallic = 0.0
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	m.render_priority = 1
	return m


# ---------------------------------------------------------------- projection

## node + surface index for a label's mesh ({mesh, surface} or a three.js name like "frame_1")
static func _resolve(bike: Node, mesh_name: String, surface = null) -> Array:
	var node := bike.find_child(mesh_name, true, false) as MeshInstance3D
	var si := -1
	if node == null:
		var cut := mesh_name.rfind("_")
		if cut > 0 and mesh_name.substr(cut + 1).is_valid_int():
			node = bike.find_child(mesh_name.substr(0, cut), true, false) as MeshInstance3D
			si = int(mesh_name.substr(cut + 1)) - 1
	if node == null or node.mesh == null:
		return []
	if surface is int:
		si = surface
	elif surface is String:
		si = _surface_by_name(node, surface)
	if si < 0 or si >= node.mesh.get_surface_count():
		return []
	return [node, si]


static func _surface_by_name(mi: MeshInstance3D, mat_name: String) -> int:
	for s in mi.mesh.get_surface_count():
		var m := mi.mesh.surface_get_material(s)
		if m and m.resource_name == mat_name:
			return s
	return -1


# clip polygon (pp positions in projector space, nn normals) to the half space sgn * p[axis] <= h
static func _clip(pp: Array, nn: Array, axis: int, sgn: float, h: float) -> Array:
	var op: Array = []
	var on: Array = []
	var cnt := pp.size()
	for i in cnt:
		var a: Vector3 = pp[i]
		var b: Vector3 = pp[(i + 1) % cnt]
		var da := sgn * a[axis] - h
		var db := sgn * b[axis] - h
		if da <= 0.0:
			op.append(a); on.append(nn[i])
		if (da <= 0.0) != (db <= 0.0):
			var t := da / (da - db)
			op.append(a.lerp(b, t))
			on.append((nn[i] as Vector3).lerp(nn[(i + 1) % cnt], t))
	return [op, on]


## project a decal onto surface `si` of `mi` (in the mesh's own space) and keep only the faces that
## look toward the projector, so it never wraps round to the far side of a tube or tyre
static func project(mi: MeshInstance3D, si: int, pos: Vector3, x_axis: Vector3, z_axis: Vector3, size: Vector3, material: Material) -> MeshInstance3D:
	var arr := mi.mesh.surface_get_arrays(si)
	var P: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var N: PackedVector3Array = arr[Mesh.ARRAY_NORMAL] if arr[Mesh.ARRAY_NORMAL] != null else PackedVector3Array()
	var I: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
	if I.is_empty():
		I.resize(P.size())
		for i in P.size():
			I[i] = i
	if N.size() != P.size():
		N.resize(P.size())
		N.fill(z_axis)
	var y_axis := z_axis.cross(x_axis).normalized()
	var proj := Transform3D(Basis(x_axis, y_axis, z_axis), pos)
	var inv := proj.affine_inverse()
	var Q: PackedVector3Array = inv * P   # projector space
	var hx := size.x * 0.5
	var hy := size.y * 0.5
	var hz := size.z * 0.5
	var out_p := PackedVector3Array()
	var out_n := PackedVector3Array()
	var out_uv := PackedVector2Array()
	for t in range(0, I.size(), 3):
		var ia := I[t]
		var ib := I[t + 1]
		var ic := I[t + 2]
		var qa := Q[ia]
		var qb := Q[ib]
		var qc := Q[ic]
		# whole triangle outside one plane: skip
		if (qa.x > hx and qb.x > hx and qc.x > hx) or (qa.x < -hx and qb.x < -hx and qc.x < -hx): continue
		if (qa.y > hy and qb.y > hy and qc.y > hy) or (qa.y < -hy and qb.y < -hy and qc.y < -hy): continue
		if (qa.z > hz and qb.z > hz and qc.z > hz) or (qa.z < -hz and qb.z < -hz and qc.z < -hz): continue
		var pp: Array = [qa, qb, qc]
		var nn: Array = [N[ia], N[ib], N[ic]]
		var inside := absf(qa.x) <= hx and absf(qb.x) <= hx and absf(qc.x) <= hx \
			and absf(qa.y) <= hy and absf(qb.y) <= hy and absf(qc.y) <= hy \
			and absf(qa.z) <= hz and absf(qb.z) <= hz and absf(qc.z) <= hz
		if not inside:
			for plane in [[0, 1.0, hx], [0, -1.0, hx], [1, 1.0, hy], [1, -1.0, hy], [2, 1.0, hz], [2, -1.0, hz]]:
				var r := _clip(pp, nn, plane[0], plane[1], plane[2])
				pp = r[0]; nn = r[1]
				if pp.size() < 3:
					break
			if pp.size() < 3:
				continue
		# fan-triangulate (keeps the source winding); drop faces turned away from the projector
		for k in range(1, pp.size() - 1):
			var ids := [0, k, k + 1]
			var nz := 0.0
			for j in ids:
				nz += (nn[j] as Vector3).dot(z_axis)
			if nz / 3.0 < 0.15:
				continue
			for j in ids:
				var q: Vector3 = pp[j]
				var nrm := (nn[j] as Vector3).normalized()
				out_p.append(proj * q + nrm * SURFACE_LIFT)
				out_n.append(nrm)
				out_uv.append(Vector2(q.x / size.x + 0.5, 1.0 - (q.y / size.y + 0.5)))
	if out_p.is_empty():
		return null
	var da := []
	da.resize(Mesh.ARRAY_MAX)
	da[Mesh.ARRAY_VERTEX] = out_p
	da[Mesh.ARRAY_NORMAL] = out_n
	da[Mesh.ARRAY_TEX_UV] = out_uv
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, da)
	am.surface_set_material(0, material)
	var d := MeshInstance3D.new()
	d.name = "decal"
	d.mesh = am
	d.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.add_child(d, true)
	return d


static func _surface_aabb(mi: MeshInstance3D, si: int) -> AABB:
	var P: PackedVector3Array = mi.mesh.surface_get_arrays(si)[Mesh.ARRAY_VERTEX]
	var bb := AABB(P[0], Vector3.ZERO)
	for p in P:
		bb = bb.expand(p)
	return bb


## bike: the "dh" node; cfg: DH_DECALS (or the same shape). Returns the decal MeshInstance3Ds.
## labels: { mesh, surface, from: [x, y], to: [x, y], text | image, length, height, z = 0, depth = 0.2,
##   fill, stroke, upright, imageMinus } -- from -> to is the tube's centre line in the mesh's space. A
##   pair of parts (fork legs, chainstays) sits at +-z: give z (the outer face) and a shallow depth so
##   each side only hits its own part.
## tyres: { text, meshes: [[node, surface], ...] } -- radii come from each tyre and its rim
static func add_bike_decals(bike: Node3D, cfg: Dictionary) -> Array:
	var made: Array = []
	if cfg.is_empty():
		return made
	var Z := Vector3(0, 0, 1)
	var NZ := Vector3(0, 0, -1)
	for L in cfg.get("labels", []):
		var hit := _resolve(bike, L["mesh"], L.get("surface"))
		if hit.is_empty():
			continue
		var mi: MeshInstance3D = hit[0]
		var si: int = hit[1]
		var a := Vector3(L["from"][0], L["from"][1], 0.0)
		var b := Vector3(L["to"][0], L["to"][1], 0.0)
		var dir := (b - a).normalized()
		var mid := a.lerp(b, 0.5)
		var depth := float(L.get("depth", 0.2))
		var z := float(L.get("z", 0.0))
		var size := Vector3(L["length"], L["height"], depth)
		if L.get("upright", false):
			# a sticker standing along the part (fork legs): the image's up runs from -> to, `length` is its
			# width across the part; image / imageMinus are the drive-side and other-side artwork
			for side in [[Z, L["image"]], [NZ, L.get("imageMinus", L["image"])]]:
				var zs: Vector3 = side[0]
				var x := dir.cross(zs).normalized()
				var m := decal_material(image_texture(side[1]), 0.35)
				made.append(project(mi, si, Vector3(mid.x, mid.y, z * zs.z), x, zs, size, m))
			continue
		var tex: Texture2D
		if L.has("image"):
			tex = image_texture(L["image"])
		else:
			tex = word_texture(bike, L["text"], float(L["length"]) / float(L["height"]), L)
		var mat := decal_material(tex, 0.3)
		_bind_text(tex, mat)
		made.append(project(mi, si, Vector3(mid.x, mid.y, z), dir, Z, size, mat))      # drive side: reads toward `to`
		made.append(project(mi, si, Vector3(mid.x, mid.y, -z), -dir, NZ, size, mat))   # other side: the other way
	var ty = cfg.get("tyres", null)
	if ty != null:
		for entry in ty["meshes"]:
			var hit := _resolve(bike, entry[0], entry[1]) if entry is Array else _resolve(bike, entry)
			if hit.is_empty():
				continue
			var mi: MeshInstance3D = hit[0]
			var si: int = hit[1]
			var bb := _surface_aabb(mi, si)
			var c := bb.get_center()
			var R := bb.size.x / 2.0
			var rim_r := R * 0.85
			var rim_s := _surface_by_name(mi, "rim")
			if rim_s < 0: rim_s = _surface_by_name(mi, "black")
			if rim_s >= 0 and rim_s != si:
				rim_r = minf(R * 0.9, _surface_aabb(mi, rim_s).size.y / 2.0)
			var r0 := rim_r + (R - rim_r) * 0.12
			var r1 := rim_r + (R - rim_r) * 0.72
			var rtex := ring_texture(bike, ty["text"], R, r0, r1)
			var mat := decal_material(rtex, 0.75)
			_bind_text(rtex, mat)
			var size := Vector3(2.0 * R, 2.0 * R, 0.2)
			made.append(project(mi, si, c, Vector3(1, 0, 0), Z, size, mat))
			made.append(project(mi, si, c, Vector3(-1, 0, 0), NZ, size, mat))
	# rim lettering: a ring of text on the rim's side wall, between the spoke bed and the hook
	var rims = cfg.get("rims", null)
	if rims != null:
		for entry in rims["meshes"]:
			var hit := _resolve(bike, entry[0], entry[1])
			if hit.is_empty():
				continue
			var mi: MeshInstance3D = hit[0]
			var si: int = hit[1]
			var bb := _surface_aabb(mi, si)
			var c := bb.get_center()
			var R := bb.size.y / 2.0
			var d := float(rims.get("depth", 0.025))
			var r0 := R - d * 0.88
			var r1 := R - d * 0.18
			var rtex := ring_texture(bike, rims["text"], R, r0, r1, rims.get("fill", Color8(0xf4, 0xf4, 0xf0)))
			var mat := decal_material(rtex, 0.4)
			_bind_text(rtex, mat)
			var size := Vector3(2.0 * R, 2.0 * R, 0.2)
			made.append(project(mi, si, c, Vector3(1, 0, 0), Z, size, mat))
			made.append(project(mi, si, c, Vector3(-1, 0, 0), NZ, size, mat))
	return made.filter(func(d): return d != null)


# ---------------------------------------------------------------- pivot bolts

static func _rel_xform(bike: Node, node: Node) -> Transform3D:
	var t := Transform3D.IDENTITY
	var o: Node = node
	while o != null and o != bike:
		if o is Node3D:
			t = (o as Node3D).transform * t
		o = o.get_parent()
	return t


static func _part(mesh: Mesh, mat: Material, xf: Transform3D) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	m.mesh = mesh
	m.material_override = mat
	m.transform = xf
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	return m


## PIVOT BOLTS: the export drops small parts (bolts) to keep the model light, which leaves the
## suspension pivots as empty bores. Put back a through-axle and a hex bolt head on each outer face.
##   list: [{ node, at: [x, y] (bike space, metres), z (outer face of the plate), r (bore radius) }]
## main.js: [{node: "rocker", at: rear.G2, z: 0.029}, {node: "rocker", at: rear.C2, z: 0.029},
##           {node: "rocker", at: rear.D, z: 0.031, r: 0.005}]
static func add_pivot_bolts(bike: Node3D, list: Array) -> Array:
	var made: Array = []
	if _bolt_mat == null:
		_bolt_mat = StandardMaterial3D.new()
		_bolt_mat.albedo_color = Color8(0x2a, 0x2d, 0x31)
		_bolt_mat.metallic = 0.85
		_bolt_mat.roughness = 0.32
		_socket_mat = StandardMaterial3D.new()
		_socket_mat.albedo_color = Color8(0x05, 0x05, 0x06)
		_socket_mat.metallic = 0.3
		_socket_mat.roughness = 0.8
	var to_z := Basis(Vector3.RIGHT, PI / 2.0)   # cylinder axis Y -> Z
	for b in list:
		var node := bike.find_child(b["node"], true, false) as Node3D
		if node == null:
			continue
		var r := float(b.get("r", 0.006))
		var z := float(b["z"])
		var g := Node3D.new()
		g.name = "pivot_bolt"
		var axle := CylinderMesh.new()
		axle.top_radius = r * 1.02; axle.bottom_radius = r * 1.02; axle.height = 2.0 * z
		axle.radial_segments = 16; axle.rings = 1
		g.add_child(_part(axle, _bolt_mat, Transform3D(to_z, Vector3.ZERO)))
		var head := CylinderMesh.new()   # hex head
		head.top_radius = r * 1.5; head.bottom_radius = r * 1.5; head.height = 0.005
		head.radial_segments = 6; head.rings = 1
		var sock := CylinderMesh.new()   # hex socket (a thin disc standing in for three's CircleGeometry)
		sock.top_radius = r * 0.6; sock.bottom_radius = r * 0.6; sock.height = 0.0002
		sock.radial_segments = 6; sock.rings = 1
		for s in [-1.0, 1.0]:
			g.add_child(_part(head, _bolt_mat, Transform3D(to_z, Vector3(0, 0, s * (z + 0.0025)))))
			g.add_child(_part(sock, _socket_mat, Transform3D(to_z, Vector3(0, 0, s * (z + 0.0051)))))
		# into the node's own space, so it moves with the part (the rocker swings as the shock works)
		g.position = _rel_xform(bike, node).affine_inverse() * Vector3(b["at"][0], b["at"][1], 0.0)
		node.add_child(g)
		made.append(g)
	return made
