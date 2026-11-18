class_name Grime
extends Node3D
## Mud and water on the bike and rider (port of src/grime.js):
##  * MUD builds up while riding dirt and sand (faster when skidding, carving and landing), taking the
##    colour of the ground it came from. It starts low and creeps upward; riding through water washes it off.
##  * WET: out of the water everything goes darker and glossy, drops run down and drip off, then it dries.
## Every bike / rider material gets two next_pass overlays (shaders/grime_mud + grime_wet), shared and
## driven by global shader uniforms, so one update moves them all. The passes are only attached while
## there is something to draw, so a clean, dry bike costs nothing.

const MUD_SHADER := preload("res://shaders/grime_mud.gdshader")
const WET_SHADER := preload("res://shaders/grime_wet.gdshader")
## how fast mud builds up (1 = the web version: fully caked after ~40 s of fast dirt riding; 0.25 = ~2.5 min)
const MUD_RATE := 0.25

var roots: Array[Node] = []       # the bike rig + the rider (the rider leaves the rig in a crash)
var mud := 0.0
var wet := 0.0
var enabled := true
var mud_col := Color(0.35, 0.235, 0.133)
var _mats := {}                   # base material -> mud pass material (by bias)
var _mud_by_bias := {}
var _wet_mat: ShaderMaterial
var _attached := 0                # 0 none, 1 mud, 2 mud + wet
var _scan_t := 0.0
var _t := 0.0
var drips: GPUParticles3D
var warm_frames := 0              # > 0: passes attached (but invisible) so their pipelines compile up front

func _init() -> void:
	name = "Grime"
	_wet_mat = ShaderMaterial.new()
	_wet_mat.shader = WET_SHADER
	_wet_mat.render_priority = 1
	_build_drips()

## many base materials are shared (glb imports, the paint / wheel caches): take our passes off them when
## the ride ends, or the next ride skips them as "already layered" and the garage bike keeps the mud
func _exit_tree() -> void:
	for m in _mats:
		if is_instance_valid(m) and m.next_pass == _mats[m]:
			m.next_pass = null
	_mats.clear()
	RenderingServer.global_shader_parameter_set("grime", Vector4.ZERO)

func watch(n: Node) -> void:
	roots.append(n)
	_scan_t = 0.0

func clean() -> void:
	mud = 0.0; wet = 0.0

## how readily a part collects mud (tyres soak it up, the helmet hardly any)
static func _bias_for(mat: Material, mi: Node) -> float:
	var n := ("%s %s %s" % [mat.resource_name, mi.name, mi.get_parent().name if mi.get_parent() else ""]).to_lower()
	for k in ["rubber", "tyre", "tire", "wheel"]:
		if k in n: return 1.8
	for k in ["lens", "goggle"]:
		if k in n: return 0.35
	for k in ["helmet", "shell", "peak", "visor"]:
		if k in n: return 0.5
	for k in ["chrome", "gold"]:
		if k in n: return 0.8
	return 1.0

func _mud_mat(bias: float) -> ShaderMaterial:
	if not _mud_by_bias.has(bias):
		var m := ShaderMaterial.new()
		m.shader = MUD_SHADER
		m.set_shader_parameter("bias", bias)
		_mud_by_bias[bias] = m
	return _mud_by_bias[bias]

func _scan() -> void:
	var stack: Array[Node] = []
	stack.append_array(roots)
	while not stack.is_empty():
		var o: Node = stack.pop_back()
		if not is_instance_valid(o): continue
		stack.append_array(o.get_children())
		if not (o is MeshInstance3D) or (o as MeshInstance3D).mesh == null: continue
		var mi := o as MeshInstance3D
		var list: Array[Material] = []
		if mi.material_override: list.append(mi.material_override)
		else:
			for s in mi.mesh.get_surface_count():
				var m := mi.get_surface_override_material(s)
				if m == null: m = mi.mesh.surface_get_material(s)
				if m: list.append(m)
		for m in list:
			if _mats.has(m) or m == _wet_mat or m.get_meta("grime_pass", false): continue
			if m is BaseMaterial3D and (m as BaseMaterial3D).transparency != BaseMaterial3D.TRANSPARENCY_DISABLED: continue
			if m.next_pass != null: continue   # already layered by something else: leave it alone
			var mm := _mud_mat(_bias_for(m, mi))
			mm.set_meta("grime_pass", true)
			_mats[m] = mm
			_set_pass(m, _attached)

