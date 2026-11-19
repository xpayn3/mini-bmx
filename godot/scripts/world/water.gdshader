// Tropical stylised water (port of water.js): gerstner-ish swell in the vertex shader (damped near the
// shore), fine drifting ripple normals, depth-tinted lagoon colours, sky fresnel, sun glints and foam
// lines rolling in to the beach. Depth comes from a small texture baked from the terrain round the player.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;
#include "res://shaders/atmos.gdshaderinc"

uniform float u_time = 0.0;
uniform sampler2D u_depth : filter_linear, repeat_disable;
uniform vec2 u_center = vec2(0.0);
uniform float u_size = 128.0;
uniform vec3 u_sun_dir = vec3(0.45, 0.8, 0.35);
uniform vec3 u_sun_col = vec3(1.0, 0.96, 0.85);
uniform vec3 u_shallow : source_color = vec3(0.22, 0.925, 0.824);
uniform vec3 u_mid : source_color = vec3(0.059, 0.725, 0.8);
uniform vec3 u_deep : source_color = vec3(0.027, 0.404, 0.69);
uniform vec3 u_sky_h : source_color = vec3(0.784, 0.933, 0.969);
uniform vec3 u_sky_z : source_color = vec3(0.424, 0.765, 0.925);
varying vec3 v_world;
varying float v_depth;
varying vec3 v_wave_n;

// smooth (cubic B-spline, 4 bilinear taps) depth lookup: bilinear on the 1 m bake showed the texel grid
// as stair steps in the shore foam and the shallow tint
float depth_tex(vec2 uv) {
	vec2 res = vec2(textureSize(u_depth, 0));
	vec2 st = uv * res - 0.5;
	vec2 i = floor(st), f = st - i;
	vec2 f2 = f * f, f3 = f2 * f;
	vec2 w0 = (1.0 - 3.0 * f + 3.0 * f2 - f3) / 6.0;
	vec2 w1 = (4.0 - 6.0 * f2 + 3.0 * f3) / 6.0;
	vec2 w2 = (1.0 + 3.0 * f + 3.0 * f2 - 3.0 * f3) / 6.0;
	vec2 w3 = f3 / 6.0;
	vec2 g0 = w0 + w1, g1 = w2 + w3;
	vec2 h0 = (i - 0.5 + w1 / g0) / res, h1 = (i + 1.5 + w3 / g1) / res;
	float a = textureLod(u_depth, vec2(h0.x, h0.y), 0.0).r, b = textureLod(u_depth, vec2(h1.x, h0.y), 0.0).r;
	float c = textureLod(u_depth, vec2(h0.x, h1.y), 0.0).r, d = textureLod(u_depth, vec2(h1.x, h1.y), 0.0).r;
	return mix(mix(a, b, g1.x), mix(c, d, g1.x), g1.y);
}

float depth_at(vec2 xz) {
	vec2 uv = (xz - u_center) / u_size + 0.5;
	// fade to "deep" over the last few metres of the baked square instead of a hard edge
	vec2 e = min(uv, 1.0 - uv) * u_size;
	float inside = smoothstep(1.0, 6.0, min(e.x, e.y));
	return mix(1.5, depth_tex(clamp(uv, 0.0, 1.0)), inside);
}

void wave(vec2 p, vec2 dir, float L, float A, inout float h, inout vec2 g) {
	vec2 d = normalize(dir);
	float k = 6.2831853 / L;
	float c = sqrt(9.81 / k) * 0.45;
	float f = k * (dot(d, p) - c * u_time);
	h += A * sin(f);
	g += A * k * cos(f) * d;
}

