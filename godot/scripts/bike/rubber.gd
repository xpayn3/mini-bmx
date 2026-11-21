class_name Rubber
extends RefCounted
## Real tyre rubber, made in code (no downloads): a compound is not black. Carbon black + oils + a little wax
## bloom make it a dark warm charcoal (sRGB ~0.17-0.22, 4-6 % reflectance), matte (roughness 0.8-0.95) with
## patchy lighter "bloom" where the surface oils dried, a fine moulded grain (the mould's blasted finish) that
## breaks up the highlights, and a soft grazing-angle sheen. All of it is one tileable texture set sampled
## triplanar in object space, so it works on any tyre mesh whatever its UVs, and the grain keeps its size when
## the tyre is scaled.

const SIZE := 512
const TILE_M := 0.10          # one texture tile = 10 cm of tyre

static var _albedo: ImageTexture
static var _normal: ImageTexture
static var _rough: ImageTexture


static func _noise(kind: int, freq: float, seed_n: int, octaves := 1) -> Image:
	var n := FastNoiseLite.new()
	n.noise_type = kind
	n.frequency = freq
	n.seed = seed_n
	if octaves > 1:
		n.fractal_type = FastNoiseLite.FRACTAL_FBM
		n.fractal_octaves = octaves
		n.fractal_gain = 0.55
	var img: Image = n.get_seamless_image(SIZE, SIZE, false, false, 0.2, true)   # tileable, 0..1 in R
	img.convert(Image.FORMAT_RF)
	return img


static func _build() -> void:
	if _albedo != null: return
	var patch := _noise(FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 0.012, 11, 3)   # dried-oil bloom: soft patches
	var fine := _noise(FastNoiseLite.TYPE_SIMPLEX, 0.30, 23)                # grain
	var speck := _noise(FastNoiseLite.TYPE_CELLULAR, 0.22, 37)             # blasted-mould stipple
	var a := Image.create(SIZE, SIZE, false, Image.FORMAT_RGB8)
	var r := Image.create(SIZE, SIZE, false, Image.FORMAT_RGB8)
	var bump := Image.create(SIZE, SIZE, false, Image.FORMAT_RF)
	for y in SIZE:
		for x in SIZE:
			var p: float = patch.get_pixel(x, y).r
			var f: float = fine.get_pixel(x, y).r
			var s: float = speck.get_pixel(x, y).r
			# albedo (multiplies the vertex colour): 0.80 .. 1.12, brownish-grey where the bloom is thick
			var v := 0.86 + 0.26 * smoothstep(0.30, 0.75, p) + 0.07 * (f - 0.5) - 0.05 * s
			var warm := 0.025 * smoothstep(0.5, 0.8, p)
			a.set_pixel(x, y, Color(clampf(v + warm, 0.0, 1.0), clampf(v, 0.0, 1.0), clampf(v - warm, 0.0, 1.0)))
			# roughness (x the material's value): bloom is a touch glossier-flat, the stipple scatters the highlights
			var rv := 0.90 - 0.10 * smoothstep(0.3, 0.8, p) + 0.12 * (s - 0.5) + 0.08 * (f - 0.5)
			r.set_pixel(x, y, Color(clampf(rv, 0.0, 1.0), clampf(rv, 0.0, 1.0), clampf(rv, 0.0, 1.0)))
			bump.set_pixel(x, y, Color(0.6 * f + 0.4 * s, 0, 0))
	bump.bump_map_to_normal_map(5.0)
	a.generate_mipmaps(); r.generate_mipmaps(); bump.generate_mipmaps()
	_albedo = ImageTexture.create_from_image(a)
	_rough = ImageTexture.create_from_image(r)
	bump.convert(Image.FORMAT_RGB8)
	_normal = ImageTexture.create_from_image(bump)


const SCAN_DIR := "res://assets/textures/rubber/"
const SCAN_LIFT := 1.8       # albedo multiplier on the scan (env BMX_RUBBER_LIFT overrides, for tests)
const SCAN_TILE_M := 0.20    # one scan tile = 20 cm of tyre (the grain is ~1.5 mm)

## true = the photographed ambientCG Rubber004 scan (colour already holds the compound's colour, so the
## vertex colour is white); false = the generated grain above (env BMX_RUBBER=gen, or the files are missing)
static func use_scan() -> bool:
	return OS.get_environment("BMX_RUBBER") != "gen" and ResourceLoader.exists(SCAN_DIR + "rubber_color.jpg")


## Turns a StandardMaterial3D (vertex colour = the compound colour) into realistic rubber.
static func apply(m: StandardMaterial3D, rough := 0.92) -> void:
	if use_scan():
		_apply_scan(m)
		return
	_build()
	m.metallic = 0.0
	m.roughness = rough
	m.metallic_specular = 0.45                      # rubber's Fresnel at normal incidence is low
	m.albedo_texture = _albedo
	m.roughness_texture = _rough
	m.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
	m.normal_enabled = true
	m.normal_texture = _normal
	m.normal_scale = 0.55
	m.uv1_triplanar = true
	m.uv1_triplanar_sharpness = 2.0
	m.uv1_scale = Vector3.ONE / TILE_M
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	# the soft grazing sheen of an oily compound
	m.rim_enabled = true
	m.rim = 0.22
	m.rim_tint = 0.6


static func _apply_scan(m: StandardMaterial3D) -> void:
	m.metallic = 0.0
	m.roughness = 1.0
	m.metallic_specular = 0.45
	m.albedo_texture = load(SCAN_DIR + "rubber_color.jpg")
	m.roughness_texture = load(SCAN_DIR + "rubber_rough.jpg")
	m.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
	m.normal_enabled = true
	m.normal_texture = load(SCAN_DIR + "rubber_normal.jpg")
	var lift := float(OS.get_environment("BMX_RUBBER_LIFT")) if OS.get_environment("BMX_RUBBER_LIFT") != "" else SCAN_LIFT
	m.albedo_color = Color(lift, lift, lift)   # the scan is nearly black (sRGB ~0.16): lifted to a dark charcoal so the tread reads
	m.normal_scale = 1.8
	m.uv1_triplanar = true
	m.uv1_triplanar_sharpness = 2.0
	m.uv1_scale = Vector3.ONE / SCAN_TILE_M
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	m.rim_enabled = true
	m.rim = 0.15
	m.rim_tint = 0.5
