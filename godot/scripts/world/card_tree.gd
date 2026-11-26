class_name CardTree
extends RefCounted
## Card trees (2026-11-26): every tree crown is leaf cards, built like the bushes (card_bush.gd) from upright /
## drooping quads with an alpha cut-out photo texture. Three levels, all from the same trees (user: "no low poly trees,
## use our new ones and make LODs from them"):
##   LOD0 pineCard / blobCard        near: full cards (fade_mode 4: full to 36 m from the rider, gone by 48 m)
##   LOD1 pineCardLod1 / blobCardLod1 the rest of the way: ~1/3 the cards, bigger (fade_mode 3)
##   (no card casts a shadow: an invisible solid crown does, add_shadow_proxy)
##   LOD2 billboards                 from ~72-88 m: one quad per crown with a crown-only cell of impostors.png (baked from
##                                   LOD0 by tools/bake_tree_impostors.tscn; tree_billboard.gdshader, fade_mode 5); past the
##                                   loaded chunks the backdrop's whole-tree billboards take over (world/far_hills.gd)
## TerrainGeo's "pine" / "blob" meshes and "leaf" / "leafSoft" materials ARE LOD1 (every crown list draws it), and
## Terrain / LevelVisuals add the LOD0 twin on the same instance buffer; LOD0 and LOD1 swap per pixel by one dither
## (shaders/deco_fade.gdshaderinc). All meshes fill the old solid crowns' unit space, so instance transforms are shared:
##   pine: base radius ~1 at y 0, tip at y 2.8      blob: a ball of radius ~1 round the origin
## Pines also get their trunk up through the crown (pineSpire). BMX_OLD_TREES=1 = the old solid crowns, no cards.

## a chunk's card twins are drawn only while the camera is this close to the chunk's middle: the card band's end (48 m,
## deco_fade.gdshaderinc CARD_OUT) + half a chunk's diagonal (34 m) + the camera's distance from the rider
const CHUNK_VIS := 100.0

const TEX_W := 256
const TEX_H := 128

## pine crown: whorls of drooping branch cards up the axis
const PINE_TOP := 2.85
## [whorls, branches x, card width x, seed, droop x]: LOD0 / LOD1
const PINE_LOD := [[24, 1.0, 1.0, 1979, 1.0], [14, 0.5, 1.5, 1980, 1.7]]   # ([0] < 20 = LOD1: tip tufts only)
## leafy crown: cards in a ball (CardBush's recipe without the ground)
const BLOB := {"cards": 130, "r": Vector3(1.0, 0.95, 1.0), "s0": 0.34, "s1": 0.55, "seed": 4242}
## metres of foliage one leaf picture covers (leaf_cluster / leaf_beech are made at real leaf size for this): a leafy
## crown's card repeats it round(card size / this) times each way (deco_cards tile_m; card size from COLOR.a x the crown)
const LEAF_TILE_M := 0.8
## LOD1: this many cards, this much bigger
const BLOB_LOD1 := [48, 1.5]

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
	add_spire(solid, solid_mesh)
	add_billboard(solid, solid_mesh)
	add_shadow_proxy(solid, solid_mesh)
	return mi


## The trees' sun shadow (2026-11-26): at real size, casting it from the LOD1 cards (layers of alpha-tested quads in
## every cascade) cost ~4-5 ms of GPU; instead the crown list casts nothing and an invisible solid crown (the old
## low-poly one, shadows only, with its dappled holes: deco.gdshader `dapple`) throws each tree's shadow.
static func add_shadow_proxy(crown: MultiMeshInstance3D, solid_mesh: String) -> MultiMeshInstance3D:
	if not solid_mesh in ["pine", "blob"]:
		return null
	TerrainGeo.ensure()
	var pm := MultiMesh.new()
	pm.transform_format = MultiMesh.TRANSFORM_3D
	pm.use_custom_data = crown.multimesh.use_custom_data
	pm.use_colors = crown.multimesh.use_colors
	pm.mesh = TerrainGeo.MESH["pineSolid" if solid_mesh == "pine" else "blobSolid"]
	pm.instance_count = crown.multimesh.instance_count
	pm.buffer = crown.multimesh.buffer
	var pi := MultiMeshInstance3D.new()
	pi.name = String(crown.name) + "_shadow"
	pi.multimesh = pm
	pi.material_override = TerrainGeo.MAT["leafSolid" if solid_mesh == "pine" else "leafSoftSolid"]
	pi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	crown.get_parent().add_child(pi)
	pi.transform = crown.transform
	pi.set_instance_shader_parameter("fade_mode", 1.0)
	pi.set_meta("cast_on", GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY)   # (Terrain's far-shadow switch)
	crown.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	crown.set_meta("shadow_proxy", pi)
	return pi


