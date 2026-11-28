class_name CardBush
extends RefCounted
## Leaf-card bushes: ~30-45 curved upright quads on a dome, each carrying a procedural leaf-cluster texture with an
## alpha cut-out (~120-180 triangles a bush, the old blob was 320). Every card stands vertical and is turned at random
## about the vertical, its front facing away from the bush's middle. Normals are bent toward the dome so the bush
## lights as one soft volume; vertex colour holds a baked "deeper inside = darker" AO.
## Unit size ~1 m radius, base at y = 0, like the old blob. Look: res://scripts/world/deco_cards.gdshader.
## Variants (mesh / list names in TerrainGeo + TerrainChunkBuilder): bush (round), bush1 (low + wide), bush2 (tall +
## loose), bushdry (dry shrub: small grey leaves + twigs, for the dry biomes). BMX_OLD_BUSH=1 = the old blobs.

const TEX := 256

## cards, dome centre y + radii, card size range, top limit, texture, seed
const VARIANTS := {
	"bush": {"cards": 40, "cy": 0.42, "r": Vector3(0.95, 0.78, 0.95), "s0": 0.62, "s1": 1.02, "top": 1.05, "tex": "leaf", "seed": 5150},
	"bush1": {"cards": 46, "cy": 0.3, "r": Vector3(1.2, 0.55, 1.2), "s0": 0.5, "s1": 0.85, "top": 0.85, "tex": "leaf", "seed": 777},
	"bush2": {"cards": 34, "cy": 0.58, "r": Vector3(0.72, 1.0, 0.72), "s0": 0.7, "s1": 1.15, "top": 1.5, "tex": "leaf", "seed": 31},
	"bushdry": {"cards": 28, "cy": 0.32, "r": Vector3(1.0, 0.6, 1.0), "s0": 0.5, "s1": 0.85, "top": 0.85, "tex": "dry", "seed": 99},
}

static var _tex := {}
static var _mat := {}


## the material of a texture kind ("leaf" | "dry")
static func material(kind: String = "leaf") -> ShaderMaterial:
	if _mat.has(kind):
		return _mat[kind]
	var m := ShaderMaterial.new()
	m.shader = preload("res://scripts/world/deco_cards.gdshader")
	m.set_shader_parameter("leaf_tex", texture(kind))
	# shell cards face every way: light the bush as one volume from both sides (as the crowns do)
	m.set_shader_parameter("volume_normals", shell_enabled())
	if kind == "leaf":
		m.set_shader_parameter("albedo", Vector3.ONE * leaf_gain() * (1.12 if shell_enabled() else 1.0))   # (a touch lighter: the bushes read as dark blobs)
		var nt := leaf_normal()
		if nt:
			m.set_shader_parameter("nrm_tex", nt)
			m.set_shader_parameter("use_nrm", true)
	if kind == "dry":
		m.set_shader_parameter("roughness", 0.9)
		m.set_shader_parameter("sway", 0.02)
		m.set_shader_parameter("scatter", 0.5)
		m.set_shader_parameter("backlight", 0.2)
	_mat[kind] = m
	return m


## leaves on transparent ground (grey-green so the instance colour tints them); "dry" = small narrow leaves + twigs
## the green leaf card from photos (assets/textures/tree_cards/leaf_cluster.png: ambientCG LeafSet005 leaves composed by
## root tools/make_tree_cards.py, BC7 + mipmaps; shared with the leafy card-tree crowns); without it, drawn here
const LEAF_PNG := "res://assets/textures/tree_cards/leaf_cluster.png"

## textures.com European Beech twigs (gitignored: made locally by tools/make_tree_cards.py; see its header) + their
## normal (RGB) / translucency (A) map in the same layout; used instead of LEAF_PNG when present
const BEECH_PNG := "res://assets/textures/tree_cards/leaf_beech.png"
const BEECH_N_PNG := "res://assets/textures/tree_cards/leaf_beech_n.png"

