class_name StudioSet
extends Node3D
## A product-photo studio for showing a bike: meant for the SHOP (user decision 2026-11-24: the garage stays the
## rider's own workshop for the bikes they own; the shop shows bikes for sale in this showroom look). A seamless
## curved backdrop (cyclorama: the floor sweeps up into the back wall, no corner line), big softboxes that
## light it and, as bright panels, draw the long clean highlights along the tubes in the paint and chrome
## (a ReflectionProbe catches them, plus SSR), a dark room round it, its own environment (`env`: AgX, no fog).
## The bike stands at the origin, the camera looks from +Z, so the cove is behind it (-Z). The camera showing it
## must leave PANEL_LAYER out of its cull mask (the softboxes are only seen in reflections). Pair it with HqStill.
##   key   : 2.4 x 1.4 m softbox high front-left, the main soft light + shadow
##   strips: two tall 0.35 x 2.4 m strip boxes behind either side: rim light and the long tube highlights
##   top   : 3 x 2 m scrim overhead: the bright sheen along the top tube, saddle, bars
##   fill  : dim, front-right, no shadow

const PROBE_LAYER := 1 << 18      # the set's meshes, for the reflection probe (the bike isn't in its own reflection)
const PANEL_LAYER := 1 << 19      # the softbox panels: in the reflections only, never in shot (keep it off the camera)
const CYC_GREY := Color(0.36, 0.36, 0.37)
const COVE_Z := -2.6              # where the floor starts curving up
const COVE_R := 2.4
const CYC_W := 26.0
const AMBIENT := 0.25

var env: Environment
var probe: ReflectionProbe
## every studio lamp, in the order a reveal switches them on: {name, light, energy, mat (its panel), glow}
var lamps: Array = []

## 0 (off) .. 1 (as set) for one lamp (light + its glowing panel)
func set_lamp(i: int, k: float) -> void:
	var L: Dictionary = lamps[i]
	(L.light as Light3D).light_energy = float(L.energy) * k
	if L.mat: (L.mat as StandardMaterial3D).emission_energy_multiplier = float(L.glow) * k

func set_all(k: float) -> void:
	for i in lamps.size(): set_lamp(i, k)
	env.ambient_light_energy = AMBIENT * k

func _ready() -> void:
	name = "Studio"
	_cyclorama()
	_softbox("strip_l", Vector3(-3.2, 1.4, -1.6), Vector2(0.35, 2.4), 2.4, 3.5, 0.35, true)     # strip left
	_softbox("strip_r", Vector3(3.2, 1.4, -1.6), Vector2(0.35, 2.4), 2.4, 3.5, 0.35, true)      # strip right
	_softbox("key", Vector3(-2.6, 3.0, 2.6), Vector2(2.4, 1.4), 1.8, 6.0, 1.2, true)            # key
	_softbox("top", Vector3(0.0, 4.2, 0.2), Vector2(3.0, 2.0), 1.6, 2.5, 1.5, false)            # top scrim
	# the backdrop light: hidden low behind the bike, a soft glow up the cove wall (the bike stands out of it)
	var bg := SpotLight3D.new()
	bg.light_energy = 4.0
	bg.spot_range = 10.0
	bg.spot_angle = 55.0
	bg.spot_angle_attenuation = 0.8
	bg.light_color = Color(0.92, 0.95, 1.0)
	bg.shadow_enabled = false
	bg.light_specular = 0.0
	add_child(bg)
	bg.look_at_from_position(Vector3(0.0, 0.15, -1.3), Vector3(0.0, 2.2, COVE_Z - COVE_R), Vector3.UP)
	lamps.append({"name": "backdrop", "light": bg, "energy": bg.light_energy, "mat": null, "glow": 0.0})
	var fill := OmniLight3D.new()
	fill.position = Vector3(3.0, 1.4, 3.2)
	fill.light_energy = 0.6
	fill.omni_range = 12.0
	fill.light_color = Color(0.94, 0.96, 1.0)
	fill.shadow_enabled = false
	fill.light_specular = 0.2
	add_child(fill)
	lamps.append({"name": "fill", "light": fill, "energy": fill.light_energy, "mat": null, "glow": 0.0})
	probe = ReflectionProbe.new()
	probe.size = Vector3(14, 9, 14)
	probe.position = Vector3(0, 2.5, 0)
	probe.origin_offset = Vector3(0, -1.6, 0)   # captured from bike height
	probe.box_projection = true
	probe.interior = true
	probe.cull_mask = PROBE_LAYER | PANEL_LAYER
	probe.update_mode = ReflectionProbe.UPDATE_ONCE
	probe.intensity = 1.0
	probe.ambient_mode = ReflectionProbe.AMBIENT_COLOR
	probe.ambient_color = Color(0.08, 0.08, 0.085)
	add_child(probe)
	env = _environment()
	if Env.s("BMX_STUDIO_NOPROBE") != "": probe.queue_free()
	if Env.s("BMX_STUDIO_NOSSR") != "": env.ssr_enabled = false

