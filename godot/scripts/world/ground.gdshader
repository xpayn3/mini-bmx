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
// trail scans (assets/textures/trail, Poly Haven CC0): colour ratio + normal xy / roughness for packed dirt, wet mud,
// stones in dirt, loose gravel. Each has its own size and turn and they are mixed by world noise, so no tile repeats.
uniform sampler2D tr_col0 : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D tr_col1 : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D tr_col2 : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D tr_col3 : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D tr_nr0 : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D tr_nr1 : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D tr_nr2 : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D tr_nr3 : filter_linear_mipmap_anisotropic, repeat_enable;
uniform float trail_scans = 1.0;   // 0 = plain trail colour (no scans bound)
uniform float trail_bump = 1.0;
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
// one trail scan at a world point: a = (cos, sin) of its turn, inv = 1 / its size in metres.
// col = colour as a ratio to the scan's mean; nr.xy = the surface normal's lean in world x / z, nr.z = roughness
void gd_trail(sampler2D ct, sampler2D nt, vec2 p, vec2 dx, vec2 dy, vec2 a, float inv, out vec3 col, out vec3 nr) {
	vec2 b = vec2(-a.y, a.x);
	vec2 uv = vec2(dot(p, a), dot(p, b)) * inv;
	vec2 gx = vec2(dot(dx, a), dot(dx, b)) * inv, gy = vec2(dot(dy, a), dot(dy, b)) * inv;
	col = textureGrad(ct, uv, gx, gy).rgb * 2.0;
	vec3 n = textureGrad(nt, uv, gx, gy).rgb;
	n.xy = n.xy * 2.0 - 1.0;
	nr = vec3(a * n.x - b * n.y, n.z);
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
	// ---- the trail's surface: four scans mixed by height (stones stand out of the mud, gravel fills the low spots) ----
	vec3 tcol = vec3(1.0);     // colour ratio on top of the baked trail colour
	vec2 tslope = vec2(0.0);   // the normal's lean, world x / z
	float trough = 0.95, th = 0.5;
	float tfade = (1.0 - smoothstep(0.2, 0.5, gpx)) * trail_scans;   // far off the scans average out to the plain colour
	vec2 pdx = dFdx(P.xz), pdy = dFdy(P.xz);
	if (t > 0.004 && tfade > 0.0) {
		const vec3 LUM = vec3(0.2126, 0.7152, 0.0722);
		// where each one lies: patches tens of metres long; dark (damp) dirt gets more mud, pale dry dirt more gravel,
		// rock faces more stones, loose gravel gathers along the trail's edges
		float dark = 1.0 - smoothstep(0.15, 0.45, dot(gB.rgb, LUM));
		float m1 = gd_noise3(vec3(P.xz * 0.13, 1.7)), m2 = gd_noise3(vec3(P.xz * 0.09 + 40.0, 5.3)), m3 = gd_noise3(vec3(P.xz * 0.21 + 90.0, 9.1));
		float edge = smoothstep(0.2, 0.55, t) * (1.0 - smoothstep(0.7, 0.97, t));
		float w0 = 0.5;
		float w1 = smoothstep(0.45, 0.72, m1) * (0.45 + 0.65 * dark);
		float w2 = smoothstep(0.42, 0.72, m2) * 0.75 + rockW * 0.7;
		float w3 = smoothstep(0.45, 0.75, m3) * (0.4 + 0.5 * (1.0 - dark)) + edge * 0.45;
		// only the scans that can show here are read (mostly one or two of the four): the height part below adds
		// at most 0.25, the blend band is 0.14
		float need = max(max(w0, w1), max(w2, w3)) - 0.4;
		vec3 c0 = vec3(1.0), c1 = vec3(1.0), c2 = vec3(1.0), c3 = vec3(1.0);
		vec3 r0 = vec3(0.0, 0.0, 0.9), r1 = r0, r2 = r0, r3 = r0;
		float h0 = 0.5, h1 = 0.5, h2 = 0.5, h3 = 0.5;
		if (w0 > need) { gd_trail(tr_col0, tr_nr0, P.xz, pdx, pdy, vec2(0.955, 0.296), 1.0 / 1.7, c0, r0); h0 = dot(c0, LUM) * 0.5; w0 += h0 * 0.25; } else { w0 = -1.0; }
		if (w1 > need) { gd_trail(tr_col1, tr_nr1, P.xz, pdx, pdy, vec2(0.454, 0.891), 1.0 / 1.45, c1, r1); h1 = dot(c1, LUM) * 0.5; w1 += (1.0 - h1) * 0.2; } else { w1 = -1.0; }   // mud sits in the low spots
		if (w2 > need) { gd_trail(tr_col2, tr_nr2, P.xz, pdx, pdy, vec2(-0.416, 0.909), 1.0 / 2.3, c2, r2); h2 = dot(c2, LUM) * 0.5; w2 += h2 * 0.25; } else { w2 = -1.0; }
		if (w3 > need) { gd_trail(tr_col3, tr_nr3, P.xz, pdx, pdy, vec2(-0.904, 0.427), 1.0 / 2.6, c3, r3); h3 = dot(c3, LUM) * 0.5; w3 += h3 * 0.25; } else { w3 = -1.0; }
		float wm = max(max(w0, w1), max(w2, w3)) - 0.14;
		w0 = max(w0 - wm, 0.0); w1 = max(w1 - wm, 0.0); w2 = max(w2 - wm, 0.0); w3 = max(w3 - wm, 0.0);
		float ws = 1.0 / (w0 + w1 + w2 + w3);
		w0 *= ws; w1 *= ws; w2 *= ws; w3 *= ws;
		vec3 tc = c0 * w0 + c2 * w2 + c3 * (w3 * 1.08);
		tc = max(1.0 + (tc - (w0 + w2 + w3 * 1.08)) * 1.3, vec3(0.05)) * (w0 + w2 + w3 * 1.08) + c1 * (w1 * 0.62);   // a little more contrast; wet mud is darker
		tcol = mix(vec3(1.0), tc, tfade);
		tslope = (r0.xy * w0 + r1.xy * w1 + r2.xy * (w2 * 1.2) + r3.xy * w3) * (1.5 * tfade);
		trough = mix(0.95, r0.z * w0 + r1.z * (w1 * 0.62) + r2.z * w2 + r3.z * w3, tfade);
		th = mix(0.5, h0 * w0 + h1 * w1 + h2 * w2 + h3 * w3, tfade);
	}
	float hD = th * 0.6 + gd_noise3(P * 3.1 + 11.0) * 0.45 + gd_noise3(P * 0.9 + 2.0) * 0.3;
	float a1 = (1.0 - t) + hG * 0.75, a2 = t + hD * 0.75;
	float m = max(a1, a2) - 0.28;
	float b1 = max(a1 - m, 0.0), b2 = max(a2 - m, 0.0);
	float wd = mix(t, b2 / max(b1 + b2, 1e-4), f3);
	// slow light / dark drifts along the trail, so a long straight never reads as one flat band
	float drift = 1.0 + (gd_noise3(vec3(P.xz * 0.05, 4.2)) - 0.5) * 0.22 + (n0 - 0.5) * 0.1;
	vec3 col = mix(gA.rgb, gB.rgb * tcol * drift, wd);
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
	ROUGHNESS = mix(0.95, trough, wd);
	SPECULAR = 0.3;
	if (wd * tfade > 0.0) {
		vec3 nw = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
		nw = normalize(nw + vec3(tslope.x, 0.0, tslope.y) * (wd * trail_bump));
		NORMAL = normalize((VIEW_MATRIX * vec4(nw, 0.0)).xyz);
	}
}

// lit by hand only so cloud shadows can dim the sun here (shaders/atmos); land is matte (roughness .95),
// wet mud / worn stones on the trail get a soft sun glint
void light() {
	DIFFUSE_LIGHT += atmos_diffuse(NORMAL, LIGHT, ATTENUATION * LIGHT_COLOR, LIGHT_IS_DIRECTIONAL, v_world, 0.0);
	if (ROUGHNESS < 0.9) {
		vec3 hv = normalize(LIGHT + VIEW);
		float nl = clamp(dot(NORMAL, LIGHT), 0.0, 1.0), nh = clamp(dot(NORMAL, hv), 0.0, 1.0), lh = max(dot(LIGHT, hv), 0.2);
		float a2 = ROUGHNESS * ROUGHNESS; a2 *= a2;
		float dd = nh * nh * (a2 - 1.0) + 1.0;
		float sp = a2 / (PI * dd * dd) * 0.04 / (4.0 * lh * lh);
		SPECULAR_LIGHT += atmos_light_col(ATTENUATION * LIGHT_COLOR, LIGHT_IS_DIRECTIONAL, v_world) * PI * nl * min(sp, 4.0) * (0.9 - ROUGHNESS) / 0.9;
	}
}
