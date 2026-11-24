// Ruts (world/ruts.gd + RutFieldCs): the dug-in depth round the rider as a window texture (RH, m, + = dug, - = lip).
// rut_win = (x0, z0, size m, on). Ground shaders: rut_depth() for colour, rut_normal() to shade the grooves' walls.
global uniform sampler2D rut_tex : filter_linear, repeat_disable;
global uniform vec4 rut_win;

float rut_depth(vec2 xz) {
	if (rut_win.w < 0.5) return 0.0;
	vec2 uv = (xz - rut_win.xy) / rut_win.z;
	if (uv.x <= 0.0 || uv.y <= 0.0 || uv.x >= 1.0 || uv.y >= 1.0) return 0.0;
	// soft out over the window's last tenth (no straight cut where the window ends)
	vec2 e = min(uv, 1.0 - uv);
	return textureLod(rut_tex, uv, 0.0).r * smoothstep(0.0, 0.1, min(e.x, e.y));
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
