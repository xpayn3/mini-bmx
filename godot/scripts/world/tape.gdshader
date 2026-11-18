// Race tape (port of tape.js TAPE_MAT): spans bow downwind, flutter and twist with the gusts.
// NORMAL = the span's side vector; CUSTOM0 = (0 at stakes .. 1 mid-span, phase, edge +-1, alive);
// CUSTOM1 = per-span variation (speed, ripple length, twist).
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform float u_time = 0.0;
uniform float u_ph = 0.0;
uniform vec3 u_wind = vec3(4.0, 0.0, 3.0);
varying vec3 v_col;

void vertex() {
	vec3 side = NORMAL;
	vec4 fl = CUSTOM0;
	vec4 vr = CUSTOM1;
	float ws = length(u_wind);
	float push = dot(u_wind, side);
	float tt = u_time * vr.x, pp = u_ph * vr.x, ph = fl.y * vr.y;
	float wave = sin(pp - ph) * 0.55 + sin(pp * 1.53 - ph * 1.9 + vr.z * 4.0) * 0.3 + sin(tt * 2.2 - ph * 0.45 + vr.y * 7.0) * 0.35;
	float gust = 0.7 + 0.3 * sin(u_time * 0.9 * vr.x + vr.z * 9.0);
	float amp = fl.x * (0.025 + 0.012 * ws) * gust;
	float tw = sin(pp * 0.4 - ph * 0.8 + vr.y * 3.0) * vr.z;
	VERTEX += side * (fl.x * push * 0.035 * gust + amp * wave + fl.x * fl.z * 0.0375 * sin(tw));
	VERTEX.y += fl.x * (0.012 * ws * sin(pp * 0.7 - ph * 0.7) - 0.02) - fl.x * fl.z * 0.0375 * (1.0 - cos(tw));
	VERTEX *= fl.w;
	v_col = COLOR.rgb;
}

void fragment() {
	ALBEDO = v_col;
	ROUGHNESS = 0.42;
	METALLIC = 0.05;
}
