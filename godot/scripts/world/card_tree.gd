class_name CardTree
extends RefCounted
## Card trees (2026-11-26): the near-ring look of the tree crowns, built like the bushes (card_bush.gd) from upright /
## drooping quads with an alpha cut-out texture. Each crown is drawn twice from the SAME instance buffer (Terrain /
## LevelVisuals add the twin): within ~36-48 m of the rider these cards, further out the old solid low-poly crown, the
## two swapped per pixel by one dither (shaders/deco_fade.gdshaderinc, fade_mode 4 = cards, 3 = solid). The solid crown
## always casts the sun shadow; the cards cast none (an alpha cut-out in every shadow cascade is the expensive part of
## leaf cards). Both meshes fill the same unit space as the solid ones, so instance transforms are shared:
##   pineCard = TerrainGeo "pine": base radius ~1 at y 0, tip at y 2.8 (three stacked cones)
##   blobCard = TerrainGeo "blob": a lumpy ball of radius ~1 round the origin
## BMX_OLD_TREES=1 = no twins (solid crowns everywhere, as before).

## a chunk's card twins are drawn only while the camera is this close to the chunk's middle: the card band's end (48 m,
## deco_fade.gdshaderinc CARD_OUT) + half a chunk's diagonal (34 m) + the camera's distance from the rider
const CHUNK_VIS := 100.0

const TEX_W := 256
const TEX_H := 128

## pine crown: whorls of drooping branch cards up the axis
const PINE_TOP := 2.85
const PINE_WHORLS := 15
## leafy crown: cards in a ball (CardBush's recipe without the ground)
const BLOB := {"cards": 58, "r": Vector3(1.0, 0.95, 1.0), "s0": 0.6, "s1": 0.95, "seed": 4242}

static var _tex := {}
static var _mat := {}
static var _mesh := {}


static func enabled() -> bool:
	return OS.get_environment("BMX_OLD_TREES") != "1"


## twin list of a solid crown list: [card mesh, card material] or [] for none
static func twin(solid_mesh: String) -> Array:
	if not enabled():
		return []
	match solid_mesh:
		"pine": return [mesh("pineCard"), material("needle")]
		"blob": return [mesh("blobCard"), material("leaf")]
	return []


## the twin MultiMeshInstance3D beside a solid crown's (same buffer); sets both instances' fade modes
## vis > 0: the twins are left out entirely past that far from the camera (a streamed chunk: its far trees' cards would
## only be folded away in the vertex stage, still costing their vertices)
static func add_twin(solid: MultiMeshInstance3D, solid_mesh: String, vis := 0.0) -> MultiMeshInstance3D:
	var tw := twin(solid_mesh)
	if tw.is_empty():
		return null
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = solid.multimesh.use_custom_data
	mm.use_colors = solid.multimesh.use_colors
	mm.mesh = tw[0]
	mm.instance_count = solid.multimesh.instance_count
	mm.buffer = solid.multimesh.buffer
	var mi := MultiMeshInstance3D.new()
	mi.name = String(solid.name) + "_cards"
	mi.multimesh = mm
	mi.material_override = tw[1]
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	solid.get_parent().add_child(mi)
	mi.transform = solid.transform
	if vis > 0.0:
		mi.visibility_range_end = vis
	solid.set_instance_shader_parameter("fade_mode", 3.0)
	mi.set_instance_shader_parameter("fade_mode", 4.0)
	if solid_mesh == "pine":
		# the trunk carries on up through the see-through crown, tapering to the tip (it stopped at the crown's foot:
		# the crown floated on a stump). Only with the cards: the solid cone hides it anyway.
		var sm := MultiMesh.new()
		sm.transform_format = MultiMesh.TRANSFORM_3D
		sm.use_custom_data = mm.use_custom_data
		sm.use_colors = mm.use_colors
		sm.mesh = mesh("pineSpire")
		sm.instance_count = mm.instance_count
		sm.buffer = mm.buffer
		var si := MultiMeshInstance3D.new()
		si.name = String(solid.name) + "_spire"
		si.multimesh = sm
		si.material_override = material("spire")
		si.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		solid.get_parent().add_child(si)
		si.transform = solid.transform
		if vis > 0.0:
			si.visibility_range_end = vis
		si.set_instance_shader_parameter("fade_mode", 4.0)
	return mi


