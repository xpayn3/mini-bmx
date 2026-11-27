// The fine snow round the rider (world/snow_patch.gd): a ~6 cm grid whose height = the ground + the snow's depth, cut down
// to a packed floor where a tyre / shoe print lies in the rut field (the prints' signed edge distance), a little snow
// pushed up beside each trench. Draws only deep snow inside the patch, on exactly the pixels ground.gdshader leaves.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;
#include "res://shaders/atmos.gdshaderinc"
#include "res://shaders/ruts.gdshaderinc"
#include "res://shaders/snow_glint.gdshaderinc"

uniform sampler2D win_h : filter_linear, repeat_disable;     // ground heights, 0.5 m (the chunks' grass_h)
uniform sampler2D win_s : filter_linear, repeat_disable;     // R snow cover, G depth 0..1
uniform vec2 win_origin;
uniform float win_texel = 0.5;
uniform float depth = 0.2;
uniform float cell = 0.0625;
uniform float sparkle = 1.0;
uniform float scatter = 0.35;
global uniform vec4 snow_patch;
global uniform sampler2D grass_win : filter_linear;
global uniform vec4 grass_win_info;

varying vec3 v_world;
varying float v_carve;
varying float v_lip;
varying vec4 v_glint;

vec2 win_uv(vec2 xz) { return ((xz - win_origin) / win_texel + 0.5) / vec2(textureSize(win_h, 0)); }

float sp_hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float sp_noise(vec2 p) {
	vec2 i = floor(p), f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(sp_hash(i), sp_hash(i + vec2(1, 0)), f.x), mix(sp_hash(i + vec2(0, 1)), sp_hash(i + vec2(1, 1)), f.x), f.y);
}

// the snow's top at a point: y, carve 0..1, lip 0..1
vec3 snow_top(vec2 xz) {
	vec2 uv = win_uv(xz);
	float g = textureLod(win_h, uv, 0.0).r;
	float lf = textureLod(win_s, uv, 0.0).g;
	float rd = 0.0, e = 9.0, st = 0.0;
	if (rut_in_near(xz)) {
		vec4 r = rut_bilerp(rut_tex, xz);
		rd = r.r; e = r.g; st = r.b;
	}
	// the trench: full inside the print (e < 0), its wall out to ~5 cm; snow shoved up just beyond it
	float carve = (1.0 - smoothstep(-0.02, 0.1, e)) * step(0.0005, st);
	float lip = smoothstep(0.08, 0.13, e) * (1.0 - smoothstep(0.14, 0.28, e)) * step(0.0005, st);
	// soft drifts (+-2 cm) so a flat field isn't a ruler
	float drift = (sp_noise(xz * 0.35) - 0.5) * 0.1 + (sp_noise(xz * 1.3 + 7.0) - 0.5) * 0.04;
	float lift = depth * lf * (1.0 + drift);
	float y = g - rd + lift * (1.0 - 0.9 * carve) + lift * 0.25 * lip;
	return vec3(y, carve * smoothstep(0.02, 0.2, lf), lip * lf);
}

float patch_k(vec2 xz) {
	if (snow_patch.w < 0.5) return 0.0;
	vec2 d = abs(xz - snow_patch.xy);
	return 1.0 - smoothstep(snow_patch.z - 3.0, snow_patch.z - 0.6, max(d.x, d.y));
}

void vertex() {
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 t = snow_top(w.xz);
	float hx0 = snow_top(w.xz - vec2(cell, 0.0)).x, hx1 = snow_top(w.xz + vec2(cell, 0.0)).x;
	float hz0 = snow_top(w.xz - vec2(0.0, cell)).x, hz1 = snow_top(w.xz + vec2(0.0, cell)).x;
	w.y = t.x;
	v_carve = t.y;
	v_lip = t.z;
	VERTEX = (inverse(MODEL_MATRIX) * vec4(w, 1.0)).xyz;
	NORMAL = normalize(vec3(hx0 - hx1, 2.0 * cell, hz0 - hz1));
	v_world = w;
}

