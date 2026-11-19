class_name RideDust
extends Node3D
## Volumetric-looking dust for the ride:
##  * the rear wheel's dust trail: a GPUParticles3D emitter that follows the rear contact patch. Every
##    physics step sets its rate (amount_ratio), throw direction (carves fling it outwards) and colour.
##    Drawn as soft, sun-lit billboards: a spherical normal so the side facing the sun is bright, light
##    scattering through when you look toward the sun, proximity fade where a puff meets the ground and
##    a fade near the camera (no hard intersections, no popping).
##  * big skids and landings also throw up FogVolume clouds (when volumetric fog is on): real
##    participating media the sun shines through and the shadows fall into.
## With a RenderingDevice (the normal case) all of that is replaced by SmokeSim: a real 3D smoke
## simulation on the GPU (fx/smoke_sim.gd); the sprites / FogVolumes above are only the fallback.

const SOFT_DUST_SHADER := """
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, diffuse_lambert, specular_disabled, shadows_disabled;
#include "res://shaders/atmos.gdshaderinc"

uniform sampler2D smoke_tex : hint_default_white, filter_linear, repeat_disable;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
uniform float soft_dist = 0.6;   // m: fades out where it meets the ground
varying vec3 v_world;
varying vec4 v_custom;

void vertex() {
	v_custom = INSTANCE_CUSTOM;
	// camera-facing billboard, spun by the particle's angle, sized by its scale
	mat4 w = mat4(normalize(INV_VIEW_MATRIX[0]), normalize(INV_VIEW_MATRIX[1]), normalize(INV_VIEW_MATRIX[2]), MODEL_MATRIX[3]);
	float a = INSTANCE_CUSTOM.x;
	w = w * mat4(vec4(cos(a), -sin(a), 0.0, 0.0), vec4(sin(a), cos(a), 0.0, 0.0), vec4(0.0, 0.0, 1.0, 0.0), vec4(0.0, 0.0, 0.0, 1.0));
	float s = length(MODEL_MATRIX[0].xyz);
	MODELVIEW_MATRIX = VIEW_MATRIX * w * mat4(vec4(s, 0, 0, 0), vec4(0, s, 0, 0), vec4(0, 0, s, 0), vec4(0, 0, 0, 1));
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
	v_world = MODEL_MATRIX[3].xyz;
}

void fragment() {
	vec2 p = UV - 0.5;
	float life = v_custom.y;
	float cell = floor(fract(v_custom.w * 13.37) * 4.0);
	vec2 c = vec2(mod(cell, 2.0), floor(cell / 2.0));
	vec4 t = texture(smoke_tex, (UV * 0.98 + 0.01 + c) * 0.5);
	// density erodes from the thin parts first as the puff ages -> wisps that tear apart
	float er = life * 0.75;
	float dens = t.r * smoothstep(er, er + 0.35, t.g);
	// a round puff: normal bulges toward the camera, so the sun side is lit and the far side shaded
	NORMAL = normalize(vec3(p.x * 1.6, -p.y * 1.6, 0.55) + vec3(0.0, 0.0, (t.b - 0.5) * 0.4));
	ALBEDO = COLOR.rgb;
	float a = dens * COLOR.a;
	// soft particle: fade where the puff cuts into the ground / bike, and right in front of the camera
	float d = textureLod(depth_tex, SCREEN_UV, 0.0).r;
	vec4 sp = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, d, 1.0);
	sp.xyz /= sp.w;
	a *= clamp((VERTEX.z - sp.z) / soft_dist, 0.0, 1.0);
	a *= smoothstep(0.4, 1.6, -VERTEX.z);
	if (a < 0.003) discard;
	ALPHA = clamp(a, 0.0, 1.0);
}

void light() {
	float sh = LIGHT_IS_DIRECTIONAL ? cloud_ratio(v_world) : 1.0;
	vec3 lc = ATTENUATION * LIGHT_COLOR / PI * sh;
	// wrapped diffuse (light bleeds round a puff) + forward scattering toward a viewer facing the sun
	float wrap = clamp(dot(NORMAL, LIGHT) * 0.6 + 0.4, 0.0, 1.0);
	float fwd = pow(clamp(dot(-VIEW, LIGHT), 0.0, 1.0), 6.0) * 0.9;
	DIFFUSE_LIGHT += (wrap + fwd) * lc;
}
"""

