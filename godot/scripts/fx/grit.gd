class_name Grit
extends GPUParticles3D
## Sand grains / specks thrown out with the dust, carried by the smoke sim's air (shaders/smoke/grit*.gdshader).
## Each frame: emit(...) from up to 8 points (tyre patches, landings, crash impacts), then update().

const MAX_EMIT := 8
const MAX_RATE := 2400.0          # grains / s at amount_ratio 1
const LIFE := 2.2

var sim: SmokeSim
var _pm: ShaderMaterial
var _dm: ShaderMaterial
var _pts: Array = []              # this frame: {p, v, spread, rate, col}

func _init(p_sim: SmokeSim) -> void:
	name = "Grit"
	sim = p_sim
	amount = int(MAX_RATE * LIFE)
	lifetime = LIFE
	local_coords = false
	fixed_fps = 0
	interpolate = false
	randomness = 0.0
	visibility_aabb = AABB(Vector3(-30, -15, -30), Vector3(60, 30, 60))
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_pm = ShaderMaterial.new()
	_pm.shader = preload("res://shaders/smoke/grit.gdshader")
	process_material = _pm
	_dm = ShaderMaterial.new()
	_dm.shader = preload("res://shaders/smoke/grit_draw.gdshader")
	var q := QuadMesh.new()
	q.size = Vector2.ONE
	q.material = _dm
	draw_pass_1 = q
	amount_ratio = 0.0
	emitting = true
	var ex: Dictionary = sim.shading_inputs()
	for m in [_pm, _dm]:
		m.set_shader_parameter("hmap", ex.hmap)
		m.set_shader_parameter("size_m", ex.size_m)
		m.set_shader_parameter("hm_cells", ex.hm_cells)
	_pm.set_shader_parameter("vel_tex", sim.vel3d)
	_dm.set_shader_parameter("light_tex", ex.light)

## grains per second from p this frame, thrown at v (+ random spread m/s), colour (sRGB)
func emit(p: Vector3, v: Vector3, spread: float, rate: float, col: Color) -> void:
	if rate <= 0.0 or _pts.size() >= MAX_EMIT: return
	_pts.append({p = p, v = v, spread = spread, rate = rate, col = col})

func update(focus: Vector3) -> void:
	global_position = focus
	var total := 0.0
	for e in _pts: total += e.rate
	var pos: Array = []; pos.resize(MAX_EMIT); pos.fill(Vector4.ZERO)
	var vel: Array = []; vel.resize(MAX_EMIT); vel.fill(Vector4.ZERO)
	var col: Array = []; col.resize(MAX_EMIT); col.fill(Vector4.ZERO)
	var acc := 0.0
	for i in _pts.size():
		var e: Dictionary = _pts[i]
		acc += e.rate / maxf(total, 1e-3)
		pos[i] = Vector4(e.p.x, e.p.y, e.p.z, acc)
		vel[i] = Vector4(e.v.x, e.v.y, e.v.z, e.spread)
		var c: Color = (e.col as Color).srgb_to_linear()
		col[i] = Vector4(c.r, c.g, c.b, 1.0)
	_pm.set_shader_parameter("em_pos", pos)
	_pm.set_shader_parameter("em_vel", vel)
	_pm.set_shader_parameter("em_col", col)
	_pm.set_shader_parameter("em_count", _pts.size())
	amount_ratio = clampf(total / MAX_RATE, 0.0, 1.0)
	var ex: Dictionary = sim.shading_inputs()
	for m in [_pm, _dm]: m.set_shader_parameter("origin", ex.origin)
	_dm.set_shader_parameter("sun_col", ex.sun_col)
	_dm.set_shader_parameter("amb_col", ex.amb_col)
	_pts.clear()