const IMPOSTOR_PNG := "res://assets/textures/tree_cards/impostors.png"
static var _bb := {}   # kind -> [quad mesh, material]

## the crown list's billboard LOD (fade_mode 5): same instance buffer, no shadow (LOD1 casts it)
static func add_billboard(crown: MultiMeshInstance3D, solid_mesh: String) -> MultiMeshInstance3D:
	var b := _billboard(solid_mesh)
	if b.is_empty():
		return null
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = crown.multimesh.use_custom_data
	mm.use_colors = crown.multimesh.use_colors
	mm.mesh = b[0]
	mm.instance_count = crown.multimesh.instance_count
	mm.buffer = crown.multimesh.buffer
	var mi := MultiMeshInstance3D.new()
	mi.name = String(crown.name) + "_billboard"
	mi.multimesh = mm
	mi.material_override = b[1]
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	crown.get_parent().add_child(mi)
	mi.transform = crown.transform
	mi.set_instance_shader_parameter("fade_mode", 5.0)
	return mi


## [quad mesh, material] for "pine" / "blob" crowns from the atlas' crown cells, [] without them
static func _billboard(solid_mesh: String) -> Array:
	var kind := "pine_crown" if solid_mesh == "pine" else "leafy_crown"
	if _bb.has(kind):
		return _bb[kind]
	_bb[kind] = []
	if not ResourceLoader.exists(IMPOSTOR_PNG):
		return []
	var j = JSON.parse_string(FileAccess.get_file_as_string(IMPOSTOR_PNG.get_basename() + ".json"))
	if not j is Dictionary:
		return []
	var first := -1
	var n := 0
	var q := Vector3.ZERO
	var cells: Array = j.get("trees", [])
	for i in cells.size():
		if cells[i].kind == kind:
			if first < 0: first = i
			n += 1
			q += Vector3(float(cells[i].y0), float(cells[i].h), float(cells[i].w))
	if n == 0:
		return []
	q /= n
	# the quad's box in the instance's own units (the shader places it; this is what the culling sees)
	var a := []
	a.resize(Mesh.ARRAY_MAX)
	a[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3(-q.z * 0.5, q.x, -q.z * 0.5), Vector3(q.z * 0.5, q.x, q.z * 0.5),
		Vector3(q.z * 0.5, q.x + q.y, q.z * 0.5), Vector3(-q.z * 0.5, q.x + q.y, -q.z * 0.5)])
	a[Mesh.ARRAY_TEX_UV] = PackedVector2Array([Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)])
	a[Mesh.ARRAY_NORMAL] = PackedVector3Array([Vector3.BACK, Vector3.BACK, Vector3.BACK, Vector3.BACK])
	a[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 2, 1, 0, 3, 2])
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a)
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://scripts/world/tree_billboard.gdshader")
	mat.set_shader_parameter("atlas", load(IMPOSTOR_PNG))
	mat.set_shader_parameter("cells", float(j.get("cells", 8)))
	mat.set_shader_parameter("cell0", float(first))
	mat.set_shader_parameter("variants", float(n))
	mat.set_shader_parameter("quad", q)
	mat.set_shader_parameter("sway", 0.02 if solid_mesh == "pine" else 0.035)
	_bb[kind] = [m, mat]
	return _bb[kind]


