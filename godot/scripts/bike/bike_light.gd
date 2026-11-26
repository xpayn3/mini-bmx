class_name BikeLight
## Bike lights (garage Bars tab › LIGHTS, `build.lights.model`): a front lamp on the handlebar, small to big,
## plus a red tail light under the saddle. Procedural shapes, made-up brands. The lamp is a real SpotLight3D
## (turns with the bars, lights the haze); on when it's dark (`BikeRig.set_lights_on`, from Game by the time
## of day). Model space: +X forward, +Y up, +Z right; the bar runs along Z.

## 2026-11-26 realistic light: the ride's exposure is one constant (1.2) instead of 3.3 at night, so the beams x 2.75 keep the
## brightness they were tuned at, against a moonlit world that is now really dark (SunSky)
const BEAM_GAIN := 2.75
## id -> look + beam. lm = the box's lumens (shown on the card); energy / range / angle = the spot light;
## size = the lamp body's radius; heads = how many lamp heads; kind: pod / can / finned / twin / bar
const MODELS := {
	"none": {"brand": "", "label": "No lights", "lm": 0},
	"glint": {"brand": "PIXIE", "label": "Glint 150", "lm": 150, "kind": "pod", "size": 0.012,
		"energy": 1.3, "range": 16.0, "angle": 24.0, "atten": 1.6, "fog": 0.25, "shadow": false},
	"luma": {"brand": "LUMEN WORKS", "label": "Luma 800", "lm": 800, "kind": "can", "size": 0.015,
		"energy": 3.0, "range": 34.0, "angle": 26.0, "atten": 1.4, "fog": 0.5, "shadow": true},
	"nocta": {"brand": "NOCTURNE", "label": "Nocta 1800", "lm": 1800, "kind": "finned", "size": 0.02,
		"energy": 5.4, "range": 50.0, "angle": 30.0, "atten": 1.25, "fog": 0.8, "shadow": true},
	"duskbane": {"brand": "NOCTURNE", "label": "Duskbane 4000", "lm": 4000, "kind": "twin", "size": 0.018,
		"energy": 9.0, "range": 70.0, "angle": 36.0, "atten": 1.1, "fog": 1.1, "shadow": true},
	"sundowner": {"brand": "HALOGRID", "label": "Sundowner 6500", "lm": 6500, "kind": "bar", "size": 0.022,
		"energy": 13.0, "range": 90.0, "angle": 44.0, "atten": 1.0, "fog": 1.4, "shadow": true},
}
const ORDER := ["none", "glint", "luma", "nocta", "duskbane", "sundowner"]
const BEAM_DOWN := 0.09        # rad: the lamp aims a little down, at the trail ~10 m ahead
const LAMP_COL := Color(1.0, 0.97, 0.9)    # cool-ish white LED
const TAIL_COL := Color(1.0, 0.06, 0.03)

static func spec_line(id: String) -> String:
	var m: Dictionary = MODELS.get(id, MODELS.none)
	if int(m.lm) <= 0: return "dark"
	return "%d lm  ·  %d m beam" % [m.lm, int(m.range)]

