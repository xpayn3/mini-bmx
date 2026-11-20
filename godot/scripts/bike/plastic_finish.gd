class_name PlasticFinish
extends RefCounted
## Real plastic surfaces from ambientCG scans (CC0, assets/textures/plastic, 4K), laid on in object space
## (triplanar) like MetalFinish, so any mesh takes them whatever its UVs, at a real size (TILE_M a tile).
## Like MetalFinish the scan only adds detail: colour and roughness are divided by the scan's means so the
## material keeps the colour + roughness it was tuned with, on average.
##   textured  Plastic012A: the moulded, finely pebbled matte plastic of an action cam body
##   mount     Plastic018A: the grainier grey plastic of mounts / buckles / sleeves (tinted by the colour)
##   gloss     Plastic006: smooth shiny plastic (bezels, buttons, trim)

const DIR := "res://assets/textures/plastic/"

## kind -> [file prefix, colour mean, roughness mean, normal strength, tile (m), use the colour map]
const KINDS := {
	"textured": ["p012a", 0.170, 0.395, 1.0, 0.07, true],
	"mount": ["p018a", 0.495, 0.426, 0.45, 0.16, false],   # its colour map + full bumps read as speckled stone
	"silicone": ["p012a", 0.170, 0.395, 0.5, 0.10, false],   # the soft sleeve: the body's pebbling, fainter
	"gloss":["p006", 0.030, 0.249, 0.5, 0.12, false],   # nearly black scan: its colour map would only add noise
}

static var _tex := {}


static func available() -> bool:
	return ResourceLoader.exists(DIR + "p012a_rough.jpg")


static func _t(n: String) -> Texture2D:
	if not _tex.has(n):
		_tex[n] = load(DIR + n + ".jpg")
	return _tex[n]


## dresses m (a StandardMaterial3D made in code, changed in place) with the plastic `kind`; returns it
static func dress(m: StandardMaterial3D, kind: String) -> StandardMaterial3D:
	if not KINDS.has(kind) or not available():
		return m
	var k: Array = KINDS[kind]
	var p: String = k[0]
	m.uv1_triplanar = true
	m.uv1_triplanar_sharpness = 4.0
	m.uv1_scale = Vector3.ONE / float(k[4])
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	m.roughness_texture = _t(p + "_rough")
	m.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
	m.roughness = minf(m.roughness / float(k[2]), 1.0)
	m.normal_enabled = true
	m.normal_texture = _t(p + "_normal")
	m.normal_scale = float(k[3])
	if bool(k[5]):
		m.albedo_texture = _t(p + "_color")
		var a := m.albedo_color
		var s := 1.0 / float(k[1])
		m.albedo_color = Color(a.r * s, a.g * s, a.b * s, a.a)
	return m