## a pine crown list's trunk up through its see-through crown, tapering to the tip (it stopped at the crown's foot: the
## crown floated on a stump). Drawn with both card levels (fade_mode 1: the decorations' far fade), no shadow.
## (blob crowns: their branches, blobLimbs)
static func add_spire(crown: MultiMeshInstance3D, solid_mesh := "pine", internal := false) -> MultiMeshInstance3D:
	if not enabled() or not solid_mesh in ["pine", "blob"]:
		return null
	var sm := MultiMesh.new()
	sm.transform_format = MultiMesh.TRANSFORM_3D
	sm.use_custom_data = crown.multimesh.use_custom_data
	sm.use_colors = crown.multimesh.use_colors
	sm.mesh = mesh("pineSpire" if solid_mesh == "pine" else "blobLimbs")
	var limb_mat := material("spire" if solid_mesh == "pine" else "limbs")
	sm.instance_count = crown.multimesh.instance_count
	sm.buffer = crown.multimesh.buffer
	var si := MultiMeshInstance3D.new()
	si.name = String(crown.name) + "_spire"
	si.multimesh = sm
	si.material_override = limb_mat
	si.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if internal:
		crown.get_parent().add_child(si, false, Node.INTERNAL_MODE_BACK)
	else:
		crown.get_parent().add_child(si)
	si.transform = crown.transform
	si.set_instance_shader_parameter("fade_mode", 1.0)
	return si


static func material(kind: String) -> ShaderMaterial:
	if _mat.has(kind):
		return _mat[kind]
	if kind == "spire" or kind == "limbs":   # the pine / leafy bark, without the crown's green instance colour
		TerrainGeo.ensure()
		var b: ShaderMaterial = TerrainGeo.MAT["trunk_pine" if kind == "spire" else "trunk"].duplicate()
		b.set_shader_parameter("use_instance", false)
		_mat[kind] = b
		return b
	var m := ShaderMaterial.new()
	m.shader = preload("res://scripts/world/deco_cards.gdshader")
	m.set_shader_parameter("volume_normals", true)
	m.set_shader_parameter("specular", 0.1)
	if kind == "needle":
		m.set_shader_parameter("leaf_tex", texture("needle"))
		m.set_shader_parameter("sway", 0.02)
		m.set_shader_parameter("flutter", 0.003)
		m.set_shader_parameter("backlight", 0.25)
		m.set_shader_parameter("scatter", 0.6)
		m.set_shader_parameter("roughness", 0.85)
		m.set_shader_parameter("cutoff", 0.45)
		m.set_shader_parameter("albedo", Vector3(1.2, 1.2, 1.2))
	else:
		var tiles := CardBush.tile_textures()
		if tiles.is_empty():   # (no photo patch: the bushes' clump card, one per card)
			m.set_shader_parameter("leaf_tex", CardBush.texture("leaf"))
		else:
			m.set_shader_parameter("leaf_tex", tiles[0])
			m.set_shader_parameter("tile_m", LEAF_TILE_M)
			if tiles[1]:
				m.set_shader_parameter("nrm_tex", tiles[1])
				m.set_shader_parameter("use_nrm", true)
		m.set_shader_parameter("sway", 0.035)
		m.set_shader_parameter("flutter", 0.006)
		m.set_shader_parameter("backlight", 0.35)
		m.set_shader_parameter("scatter", 0.85)
		m.set_shader_parameter("albedo", CardBush.leaf_gain() * Vector3(1.25, 1.18, 1.3))   # (the bushes' card, a little brighter for crowns)
	_mat[kind] = m
	return m