static func material(kind: String) -> ShaderMaterial:
	if _mat.has(kind):
		return _mat[kind]
	if kind == "spire":   # the pine bark, without the crown's green instance colour
		TerrainGeo.ensure()
		var b: ShaderMaterial = TerrainGeo.MAT["trunk_pine"].duplicate()
		b.set_shader_parameter("use_instance", false)
		_mat[kind] = b
		return b
	var m := ShaderMaterial.new()
	m.shader = preload("res://scripts/world/deco_cards.gdshader")
	m.set_shader_parameter("volume_normals", true)
	m.set_shader_parameter("specular", 0.1)
	if kind == "needle":
		m.set_shader_parameter("leaf_tex", texture("needle"))
		m.set_shader_parameter("sway", 0.02)       # = TerrainGeo "leaf" (the solid pine): the twins sway together
		m.set_shader_parameter("flutter", 0.003)
		m.set_shader_parameter("backlight", 0.25)
		m.set_shader_parameter("scatter", 0.6)
		m.set_shader_parameter("roughness", 0.85)
		m.set_shader_parameter("cutoff", 0.45)
		m.set_shader_parameter("albedo", Vector3(1.2, 1.2, 1.2))   # (cards read darker than the cone: self-shading)
	else:
		m.set_shader_parameter("leaf_tex", CardBush.texture("leaf"))
		m.set_shader_parameter("sway", 0.035)      # = "leafSoft" (the solid blob)
		m.set_shader_parameter("flutter", 0.006)
		m.set_shader_parameter("backlight", 0.35)
		m.set_shader_parameter("scatter", 0.85)
		m.set_shader_parameter("albedo", CardBush.leaf_gain() * Vector3(1.25, 1.18, 1.3))   # (the leaf card is darker than the solid crown's white)
	_mat[kind] = m
	return m


## a pine branch on a transparent card: the stem along u (0 at the trunk .. 1 at the tip), side shoots, needles
## the photo branch (assets/textures/tree_cards/needle_branch.png: ambientCG PineNeedles001 needle bundles stamped along a
## twig by root tools/make_tree_cards.py, BC7 + mipmaps); without the file, drawn here
const NEEDLE_PNG := "res://assets/textures/tree_cards/needle_branch.png"

static func texture(kind: String) -> Texture2D:
	if _tex.has(kind):
		return _tex[kind]
	if kind == "needle" and ResourceLoader.exists(NEEDLE_PNG) and OS.get_environment("BMX_OLD_TREES_TEX") != "1":
		_tex[kind] = load(NEEDLE_PNG)
		return _tex[kind]
	var img := Image.create(TEX_W, TEX_H, true, Image.FORMAT_RGBA8)
	img.fill(Color(0.6, 0.72, 0.55, 0.0))   # transparent texels carry needle colour: no dark fringe in the mips
	var rng := RandomNumberGenerator.new()
	rng.seed = 2611
	var cy := TEX_H * 0.5
	# the stem, wandering a little, and side shoots off it, each carrying needles
	var shoots: Array = []   # [start, dir, length]
	var p := Vector2(2, cy)
	var ang := 0.0
	var stem: Array = []
	while p.x < TEX_W - 6:
		stem.append(p)
		ang = clampf(ang + rng.randf_range(-0.05, 0.05), -0.12, 0.12)
		p += Vector2(cos(ang), sin(ang))
	shoots.append([stem, 1.0])
	for i in 22:
		var t := 0.06 + i / 22.0 * 0.9 + rng.randf_range(-0.02, 0.02)
		var s0: Vector2 = stem[int(t * (stem.size() - 1))]
		var sd := 1.0 if i % 2 == 0 else -1.0
		var a := sd * rng.randf_range(0.55, 0.95)
		var len := TEX_H * 0.55 * (1.0 - t * 0.7) * rng.randf_range(0.75, 1.1)
		var pts: Array = []
		var q := s0
		for s in int(len):
			pts.append(q)
			a += -sd * 0.012
			q += Vector2(cos(a), sin(a))
			if q.y < 3 or q.y > TEX_H - 4: break
		shoots.append([pts, 0.6])
	# needles first (stems drawn over them)
	for sh in shoots:
		var pts: Array = sh[0]
		for k in range(0, pts.size()):
			var base: Vector2 = pts[k]
			var tdir := (pts[mini(k + 1, pts.size() - 1)] - pts[maxi(k - 1, 0)]) as Vector2
			if tdir.length() < 0.01: continue
			tdir = tdir.normalized()
			var fade := 1.0 - float(k) / maxf(pts.size(), 1) * 0.35
			for side: float in [-1.0, 1.0]:
				var nl := rng.randf_range(10.0, 18.0) * float(sh[1] * 0.4 + 0.6) * fade
				var na := side * rng.randf_range(0.45, 1.25)
				var nd := tdir.rotated(na)
				var g := rng.randf_range(0.62, 0.95)
				var warm := rng.randf() * 0.1
				_line(img, base, base + nd * nl, Color(g * (0.82 + warm), g * 0.98, g * 0.74, 1.0), 1.0)
	for sh in shoots:
		var pts: Array = sh[0]
		for k in pts.size() - 1:
			var w: float = (1.2 if sh[1] > 0.9 else 0.7) * (1.0 - float(k) / pts.size() * 0.5)
			_line(img, pts[k], pts[k + 1], Color(0.5, 0.5, 0.34, 1.0), w)
	img.generate_mipmaps()
	img.compress(Image.COMPRESS_S3TC)   # (DXT5 with its mips)
	var tex := ImageTexture.create_from_image(img)
	_tex[kind] = tex
	return tex


