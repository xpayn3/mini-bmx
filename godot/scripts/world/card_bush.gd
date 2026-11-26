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
	if kind == "leaf":
		m.set_shader_parameter("albedo", Vector3.ONE * leaf_gain())
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

static func _photo_leaf() -> bool:
	return ResourceLoader.exists(LEAF_PNG) and OS.get_environment("BMX_OLD_TREES_TEX") != "1"

## the photo card is brighter than the drawn one: this keeps the bushes' / crowns' overall tone
static func leaf_gain() -> float:
	return 0.72 if _photo_leaf() else 1.0

static func texture(kind: String) -> Texture2D:
	if _tex.has(kind):
		return _tex[kind]
	if kind == "leaf" and _photo_leaf():
		_tex[kind] = load(LEAF_PNG)
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


static func mesh(variant: String = "bush") -> ArrayMesh:
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
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m
