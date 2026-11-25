// Ruts + tyre prints (world/ruts.gd + RutFieldCs): where tyres rolled, kept in the ground.
// Near: a toroidal window round the rider (5 cm cells, sampled with repeat): rut_tex = (depth m (+ dug, - lip), signed
// distance to the prints' edge (m, < 0 inside, 9 = none: the union of all prints, so it blends cleanly where they
// overlap), strength, blood), rut_dir_tex = (skid smear 0..1, direction (cos 2a, sin 2a) * 0.5 + 0.5).
// rut_win = (x0, z0, size m, on): the window's place.
// Far: 25 cm texels, 200 m round the rider: r = the deepest cell, g = the prints' cover.
// Ground shaders: rut_depth() / rut_normal() / rut_colour() for the grooves, rut_prints() for the tread marks.
global uniform sampler2D rut_tex : filter_linear, repeat_enable;
global uniform sampler2D rut_dir_tex : filter_linear, repeat_enable;
global uniform vec4 rut_win;
global uniform vec4 rut_ctr;   // (rider x, rider z, fade starts, fade ends): the near layer dissolves with the distance from the RIDER

global uniform sampler2D rut_tread_tex : filter_linear_mipmap_anisotropic, repeat_enable;   // the tread, mipmapped (Ruts.tread_texture)
global uniform sampler2D rut_far_tex : filter_linear, repeat_disable;
global uniform vec4 rut_far_win;

const float RUT_FAR_A = 75.0;   // m from the rider: the far layer is full up to here, gone by RUT_FAR_B (its window is >= 92 m wide each way)
const float RUT_FAR_B = 90.0;