## a pine branch on a transparent card: the stem along u (0 at the trunk .. 1 at the tip), side shoots, needles
## the photo branch (assets/textures/tree_cards/needle_branch.png: ambientCG PineNeedles001 needle bundles stamped along a
## twig by root tools/make_tree_cards.py, BC7 + mipmaps); without the file, drawn here
const NEEDLE_PNG := "res://assets/textures/tree_cards/needle_tuft.png"   # (a fan of needle twigs: the pines' tufts)

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
			"pineCard": _mesh[name] = _pine(PINE_LOD[0])
			"pineCardLod1": _mesh[name] = _pine(PINE_LOD[1])
			"blobCardLod1": _mesh[name] = _blob(int(BLOB_LOD1[0]), float(BLOB_LOD1[1]))
			"trunkFlare": _mesh[name] = _trunk_flare()
			"blobLimbs": _mesh[name] = _blob_limbs()
			"pineSpire": _mesh[name] = _pine_wood()
			_: _mesh[name] = _blob(int(BLOB.cards), 1.0)
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

	## size: the card's size in the mesh's units (COLOR.a: leafy crowns repeat their foliage picture by it, deco_cards tile_m)
	func vert(p: Vector3, n: Vector3, ao: float, t: Vector2, size := 1.0) -> void:
		pos.append(p); nor.append(n); col.append(Color(ao, ao, ao, size)); uv.append(t)

	## a tapering tube along pts (radii per point), `sides` round, bark-ready (the deco shader maps bark in world space)
	func tube(pts: Array, radii: Array, sides: int, ao0: float, ao1: float) -> void:
		var rings := []
		for i in pts.size():
			var d: Vector3 = (pts[mini(i + 1, pts.size() - 1)] - pts[maxi(i - 1, 0)]).normalized()
			var a := Vector3.RIGHT if absf(d.dot(Vector3.UP)) > 0.9 else Vector3.UP
			var u := d.cross(a).normalized()
			var v := d.cross(u)
			var ring := []
			for k in sides:
				var t := TAU * k / sides
				var n := u * cos(t) + v * sin(t)
				ring.append([pts[i] + n * float(radii[i]), n])
			rings.append(ring)
		for i in pts.size() - 1:
			var ao := lerpf(ao0, ao1, float(i) / maxf(pts.size() - 2, 1))
			for k in sides:
				var k2 := (k + 1) % sides
				for e in [[i, k], [i + 1, k2], [i + 1, k], [i, k], [i, k2], [i + 1, k2]]:
					var q: Array = rings[e[0]][e[1]]
					vert(q[0], q[1], ao, Vector2(float(e[1]) / sides, float(e[0])))

	func commit() -> ArrayMesh:
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


## A pine crown as real branches carrying needle TUFTS (2026-11-26, user: realistic pines with clumped foliage, sky and
## trunk showing between the clumps, ragged outline): PINE_BRANCHES spiral up the crown (golden angle), each of random
## length / droop / rise, ~18 % missing (gaps); along its outer half 2-4 tufts (the needle_tuft fan, laid along the branch:
## one card lying flat, one upright, so a tuft reads from every side). The branches themselves are bark tubes in the
## trunk mesh (pineSpire). LOD1: the same branches, only the tip tuft, larger. The crown instance is stretched taller than
## wide (y scale / x scale ~ ASPECT for real crowns), so vertical sizes are pre-squeezed by it (tufts come out undistorted).
const PINE_BRANCHES := 90
const ASPECT := 1.5
const PINE_LOD_SEED := 1979

## the crown's outline: radius (unit space) at height y, ragged by branch
static func pine_env(y: float) -> float:
	return 1.25 * pow(maxf(0.0, 1.0 - y / 2.95), 0.95)

## the branch layout both the tufts and the bark limbs use: [root, dir (unit, horizontal-ish), length, pitch]
static func pine_branches() -> Array:
	if _mesh.has("_branches"):
		return _mesh["_branches"]
	var out := []
	var rng := RandomNumberGenerator.new()
	rng.seed = PINE_LOD_SEED
	for k in PINE_BRANCHES:
		var t := (k + 0.5) / PINE_BRANCHES
		var y := 0.03 + t * 2.55 + rng.randf_range(-0.03, 0.03)
		var gone := rng.randf() < 0.12 and t < 0.85
		var a := k * 2.39996 + rng.randf_range(-0.3, 0.3)
		var ln := pine_env(y) * rng.randf_range(0.6, 1.15)
		var pitch := lerpf(-0.35, 0.35, t) + rng.randf_range(-0.18, 0.18)   # low ones droop, high ones reach up
		if not gone:
			out.append([Vector3(0, y, 0), Vector3(cos(a), 0, sin(a)), maxf(ln, 0.12), pitch])
	_mesh["_branches"] = out
	return out