static func _photo_leaf() -> bool:
	return (ResourceLoader.exists(LEAF_PNG) or _beech()) and Env.raw("BMX_OLD_TREES_TEX") != "1"

static func _beech() -> bool:
	return ResourceLoader.exists(BEECH_PNG) and ResourceLoader.exists(BEECH_N_PNG) and Env.raw("BMX_NO_BEECH") != "1"

## the leafy crowns' card: the same foliage as a dense seamless patch (repeated across big cards, deco_cards tile_m)
const TILE_PNG := "res://assets/textures/tree_cards/leaf_tile.png"
const BEECH_TILE_PNG := "res://assets/textures/tree_cards/leaf_beech_tile.png"
const BEECH_TILE_N_PNG := "res://assets/textures/tree_cards/leaf_beech_tile_n.png"

static func _beech_tile() -> bool:
	return ResourceLoader.exists(BEECH_TILE_PNG) and ResourceLoader.exists(BEECH_TILE_N_PNG) and Env.raw("BMX_NO_BEECH") != "1"

## [albedo, normal / translucency or null] for crowns; [] = no photo tile (use the bush card)
static func tile_textures() -> Array:
	if Env.raw("BMX_OLD_TREES_TEX") == "1":
		return []
	if _beech_tile():
		return [load(BEECH_TILE_PNG), load(BEECH_TILE_N_PNG)]
	if ResourceLoader.exists(TILE_PNG):
		return [load(TILE_PNG), null]
	return []

## the green leaf card's normal / translucency map, or null (no beech atlas)
static func leaf_normal() -> Texture2D:
	return load(BEECH_N_PNG) if _beech() and Env.raw("BMX_OLD_TREES_TEX") != "1" else null

## the photo card is brighter than the drawn one: this keeps the bushes' / crowns' overall tone
static func leaf_gain() -> float:
	return 0.72 if _photo_leaf() else 1.0

