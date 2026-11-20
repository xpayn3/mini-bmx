class_name PantsLook
extends RefCounted
## The rider's trousers: a fabric (Poly Haven scans, CC0, assets/textures/<id>/: grey weave, normal, roughness,
## AO) dyed in the pants colour, and a printed pattern on top in a second colour (shaders/pants_fabric.gdshader:
## camo, tiger, leopard, flames...). Look keys: pants (colour), pantsFabric, pantsPattern, pantsPrint (colour).
## Picked in the rider room Kit tab and the tuning card Look > Clothes.

## id, label, texture folder ("" = plain dyed cloth), tile (m: about the scan's real size), grain (contrast), roughness, normal strength
const FABRICS := [
	["denim", "Denim", "denim_fabric_06", 0.42, 1.6, 0.9, 1.6],
	["herringbone", "Herringbone", "poly_wool_herringbone", 0.42, 1.8, 0.85, 1.6],
	["corduroy", "Corduroy", "ribbed_corduroy", 0.36, 2.2, 0.9, 2.0],
	["linen", "Linen", "rough_linen", 0.36, 1.8, 0.88, 1.4],
	["jersey", "Jersey knit", "cotton_jersey", 0.3, 1.6, 0.92, 1.2],
	["plain", "Plain", "", 0.2, 0.0, 0.9, 0.0],
]
const PATTERNS := [
	["none", "None"], ["camo", "Camo"], ["digicamo", "Digital camo"], ["tiger", "Tiger"], ["zebra", "Zebra"],
	["leopard", "Leopard"], ["checker", "Checker"], ["tiedye", "Tie-dye"], ["flames", "Flames"], ["lightning", "Lightning"],
]
const DEFAULT_FABRIC := "denim"
const DEFAULT_PATTERN := "none"
const DEFAULT_PRINT := "#ff7a1a"

static var _shader: Shader
static var _tex := {}


static func make() -> ShaderMaterial:
	if _shader == null: _shader = load("res://shaders/pants_fabric.gdshader")
	var m := ShaderMaterial.new()
	m.shader = _shader
	m.resource_name = "pants"
	return m


static func _fabric(id: String) -> Array:
	for f in FABRICS:
		if f[0] == id: return f
	return FABRICS[0]


static func _pattern_index(id: String) -> int:
	for i in PATTERNS.size():
		if PATTERNS[i][0] == id: return i
	return 0


static func _t(folder: String, map: String) -> Texture2D:
	var key := folder + "/" + map
	if not _tex.has(key):
		var p := "res://assets/textures/%s/%s_%s_2k.jpg" % [folder, folder, map]
		_tex[key] = load(p) if ResourceLoader.exists(p) else null
	return _tex[key]


## colour: the pants colour (already shaded for the knee etc.); look: the rider's look
static func apply(m: ShaderMaterial, colour: Color, look: Dictionary) -> void:
	if m == null: return
	var f := _fabric(str(look.get("pantsFabric", DEFAULT_FABRIC)))
	var folder: String = f[2]
	m.set_shader_parameter("base_col", colour)
	m.set_shader_parameter("pat_col", Color(str(look.get("pantsPrint", DEFAULT_PRINT))))
	m.set_shader_parameter("pattern", _pattern_index(str(look.get("pantsPattern", DEFAULT_PATTERN))))
	var has := folder != "" and _t(folder, "grey") != null
	m.set_shader_parameter("fabric", 1.0 if has else 0.0)
	if has:
		m.set_shader_parameter("fab_grey", _t(folder, "grey"))
		m.set_shader_parameter("fab_normal", _t(folder, "nor_gl"))
		m.set_shader_parameter("fab_rough", _t(folder, "rough"))
		m.set_shader_parameter("fab_ao", _t(folder, "ao"))
	m.set_shader_parameter("tile", float(f[3]))
	m.set_shader_parameter("grain", float(f[4]))
	m.set_shader_parameter("rough_base", float(f[5]))
	m.set_shader_parameter("normal_k", float(f[6]))
