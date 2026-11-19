// The WET HALO round a pool of blood (second pass of fx/blood_pool.gd's mesh): dirt next to the pool has
// soaked some up, so a band round it is darker and a little red-brown. It creeps out over the first
// ~20 s (capillary soaking), ragged. Multiplies the ground under it (blend_mul), only outside the pool.
shader_type spatial;
render_mode blend_mul, unshaded, depth_draw_never, cull_disabled, shadows_disabled;

uniform sampler2D depth_tex : filter_linear, repeat_disable;
uniform float pool_t = 0.0;
uniform float seed = 0.0;
uniform float grid_m = 6.4;
uniform float wipe_at = 1e9;
uniform float wipe_len = 4.0;

varying vec3 v_world;

float bh(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float bn(vec2 p) {
	vec2 i = floor(p), f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(bh(i), bh(i + vec2(1, 0)), f.x), mix(bh(i + vec2(0, 1)), bh(i + vec2(1, 1)), f.x), f.y);
}

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 view = (MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float vd = length(view);
	VERTEX = (inverse(MODELVIEW_MATRIX) * vec4(view - view / max(vd, 1e-3) * (0.05 + vd * 0.004), 1.0)).xyz;
}

void fragment() {
	vec2 w = v_world.xz;
	float inside = smoothstep(0.0009, 0.0014, texture(depth_tex, UV).r);
	// how far the soaking has crept: 3 cm at once, up to ~10 cm, ragged
	float reach = (0.03 + 0.07 * smoothstep(0.0, 20.0, pool_t)) * (0.6 + 0.8 * bn(w * 9.0 + seed));
	float near = 0.0;
	for (int k = 0; k < 8; k++) {
		float an = float(k) * 0.785398;
		for (int s = 1; s <= 2; s++) {
			vec2 o = vec2(cos(an), sin(an)) * reach * float(s) * 0.5 / grid_m;
			near = max(near, texture(depth_tex, UV + o).r * (s == 1 ? 1.0 : 0.7));
		}
	}
	float halo = smoothstep(0.0004, 0.0018, near) * (1.0 - inside);
	halo *= 0.75 + 0.25 * bn(w * 30.0 - seed);
	vec2 eb = min(UV, 1.0 - UV);
	halo *= smoothstep(0.01, 0.05, min(eb.x, eb.y));
	halo *= 1.0 - smoothstep(0.0, wipe_len, pool_t - wipe_at);
	// damp dirt: darker, a touch of red-brown
	ALBEDO = mix(vec3(1.0), vec3(0.58, 0.46, 0.43), halo);
}
