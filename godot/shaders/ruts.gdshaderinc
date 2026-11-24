// Ruts (world/ruts.gd + RutFieldCs): the dug-in depth round the rider as a window texture (RH, m, + = dug, - = lip).
// rut_win = (x0, z0, size m, on). Ground shaders: rut_depth() for colour, rut_normal() to shade the grooves' walls.
global uniform sampler2D rut_tex : filter_linear, repeat_disable;
global uniform vec4 rut_win;
global uniform vec4 rut_ctr;   // (rider x, rider z, fade starts, fade ends): the ruts dissolve with the distance from the RIDER

global uniform sampler2D rut_far_tex : filter_linear, repeat_disable;
global uniform vec4 rut_far_win;   // the far layer: 25 cm texels, 200 m round the rider, the deepest cell of each 5 x 5

const float RUT_FAR_A = 65.0;   // m from the rider: the far layer is full up to here, gone by RUT_FAR_B (its window is >= 96 m wide each way)
const float RUT_FAR_B = 85.0;

float rut_depth(vec2 xz) {
	float d = distance(xz, rut_ctr.xy);
	// near layer (5 cm texels) up to ~20 m, the far layer beyond, blended by the distance from the RIDER, smoothly:
	// the windows hop a tile at a time, so their edges must never be where anything shows
	float fn = 1.0 - smoothstep(rut_ctr.z, rut_ctr.w, d);
	float fr = 1.0 - smoothstep(RUT_FAR_A, RUT_FAR_B, d);
	float dn = 0.0;
	float df = 0.0;
	if (fn > 0.0 && rut_win.w > 0.5) {
		vec2 uv = (xz - rut_win.xy) / rut_win.z;
		if (uv.x > 0.0 && uv.y > 0.0 && uv.x < 1.0 && uv.y < 1.0) dn = textureLod(rut_tex, uv, 0.0).r;
	}
	if (fn < 1.0 && fr > 0.0 && rut_far_win.w > 0.5) {
		vec2 uv = (xz - rut_far_win.xy) / rut_far_win.z;
		if (uv.x > 0.0 && uv.y > 0.0 && uv.x < 1.0 && uv.y < 1.0) df = textureLod(rut_far_tex, uv, 0.0).r * fr;
	}
	return mix(df, dn, fn);
}

// the surface normal (world) tilted by the groove's slope: d is depth (down), so the ground's height is -d
vec3 rut_normal(vec2 xz, vec3 n) {
	if (rut_win.w < 0.5) return n;
	float e = 0.03;
	float dx = rut_depth(xz + vec2(e, 0.0)) - rut_depth(xz - vec2(e, 0.0));
	float dz = rut_depth(xz + vec2(0.0, e)) - rut_depth(xz - vec2(0.0, e));
	// height = -depth: slope = -gradient; scaled up a little so a 2-3 cm groove reads at riding distance
	return normalize(n + vec3(dx, 0.0, dz) / (2.0 * e) * 1.6);
}

// a groove's bottom is packed / damp (darker), the lip of pushed-up loose dirt a little lighter
vec3 rut_colour(vec3 c, float d) {
	float g = smoothstep(0.003, 0.06, d);
	float lip = smoothstep(0.001, 0.012, -d);
	return c * (1.0 - 0.16 * g) * (1.0 + 0.10 * lip);   // (0.32 read too dark, user 2026-11-24)
}
