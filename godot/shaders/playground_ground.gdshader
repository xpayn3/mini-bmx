shader_type spatial;
// The test playground's ground: vertex colour (grass plane / dirt lanes) with a world-space measuring grid:
// thin lines every 1 m, bold every 5 m, and height contours every 0.25 m (bold every 1 m) on anything built up,
// so heights / distances / angles read off a screenshot.
render_mode cull_back, diffuse_burley, specular_schlick_ggx;
#include "res://shaders/ruts.gdshaderinc"

uniform float line_1m = 0.18;      // darkening of the 1 m lines
uniform float line_5m = 0.38;
uniform float contour = 0.30;
uniform float grid_fade = 140.0;   // lines fade out by this distance (no moire far away)

varying vec3 wpos;
varying vec3 wnrm;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

float grid_line(vec2 p, float period, float width_px) {
	vec2 q = p / period;
	vec2 d = abs(fract(q - 0.5) - 0.5) / max(fwidth(q), vec2(1e-5));
	return 1.0 - clamp(min(d.x, d.y) / width_px, 0.0, 1.0);
}

float iso_line(float v, float period, float width_px) {
	float q = v / period;
	float d = abs(fract(q - 0.5) - 0.5) / max(fwidth(q), 1e-5);
	return 1.0 - clamp(d / width_px, 0.0, 1.0);
}

void fragment() {
	vec3 c = COLOR.rgb;
	float dist = length(wpos - (INV_VIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz);
	float fade = 1.0 - smoothstep(grid_fade * 0.6, grid_fade, dist);
	// the grid is laid on the ground seen from above: on steep faces it is the plan grid projected (still metres in x / z)
	float g1 = grid_line(wpos.xz, 1.0, 0.9);
	float g5 = grid_line(wpos.xz, 5.0, 1.4);
	float dark = max(g1 * line_1m, g5 * line_5m) * fade;
	// contours on built ground (y away from 0)
	float built = smoothstep(0.02, 0.08, abs(wpos.y));
	float c1 = iso_line(wpos.y, 0.25, 0.8);
	float c4 = iso_line(wpos.y, 1.0, 1.3);
	dark = max(dark, max(c1 * contour * 0.6, c4 * contour) * built * fade);
	// a little world noise so the flat isn't plastic
	float n = fract(sin(dot(floor(wpos.xz * 6.0), vec2(12.9898, 78.233))) * 43758.5453);
	c *= 0.94 + 0.06 * n;
	// ruts: the grooves darker, their walls shaded from the dug depth's slope
	float rd = rut_depth(wpos.xz);
	c = rut_colour(c, rd);
	if (rut_win.w > 0.5) NORMAL = normalize((VIEW_MATRIX * vec4(rut_normal(wpos.xz, normalize(wnrm)), 0.0)).xyz);
	ALBEDO = c * (1.0 - dark);
	ROUGHNESS = 0.92 - 0.12 * smoothstep(0.01, 0.06, rd);   // (packed groove bottom: a touch smoother)
	SPECULAR = 0.3;
}