func _mat(c: Color, rough: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic_specular = 0.35
	return m

## floor -> quarter circle -> wall, swept across x; one smooth surface
func _cyclorama() -> void:
	var prof := []   # (z, y) from the front of the floor round to the top of the wall
	prof.append(Vector2(9.0, 0.0))
	for i in 25:
		var a := float(i) / 24.0 * PI * 0.5
		prof.append(Vector2(COVE_Z - sin(a) * COVE_R, COVE_R - cos(a) * COVE_R))
	prof.append(Vector2(COVE_Z - COVE_R, 8.0))
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var nx := 24
	for j in prof.size() - 1:
		var p0: Vector2 = prof[j]
		var p1: Vector2 = prof[j + 1]
		var n0 := _prof_normal(prof, j)
		var n1 := _prof_normal(prof, j + 1)
		for i in nx:
			var x0 := -CYC_W * 0.5 + CYC_W * i / nx
			var x1 := -CYC_W * 0.5 + CYC_W * (i + 1) / nx
			var a := Vector3(x0, p0.y, p0.x); var b := Vector3(x1, p0.y, p0.x)
			var c := Vector3(x1, p1.y, p1.x); var d := Vector3(x0, p1.y, p1.x)
			for v in [[a, n0], [c, n1], [b, n0], [a, n0], [d, n1], [c, n1]]:
				st.set_normal(v[1])
				st.add_vertex(v[0])
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	var m := _mat(CYC_GREY, 0.55)   # a satin floor: the bike's soft reflection under it
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = m
	mi.layers = 1 | PROBE_LAYER
	add_child(mi)

static func _prof_normal(prof: Array, j: int) -> Vector3:
	var a: Vector2 = prof[maxi(j - 1, 0)]
	var b: Vector2 = prof[mini(j + 1, prof.size() - 1)]
	var t := (b - a).normalized()   # along the profile, (z, y): back along the floor, then up the wall
	return Vector3(0.0, -t.x, t.y)   # floor (-1, 0) -> up, wall (0, 1) -> towards the bike

## a softbox: a glowing panel (seen in reflections) facing the bike + the spot light it gives
func _softbox(nm: String, at: Vector3, sz: Vector2, glow: float, energy: float, soft: float, shadow: bool) -> void:
	var aim := Vector3(0.0, 0.75, 0.0)
	var panel := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = sz
	panel.mesh = q
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(1, 1, 1)
	m.emission_enabled = true
	m.emission = Color(1.0, 0.99, 0.97)
	m.emission_energy_multiplier = glow
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	panel.material_override = m
	panel.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	panel.layers = PANEL_LAYER
	add_child(panel)
	panel.look_at_from_position(at, aim, Vector3.UP if absf((aim - at).normalized().y) < 0.95 else Vector3.FORWARD)
	panel.rotate_object_local(Vector3.UP, PI)   # a QuadMesh faces +Z: turn it to face the bike
	# a dark frame round the panel, so it reads as a softbox
	var frame := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(sz.x + 0.08, sz.y + 0.08, 0.12)
	frame.mesh = bm
	frame.material_override = _mat(Color(0.05, 0.05, 0.05), 0.6)
	frame.position = Vector3(0, 0, -0.07)
	frame.layers = PANEL_LAYER
	panel.add_child(frame)
	var sp := SpotLight3D.new()
	sp.light_energy = energy
	sp.light_size = soft          # wide penumbra (PCSS)
	sp.spot_range = 14.0
	sp.spot_angle = 30.0
	sp.spot_angle_attenuation = 1.4
	sp.light_color = Color(1.0, 0.98, 0.95)
	sp.shadow_enabled = shadow
	sp.shadow_blur = 1.5
	add_child(sp)
	sp.look_at_from_position(at, aim, Vector3.UP if absf((aim - at).normalized().y) < 0.95 else Vector3.FORWARD)
	lamps.append({"name": nm, "light": sp, "energy": energy, "mat": m, "glow": glow})

func _environment() -> Environment:
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.015, 0.015, 0.016)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.5, 0.5, 0.52)
	e.ambient_light_energy = AMBIENT
	e.reflected_light_source = Environment.REFLECTION_SOURCE_BG
	e.tonemap_mode = Environment.TONE_MAPPER_AGX
	e.tonemap_exposure = 1.0
	e.ssao_enabled = true
	e.ssao_radius = 0.6
	e.ssao_intensity = 1.6
	e.ssil_enabled = true
	e.ssil_radius = 2.0
	e.ssil_intensity = 0.7
	e.ssr_enabled = true
	e.ssr_max_steps = 128
	e.sdfgi_enabled = true
	e.sdfgi_use_occlusion = true
	e.sdfgi_min_cell_size = 0.1
	e.sdfgi_cascades = 3
	e.sdfgi_energy = 0.8
	e.glow_enabled = false   # (bloom off: the clearcoat's small bright highlights bloomed the whole bike into a white haze)
	e.adjustment_enabled = true
	e.adjustment_contrast = 1.06
	e.adjustment_saturation = 1.05
	return e
