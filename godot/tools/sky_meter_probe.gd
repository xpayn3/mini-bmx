extends SceneTree
## -s tool (with a window): checks world/sky_meter.gd. The card must follow the sky's light_energy 1:1 (card/le constant)
## and every read must come back fresh. Prints SKYPROBE lines.
var meter
var mat := ShaderMaterial.new()
var i := 0
var t := 0.0
const LE := [1.0, 0.5, 2.0, 0.25, 1.0, 1.0, 1.0]
const GOLD := [0.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0]
var busy := false

func _initialize() -> void:
	mat.shader = load("res://shaders/sky_hdri.gdshader")
	mat.set_shader_parameter("hdri", load("res://assets/hdri/kloofendal_48d_partly_cloudy_puresky_4k.hdr"))
	mat.set_shader_parameter("sunny", 1.0)
	meter = load("res://scripts/world/sky_meter.gd").new(mat)
	root.add_child(meter)

func _process(dt: float) -> bool:
	t += dt
	if t < 0.5 or busy: return false
	if i >= LE.size(): return true
	var le: float = LE[i]
	mat.set_shader_parameter("light_energy", le)
	mat.set_shader_parameter("golden", GOLD[i])
	busy = true
	var el := deg_to_rad(40.0)
	meter.measure(Vector3(cos(el), sin(el), 0.0), func(s: Color) -> void:
		print("SKYPROBE le=%.2f golden=%.0f card=%.4f card/le=%.4f rgb=%s" % [le, GOLD[i], s.g, s.g / maxf(le, 1e-6), s])
		busy = false
		i += 1)
	return false
