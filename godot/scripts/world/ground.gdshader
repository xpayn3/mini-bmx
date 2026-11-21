// Terrain ground (port of grounddetail.js): two baked layers -- land and trail dirt -- blended by
// HEIGHT, not a soft fade, so trail edges come out ragged (stones poke through, grass creeps over the
// dirt). Procedural world-space detail fades out before it gets smaller than a pixel.
//   land_tex rgb = land colour (with baked AO)   a = dirt weight
//   dirt_tex rgb = trail dirt colour (with AO)   a = rock-face weight
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;
#include "res://shaders/atmos.gdshaderinc"

uniform sampler2D land_tex : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D dirt_tex : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
varying vec3 v_world;
// the grass carpet's window (world/grass_field.gd): a = how much grass grows here; info = origin xz, texel, radius (0 = off)
global uniform sampler2D grass_win : filter_linear;
global uniform vec4 grass_win_info;

vec3 gd_hash3(vec2 p) {
	vec3 q = fract(vec3(p.xyx) * vec3(0.1031, 0.1030, 0.0973));
	q += dot(q, q.yxz + 33.33);
	return fract((q.xxy + q.yzz) * q.zyx);
}
float gd_hash(vec3 p) { p = fract(p * 0.1031); p += dot(p, p.zyx + 31.32); return fract((p.x + p.y) * p.z); }
float gd_noise3(vec3 p) {
	vec3 i = floor(p), f = fract(p), u = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(gd_hash(i), gd_hash(i + vec3(1, 0, 0)), u.x), mix(gd_hash(i + vec3(0, 1, 0)), gd_hash(i + vec3(1, 1, 0)), u.x), u.y),
	           mix(mix(gd_hash(i + vec3(0, 0, 1)), gd_hash(i + vec3(1, 0, 1)), u.x), mix(gd_hash(i + vec3(0, 1, 1)), gd_hash(i + vec3(1, 1, 1)), u.x), u.y), u.z);
}
vec2 gd_pebbles(vec2 p) {
	p += (vec2(gd_noise3(vec3(p * 1.7, 3.1)), gd_noise3(vec3(p * 1.7, 8.7))) - 0.5) * 0.5;
	vec2 i = floor(p), f = fract(p);
	vec2 best = vec2(0.0);
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 g = vec2(float(x), float(y));
			vec3 h = gd_hash3(i + g + 17.0);
			if (h.z < 0.55) continue;
			float r = 0.07 + 0.22 * (h.z - 0.55) * (h.z - 0.55) * 4.0;
			vec2 dv = (g + 0.2 + 0.6 * h.xy - f) * vec2(1.0, 0.75 + 0.5 * h.x);
			float k = 1.0 - smoothstep(r * 0.4, r, length(dv));
			if (k > best.x) best = vec2(k, h.y * 2.0 - 0.6);
		}
	}
	return best;
}

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec4 gA = texture(land_tex, UV), gB = texture(dirt_tex, UV);
	vec3 P = v_world;
	float gpx = length(fwidth(P.xz));
	float f1 = 1.0 - smoothstep(0.012, 0.04, gpx);
	float f2 = 1.0 - smoothstep(0.035, 0.12, gpx);
	float f3 = 1.0 - smoothstep(0.1, 0.45, gpx);
	float t = gA.a, rockW = gB.a;
	float n0 = gd_noise3(P * 2.3 + 3.3), n1 = gd_noise3(P * 9.0), n2 = gd_noise3(P * 23.0 + 7.1);
	float hG = mix(0.5, n1, f2) * 0.55 + mix(0.5, n2, f1) * 0.25 + n0 * 0.2;
	vec2 pb = gd_pebbles(P.xz * 16.0);   // fine grit: ~6 cm cells
	float peb = pb.x * (1.0 - smoothstep(0.018, 0.06, gpx));   // gone before they're smaller than a pixel
	float hD = peb * 0.6 + gd_noise3(P * 3.1 + 11.0) * 0.45 + gd_noise3(P * 0.9 + 2.0) * 0.3;
	float a1 = (1.0 - t) + hG * 0.75, a2 = t + hD * 0.75;
	float m = max(a1, a2) - 0.28;
	float b1 = max(a1 - m, 0.0), b2 = max(a2 - m, 0.0);
	float wd = mix(t, b2 / max(b1 + b2, 1e-4), f3);
	vec3 col = mix(gA.rgb, gB.rgb, wd);
	col *= mix(1.0, 1.0 + peb * 0.2 * pb.y + (n2 - 0.5) * 0.14 * f1, wd);
	float rk = gd_noise3(P * 4.3 + 5.0) * 0.6 + gd_noise3(P * 13.0) * 0.4 * f2;
	col *= mix(1.0, 0.78 + 0.44 * rk, rockW * (1.0 - wd) * f3);
	// under the grass carpet the floor is the shaded ground between the blades: darker and a touch greener,
	// the colour of the blades' roots, fading back to the plain land colour where the blades end
	if (grass_win_info.w > 0.0) {
		vec2 guv = ((P.xz - grass_win_info.xy) / grass_win_info.z + 0.5) / 481.0;
		if (guv.x > 0.0 && guv.x < 1.0 && guv.y > 0.0 && guv.y < 1.0) {
			float gden = clamp(texture(grass_win, guv).a * 1.6, 0.0, 1.0);
			float gd = length(P.xz - CAMERA_POSITION_WORLD.xz);
			float gfar = 1.0 - smoothstep(grass_win_info.w - 24.0, grass_win_info.w, gd);
			float under = gden * gfar * (1.0 - wd);
			col = mix(col, col * vec3(0.66, 0.76, 0.56), under * 0.85);
		}
	}
	ALBEDO = col;
	ROUGHNESS = 0.95;
	SPECULAR = 0.3;
}

// lit by hand only so cloud shadows can dim the sun here (shaders/atmos); ground is matte (roughness .95)
void light() {
	DIFFUSE_LIGHT += atmos_diffuse(NORMAL, LIGHT, ATTENUATION * LIGHT_COLOR, LIGHT_IS_DIRECTIONAL, v_world, 0.0);
}