// the near window read with a bilinear blend done here (four texelFetch, toroidal): the print's edge is a signed
// distance field and needs a true linear blend between the 5 cm cells, whatever filter the GPU texture's sampler uses
// (the hardware path drew it as a staircase of cells)
vec4 rut_bilerp(sampler2D t, vec2 xz) {
	ivec2 n = textureSize(t, 0);
	vec2 p = xz / (rut_win.z / float(n.x)) - 0.5;
	ivec2 i = ivec2(floor(p));
	vec2 f = p - vec2(i);
	ivec2 i0 = ivec2(((i % n) + n) % n), i1 = ivec2((((i + 1) % n) + n) % n);
	vec4 a = texelFetch(t, i0, 0), b = texelFetch(t, ivec2(i1.x, i0.y), 0);
	vec4 c = texelFetch(t, ivec2(i0.x, i1.y), 0), d = texelFetch(t, i1, 0);
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

bool rut_in_near(vec2 xz) {
	vec2 q = (xz - rut_win.xy) / rut_win.z;
	return rut_win.w > 0.5 && q.x > 0.0 && q.y > 0.0 && q.x < 1.0 && q.y < 1.0;
}
// near / far blend by the distance from the RIDER, smoothly: the windows hop a tile at a time, so their edges must never
// be where anything shows
float rut_near_k(vec2 xz) { return 1.0 - smoothstep(rut_ctr.z, rut_ctr.w, distance(xz, rut_ctr.xy)); }
float rut_far_k(vec2 xz) { return 1.0 - smoothstep(RUT_FAR_A, RUT_FAR_B, distance(xz, rut_ctr.xy)); }
vec2 rut_far_sample(vec2 xz) {
	if (rut_far_win.w < 0.5) return vec2(0.0);
	vec2 uv = (xz - rut_far_win.xy) / rut_far_win.z;
	if (uv.x <= 0.0 || uv.y <= 0.0 || uv.x >= 1.0 || uv.y >= 1.0) return vec2(0.0);
	return textureLod(rut_far_tex, uv, 0.0).rg;
}

float rut_depth(vec2 xz) {
	float fn = rut_near_k(xz);
	float fr = rut_far_k(xz);
	float dn = 0.0;
	float df = 0.0;
	if (fn > 0.0 && rut_in_near(xz)) dn = rut_bilerp(rut_tex, xz).r;
	if (fn < 1.0 && fr > 0.0) df = rut_far_sample(xz).r * fr;
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

// ---- tyre prints (were fx.gd's mesh ribbon + tyre_track.gdshader; the same tread, now in the ground) ----
const float RUT_ROW = 0.024;   // m between knob rows (the tread texture holds two: world/ruts.gd TREAD_ROW)
float rut_hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float rut_vnoise(vec2 p) {
	vec2 i = floor(p), f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(rut_hash(i), rut_hash(i + vec2(1, 0)), f.x), mix(rut_hash(i + vec2(0, 1)), rut_hash(i + vec2(1, 1)), f.x), f.y);
}
// the prints at a point: x = how much of the ground is print here (0..1), y = tread depth 0..1 (the knobs' dimples,
// their average where a pixel is too big for them), z = the lip of pushed-out soil, w = blood on it.
// px = the pixel's size on the ground (m): the knobs fade to their average, the print itself never fades (far off it is
// the far layer's cover: its average shade).
vec4 rut_prints(vec2 xz, float px, out vec2 kslope) {
	kslope = vec2(0.0);
	float fn = rut_near_k(xz);
	vec4 o = vec4(0.0, 0.35, 0.0, 0.0);
	if (fn > 0.0 && rut_in_near(xz)) {
		vec4 s = rut_bilerp(rut_tex, xz);
		float e = s.g;                                  // signed distance to the prints' edge (m, < 0 inside)
		if (e < 0.5 * px && s.b > 0.001) {
			vec4 t = rut_bilerp(rut_dir_tex, xz);
			// across the print: 0 middle .. 1 its edge, from the edge distance (a print is ~4.5 cm half wide), so it
			// stays continuous where prints overlap
			float au = clamp(1.0 + e / 0.045, 0.0, 1.0);
			// how much of it is a skid: any hint of one wipes the knobs out completely (a partial blend at a skid's edges /
			// where it crosses the front print let a faded, smudged copy of the tread and its bump through: user)
			float smear = smoothstep(0.02, 0.25, t.r);
			vec2 c = t.gb * 2.0 - 1.0;
			float a = 0.5 * atan(c.y, c.x);
			vec2 dir = vec2(cos(a), sin(a));
			// metres along the print. The half of a doubled angle comes out either way round between neighbouring cells
			// (where a print runs along the world's z axis), so v and the across position flip sign there: everything
			// drawn from them must look the same both ways (the tread texture is symmetric; the noises read |v|, |am|)
			float v = dot(xz, dir);
			float va = abs(v);
			// soft for its last 3 cm inside the edge; a pixel bigger than that widens the fade (its average kept: no
			// shimmer far off)
			float band = 1.0 - smoothstep(-0.03 - 0.5 * px, 0.5 * px, e);
			// the soil pushed out at its edge: a broad soft band (a 1 cm line flickered once it was smaller than a pixel)
			float lip = smoothstep(-0.03, -0.012, e) * (1.0 - smoothstep(-0.008, 0.004 + px, e));
			// the knobs from the mipmapped tread texture: crisp as far as a pixel resolves them, their average beyond, no
			// shimmer (procedural knobs had to be faded out early and the tread was lost)
			vec2 tuv = vec2(au, v / (2.0 * RUT_ROW));
			vec2 tgx = vec2(px / 0.045, 0.0), tgy = vec2(0.0, px / (2.0 * RUT_ROW));
			float h = textureGrad(rut_tread_tex, tuv, tgx, tgy).r;
			// the knob rows' relief, from the same mipmapped texture (its slope along the print, read two samples a pixel
			// apart): the dimples catch the light up close and flatten with distance exactly as the texture blurs, never
			// shimmering (a per-pixel screen-space slope did). dh/dv x dir does not care which way dir came out.
			float dv = max(px, 0.002);
			float h1 = textureGrad(rut_tread_tex, tuv + vec2(0.0, dv / (2.0 * RUT_ROW)), tgx, tgy).r;
			float h0 = textureGrad(rut_tread_tex, tuv - vec2(0.0, dv / (2.0 * RUT_ROW)), tgx, tgy).r;
			kslope = dir * (-(h1 - h0) / (2.0 * dv) * 0.004 * 3.0) * (1.0 - smear);   // 4 mm dimples, x3 to read
			// a skid: the sliding tyre leaves no knob marks, just a plain pressed-in band (user, 2026-11-25: "just a
			// depression"): the knobs fade out as the skid comes in, nothing else is drawn in it. (Drag lines, grain and
			// stripes were tried first: any fine pattern along a sliding tyre swims and flickers.)
			h = mix(h, 0.3, smear);
			float nv = 0.6 * rut_vnoise(vec2(va * 1.3 + 57.0, au * 1.1 + 7.0)) + 0.4 * rut_vnoise(vec2(va * 6.0, au * 4.0 + 23.0));
			// a skid presses darker and more evenly (no blotchy noise), with more soil pushed up at its edges
			float cover = s.b * band * (0.6 + 0.2 * h) * mix(mix(0.65, 1.15, nv), 1.05, smear);
			o = vec4(cover, h, lip * s.b * (1.0 + smear), s.a);
		}
		o.x *= fn; o.z *= fn;
		kslope *= min(o.x * 1.5, 1.0);
	}
	if (fn < 1.0) o.x += clamp(rut_far_sample(xz).g * 1.4, 0.0, 0.85) * rut_far_k(xz) * (1.0 - fn);
	return o;
}
// the ground under a print: pressed soil darker, the dimples darker still, the lip a touch lighter, blood red
vec3 rut_print_colour(vec3 c, vec4 p) {
	// (the old mesh tracks' look: pressed soil darker, the knobs' dimples darker still, the lip a touch lighter)
	vec3 pc = c * (0.62 - 0.2 * p.y) + c * 0.1 * p.z;
	pc = mix(pc, vec3(0.32, 0.012, 0.01), p.w * 0.9);
	return mix(c, pc, clamp(p.x, 0.0, 1.0));
}