## where along a branch (0 root .. 1 tip) it is: gently curving (out, then the tip turning up)
static func branch_point(br: Array, t: float) -> Vector3:
	var root: Vector3 = br[0]
	var d: Vector3 = br[1]
	var ln: float = br[2]
	var pitch: float = br[3]
	var up := (sin(pitch) * t + 0.12 * t * t) * ln / ASPECT
	return root + d * cos(pitch) * ln * t + Vector3(0, up, 0)

static func _pine(lod: Array) -> ArrayMesh:
	var b := _Buf.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = int(lod[3])
	var lod1: bool = int(lod[0]) < 20
	for br in pine_branches():
		var ln: float = br[2]
		var n := 2 if lod1 else clampi(int(round(2.0 + ln * 3.5)), 3, 6)
		for q in n:
			var t := 1.0 - float(q) / maxf(n, 1) * 0.7
			var at := branch_point(br, t)
			var fwd := (branch_point(br, minf(t + 0.05, 1.0)) - branch_point(br, maxf(t - 0.05, 0.0))).normalized()
			if fwd.length() < 0.5: fwd = br[1]
			var size := ln * rng.randf_range(0.6, 0.85) * (1.0 - 0.3 * (1.0 - t)) * (1.4 if lod1 else 1.0)
			size = clampf(size, 0.2, 0.95)
			# (tufts off the branch's sides too, not all on its line)
			var side := fwd.cross(Vector3.UP).normalized() * rng.randf_range(-0.12, 0.12) * ln
			_tuft(b, at + side, (fwd + side * 0.8).normalized(), size, rng, at.y)
	# the leader: tufts pointing up at the top
	for k in (2 if lod1 else 3):
		var a := k * TAU / 3.0 + 0.4
		var fwd := Vector3(cos(a) * 0.35, 1.0, sin(a) * 0.35).normalized()
		_tuft(b, Vector3(0, 2.45, 0), fwd, 0.42, rng, 2.6)
	return b.commit()


## one tuft: two cards laid along `fwd` from `at` (the fan's root at u ~ 0.1): one lying flat-ish, one upright
static func _tuft(b: _Buf, at: Vector3, fwd: Vector3, size: float, rng: RandomNumberGenerator, y: float) -> void:
	var side := fwd.cross(Vector3.UP)
	if side.length() < 0.2: side = Vector3.RIGHT
	side = side.normalized()
	var up := side.cross(fwd).normalized()
	var roll := rng.randf_range(-0.45, 0.45)
	var flat := (side * cos(roll) + up * sin(roll)).normalized()   # the lying card's across
	for across in [flat, up]:
		var p0 := at - fwd * size * 0.1
		var p1 := at + fwd * size * 0.9
		var h: Vector3 = across * size * 0.5
		var corners := [p0 - h, p1 - h, p1 + h, p0 + h]
		var uvs := [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)]
		var cn: Vector3 = fwd.cross(across).normalized()
		for e in [0, 2, 1, 0, 3, 2]:
			var p: Vector3 = corners[e]
			p.y = at.y + (p.y - at.y) / ASPECT
			var radial := Vector3(p.x, 0, p.z)
			var rl := radial.length()
			var nrm := (radial / maxf(rl, 0.001) * 0.6 + Vector3(0, 0.5, 0) + cn * 0.25 * (1.0 if cn.y >= 0 else -1.0)).normalized()
			var reach := clampf(rl / maxf(pine_env(y), 0.2), 0.0, 1.0)
			var ao := (0.5 + 0.5 * smoothstep(0.0, 0.85, reach)) * (0.78 + 0.22 * clampf(p.y / PINE_TOP, 0.0, 1.0))
			b.vert(p, nrm, ao, uvs[e])


