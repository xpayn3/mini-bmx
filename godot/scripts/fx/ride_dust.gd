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
static var _dust_mat: ShaderMaterial
static var _fog_tex: NoiseTexture3D

func _init() -> void:
	name = "RideDust"
	_build_emitter()
	_build_fog_puffs()

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