// integer hash of a lattice point (the old sin() hash lost precision far from the origin -> blocky noise)
float hash(vec2 p) {
	uvec2 q = uvec2(ivec2(p)) * uvec2(1597334673u, 3812015801u);
	uint n = (q.x ^ q.y) * 1597334673u;
	return float(n >> 8u) * (1.0 / 16777216.0);
}
float hash1(float x) { return hash(vec2(x, 913.0)); }
// quintic fade: the noise slope is smooth across cells (cubic left creases = faceted, square-ish shading)
float vnoise(vec2 p) {
	vec2 i = floor(p), f = fract(p);
	vec2 u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), u.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), u.x), u.y);
}
vec3 noised(vec2 p) {
	vec2 i = floor(p), f = fract(p);
	vec2 u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0), du = 30.0 * f * f * (f * (f - 2.0) + 1.0);
	float a = hash(i), b = hash(i + vec2(1, 0)), c = hash(i + vec2(0, 1)), d = hash(i + vec2(1, 1));
	float k = a - b - c + d;
	return vec3(a + (b - a) * u.x + (c - a) * u.y + k * u.x * u.y, du * (vec2(b - a, c - a) + k * u.yx));
}
vec2 ripples(vec2 p, float t, float px) {
	vec2 g = vec2(0.0);
	float amp = 0.05, freq = 1.1;
	mat2 M = mat2(1.0);
	mat2 ROT = mat2(vec2(0.80, -0.60), vec2(0.60, 0.80));
	for (int i = 0; i < 6; i++) {
		M = ROT * M;
		float fi = float(i);
		vec2 wind = vec2(cos(fi * 0.45 + 0.3), sin(fi * 0.45 + 0.3));
		vec2 drift = wind * t * (0.3 + 0.18 * fi);
		vec2 q = (M * p) * freq;
		q = vec2(q.x * 0.55, q.y) + drift + fi * 17.3;
		vec2 gq = noised(q).yz * vec2(0.55, 1.0);
		float fade = 1.0 - smoothstep(0.15, 0.45, freq * px);
		g += (gq * M) * amp * freq * fade;
		freq *= 1.85; amp *= 0.56;
	}
	return g;
}

void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float d = depth_at(wp.xz);
	float damp = smoothstep(-0.05, 0.5, d) * 0.85 + 0.15;
	float h = 0.0; vec2 g = vec2(0.0);
	wave(wp.xz, vec2(1.0, 0.30), 4.6, 0.030, h, g);
	wave(wp.xz, vec2(-0.4, 1.00), 3.1, 0.022, h, g);
	wave(wp.xz, vec2(0.7, -0.80), 2.2, 0.014, h, g);
	wave(wp.xz, vec2(-1.0, -0.25), 6.8, 0.026, h, g);
	wave(wp.xz, vec2(0.2, 1.00), 1.6, 0.008, h, g);
	h *= 1.8;   // the swell read too faint
	g *= 1.8;
	VERTEX.y += h * damp;
	v_wave_n = normalize(vec3(-g.x * damp, 1.0, -g.y * damp));
	v_world = wp + vec3(0.0, h * damp, 0.0);
	v_depth = d;
}