static func _line(img: Image, a: Vector2, b: Vector2, c: Color, w: float) -> void:
	var n := int(ceil((b - a).length())) + 1
	var r := int(ceil(w * 0.5))
	for i in n:
		var p := a.lerp(b, float(i) / maxf(n - 1, 1))
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var x := int(p.x) + dx
				var y := int(p.y) + dy
				if x >= 0 and y >= 0 and x < TEX_W and y < TEX_H:
					img.set_pixel(x, y, c)


static func mesh(name: String) -> ArrayMesh:
	if not _mesh.has(name):
		match name:
			"pineCard": _mesh[name] = _pine()
			"pineSpire":   # crown-space trunk: from just under the crown's foot to its tip (radius as the trunk's top / crown scale)
				var g := GeoBuf.cylinder(0.006, 0.09, PINE_TOP + 0.15, 6).translate(0, (PINE_TOP + 0.15) * 0.5 - 0.1, 0)
				_mesh[name] = g.to_mesh(false, TerrainGeo._soft_normals(g))
			_: _mesh[name] = _blob()
	return _mesh[name]


## the pine's radius at height y of its unit crown: the three cones' outline, tiered
static func pine_radius(y: float) -> float:
	var r := 0.0
	for c in [[0.0, 1.6, 1.0], [0.95, 2.25, 0.75], [1.8, 2.8, 0.45]]:
		if y >= c[0] and y <= c[1]:
			r = maxf(r, c[2] * (1.0 - (y - c[0]) / (c[1] - c[0])))
	return r


class _Buf:
	var pos := PackedVector3Array()
	var nor := PackedVector3Array()
	var col := PackedColorArray()
	var uv := PackedVector2Array()

	func vert(p: Vector3, n: Vector3, ao: float, t: Vector2) -> void:
		pos.append(p); nor.append(n); col.append(Color(ao, ao, ao)); uv.append(t)

	func commit() -> ArrayMesh:
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = pos
		arr[Mesh.ARRAY_NORMAL] = nor
		arr[Mesh.ARRAY_COLOR] = col
		arr[Mesh.ARRAY_TEX_UV] = uv
		var m := ArrayMesh.new()
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		return m


## whorls of branch cards: each from the trunk out to the crown's outline, drooping, folded along its stem (a shallow V,
## so it has body from the side too), normals bent out from the axis (the crown lights like the cone it replaces)
static func _pine() -> ArrayMesh:
	var b := _Buf.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 1979
	for w in PINE_WHORLS:
		var t := (w + 0.5) / PINE_WHORLS
		var y := 0.04 + t * 2.45 + rng.randf_range(-0.05, 0.05)
		var R := maxf(pine_radius(y + 0.1) * 1.25, 0.2)
		var n := clampi(int(round(5.0 + R * 5.0)), 4, 10)
		var a0 := rng.randf() * TAU
		for k in n:
			var a := a0 + TAU * (k + rng.randf_range(-0.25, 0.25)) / n
			var out := Vector3(cos(a), 0, sin(a))
			var side := Vector3(-out.z, 0, out.x)
			var len := R * rng.randf_range(0.9, 1.08)
			var droop := rng.randf_range(0.18, 0.38) * (1.0 - 0.4 * t) * len
			var width := len * 0.8 + 0.2
			var root := Vector3(0, y + 0.05, 0) + out * 0.04
			var tip := root + out * len + Vector3(0, -droop, 0)
			var mid := root.lerp(tip, 0.5) + Vector3(0, droop * 0.18, 0)   # arched stem
			_branch(b, root, mid, tip, side, width, y)
	# the leader: two crossed upright cards at the top
	for k in 2:
		var a := k * PI / 2.0 + 0.3
		var side := Vector3(cos(a), 0, sin(a))
		var y0 := 2.35
		var q := [Vector3(0, y0, 0) - side * 0.3, Vector3(0, y0, 0) + side * 0.3, Vector3(0, PINE_TOP, 0) + side * 0.06, Vector3(0, PINE_TOP, 0) - side * 0.06]
		var nn := Vector3(side.z, 0.5, -side.x).normalized()
		var uvs := [Vector2(0, 0), Vector2(0, 1), Vector2(1, 0.6), Vector2(1, 0.4)]   # stem up the card (u along it)
		for e in [0, 2, 1, 0, 3, 2]:
			b.vert(q[e], nn, 0.95, uvs[e])
	return b.commit()