void fragment() {
	vec3 P = v_world;
	vec4 sw = texture(win_s, win_uv(P.xz));
	if (PROJECTION_MATRIX[3][3] < 0.5) {
		// the ground draws the pixels it keeps (ground.gdshader: same pattern, its deep snow > 0.06 handed over)
		float gn = fract(52.9829189 * fract(dot(FRAGCOORD.xy, vec2(0.06711056, 0.00583715))));
		if (sw.g < 0.04 || gn >= patch_k(P.xz)) discard;
	} else if (sw.g < 0.04) {
		discard;
	}
	float old_s = smoothstep(0.35, 0.75, sp_noise(P.xz * 0.035 + 3.0));
	vec3 snowc = mix(vec3(0.80, 0.83, 0.87), vec3(0.70, 0.72, 0.75), old_s * 0.6) * (0.96 + 0.08 * sp_noise(P.xz * 0.16));
	// the trench floor is packed, a little greyer; its walls catch less sky (a touch darker)
	vec3 packed = vec3(0.56, 0.59, 0.64);
	vec3 col = mix(snowc, packed, v_carve * 0.85);
	col *= 1.0 - 0.18 * v_carve;   // (the trench holds shade: less sky reaches its floor)
	// thin snow at the patches' edges lets the land show through (its colour from the grass window)
	if (grass_win_info.w > 0.0) {
		vec2 guv = ((P.xz - grass_win_info.xy) / grass_win_info.z + 0.5) / 481.0;
		if (guv.x > 0.0 && guv.y > 0.0 && guv.x < 1.0 && guv.y < 1.0) {
			vec3 land = texture(grass_win, guv).rgb;
			land = land * land;   // (sRGB-ish to linear, near enough)
			col = mix(land, col, smoothstep(0.04, 0.3, sw.g));
		}
	}
	// the crust: wind-packed lumps + fine grain (fading with the pixel's size), and a slightly glazed sheen in patches
	float gpx = length(fwidth(P.xz));
	vec3 wn = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vec2 cs = snow_crust(P.xz, 1.0 - smoothstep(0.01, 0.04, gpx)) * (1.0 - smoothstep(0.05, 0.2, gpx)) * (1.0 - v_carve * 0.7);
	wn = normalize(wn - vec3(cs.x, 0.0, cs.y));
	NORMAL = normalize((VIEW_MATRIX * vec4(wn, 0.0)).xyz);
	float glaze = smoothstep(0.55, 0.8, sp_noise(P.xz * 0.5 + 11.0));
	col *= 0.97 + 0.06 * sp_noise(P.xz * 3.0);
	ALBEDO = col;
	ROUGHNESS = mix(mix(0.72, 0.5, glaze), 0.55, v_carve);
	SPECULAR = 0.35;
	v_glint = snow_glint(P.xz, wn, gpx, VIEW_MATRIX);
	v_glint.w *= sparkle * (1.0 - v_carve);
}

void light() {
	vec3 lc = atmos_light_col(ATTENUATION * LIGHT_COLOR, LIGHT_IS_DIRECTIONAL, v_world);
	float ndl = dot(NORMAL, LIGHT);
	DIFFUSE_LIGHT += clamp((ndl + scatter) / (1.0 + scatter), 0.0, 1.0) * lc;
	if (ndl > 0.0) {
		// the same sheen as ground.gdshader (so the patch and the ground beside it match), then the glitter
		vec3 hv = normalize(LIGHT + VIEW);
		float nh = clamp(dot(NORMAL, hv), 0.0, 1.0), lh = max(dot(LIGHT, hv), 0.2);
		float a2 = ROUGHNESS * ROUGHNESS; a2 *= a2;
		float dd = nh * nh * (a2 - 1.0) + 1.0;
		float sp = a2 / (PI * dd * dd) * 0.04 / (4.0 * lh * lh);
		SPECULAR_LIGHT += lc * PI * ndl * min(sp, 4.0) * max(0.9 - ROUGHNESS, 0.0) / 0.9;
		SPECULAR_LIGHT += snow_glint_light(v_glint, LIGHT, VIEW, lc);
	}
}