static func _mat(col: Color, metal: float, rough: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.metallic = metal
	m.roughness = rough
	return m

## the glowing lens; `on` sets its glow (BikeRig keeps the material to switch it)
static func lens_mat(col: Color) -> StandardMaterial3D:
	var m := _mat(Color(0.9, 0.9, 0.92), 0.0, 0.08)
	m.emission_enabled = true
	m.emission = col
	m.emission_energy_multiplier = 0.0
	return m

static func _cyl(r: float, h: float, mat: Material, sides := 20) -> MeshInstance3D:
	var cm := CylinderMesh.new()
	cm.top_radius = r; cm.bottom_radius = r; cm.height = h
	cm.radial_segments = sides; cm.rings = 1
	var mi := MeshInstance3D.new()
	mi.mesh = cm
	mi.material_override = mat
	return mi

static func _box(s: Vector3, mat: Material) -> MeshInstance3D:
	var bm := BoxMesh.new(); bm.size = s
	var mi := MeshInstance3D.new()
	mi.mesh = bm
	mi.material_override = mat
	return mi

## a cylinder lying along +X (lamp body), centred at `at`
static func _can(root: Node3D, at: Vector3, r: float, length: float, mat: Material) -> MeshInstance3D:
	var mi := _cyl(r, length, mat)
	mi.rotation = Vector3(0, 0, -PI * 0.5)
	mi.position = at
	root.add_child(mi)
	return mi

## the lamp on the bar: {node, lens: [materials], spot: SpotLight3D}. `bar_r` = the bar tube's radius,
## the node's origin = the bar's centre line where the clamp sits.
static func build(id: String, bar_r: float) -> Dictionary:
	var m: Dictionary = MODELS.get(id, MODELS.none)
	if int(m.get("lm", 0)) <= 0: return {}
	var root := Node3D.new()
	root.name = "BikeLight"
	var black := _mat(Color(0.035, 0.035, 0.04), 0.6, 0.38)
	var rubber := _mat(Color(0.02, 0.02, 0.022), 0.0, 0.8)
	var alu := _mat(Color(0.12, 0.12, 0.13), 0.85, 0.3)
	var lens := lens_mat(LAMP_COL)
	var ring := _mat(Color(0.7, 0.7, 0.72), 1.0, 0.18)
	var r: float = m.size
	var lens_x := 0.0
	var lens_y := 0.0
	var heads: Array = []   # lamp head centres (y, z) for lenses
	var kind: String = m.kind
	# clamp round the bar (along Z)
	var clamp_w := 0.016 if kind != "bar" else 0.012
	var clamps: Array = [0.0] if kind != "bar" else [-0.06, 0.06]
	for cz in clamps:
		var c := _cyl(bar_r + 0.0035, clamp_w, rubber if kind == "pod" else black, 16)
		c.rotation = Vector3(PI * 0.5, 0, 0)
		c.position = Vector3(0, 0, cz)
		root.add_child(c)
	match kind:
		"pod":   # a silicone LED pod strapped on top of the bar
			var y := bar_r + r * 0.9
			var b := _can(root, Vector3(0.008, y, 0), r, 0.04, rubber)
			b.mesh.top_radius = r * 0.85
			lens_x = 0.028; heads = [Vector2(y, 0)]
		"can":   # a compact alloy can on a short stalk
			var y := bar_r + 0.008 + r
			root.add_child(_at(_box(Vector3(0.016, 0.012, 0.012), black), Vector3(0, bar_r + 0.004, 0)))
			_can(root, Vector3(0.01, y, 0), r, 0.062, alu)
			_can(root, Vector3(-0.024, y, 0), r * 0.8, 0.006, black)   # rear cap with the button
			lens_x = 0.041; heads = [Vector2(y, 0)]
		"finned":   # a big head with cooling fins round it
			var y := bar_r + 0.01 + r
			root.add_child(_at(_box(Vector3(0.02, 0.014, 0.016), black), Vector3(0, bar_r + 0.005, 0)))
			_can(root, Vector3(0.012, y, 0), r, 0.085, alu)
			for i in 6:
				_can(root, Vector3(-0.022 + i * 0.008, y, 0), r + 0.0045, 0.0025, black)
			_can(root, Vector3(0.052, y, 0), r + 0.002, 0.008, black)   # bezel
			lens_x = 0.0565; heads = [Vector2(y, 0)]
		"twin":   # two heads side by side on a bridge
			var y := bar_r + 0.012 + r
			root.add_child(_at(_box(Vector3(0.03, 0.014, 0.072), black), Vector3(0.004, bar_r + 0.006, 0)))
			for sz in [-0.022, 0.022]:
				_can(root, Vector3(0.012, y, sz), r, 0.074, alu)
				for i in 4:
					_can(root, Vector3(-0.016 + i * 0.008, y, sz), r + 0.004, 0.0025, black)
				_can(root, Vector3(0.047, y, sz), r + 0.0018, 0.006, black)
				heads.append(Vector2(y, sz))
			lens_x = 0.0505
		"bar":   # a wide LED bar over the bars, five lenses
			var y := bar_r + 0.022 + 0.022
			for cz in [-0.06, 0.06]:
				root.add_child(_at(_box(Vector3(0.014, 0.026, 0.01), black), Vector3(0, bar_r + 0.014, cz)))
			root.add_child(_at(_box(Vector3(0.05, 0.044, 0.19), alu), Vector3(0.006, y, 0)))
			for i in 9:   # fins on top
				root.add_child(_at(_box(Vector3(0.04, 0.008, 0.003), black), Vector3(0.0, y + 0.026, -0.08 + i * 0.02)))
			root.add_child(_at(_box(Vector3(0.006, 0.048, 0.196), black), Vector3(0.033, y, 0)))   # bezel
			for i in 5:
				heads.append(Vector2(y, -0.072 + i * 0.036))
			lens_x = 0.0365
	var lens_r := r * 0.82 if kind != "bar" else 0.0145
	for h in heads:
		var l := _cyl(lens_r, 0.003, lens, 20)
		l.rotation = Vector3(0, 0, -PI * 0.5)
		l.position = Vector3(lens_x, h.x, h.y)
		l.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(l)
		var rr := _cyl(lens_r + 0.0015, 0.0025, ring, 20)   # chrome reflector rim
		rr.rotation = Vector3(0, 0, -PI * 0.5)
		rr.position = Vector3(lens_x - 0.0006, h.x, h.y)
		root.add_child(rr)
	# the beam: one spot from the middle of the heads, just in front of the lenses (out of the lamp's own shadow)
	var hc := Vector2.ZERO
	for h in heads: hc += h
	hc /= maxf(heads.size(), 1)
	var sp := SpotLight3D.new()
	sp.name = "Beam"   # (BEAM_GAIN below)
	sp.light_color = LAMP_COL
	sp.light_energy = m.energy * BEAM_GAIN
	sp.spot_range = m.range
	sp.spot_angle = m.angle
	sp.spot_angle_attenuation = m.atten
	sp.spot_attenuation = 0.85
	sp.light_size = 0.03
	sp.light_specular = 0.6
	sp.light_volumetric_fog_energy = m.fog
	sp.shadow_enabled = m.shadow
	sp.shadow_bias = 0.04
	sp.shadow_normal_bias = 1.0
	sp.shadow_blur = 1.2
	sp.distance_fade_enabled = false
	sp.position = Vector3(lens_x + 0.02, hc.x, hc.y)
	sp.basis = Basis.looking_at(Vector3(cos(BEAM_DOWN), -sin(BEAM_DOWN), 0.0), Vector3.UP)
	sp.visible = false
	root.add_child(sp)
	# a soft close glow so the bars / hands catch some light (the spot only lights ahead)
	var glow := OmniLight3D.new()
	glow.name = "Spill"
	glow.light_color = LAMP_COL
	glow.light_energy = 0.12 + float(m.lm) / 30000.0
	glow.omni_range = 0.9
	glow.omni_attenuation = 2.0
	glow.light_specular = 0.1
	glow.shadow_enabled = false
	glow.position = Vector3(lens_x + 0.05, hc.x, hc.y)
	glow.visible = false
	root.add_child(glow)
	return {"node": root, "lens": [lens], "lights": [sp, glow], "glow": 3.0 + float(m.lm) / 600.0}

static func _at(mi: Node3D, p: Vector3) -> Node3D:
	mi.position = p
	return mi

## the red tail light (a small LED box on the seat post under the saddle, facing back)
static func build_tail() -> Dictionary:
	var root := Node3D.new()
	root.name = "TailLight"
	var black := _mat(Color(0.03, 0.03, 0.035), 0.3, 0.5)
	root.add_child(_box(Vector3(0.014, 0.034, 0.024), black))
	var lens := lens_mat(TAIL_COL)
	lens.albedo_color = Color(0.5, 0.02, 0.02)
	var l := _box(Vector3(0.003, 0.028, 0.019), lens)
	l.position = Vector3(-0.0075, 0, 0)
	root.add_child(l)
	var o := OmniLight3D.new()
	o.light_color = TAIL_COL
	o.light_energy = 0.12
	o.omni_range = 1.2
	o.omni_attenuation = 2.2
	o.light_specular = 0.1
	o.position = Vector3(-0.08, 0, 0)
	o.visible = false
	root.add_child(o)
	return {"node": root, "lens": [lens], "lights": [o], "glow": 4.0}
