class_name AmbientMotes
extends Node3D
## A little magic in the air round the rider, from the time of day:
##   by day   pollen / seed fluff drifting in the sunlight (tiny, pale, catches the light)
##   at dusk / night   fireflies low over the grass, each pulsing on its own (they bloom)
## Two GPUParticles3D in world space; this node follows the rider, the particles stay where they were born.
## Game calls update(focus, night, golden) every frame. Nothing runs while both are off.

const POLLEN_N := 900
const FIREFLY_N := 420

var _pollen: GPUParticles3D
var _flies: GPUParticles3D
var _k_pollen := -1.0
var _k_flies := -1.0

const DOT_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;
uniform vec3 col = vec3(1.0);
uniform float energy = 1.0;
uniform float pulse = 0.0;      // 0 = steady, 1 = firefly blink
uniform float strength = 1.0;   // time-of-day fade (set from Game)
varying float v_ph;
varying float v_life;
void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0),
		vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0), vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0), vec4(0.0, 0.0, 0.0, 1.0));
	v_ph = fract(sin(float(INSTANCE_ID) * 12.9898) * 43758.5453);
	v_life = INSTANCE_CUSTOM.y;   // 0..1 through its life
}
void fragment() {
	float d = length(UV - 0.5) * 2.0;
	float a = pow(max(1.0 - d, 0.0), 2.2);
	// fade in / out over its life so nothing pops
	a *= smoothstep(0.0, 0.15, v_life) * (1.0 - smoothstep(0.8, 1.0, v_life));
	a *= smoothstep(1.2, 4.0, length(VERTEX));   // none right at the lens (big blurry discs)
	if (pulse > 0.0) {
		// a firefly: slow glow up, quick fade, its own rhythm (2.5..5 s), dark most of the time
		float t = fract(TIME / (2.5 + v_ph * 2.5) + v_ph);
		float b = smoothstep(0.0, 0.18, t) * (1.0 - smoothstep(0.22, 0.55, t));
		a *= mix(1.0, 0.04 + b, pulse);
	}
	ALBEDO = col * energy * a * strength;
}
"""

func _init() -> void:
	name = "AmbientMotes"
	var sh := Shader.new()
	sh.code = DOT_SHADER
	_pollen = _make(sh, POLLEN_N, 7.0, Vector3(16, 3.5, 16), 0.02, Color(1.0, 0.92, 0.7), 0.22, 0.0,
		Vector3(0.0, 0.03, 0.0), 0.12, 0.35)
	_flies = _make(sh, FIREFLY_N, 6.0, Vector3(18, 1.1, 18), 0.06, Color(0.62, 1.0, 0.12), 1.8, 1.0,
		Vector3(0.0, 0.0, 0.0), 0.25, 0.5)

func _make(sh: Shader, n: int, life: float, box: Vector3, size: float, col: Color, energy: float, pulse: float,
		grav: Vector3, vel: float, turb: float) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = n
	p.lifetime = life
	p.preprocess = life
	p.local_coords = false
	p.fixed_fps = 30
	p.interpolate = true
	p.emitting = false
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.visibility_aabb = AABB(-box - Vector3(6, 6, 6), (box + Vector3(6, 6, 6)) * 2.0)
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = box
	pm.gravity = grav
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 180.0
	pm.initial_velocity_min = vel * 0.3
	pm.initial_velocity_max = vel
	pm.damping_min = 0.05
	pm.damping_max = 0.2
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = turb
	pm.turbulence_noise_scale = 3.0
	pm.turbulence_noise_speed_random = 0.4
	pm.scale_min = 0.5
	pm.scale_max = 1.3
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	var m := ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter("col", Vector3(col.r, col.g, col.b))
	m.set_shader_parameter("energy", energy)
	m.set_shader_parameter("pulse", pulse)
	q.material = m
	p.draw_pass_1 = q
	add_child(p)
	return p

## focus = the rider (world), night 0..1, golden 0..1 (low sun)
func update(focus: Vector3, night: float, golden: float) -> void:
	global_position = focus + Vector3(0, 1.0, 0)
	_flies.position = Vector3(0, -0.2, 0)
	var kp := clampf((1.0 - night) * (1.0 - night) * (0.55 + 0.45 * golden), 0.0, 1.0)   # sunlit air; gone as dusk falls
	var kf := smoothstep(0.25, 0.75, maxf(night, golden * 0.6))
	_apply(_pollen, kp, "_k_pollen")
	_apply(_flies, kf, "_k_flies")

func _apply(p: GPUParticles3D, k: float, key: String) -> void:
	if absf(k - float(get(key))) < 0.01:
		return
	set(key, k)
	var on := k > 0.02
	if p.emitting != on:
		p.emitting = on
	p.visible = on
	(p.draw_pass_1.surface_get_material(0) as ShaderMaterial).set_shader_parameter("strength", k)