static func texture(kind: String) -> Texture2D:
	if _tex.has(kind):
		return _tex[kind]
	if kind == "leaf" and _photo_leaf():
		_tex[kind] = load(BEECH_PNG if _beech() else LEAF_PNG)
		return _tex[kind]
	var img := Image.create(TEX, TEX, true, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	if kind == "dry":
		img.fill(Color(0.7, 0.7, 0.58, 0.0))
		rng.seed = 4711
		_twigs(img, rng, 16)
		_leaves(img, rng, 190, 0.045, 0.07, 0.3, 0.42, 0.34, 0.55, 0.5, Vector3(0.98, 1.0, 0.86))
	else:
		img.fill(Color(0.62, 0.74, 0.5, 0.0))   # transparent texels carry leaf colour: no dark fringe in the mips
		rng.seed = 90210
		_leaves(img, rng, 120, 0.085, 0.145, 0.34, 0.48, 0.36, 0.62, 0.5, Vector3(1.0, 1.0, 0.9))
	img.generate_mipmaps()
	img.compress(Image.COMPRESS_S3TC)   # (DXT5 with its mips: a quarter of the memory of raw RGBA)
	var t := ImageTexture.create_from_image(img)
	_tex[kind] = t
	return t


static func _leaves(img: Image, rng: RandomNumberGenerator, count: int, l0: float, l1: float, w0: float, w1: float,
		spread: float, g0: float, gspan: float, tint: Vector3) -> void:
	for i in count:
		# centre inside a rounded blob, so the card's edge is ragged leaf tips, never a hard rectangle
		var a := rng.randf() * TAU
		var r := sqrt(rng.randf()) * TEX * spread
		var c := Vector2(TEX * 0.5, TEX * 0.5) + Vector2(cos(a), sin(a)) * r
		var ang := rng.randf() * TAU
		var len := TEX * (l0 + rng.randf() * (l1 - l0))
		var wid := len * (w0 + rng.randf() * (w1 - w0))
		var g := g0 + rng.randf() * gspan
		var warm := rng.randf() * 0.12
		var dir := Vector2(cos(ang), sin(ang))
		var side := Vector2(-dir.y, dir.x)
		var ext := int(len + 2)
		for py in range(maxi(int(c.y) - ext, 0), mini(int(c.y) + ext, TEX - 1)):
			for px in range(maxi(int(c.x) - ext, 0), mini(int(c.x) + ext, TEX - 1)):
				var d := Vector2(px + 0.5, py + 0.5) - c
				var u := d.dot(dir) / len + 0.5   # 0 stem .. 1 tip
				if u < 0.0 or u > 1.0:
					continue
				var v := d.dot(side) / wid
				var half := sin(PI * pow(u, 0.8)) * 0.5   # lens outline, fatter towards the stem
				if absf(v) > half:
					continue
				var rib := 1.0 + 0.22 * (1.0 - smoothstep(0.0, 0.07, absf(v)))   # lighter midrib
				var shade := g * rib * (0.78 + 0.3 * u) * (0.94 + 0.12 * (v / maxf(half, 0.01)))
				img.set_pixel(px, py, Color(shade * tint.x * (1.0 + warm), shade * tint.y, shade * tint.z * (1.0 - warm * 0.5), 1.0))


## thin brown twigs radiating from near the bottom middle of the card
static func _twigs(img: Image, rng: RandomNumberGenerator, count: int) -> void:
	for i in count:
		var p := Vector2(TEX * (0.4 + rng.randf() * 0.2), TEX * (0.78 + rng.randf() * 0.12))
		var ang := -PI / 2.0 + rng.randf_range(-1.1, 1.1)
		var len := TEX * (0.25 + rng.randf() * 0.3)
		var shade := 0.4 + rng.randf() * 0.2
		for s in int(len):
			p += Vector2(cos(ang), sin(ang))
			ang += rng.randf_range(-0.12, 0.12)
			for dy in 2:
				for dx in 2:
					var x := int(p.x) + dx
					var y := int(p.y) + dy
					if x >= 0 and y >= 0 and x < TEX and y < TEX:
						img.set_pixel(x, y, Color(shade * 1.1, shade * 0.9, shade * 0.7, 1.0))


## Shell bushes (2026-11-27, user: "bushes are too bad quality"): the old 30-46 big upright cards read as a few flat
## pictures, thin from above. Like scanned / SpeedTree bushes: ~3x more, smaller twig cards laid along the bush's outer
## shell, each facing out of it (tilted only as far as the shell is: the top ones look up, the sides out) with its twig
## growing outward from its base (the photo's stems are at the bottom of the card), turned / mirrored at random, some
## reaching past the outline for a ragged edge; an inner core of upright cards in shade gives it depth. ~4 triangles a card.
## It is the near LOD (LOD0, CardTree.add_twin: full to 36 m, gone by 48 m, ~4-650 triangles a bush); past it and in
## the shadow pass the upright-card bush (`mesh`, ~160 triangles) as before. BMX_OLD_BUSH2=1 = no near LOD.
const SHELL := {
	"bush": {"shell": 120, "core": 34, "s0": 0.3, "s1": 0.5},
	"bush1": {"shell": 130, "core": 34, "s0": 0.27, "s1": 0.45},
	"bush2": {"shell": 108, "core": 30, "s0": 0.32, "s1": 0.52},
	"bushdry": {"shell": 84, "core": 22, "s0": 0.28, "s1": 0.46},
}

static var _shell := {}

static func shell_enabled() -> bool:
	return Env.raw("BMX_OLD_BUSH2") != "1"

## LOD1 (everywhere, + the shadow caster): the upright-card bush
static func mesh(variant: String = "bush") -> ArrayMesh:
	return _mesh_upright(variant)

## LOD0 near the rider (cached)
static func shell_mesh(variant: String) -> ArrayMesh:
	if not _shell.has(variant):
		_shell[variant] = _mesh_shell(variant)
	return _shell[variant]

static func _mesh_shell(variant: String) -> ArrayMesh:
	var V: Dictionary = VARIANTS[variant]
	var S: Dictionary = SHELL[variant]
	var dc := Vector3(0, V.cy, 0)
	var dr: Vector3 = V.r
	var top: float = V.top
	var rng := RandomNumberGenerator.new()
	rng.seed = int(V.seed) + 17
	var b := CardTree._Buf.new()
	var n: int = int(S.shell) + int(S.core)
	for k in n:
		# a direction over the dome (golden-angle azimuth + jitter: even cover, no bald patch), filled through the
		# volume but thickest towards the outside (that is what you see; the inside is shade between the twigs)
		var fy := rng.randf_range(-0.3, 1.0)
		var az := k * 2.39996 + rng.randf_range(-0.4, 0.4)
		var ry := sqrt(maxf(1.0 - fy * fy, 0.0))
		var dir := Vector3(cos(az) * ry, fy, sin(az) * ry)
		var rad := 0.25 + 0.75 * pow(rng.randf(), 0.45)
		var core := rad < 0.55
		var p := dc + dir * rad * dr
		if p.y < 0.04:
			p.y = rng.randf_range(0.04, 0.2)
		# the shell's outward normal at that point (an ellipsoid's: dir / r^2)
		var nout := Vector3(dir.x / dr.x, dir.y / dr.y, dir.z / dr.z).normalized()
		var s: float = rng.randf_range(S.s0, S.s1) * (0.8 if core else 1.0)
		# the card's front: mostly upright, turned roughly out of the bush; on the top it tips up towards the sky
		# (at most ~45 deg: cards lying flat smear seen from the side)
		var ra := rng.randf() * TAU
		var h := (Vector3(dir.x, 0, dir.z) * 0.9 + Vector3(cos(ra), 0, sin(ra)) * 0.7)
		if h.length() < 0.05:
			h = Vector3(cos(ra), 0, sin(ra))
		h = h.normalized()
		var tilt := clampf(nout.y, 0.0, 1.0) * 0.6 + rng.randf_range(-0.1, 0.1)
		var face := (h * cos(tilt) + Vector3.UP * sin(tilt)).normalized()
		# its stem (texture bottom) -> tip (texture top) axis: world up laid in the card, leaning a little at random
		var up := (Vector3.UP - face * face.y).normalized().rotated(face, rng.randf_range(-0.5, 0.5))
		var side := up.cross(face).normalized()
		# the base sits a little inside, the tip may reach past the outline
		var c := p + up * s * (0.15 if core else rng.randf_range(0.05, 0.25))
		c.y = clampf(c.y, s * 0.35 + 0.02, maxf(top - s * 0.2, s * 0.35 + 0.03))
		var flip := 1.0 if rng.randf() < 0.5 else -1.0   # mirrored cards: the one photo reads as many twigs
		var fold := 0.12 * s
		var g: Array = []   # 3 x 2: rows base / tip, columns across
		for ry2 in 2:
			var row: Array = []
			for cx in 3:
				var q := c + side * (cx - 1) * 0.5 * s + up * (ry2 - 0.5) * s + face * (fold * (1.0 - absf(cx - 1)))
				q.y = maxf(q.y, 0.02)
				row.append(q)
			g.append(row)
		for cx in 2:
			for tri in [[Vector2i(cx, 0), Vector2i(cx + 1, 0), Vector2i(cx + 1, 1)], [Vector2i(cx, 0), Vector2i(cx + 1, 1), Vector2i(cx, 1)]]:
				for e in [tri[0], tri[2], tri[1]]:
					var q: Vector3 = g[e.y][e.x]
					var o := (q - dc) / dr
					var depth := clampf(o.length(), 0.0, 1.1)
					var ao := (0.42 + 0.58 * smoothstep(0.15, 1.0, depth)) * (0.75 + 0.25 * clampf(q.y / maxf(top, 0.5), 0.0, 1.0))
					if core:
						ao *= 0.85
					var nrm := (o.normalized() * 0.65 + face * 0.35).normalized()
					var u: float = 0.5 + (e.x * 0.5 - 0.5) * flip
					b.vert(q, nrm, ao, Vector2(u, 1.0 - e.y), s)
	return b.commit()


static func _mesh_upright(variant: String) -> ArrayMesh:
	var V: Dictionary = VARIANTS[variant]
	var dome_c := Vector3(0, V.cy, 0)
	var dome_r: Vector3 = V.r
	var rng := RandomNumberGenerator.new()
	rng.seed = V.seed
	var pos := PackedVector3Array()
	var nor := PackedVector3Array()
	var col := PackedColorArray()
	var uv := PackedVector2Array()
	for k in int(V.cards):
		# a point in the dome, mostly towards its shell (that is the part you see)
		var dir := Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.15, 1), rng.randf_range(-1, 1)).normalized()
		var rad := 0.3 + 0.7 * pow(rng.randf(), 0.55)
		var p := dome_c + dir * rad * dome_r
		# every card stands upright; only its turn about the vertical is random (the front side is the one facing
		# away from the bush's middle, so the dome normals stay right)
		var yaw := rng.randf() * TAU
		var d := Vector3(cos(yaw), 0, sin(yaw))
		if d.dot(Vector3(dir.x, 0, dir.z)) < 0.0:
			d = -d
		var u2 := Vector3.UP.cross(d).normalized()
		var v2 := Vector3.UP
		var s: float = V.s0 + rng.randf() * (V.s1 - V.s0)
		p.y = clampf(p.y, s * 0.5 + 0.02, maxf(float(V.top) - s * 0.5, s * 0.5 + 0.03))   # bottom on the ground, top inside the dome
		# two halves folded along the middle (a curved card): columns x = -s/2, 0, +s/2, rows y = -s/2, +s/2
		var fold := 0.1 * s
		var vt: Array = []   # [row][col] -> position
		for ry in 2:
			var row: Array = []
			for cx in 3:
				var fx := (cx - 1) * 0.5 * s
				var fy := (ry - 0.5) * s
				var q := p + u2 * fx + v2 * fy + d * (fold * (1.0 - absf(cx - 1)))
				q.y = maxf(q.y, 0.02)
				row.append(q)
			vt.append(row)
		var quad := func(a: Vector2i, b: Vector2i, c: Vector2i) -> void:
			# front faces look along +d: Godot's front is clockwise, so reverse the counter-clockwise order
			for e in [a, c, b]:
				var q: Vector3 = vt[e.y][e.x]
				var out := (q - dome_c) / dome_r
				var depth := clampf(out.length(), 0.0, 1.0)
				var ao := (0.4 + 0.6 * smoothstep(0.05, 1.0, depth)) * (0.72 + 0.28 * clampf(q.y / 0.9, 0.0, 1.0))
				pos.append(q)
				nor.append((out.normalized() * 0.7 + d * 0.3).normalized())
				col.append(Color(ao, ao, ao))
				uv.append(Vector2(e.x * 0.5, 1.0 - e.y))
		for cx in 2:
			quad.call(Vector2i(cx, 0), Vector2i(cx + 1, 0), Vector2i(cx + 1, 1))
			quad.call(Vector2i(cx, 0), Vector2i(cx + 1, 1), Vector2i(cx, 1))
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = pos
	arr[Mesh.ARRAY_NORMAL] = nor
	arr[Mesh.ARRAY_COLOR] = col
	arr[Mesh.ARRAY_TEX_UV] = uv
	var st := SurfaceTool.new()
	st.create_from_arrays(arr)
	st.generate_tangents()   # (the leaf card's normal map)
	return st.commit()