const MAX_RATE := 190.0   # particles / s at amount_ratio 1

var emitter: GPUParticles3D
var pm: ParticleProcessMaterial
var _rate := 0.0
var _puffs: Array[FogVolume] = []
var _puff_age: PackedFloat32Array
var _puff_life: PackedFloat32Array
var _puff_peak: PackedFloat32Array
var _puff_vel: Array[Vector3] = []
var _puff_next := 0
var fog_on := false
var sim: SmokeSim = null
var grit: Grit = null
var _grit_bursts: Array = []      # {p, v, spread, rate, col, t}
var _feed_on := false
var _feed_p := Vector3.ZERO
var _feed_prev := Vector3.INF
var _feed_v := Vector3.ZERO
var _feed_rate := 0.0
var _feed_r := 0.3
var _feed_fan := 30.0
var _feed_col := Color(0.8, 0.68, 0.52)
var _front_on := false
var _feed_age := 0.0
var _front_age := 0.0
var _front_p := Vector3.ZERO
var _front_prev := Vector3.INF
var _front_v := Vector3.ZERO
var _front_rate := 0.0
const PATCH_R := 0.24   # m: the contact patch, as small as the sim's 0.2 m cells allow
var _pulse_t := 0.0
var _gust := FastNoiseLite.new()
static var _dust_mat: ShaderMaterial
static var _fog_tex: NoiseTexture3D

func _init() -> void:
	name = "RideDust"
	_build_emitter()
	_build_fog_puffs()
	if RenderingServer.get_rendering_device() != null and OS.get_environment("BMX_SPRITE_DUST") == "":
		sim = SmokeSim.new()
		if sim.ok:
			add_child(sim)
			grit = Grit.new(sim)
			add_child(grit)
			emitter.visible = false
		else:
			sim.free()
			sim = null

## the sim needs the ground and the sun (call once the world exists)
func attach(terrain, sun: DirectionalLight3D) -> void:
	if sim == null: return
	if sim.terrain != terrain:   # a new world: forget the old ground and dust
		sim.terrain = terrain
		sim.reset()
	sim.sun = sun

## per drawn frame: run the simulation around the rider
func sim_step(dt: float, focus: Vector3, fwd: Vector3, wind: Vector2) -> void:
	if sim == null: return
	sim.wind = wind * 2.8   # m/s at gust strength 1
	# the tyres only dust while the ride feeds them (every physics step); in a crash nothing does, so
	# switch them off instead of puffing on at the last wheel positions
	_feed_age += dt
	_front_age += dt
	if _feed_age > 0.1: _feed_on = false
	if _front_age > 0.1: _front_on = false
	_pulse_t += dt
	var pulse := clampf(0.9 + _gust.get_noise_1d(_pulse_t * 60.0) * 2.6, 0.0, 2.6)   # gusts with gaps
	_feed_prev = _patch(_feed_on, _feed_p, _feed_prev, _feed_v, _feed_rate * pulse, _feed_fan, _feed_col)
	# the front tyre kicks up a little too (its own gusts)
	var fpulse := clampf(0.9 + _gust.get_noise_1d(_pulse_t * 60.0 + 500.0) * 2.6, 0.0, 2.6)
	_front_prev = _patch(_front_on, _front_p, _front_prev, _front_v, _front_rate * fpulse, _feed_fan, _feed_col)
	sim.step(dt, focus, fwd)
	if grit != null:
		for i in range(_grit_bursts.size() - 1, -1, -1):
			var b: Dictionary = _grit_bursts[i]
			grit.emit(b.p, b.v, b.spread, b.rate, b.col)
			b.t -= dt
			if b.t <= 0.0: _grit_bursts.remove_at(i)
		grit.update(focus)