## a leafy crown: CardBush's upright folded cards in a ball (no ground clamp), dome normals, inside darker
## a leafy crown's clumps (unit ball space): [centre, radius]: one big middle-top lobe and 4 round it, overlapping, so the
## outline is lumpy like a real broadleaf crown; the branches (blobLimbs) run into them
static func blob_lobes() -> Array:
	if _mesh.has("_lobes"):
		return _mesh["_lobes"]
	var out := [[Vector3(0, 0.25, 0), 0.62]]
	var rng := RandomNumberGenerator.new()
	rng.seed = 5150
	for k in 5:
		var a := k * TAU / 5.0 + rng.randf_range(-0.35, 0.35)
		var r := rng.randf_range(0.45, 0.58)
		out.append([Vector3(cos(a) * (1.0 - r) * 1.05, rng.randf_range(-0.35, 0.2), sin(a) * (1.0 - r) * 1.05), r])
	_mesh["_lobes"] = out
	return out

static func _blob(cards: int, size_k: float) -> ArrayMesh:
	var b := _Buf.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = BLOB.seed
	var R: Vector3 = BLOB.r
	var lobes := blob_lobes()
	for k in cards:
		# a point in one of the lobes (weighted by size), mostly towards its shell
		var lb: Array = lobes[k % lobes.size()]
		var dir := Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.6, 1), rng.randf_range(-1, 1)).normalized()
		var rad := 0.35 + 0.65 * pow(rng.randf(), 0.5)
		var p: Vector3 = (lb[0] as Vector3) + dir * rad * float(lb[1]) * R
		var yaw := rng.randf() * TAU
		var d := Vector3(cos(yaw), 0, sin(yaw))
		if d.dot(Vector3(dir.x, 0, dir.z)) < 0.0:
			d = -d
		var u2 := Vector3.UP.cross(d).normalized()
		var s: float = (BLOB.s0 + rng.randf() * (BLOB.s1 - BLOB.s0)) * size_k
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
					b.vert(q, (o.normalized() * 0.75 + d * 0.25).normalized(), ao, Vector2(e.x * 0.5, 1.0 - e.y), s)
	return b.commit()


## the trunk (TerrainGeo "trunk": unit height, radius 0.16 at the foot .. 0.1 at the top, like the old cylinder) with its
## foot flaring out into ROOT_LOBES buttress roots (user: "roots on the bottom, it flares out"): over the lowest FLARE_H of
## its height the radius grows to ~2.6x at the ground, most of it in ridges running out from the trunk. The flare scales
## with the trunk's height (a tall forest pine gets a bigger one). Every tree's trunk uses it (BMX_OLD_TREES=1: not).
const ROOT_LOBES := 5
const FLARE_H := 0.1
const TRUNK_RINGS := [0.0, 0.01, 0.025, 0.05, 0.08, 0.12, 0.4, 1.0]
const TRUNK_SIDES := 15

static func _trunk_r(y: float, th: float) -> float:
	var r := lerpf(0.16, 0.1, y)
	var f := pow(maxf(0.0, 1.0 - y / FLARE_H), 2.0)
	var lobe := pow(maxf(0.0, cos(ROOT_LOBES * th + 0.7)), 2.5)
	return r * (1.0 + f * (0.7 + 2.3 * lobe))