void fragment() {
	float d = max(v_depth, 0.0);
	vec3 cam = (INV_VIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float dist = length(cam - v_world);
	float px = length(fwidth(v_world.xz));
	vec2 rg = ripples(v_world.xz, u_time, px);
	vec3 N = normalize(v_wave_n + vec3(-rg.x, 0.0, -rg.y));
	vec3 V = normalize(cam - v_world);
	vec3 L = normalize(u_sun_dir);
	float t1 = exp(-d * 1.9), t2 = exp(-d * 0.55);
	vec3 col = mix(u_deep, u_mid, t2);
	col = mix(col, u_shallow, t1);
	float tint = vnoise(v_world.xz * 0.045 + 3.1) * 0.65 + vnoise(v_world.xz * 0.11 - 7.7) * 0.35;
	col *= mix(0.93, 1.07, tint);
	col = mix(col, col * vec3(0.92, 1.04, 1.0), smoothstep(0.4, 0.8, tint) * 0.6);
	float slopeK = clamp(length(N.xz) * 5.0, 0.0, 1.0);
	col += u_shallow * slopeK * 0.06 * (1.0 - t1 * 0.5);
	vec3 R = reflect(-V, N);
	vec3 sky = mix(u_sky_h, u_sky_z, smoothstep(0.0, 0.65, R.y));
	float fres = 0.02 + 0.98 * pow(1.0 - max(dot(N, V), 0.0), 5.0);
	vec3 refl = sky * clamp(fres * 1.25, 0.0, 0.8);
	col *= 1.0 - clamp(fres * 1.25, 0.0, 0.8);
	vec3 H = normalize(L + V);
	float nh = max(dot(N, H), 0.0);
	float glint = (pow(nh, 700.0) * 2.2 / (1.0 + dist * 0.025) + pow(nh, 60.0) * 0.18) * smoothstep(0.7, 1.0, cloud_shade(v_world));
	// foam: lines rolling in to the beach (shore distance approximated from the depth) + edge foam
	vec2 wp = v_world.xz;
	float sd = d / 0.12;
	float wob = vnoise(wp * 0.12 + 4.0) * 1.2 + vnoise(wp * 0.35 - 2.0) * 0.35;
	// the swell's clock wanders (sets of waves come quicker / slower) but never runs backwards
	float clock = u_time * 0.28 + 0.045 * sin(u_time * 0.173) + 0.03 * sin(u_time * 0.071 + 1.3);
	float phase = pow(max(sd, 0.0), 0.8) / 1.8 + clock + wob;
	float s = fract(phase);
	// every wave its own size, and it breaks in patches along the shore: no identical line looping in
	float wave_id = floor(phase);
	float wsz = hash1(wave_id);
	float patchy = smoothstep(0.25, 0.65, vnoise(wp * 0.07 + vec2(wave_id * 3.7, wave_id * 1.9)) * 0.7 + wsz * 0.5);
	float wk = mix(0.65, 1.0, wsz) * mix(0.55, 1.0, patchy);
	// rotated, unaligned octaves: thresholded axis-aligned noise broke the froth into little squares
	vec2 lw = mat2(vec2(0.8, -0.6), vec2(0.6, 0.8)) * wp;
	vec2 lw2 = mat2(vec2(0.28, 0.96), vec2(-0.96, 0.28)) * wp;
	float lace = vnoise(lw * 2.4 + vec2(u_time * 0.15, -u_time * 0.11) + vnoise(wp * 0.9) * 1.5) * 0.6
		+ vnoise(lw2 * 5.3 - u_time * 0.2) * 0.4;
	float line = smoothstep(0.0, 0.025, s) * (1.0 - smoothstep(0.06, 0.15, s)) * mix(0.7, 1.0, lace);
	float froth = smoothstep(0.04, 0.09, s) * (1.0 - smoothstep(0.1, 0.5, s)) * smoothstep(0.4, 0.85, lace) * 0.6;
	float approach = (1.0 - smoothstep(1.5, 8.0, sd)) * smoothstep(0.02, 0.08, d);
	float waves = (line * 1.25 + froth) * approach * wk;
	float ap = clock + wob;
	float arrive = smoothstep(0.75, 1.0, fract(ap)) * mix(0.3, 1.0, hash1(floor(ap) + 101.0));
	float n1 = vnoise(wp * 1.6 + u_time * 0.2), n2 = vnoise(wp * 4.5 - u_time * 0.3);
	float lip = 1.0 - smoothstep(0.0, 0.07 + n1 * 0.06 + arrive * 0.07, d);
	float foam = clamp(max(lip * mix(0.55, 1.0, n2), waves), 0.0, 1.0);
	col = mix(col, vec3(1.0), foam * 0.85);
	ALBEDO = col;
	EMISSION = refl * (1.0 - foam) + u_sun_col * glint * (1.0 - foam);
	NORMAL = normalize((VIEW_MATRIX * vec4(N, 0.0)).xyz);
	ROUGHNESS = mix(0.06, 0.6, foam);
	SPECULAR = 0.5;
	float alpha = mix(0.55, 0.95, 1.0 - t2);
	alpha = max(alpha, foam * 0.95);
	alpha *= smoothstep(-0.02, 0.06, v_depth + 0.06);
	ALPHA = alpha;
}