## dust comes only from a tyre's contact patch: small sources on the ground along the path the patch
## swept this frame, each spraying its own way (back / out / up, in gusts). The cloud is what the sim
## makes of that spray: it fans out, rolls and spreads from there. Returns the new "previous" point.
func _patch(on: bool, p: Vector3, prev: Vector3, v: Vector3, rate: float, fan: float, col: Color) -> Vector3:
	if not on or rate <= 0.0: return Vector3.INF
	var from := prev if prev != Vector3.INF and prev.distance_to(p) < 2.0 else p
	var k := clampi(ceili(from.distance_to(p) / 0.15), 1, 5)
	var sp := v.length()
	for i in k:
		var at := from.lerp(p, (i + 1.0) / k)
		var yaw := (randf() - 0.5) * deg_to_rad(fan) * 1.6
		var jv := v.rotated(Vector3.UP, yaw) * (0.6 + randf() * 0.8) + Vector3(0, randf() * (0.8 + sp * 0.25), 0)
		# faster riding flings the spray harder / wider: it grows into a cloud sooner
		var fast := clampf((sim.speed - 3.0) / 9.0, 0.0, 1.0)
		sim.add_source(at, jv * (1.0 + fast * 0.5), PATCH_R, rate * 14.0 / k, 10.0, 0.6 + randf() * 0.8 + fast * 1.6, col)
	# grit: grains flicked off the tread with the dust (fewer but further than the dust)
	if grit != null:
		grit.emit(p, v * 1.4 + Vector3(0, 0.6 + sp * 0.15, 0), 0.8 + sp * 0.35, rate * 26.0, col)
	return p

## grains thrown for secs (landings, crash impacts)
func grit_burst(p: Vector3, v: Vector3, spread: float, rate: float, secs: float, col: Color) -> void:
	if grit == null or rate <= 0.0: return
	_grit_bursts.append({p = p, v = v, spread = spread, rate = rate, col = col, t = secs})

## per physics step: the front tyre's patch (sim only; a lighter dusting than the rear)
func feed_front(front: Vector3, throw_v: Vector3, rate: float, alpha: float) -> void:
	_front_age = 0.0
	_front_on = sim != null and rate > 0.5 and alpha > 0.0
	if not _front_on: return
	_front_p = front + Vector3(0, 0.08, 0)
	_front_v = throw_v
	_front_rate = rate * alpha * alpha * 2.2

## a landing: dust squeezed out from under each tyre as it hits (the tyre and the air under it push it
## out sideways along the ground), carried on a little with the bike. How much / how far: the impact.
## patches: the tyres' ground contact points; vel: the bike's velocity
func landing_dust(patches: Array, vel: Vector3, impact: float, col: Color, amount: float) -> void:
	if sim == null or amount <= 0.0: return
	var k := clampf((impact - 1.5) / 7.0, 0.1, 1.0)
	for p in patches:
		var at: Vector3 = p + Vector3(0, 0.08, 0)
		sim.burst(at, vel * 0.25 + Vector3(0, 0.3 + k * 0.6, 0), 0.26 + k * 0.12, (40.0 + 120.0 * k) * amount,
			0.8 + k * 2.4, 0.07 + k * 0.05, col, 18.0)
		grit_burst(at, vel * 0.3 + Vector3(0, 0.8 + k * 1.2, 0), 1.0 + k * 2.5, 2400.0 * k * amount, 0.08, col)
	sim.tint(col)