## one branch card: u along the stem (root .. tip), v across; folded up along the stem
static func _branch(b: _Buf, root: Vector3, mid: Vector3, tip: Vector3, side: Vector3, width: float, y: float) -> void:
	var fold := Vector3(0, width * 0.12, 0)
	# 3 x 3 grid: rows along the stem (root, mid, tip), columns across (-1, 0 = stem, +1)
	var spine := [root, mid, tip]
	var wk := [0.45, 1.0, 0.7]   # narrow at the trunk and the tip
	var g: Array = []
	for r in 3:
		var row: Array = []
		for c in 3:
			var off: Vector3 = side * (c - 1) * 0.5 * width * wk[r]
			var p: Vector3 = spine[r] + off + (fold if c == 1 else -fold * 0.3)
			row.append(p)
		g.append(row)
	for r in 2:
		for c in 2:
			var quad := [Vector2i(c, r), Vector2i(c + 1, r), Vector2i(c + 1, r + 1), Vector2i(c, r + 1)]
			for e in [0, 2, 1, 0, 3, 2]:
				var ix: Vector2i = quad[e]
				var p: Vector3 = g[ix.y][ix.x]
				var radial := Vector3(p.x, 0, p.z)
				var rl := radial.length()
				# normal: out from the axis and up a bit (the cone's), the card's own up mixed in
				var nrm := (radial / maxf(rl, 0.001) * 0.75 + Vector3(0, 0.55, 0)).normalized()
				var reach := clampf(rl / maxf(pine_radius(y) + 0.1, 0.2), 0.0, 1.0)
				var ao := (0.45 + 0.55 * smoothstep(0.0, 0.9, reach)) * (0.75 + 0.25 * clampf(p.y / PINE_TOP, 0.0, 1.0))
				b.vert(p, nrm, ao, Vector2(ix.y * 0.5, 1.0 - ix.x * 0.5))


## a leafy crown: CardBush's upright folded cards in a ball (no ground clamp), dome normals, inside darker
static func _blob() -> ArrayMesh:
	var b := _Buf.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = BLOB.seed
	var R: Vector3 = BLOB.r
	for k in int(BLOB.cards):
		var dir := Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.75, 1), rng.randf_range(-1, 1)).normalized()
		var rad := 0.3 + 0.7 * pow(rng.randf(), 0.5)
		var p := dir * rad * R
		var yaw := rng.randf() * TAU
		var d := Vector3(cos(yaw), 0, sin(yaw))
		if d.dot(Vector3(dir.x, 0, dir.z)) < 0.0:
			d = -d
		var u2 := Vector3.UP.cross(d).normalized()
		var s: float = BLOB.s0 + rng.randf() * (BLOB.s1 - BLOB.s0)
		var fold := 0.1 * s
		var vt: Array = []
		for ry in 2:
			var row: Array = []
			for cx in 3:
				row.append(p + u2 * (cx - 1) * 0.5 * s + Vector3.UP * (ry - 0.5) * s + d * (fold * (1.0 - absf(cx - 1))))
			vt.append(row)
		for cx in 2:
			for tri in [[Vector2i(cx, 0), Vector2i(cx + 1, 0), Vector2i(cx + 1, 1)], [Vector2i(cx, 0), Vector2i(cx + 1, 1), Vector2i(cx, 1)]]:
				for e in [tri[0], tri[2], tri[1]]:
					var q: Vector3 = vt[e.y][e.x]
					var o := q / R
					var depth := clampf(o.length(), 0.0, 1.0)
					var ao := (0.4 + 0.6 * smoothstep(0.05, 1.0, depth)) * (0.7 + 0.3 * clampf(o.y * 0.5 + 0.5, 0.0, 1.0))
					b.vert(q, (o.normalized() * 0.75 + d * 0.25).normalized(), ao, Vector2(e.x * 0.5, 1.0 - e.y))
	return b.commit()
