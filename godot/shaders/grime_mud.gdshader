// Mud on the bike and rider (port of src/grime.js), drawn as a next_pass over each part's own material
// so it works on every material (imported, car paint, the rider's): splotches are opaque, alpha-scissored
// mud, lit like any surface. It starts low down (tyres, chainstays, shoes) and creeps up as it builds;
// the noise lives in each part's own space, so mud sticks to the part (the tyre's mud turns with it).
// Globals (scripts/bike/grime.gd): grime.x = mud 0..1, grime.y = wet 0..1, mud_col, grime_root =
// world -> bike root (y = height above the ground).
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

global uniform vec4 grime;
global uniform vec4 mud_col : source_color;
global uniform mat4 grime_root;
uniform float bias = 1.0;   // how readily this part collects mud (tyres 1.8 .. helmet 0.5)

varying vec3 v_local;
varying float v_hgt;

float gr_hash(vec3 p) { p = fract(p * 0.3183099 + 0.1); p *= 17.0; return fract(p.x * p.y * p.z * (p.x + p.y + p.z)); }
float gr_noise(vec3 x) {
	vec3 i = floor(x), f = fract(x); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(gr_hash(i), gr_hash(i + vec3(1,0,0)), f.x), mix(gr_hash(i + vec3(0,1,0)), gr_hash(i + vec3(1,1,0)), f.x), f.y),
	           mix(mix(gr_hash(i + vec3(0,0,1)), gr_hash(i + vec3(1,0,1)), f.x), mix(gr_hash(i + vec3(0,1,1)), gr_hash(i + vec3(1,1,1)), f.x), f.y), f.z);
}

void vertex() {
	v_local = VERTEX;
	v_hgt = (grime_root * (MODEL_MATRIX * vec4(VERTEX, 1.0))).y;
	// drawn exactly over the part: nudge toward the camera so it wins the depth test (reverse Z)
	POSITION = PROJECTION_MATRIX * (MODELVIEW_MATRIX * vec4(VERTEX, 1.0));
	POSITION.z += 0.00004 * POSITION.w;
}

void fragment() {
	float hgt = clamp(v_hgt / 1.5, 0.0, 1.0);
	float cover = grime.x * bias * (1.25 - hgt * 1.4);
	float n = gr_noise(v_local * 26.0) * 0.6 + gr_noise(v_local * 71.0) * 0.4;
	float fleck = gr_noise(v_local * 190.0);
	float m = max(smoothstep(1.0 - cover, 1.08 - cover, n), step(1.0 - cover * 0.35, fleck));
	vec3 mc = mud_col.rgb * (0.8 + 0.4 * gr_noise(v_local * 9.0));
	// wet mud: darker and glossy
	float w = grime.y;
	ALBEDO = mc * (1.0 - w * 0.43);
	ROUGHNESS = mix(0.93, 0.3, w);
	SPECULAR = 0.5;
	ALPHA = m;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
}
