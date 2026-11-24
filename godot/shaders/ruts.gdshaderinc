// Ruts (world/ruts.gd + RutFieldCs): the dug-in depth round the rider as a window texture (RH, m, + = dug, - = lip).
// rut_win = (x0, z0, size m, on). Ground shaders: rut_depth() for colour, rut_normal() to shade the grooves' walls.
global uniform sampler2D rut_tex : filter_linear, repeat_disable;
global uniform vec4 rut_win;
global uniform vec4 rut_ctr;   // (rider x, rider z, fade starts, fade ends): the ruts dissolve with the distance from the RIDER

float rut_depth(vec2 xz) {
	if (rut_win.w < 0.5) return 0.0;
	vec2 uv = (xz - rut_win.xy) / rut_win.z;
	if (uv.x <= 0.0 || uv.y <= 0.0 || uv.x >= 1.0 || uv.y >= 1.0) return 0.0;
	// dissolve with the distance from the rider, smoothly, all the way to zero well inside the window: the window itself
	// hops a tile at a time, so it must never show (a fade tied to its edge popped the ruts in / out in 8 m blocks)
	float f = 1.0 - smoothstep(rut_ctr.z, rut_ctr.w, distance(xz, rut_ctr.xy));
	if (f <= 0.0) return 0.0;
	return textureLod(rut_tex, uv, 0.0).r * f;
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