static func _trunk_flare() -> ArrayMesh:
	var b := _Buf.new()
	var P := func(y: float, th: float) -> Vector3:
		var r := _trunk_r(y, th)
		return Vector3(sin(th) * r, y, cos(th) * r)
	var N := func(y: float, th: float) -> Vector3:
		var dth := 0.01
		var dy := 0.004
		var tth: Vector3 = P.call(y, th + dth) - P.call(y, th - dth)
		var ty: Vector3 = P.call(minf(y + dy, 1.0), th) - P.call(maxf(y - dy, 0.0), th)
		return ty.cross(tth).normalized()
	for i in TRUNK_RINGS.size() - 1:
		var y0: float = TRUNK_RINGS[i]
		var y1: float = TRUNK_RINGS[i + 1]
		for k in TRUNK_SIDES:
			var t0 := TAU * k / TRUNK_SIDES
			var t1 := TAU * (k + 1) / TRUNK_SIDES
			for e in [[y0, t0], [y1, t1], [y1, t0], [y0, t0], [y0, t1], [y1, t1]]:
				var y: float = e[0]
				var ao := 0.72 + 0.28 * smoothstep(0.0, FLARE_H, y)   # the ground's shade in the root hollows
				b.vert(P.call(y, e[1]), N.call(y, e[1]), ao, Vector2(e[1] / TAU, y))
	return b.commit()


## branches inside a leafy crown (TerrainGeo "blob" space: a ball of radius ~1 round the origin; user: "some branches for
## the leaf types"): the trunk carried up into the crown, splitting into LIMBS limbs reaching out toward the shell, each
## with a twig or two. Seen through the gaps of the card crowns. Bark like the trunk (CardTree material "spire").
const LIMBS := 5

static func _blob_limbs() -> ArrayMesh:
	var b := _Buf.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 6061
	# the leader: from below the crown (where the trunk mesh ends) up into the middle lobe
	var lead := [Vector3(0, -1.05, 0), Vector3(0.02, -0.6, 0.01), Vector3(-0.03, -0.15, 0.02), Vector3(0.0, 0.4, -0.02)]
	b.tube(lead, [0.07, 0.06, 0.045, 0.018], 6, 0.55, 0.85)
	# a limb into every side lobe, forking into twigs inside it
	var lobes := blob_lobes()
	for l in range(1, lobes.size()):
		var c: Vector3 = lobes[l][0]
		var p0 := Vector3(0, rng.randf_range(-0.7, -0.35), 0)
		var mid := p0.lerp(c, 0.5) + Vector3(0, 0.08, 0)
		var r0 := rng.randf_range(0.04, 0.055)
		b.tube([p0, mid, c], [r0, r0 * 0.7, r0 * 0.4], 5, 0.6, 0.9)
		for k in 3:
			var a := rng.randf() * TAU
			var e := c + Vector3(cos(a), rng.randf_range(0.0, 0.6), sin(a)).normalized() * float(lobes[l][1]) * rng.randf_range(0.5, 0.8)
			b.tube([c, c.lerp(e, 0.5) + Vector3(0, 0.03, 0), e], [r0 * 0.35, r0 * 0.22, 0.005], 4, 0.7, 0.9)
	return b.commit()