## a burst of dust (crash, smash, hard landing)
func puff_burst(pos: Vector3, power: float, col: Color, amount: float) -> void:
	if sim == null: return
	sim.burst(pos + Vector3(0, 0.25, 0), Vector3(0, 0.6, 0), 0.5 + power * 0.25, 30.0 * amount, 1.2 + power * 1.4, 0.15, col)

static func dust_material() -> ShaderMaterial:
	if _dust_mat == null:
		var sh := Shader.new()
		sh.code = SOFT_DUST_SHADER
		_dust_mat = ShaderMaterial.new()
		_dust_mat.shader = sh
		_dust_mat.set_shader_parameter("smoke_tex", FX.smoke_texture())
	return _dust_mat

func _build_emitter() -> void:
	emitter = GPUParticles3D.new()
	emitter.name = "RearDust"
	emitter.amount = int(MAX_RATE * 3.2)
	emitter.lifetime = 3.2
	emitter.local_coords = false
	emitter.interpolate = true
	emitter.fract_delta = true
	emitter.randomness = 0.3
	emitter.draw_order = GPUParticles3D.DRAW_ORDER_VIEW_DEPTH
	emitter.visibility_aabb = AABB(Vector3(-25, -6, -25), Vector3(50, 20, 50))
	emitter.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	emitter.amount_ratio = 0.0
	emitter.emitting = true
	pm = ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.08
	pm.direction = Vector3(0, 0, 1)
	pm.spread = 28.0
	pm.initial_velocity_min = 1.0
	pm.initial_velocity_max = 3.0
	pm.gravity = Vector3(0, 0.12, 0)          # warm dust rises a touch
	pm.damping_min = 1.6
	pm.damping_max = 2.2
	pm.particle_flag_damping_as_friction = true
	pm.angle_min = -180.0
	pm.angle_max = 180.0
	pm.angular_velocity_min = -35.0
	pm.angular_velocity_max = 35.0
	pm.scale_min = 0.38
	pm.scale_max = 0.62
	var sc := Curve.new()
	sc.add_point(Vector2(0.0, 1.0))
	sc.add_point(Vector2(0.25, 2.6))
	sc.add_point(Vector2(1.0, 4.2))
	sc.max_value = 5.0
	var sct := CurveTexture.new(); sct.curve = sc
	pm.scale_curve = sct
	var ac := Curve.new()   # quick fade-in, long fade-out
	ac.add_point(Vector2(0.0, 0.0))
	ac.add_point(Vector2(0.06, 1.0))
	ac.add_point(Vector2(1.0, 0.0))
	var act := CurveTexture.new(); act.curve = ac
	pm.alpha_curve = act
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 0.6
	pm.turbulence_noise_scale = 3.0
	pm.turbulence_influence_min = 0.02
	pm.turbulence_influence_max = 0.06
	pm.lifetime_randomness = 0.3
	emitter.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(1, 1)
	q.material = dust_material()
	emitter.draw_pass_1 = q
	add_child(emitter)

## per physics step: where the rear tyre is, which way the dust is thrown (world, m/s), how many
## puffs per second, their colour (sRGB) and opacity
func feed(rear: Vector3, throw_v: Vector3, rate: float, col: Color, alpha: float, fan_deg: float) -> void:
	_rate = rate
	if sim != null:
		_feed_age = 0.0
		_feed_on = rate > 0.5 and alpha > 0.0
		if not _feed_on: return
		_feed_p = rear + Vector3(0, 0.08, 0)   # the first cell above the ground
		_feed_fan = fan_deg
		_feed_v = throw_v
		_feed_rate = rate * alpha * alpha * 2.2   # grass (low alpha) barely dusts, dry dirt billows
		_feed_r = 0.32 + clampf(rate / 120.0, 0.0, 1.0) * 0.3 + fan_deg / 70.0 * 0.15
		sim.tint(col)
		_feed_col = col
		return
	emitter.global_position = rear
	var sp := throw_v.length()
	if sp > 0.05:
		var z := throw_v / sp
		var x := Vector3.UP.cross(z)
		if x.length_squared() < 1e-4: x = Vector3.RIGHT
		x = x.normalized()
		emitter.global_basis = Basis(x, z.cross(x), z)
	pm.initial_velocity_min = sp * 0.6
	pm.initial_velocity_max = sp * 1.3
	pm.spread = fan_deg
	var c := col.srgb_to_linear()
	c.a = minf(1.0, alpha * 1.3)
	pm.color = c
	emitter.amount_ratio = clampf(rate / MAX_RATE, 0.0, 1.0)

