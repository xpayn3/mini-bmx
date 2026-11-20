class_name MetalFinish
extends RefCounted
## Real metal surfaces for the bike's bare metal parts (bolts, rotors, spokes, hubs, cassette, chain,
## anodised crowns / cranks, stanchions): the ambientCG Metal009 brushed-metal scan (CC0,
## assets/textures/brushed_metal) laid on in object space (triplanar), so it works on any mesh whatever
## its UVs and keeps a real size: one tile = TILE_M of metal, the brushing lines ~0.1 mm apart.
## The scan only adds micro detail: its colour and roughness are normalised by their means (0.58 / 0.47)
## so every part keeps the colour + roughness it was tuned with, on average.

const DIR := "res://assets/textures/brushed_metal/"
const TILE_M := 0.16
const COLOR_MEAN := 0.58
const ROUGH_MEAN := 0.47

## per material name: [normal strength, colour streaks (>= 0.5 = the scan's tone variation shows)]
const KINDS := {
	"chrome": [0.35, 1.0],    # bolts, rotors, spokes, cassette: brushed / ground steel
	"hub": [0.3, 0.8],
	"spokes": [0.25, 0.8],
	"chain": [0.3, 0.6],
	"black": [0.18, 0.4],     # anodised aluminium: the brushing shows through the dye, faintly
	"gold": [0.08, 0.25],     # polished stanchions: nearly mirror, only a faint grain
}

static var _cache := {}
static var _tex := {}


static func available() -> bool:
	return ResourceLoader.exists(DIR + "metal_rough.jpg")


static func _t(n: String) -> Texture2D:
	if not _tex.has(n):
		_tex[n] = load(DIR + "metal_%s.jpg" % n)
	return _tex[n]


## A dressed copy of m (cached per source material), or m itself when it isn't bare metal.
static func dress(m: Material) -> Material:
	if not (m is StandardMaterial3D) or not available():
		return m
	var sm := m as StandardMaterial3D
	if sm.has_meta("metal_finish") or sm.albedo_texture != null or sm.normal_enabled:
		return m
	var kind := sm.resource_name
	if not KINDS.has(kind) or sm.metallic < 0.45:
		return m
	var key := sm.get_instance_id()
	if _cache.has(key):
		return _cache[key]
	var k: Array = KINDS[kind]
	var d: StandardMaterial3D = sm.duplicate()
	d.set_meta("metal_finish", true)
	d.uv1_triplanar = true
	d.uv1_triplanar_sharpness = 4.0
	d.uv1_scale = Vector3.ONE / TILE_M
	d.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	d.roughness_texture = _t("rough")
	d.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
	d.roughness = minf(sm.roughness / ROUGH_MEAN, 1.0)   # material roughness x texture: same mean as before
	d.normal_enabled = true
	d.normal_texture = _t("normal")
	d.normal_scale = float(k[0])
	if float(k[1]) >= 0.5:   # the scan's tone streaks (+-4 %), lifted so texture x colour = the old colour
		d.albedo_texture = _t("color")
		var a := sm.albedo_color
		d.albedo_color = Color(a.r / COLOR_MEAN, a.g / COLOR_MEAN, a.b / COLOR_MEAN, a.a)
	_cache[key] = d
	return d


## The brake disc's heat-glow shader (BikeFX.ROTOR_SHADER) takes the same scan, ground in rings round the axle.
static func dress_rotor(m: ShaderMaterial) -> void:
	if m == null or not available():
		return
	m.set_shader_parameter("rough_tex", _t("rough"))
	m.set_shader_parameter("detail", 1.0)


## Dresses every bare-metal surface under root (surface overrides already set, e.g. paint, are kept).
static func apply(root: Node) -> void:
	if not available():
		return
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var o: Node = stack.pop_back()
		stack.append_array(o.get_children())
		if o is MeshInstance3D and (o as MeshInstance3D).mesh:
			var mi := o as MeshInstance3D
			if mi.material_override:
				continue
			for i in mi.mesh.get_surface_count():
				var cur := mi.get_surface_override_material(i)
				var src := cur if cur else mi.mesh.surface_get_material(i)
				if src == null:
					continue
				var d := dress(src)
				if d != src:
					mi.set_surface_override_material(i, d)