## Real-world tree sizes (2026-11-26, user: "leaves too big, realistic scales, trunk thickness and height, can vary").
## One place for the proportions every tree placer uses (world chunks, levels, the far backdrop). r1..r4 = random 0..1.
## Returns metres: "H" total height, "cb" where the crown starts, "R" crown radius, "rt" trunk radius at the foot (above
## the root flare), and the instance scales for TerrainGeo's unit meshes:
##   "trunk" = Vector3 scale of the trunk mesh (unit height, radius 0.16 at the foot), from the ground
##   "crown" = Vector3 scale of the crown mesh, "crown_y" = its origin above the ground (pine: crown foot, blob: middle)
## Pines (Scots pine / spruce): 9-22 m, a tall forest's 18-30 m with the crown in the top ~half, young ones 4-8 m; crown
## radius ~0.22-0.30 of its length. Leafy (beech-like): 10-20 m, young 4-8 m, crown 0.45-0.65 of the height wide.
## Trunk radius ~1.1-2 % of the height (a 20 m pine ~0.5 m across). Savanna: 5-9 m flat-topped. Snag: a dead pole.
static func dims(kind: String, r1: float, r2: float, r3: float, r4: float, tall := false, shrink := 0.0) -> Dictionary:
	var d := {}
	match kind:
		"pine":
			var young := r1 < 0.18 and not tall
			var H := lerpf(4.0, 8.0, r2) if young else (lerpf(18.0, 30.0, r2) if tall else lerpf(9.0, 22.0, pow(r2, 1.3)))
			H *= 1.0 - shrink
			var cbf := lerpf(0.45, 0.62, r3) if tall else (lerpf(0.05, 0.15, r3) if young else lerpf(0.15, 0.35, r3))
			var cb := H * cbf
			var L := H - cb
			var R := L * lerpf(0.22, 0.3, r4)
			var rt := H * lerpf(0.011, 0.016, r4) + 0.03
			d = {"H": H, "cb": cb, "R": R, "rt": rt, "trunk": Vector3(rt / 0.16, cb + L * 0.2, rt / 0.16),
				"crown": Vector3(R / 1.1, L / PINE_TOP, R / 1.1), "crown_y": cb}
		"leafy":
			var young := r1 < 0.2
			var H := lerpf(4.0, 8.0, r2) if young else lerpf(10.0, 20.0, pow(r2, 1.2))
			H *= 1.0 - shrink
			var a := H * lerpf(0.24, 0.32, r3)          # crown's vertical half-size
			var R := H * lerpf(0.22, 0.32, r4)          # crown radius
			var cy := H - a
			var rt := H * lerpf(0.014, 0.02, r4) + 0.03
			d = {"H": H, "cb": cy - a, "R": R, "rt": rt, "trunk": Vector3(rt / 0.16, cy - a * 0.3, rt / 0.16),
				"crown": Vector3(R / 1.3, a / 1.3, R / 1.3), "crown_y": cy}
		"savanna":
			var H := lerpf(5.0, 9.0, r2)
			var a := lerpf(0.8, 1.3, r3)
			var R := lerpf(3.0, 5.0, r4)
			var rt := lerpf(0.12, 0.2, r1)
			d = {"H": H, "cb": H - 2.0 * a, "R": R, "rt": rt, "trunk": Vector3(rt / 0.16, H - a, rt / 0.16),
				"crown": Vector3(R / 1.3, a / 1.3, R / 1.3), "crown_y": H - a}
		_:   # snag: a dead, bare pole
			var H := lerpf(6.0, 14.0, r2)
			var rt := H * 0.012 + 0.04
			d = {"H": H, "cb": H, "R": 0.0, "rt": rt, "trunk": Vector3(rt / 0.16, H, rt / 0.16), "crown": Vector3.ZERO, "crown_y": H}
	return d


## dims() for a tree known by its place (level trees, the far backdrop): the four random numbers hashed from x, z
static func dims_at(kind: String, x: float, z: float, tall := false) -> Dictionary:
	var h := func(k: float) -> float:
		return fposmod(sin(x * 12.9898 + z * 78.233 + k * 37.719) * 43758.5453, 1.0)
	return dims(kind, h.call(1.0), h.call(2.0), h.call(3.0), h.call(4.0), tall)



## the pine's wood inside its crown (crown space): the trunk carried up to the tip and every branch of pine_branches()
## out to its last tuft, tapering (bark, CardTree material "spire")
static func _pine_wood() -> ArrayMesh:
	var b := _Buf.new()
	b.tube([Vector3(0, -0.1, 0), Vector3(0, 0.8, 0), Vector3(0, 1.8, 0), Vector3(0, PINE_TOP, 0)], [0.09, 0.07, 0.04, 0.006], 6, 0.6, 0.9)
	for br in pine_branches():
		var pts := []
		for k in 4:
			pts.append(branch_point(br, k / 3.0 * 0.95))
		var r0: float = clampf(float(br[2]) * 0.02, 0.008, 0.022)
		b.tube(pts, [r0, r0 * 0.7, r0 * 0.45, r0 * 0.2], 4, 0.55, 0.85)
	return b.commit()