# ---------------------------------------------------------------- FogVolume puffs
func _build_fog_puffs() -> void:
	if _fog_tex == null:
		var n := FastNoiseLite.new()
		n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		n.frequency = 0.09
		n.fractal_octaves = 3
		_fog_tex = NoiseTexture3D.new()
		_fog_tex.width = 32; _fog_tex.height = 32; _fog_tex.depth = 32
		_fog_tex.noise = n
	var N := 6
	_puff_age.resize(N); _puff_life.resize(N); _puff_peak.resize(N)
	for i in N:
		var fv := FogVolume.new()
		fv.shape = RenderingServer.FOG_VOLUME_SHAPE_ELLIPSOID
		fv.size = Vector3(2, 1, 2)
		var fm := FogMaterial.new()
		fm.density = 0.0
		fm.edge_fade = 0.5
		fm.height_falloff = 0.0   # (world-space height: the trails are ~100 m up, any falloff kills it)
		fm.density_texture = _fog_tex
		fv.material = fm
		add_child(fv)
		_puffs.append(fv)
		_puff_vel.append(Vector3.ZERO)
		_puff_age[i] = 1e9; _puff_life[i] = 1.0

## a big dusty moment (hard skid, landing, crash): a dust cloud that swells, drifts and thins out
func cloud(pos: Vector3, vel: Vector3, col: Color, size: float, density: float) -> void:
	if sim != null:
		sim.burst(pos + Vector3(0, 0.3, 0), vel + Vector3(0, 0.5, 0), size * 0.32, density * 22.0, 1.6 + size * 0.3, 0.22, col)
		return
	if not fog_on: return
	var i := _puff_next
	_puff_next = (i + 1) % _puffs.size()
	var fv := _puffs[i]
	fv.global_position = pos + Vector3(0, size * 0.25, 0)
	fv.size = Vector3(size, size * 0.55, size)
	(fv.material as FogMaterial).albedo = col
	_puff_age[i] = 0.0
	_puff_life[i] = 2.2 + size * 0.4
	_puff_peak[i] = density
	_puff_vel[i] = vel

## compile every pipeline these effects use now, while the screen is faded out, instead of hitching
## the first time a skid or landing happens
func warm_up(at: Vector3) -> void:
	emitter.global_position = at
	emitter.amount_ratio = 0.05
	var fv := _puffs[0]
	fv.global_position = at
	(fv.material as FogMaterial).density = 0.0
	_puff_age[0] = 0.0; _puff_life[0] = 0.3; _puff_peak[0] = 0.0

func _process(dt: float) -> void:
	for i in _puffs.size():
		if _puff_age[i] > _puff_life[i]:
			if (_puffs[i].material as FogMaterial).density != 0.0: (_puffs[i].material as FogMaterial).density = 0.0
			continue
		_puff_age[i] += dt
		var k := _puff_age[i] / _puff_life[i]
		var fv := _puffs[i]
		_puff_vel[i] *= exp(-dt * 1.5)
		fv.global_position += (_puff_vel[i] + Vector3(0, 0.25, 0)) * dt
		fv.size *= 1.0 + dt * 0.45 * (1.0 - k)
		(fv.material as FogMaterial).density = _puff_peak[i] * minf(1.0, k * 8.0) * pow(1.0 - k, 1.4)