func _set_pass(m: Material, state: int) -> void:
	m.next_pass = null if state == 0 else _mats[m]

## per physics step. surf: 0 grass, 1 dirt, 2 water, 3 sand. col = colour of the ground here
func feed(dt: float, surf: int, speed: float, skid: bool, air: bool, landed: float, col: Color) -> void:
	if surf == 2:   # riding through water washes the mud off and soaks everything
		mud = maxf(0.0, mud - dt * (0.12 + speed * 0.05))
		wet = minf(1.0, wet + dt * 3.0)
		return
	var rate := 0.0
	if not air and speed > 0.5:
		if surf == 1: rate = speed * 0.0025 + (0.08 if skid else 0.0)
		elif surf == 3: rate = speed * 0.0016 + (0.05 if skid else 0.0)
		else: rate = 0.01 if skid else 0.0
	if wet > 0.3: rate *= 2.5   # a wet bike picks mud up much faster
	var gain := (rate * dt + (0.05 * landed if landed > 0.0 and surf != 0 else 0.0)) * MUD_RATE
	if gain > 0.0:
		# the colour shifts toward the ground it's picking up now (darker: damp, packed dirt)
		var target := (col * (0.62 if surf == 3 else 0.5)).lerp(Color(0.3, 0.2, 0.11), 0.35)
		target.a = 1.0
		mud_col = mud_col.lerp(target, minf(1.0, gain / (mud + gain + 0.02)))
		mud = minf(1.0, mud + gain)
	wet *= exp(-dt / 7.0)   # dries off over a few seconds

## per frame. bike_root: world -> bike-root transform source (the rig: y = height above the ground)
func update(dt: float, bike_root: Node3D) -> void:
	_t += dt
	_scan_t -= dt
	if _scan_t <= 0.0:
		_scan_t = 1.5   # catches parts that load later (helmet, drivetrain)
		_scan()
	var m := mud if enabled else 0.0
	var w := wet if enabled else 0.0
	var state := 0
	if m > 0.002 or w > 0.01: state = 1
	if w > 0.01 or warm_frames > 0: state = 2
	if warm_frames > 0:
		warm_frames -= 1
		drips.emitting = true
	if state != _attached:
		_attached = state
		for b in _mud_by_bias.values():
			b.next_pass = _wet_mat if state == 2 else null
		for mat in _mats: _set_pass(mat, state)
	RenderingServer.global_shader_parameter_set("grime", Vector4(m, w, _t, 0))
	RenderingServer.global_shader_parameter_set("mud_col", mud_col)
	RenderingServer.global_shader_parameter_set("grime_root", Projection(bike_root.global_transform.affine_inverse()))
	# drips off the bike while it is still wet
	drips.global_position = bike_root.global_position + Vector3(0, 0.55, 0)
	drips.global_basis = bike_root.global_basis
	drips.emitting = w > 0.12 or warm_frames > 0
	drips.amount_ratio = clampf((w - 0.1) * 1.3, 0.0, 1.0)

func _build_drips() -> void:
	drips = GPUParticles3D.new()
	drips.name = "Drips"
	drips.amount = 60
	drips.lifetime = 0.7
	drips.local_coords = false
	drips.emitting = false
	drips.visibility_aabb = AABB(Vector3(-2, -2, -2), Vector3(4, 4, 4))
	drips.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(0.7, 0.35, 0.12)
	pm.direction = Vector3(0, -1, 0)
	pm.spread = 8.0
	pm.initial_velocity_min = 0.0
	pm.initial_velocity_max = 0.3
	pm.gravity = Vector3(0, -9.8, 0)
	pm.scale_min = 0.6
	pm.scale_max = 1.2
	drips.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.012, 0.045)
	var mat := StandardMaterial3D.new()
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	mat.billboard_keep_scale = true
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.85, 0.93, 1.0, 0.55)
	q.material = mat
	drips.draw_pass_1 = q
	add_child(drips)
