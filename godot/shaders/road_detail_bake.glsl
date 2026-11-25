#[compute]
#version 450
// Road detail bake (world/road_detail.gd): the trail's surface marks, worked out ONCE per texel of a camera-following
// clipmap and kept in textures, so the ground shader reads them with mipmaps (distance blurs them into their average,
// like a racing game's road texture) instead of working them out per pixel and switching them off by pixel size.
//
// One dispatch = one 64 x 64-texel tile of one clipmap level, lying wholly inside one 48 m terrain chunk (the levels'
// cells divide 48 m and the tiles line up with chunk edges), reading that chunk's baked trail frame textures.
//
// Outputs (the texture layout, also documented in road_detail.gd LAYOUT):
//   A rgba8   r = colour multiplier k / 2, g = tyre prints, b = damp soil, a = standing water (before "level ground")
//   B rgba16f rg = slope (d height / dx, dz) of the surface relief (m/m), b = mean squared slope (bumpiness the mips
//             average away: the ground shader turns what is lost into roughness), a = pebble height 0..1 (dirt / land blend)
//   C rgba8   r = baked (1; 0 = nothing here yet), g = ridden lines, b = loose grit, a = edge stones
//
// Each texel is supersampled (S x S samples, pc.b.w) and every mark is drawn with an area-preserving filter of the
// sample spacing (lineaa), so even the coarse level is band-limited: no aliasing to fade out.
//
// ADDING A LAYER: write a `void layer_x(inout Surf s, Ctx c)` below, call it from surface(), give it its Params slot
// (road_detail.gd PARAMS, same order as P[] here) and, if it needs its own channel, add it to Surf + the outputs.
layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(set = 0, binding = 0) uniform sampler2D trail_tex;    // r across (m, signed), g ridden line place, b along (m), a run-off skid place
layout(set = 0, binding = 1) uniform sampler2D trail2_tex;   // r road, g dry biome, b built jump, a skid strength
layout(set = 0, binding = 2) uniform sampler2D trail3_tex;   // r riders in the air, g corner load
layout(set = 0, binding = 3) uniform sampler2D land_tex;     // a = trail dirt weight
layout(set = 0, binding = 4, rgba8) uniform restrict writeonly image2D out_a;
layout(set = 0, binding = 5, rgba16f) uniform restrict writeonly image2D out_b;
layout(set = 0, binding = 6, rgba8) uniform restrict writeonly image2D out_c;
layout(set = 0, binding = 7, std430) restrict readonly buffer Params { float P[]; } prm;

layout(push_constant, std430) uniform Push {
	vec4 a;   // tile's first world texel (x, z) as floats, cell (m), mode (0 bake, 1 clear)
	vec4 b;   // chunk centre (x, z) m, toroidal texel offset of the tile (x, z) ... packed: see below
	vec4 c;   // slot texel origin (x, z) in the level texture, samples per side S, unused
} pc;

// ---- Params (road_detail.gd PARAMS: keep the same order) ----
#define P_PLAY        prm.P[0]    // share of 26 m stretches with a playful mark
#define P_PUDDLES     prm.P[1]    // 0 none, 1 normal, > 1 every wet road
#define P_LINES       prm.P[2]    // ridden lines' strength
#define P_PRINTS      prm.P[3]    // tyre prints' strength
#define P_STRAY       prm.P[4]    // stray lines' strength
#define P_PEBBLES     prm.P[5]    // grit / pebbles on the dirt
#define P_EDGE_STONES prm.P[6]    // stones along the trail's edges
#define P_EDGE_SIZE   prm.P[7]    // their size (x)
#define P_EDGE_VAR    prm.P[8]    // ragged edge wander (as ground.gdshader trail_edge_var)
#define P_EDGE_FADE   prm.P[9]    // edge fade width (trail_edge_fade)
#define P_GROOVE      prm.P[10]   // how much darker the worn riding line is
#define P_FOOTPRINTS  prm.P[11]   // walkers' footprints along the trail (0 = none)

// ---- ground.gdshader's noise, bit for bit ----
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
// the ground's 3D noises read world y; the bake has no height, so they read y = 0 (a slice of the same noise)
float gn(vec2 p, float s, float o) { return gd_noise3(vec3(p.x, 0.0, p.y) * s + o); }

// a band 0..1 of distance d from a line: full inside a, gone past b. Area preserving for any sample spacing fw: the
// edge is never sharper than fw, and where the band is narrower than fw it gets fainter instead (its average is kept)
float lineaa(float d, float a, float b, float fw) {
	float m = 0.5 * (a + b), h = max(0.5 * (b - a), fw);
	return 1.0 - smoothstep(m - h, m + h, d);
}
// a fade of detail of size `sz` (m) that the sample spacing can't carry: 1 = resolved, 0 = leave its average
float res(float sz, float fw) { return 1.0 - smoothstep(sz * 0.35, sz * 1.1, fw); }

// voronoi pebbles (ground.gdshader gd_pebbles) with a threshold / size: x = cover 0..1, y = shade -0.6..1.4
vec2 pebbles(vec2 p, float keep, float r0, float r1, float seed) {
	p += (vec2(gd_noise3(vec3(p * 1.7, 3.1 + seed)), gd_noise3(vec3(p * 1.7, 8.7 + seed))) - 0.5) * 0.5;
	vec2 i = floor(p), f = fract(p);
	vec2 best = vec2(0.0);
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 g = vec2(float(x), float(y));
			vec3 h = gd_hash3(i + g + 17.0 + seed * 7.0);
			if (h.z < keep) continue;
			float q = (h.z - keep) / max(1.0 - keep, 1e-3);
			float r = r0 + (r1 - r0) * q * q;
			vec2 dv = (g + 0.2 + 0.6 * h.xy - f) * vec2(1.0, 0.75 + 0.5 * h.x);
			float k = 1.0 - smoothstep(r * 0.4, r, length(dv));
			if (k > best.x) best = vec2(k, h.y * 2.0 - 0.6);
		}
	}
	return best;
}

// what a point of road is made of
struct Surf {
	float k;        // colour multiplier on the dirt
	float hgt;      // relief height (m): worn lines below, grit / stones above
	float prints, wet, puddle, driven, loose, stones, peb;
	float skid;     // a run-off skid (shares A.g with the prints: it widens the dirt into the grass in the ground shader)
};

// the trail's frame + the chunk's data at a point
struct Ctx {
	vec2 p;         // world xz
	vec2 uv;        // the chunk textures' uv
	float fw;       // sample spacing (m): the filter width every mark is drawn with
	float t;        // trail dirt weight (warped like ground.gdshader's ragged edge)
	vec4 tf, tf2;
	vec2 tf3;
	float tfk;      // 0 where the frame jumps (side-path junctions): no frame-drawn marks
	float ac, off, sl, rd, dry, jm, t_air, depth_k;
	float n0, n1, n2;
	float f1, f2, f3;   // ground.gdshader's fine-detail fades, now from the sample spacing
};

// ---- the ragged trail edge, as ground.gdshader (so stones sit on the edge that is drawn) ----
float warped_t(vec2 P, vec2 UV, float t0, float f3) {
	if (P_EDGE_VAR <= 0.0) return t0;
	float jmk = max(textureLod(trail2_tex, UV, 0.0).b, 0.85 * smoothstep(0.3, 0.65, textureLod(trail3_tex, UV, 0.0).g));
	vec2 q0 = P;
	vec2 w1 = vec2(gd_noise3(vec3(q0 * 0.033, 3.3)), gd_noise3(vec3(q0 * 0.033 + 17.0, 7.7))) - 0.5;
	vec2 w2 = vec2(gd_noise3(vec3(q0 * 0.11, 2.1)), gd_noise3(vec3(q0 * 0.11 + 31.0, 4.4))) - 0.5;
	vec2 w3 = vec2(gd_noise3(vec3(q0 * 0.55, 1.1)), gd_noise3(vec3(q0 * 0.55 + 9.0, 5.5))) - 0.5;
	float loose = 0.45 + 1.1 * gd_noise3(vec3(q0 * 0.017, 8.8));
	vec2 wm = (w1 * 4.4 + w2 * 2.2 + w3 * 1.0 * f3) * loose * P_EDGE_VAR * (1.0 - jmk);
	vec2 bd = min(UV, 1.0 - UV);
	float bk = smoothstep(0.0, 0.05, min(bd.x, bd.y));
	wm *= bk;
	float sp = (0.9 + 0.5 * P_EDGE_FADE) * bk * (1.0 - jmk) / 48.0;
	vec2 u0 = UV + wm / 48.0;
	float ta = textureLod(land_tex, u0 + vec2(sp, sp * 0.4), 0.0).a + textureLod(land_tex, u0 + vec2(-sp, -sp * 0.4), 0.0).a
		+ textureLod(land_tex, u0 + vec2(-sp * 0.4, sp), 0.0).a + textureLod(land_tex, u0 + vec2(sp * 0.4, -sp), 0.0).a;
	return mix(t0, ta * 0.25, bk * (1.0 - jmk));
}

Ctx context(vec2 P, vec2 UV, float fw) {
	Ctx c;
	c.p = P; c.uv = UV; c.fw = fw;
	float g = fw * 1.5;   // ~ the old per-pixel footprint (length of fwidth) for the same detail size
	c.f1 = 1.0 - smoothstep(0.012, 0.04, g);
	c.f2 = 1.0 - smoothstep(0.035, 0.12, g);
	c.f3 = 1.0 - smoothstep(0.1, 0.45, g);
	c.t = warped_t(P, UV, textureLod(land_tex, UV, 0.0).a, c.f3);
	c.tf = textureLod(trail_tex, UV, 0.0);
	c.tf2 = textureLod(trail2_tex, UV, 0.0);
	c.tf3 = textureLod(trail3_tex, UV, 0.0).rg;
	// the frame's seam test (ground.gdshader): the four texels the filter blends
	vec2 tsz = vec2(textureSize(trail_tex, 0));
	ivec2 ti = clamp(ivec2(floor(UV * tsz - 0.5)), ivec2(0), ivec2(tsz) - 2);
	vec3 ta = texelFetch(trail_tex, ti, 0).rgb, tb = texelFetch(trail_tex, ti + ivec2(1, 0), 0).rgb;
	vec3 tc = texelFetch(trail_tex, ti + ivec2(0, 1), 0).rgb, td = texelFetch(trail_tex, ti + ivec2(1, 1), 0).rgb;
	vec3 tspan = max(max(ta, tb), max(tc, td)) - min(min(ta, tb), min(tc, td));
	c.tfk = 1.0 - smoothstep(1.8, 3.5, max(tspan.b, tspan.r + tspan.g));
	c.ac = c.tf.r; c.off = c.tf.g; c.sl = c.tf.b; c.rd = c.tf2.r; c.dry = c.tf2.g; c.jm = c.tf2.b;
	c.t_air = c.tf3.r;
	c.depth_k = mix(0.2, 1.5, c.tf3.g);
	c.n0 = gn(P, 2.3, 3.3);
	c.n1 = mix(0.5, gn(P, 9.0, 0.0), c.f2);
	c.n2 = mix(0.5, gn(P, 23.0, 7.1), c.f1);
	return c;
}

// ---- layers ----
void layer_skid(inout Surf s, Ctx c, out float m_skid) {
	m_skid = 0.0;
	float skf = c.tf2.a * c.tfk;
	if (skf <= 0.0) return;
	float sd = c.ac - c.tf.a + (gd_noise3(vec3(c.sl * 0.7, 31.0, 4.0)) - 0.5) * 0.1;
	float sk = max(lineaa(abs(sd), 0.025, 0.06, c.fw), 0.6 * lineaa(abs(sd - 0.13), 0.02, 0.05, c.fw));
	m_skid = sk * skf * (0.65 + 0.35 * gd_noise3(vec3(c.sl * 2.3, c.ac * 30.0, 9.0)));
}

// every rider's own narrow line (most on the racing line), ground.gdshader LG / LD / LW
void layer_lines(inout Surf s, Ctx c, out float line) {
	const float LG[9] = float[9](1.0, 1.0, 1.0, 1.0, 0.9, 1.15, 0.8, 0.55, 1.35);
	const float LD[9] = float[9](0.0, 0.06, -0.07, 0.13, 0.22, 0.3, -0.28, -0.5, 0.55);
	const float LW[9] = float[9](0.9, 0.8, 0.8, 0.65, 0.5, 0.5, 0.5, 0.4, 0.35);
	line = 0.0;
	float alt = 0.0;
	for (int i = 0; i < 9; i++) {
		float fi = float(i);
		float loose_k = abs(LD[i]) + abs(LG[i] - 1.0);
		float wob = (sin(c.sl * (0.047 + 0.011 * fi) + fi * 2.4) + sin(c.sl * (0.021 + 0.007 * fi) + fi * 5.1)) * (0.02 + 0.3 * loose_k);
		float cc = c.off * LG[i] + LD[i] * (1.0 + 0.5 * c.rd) + wob;
		float pres = i < 4 ? 1.0 : smoothstep(-0.25, 0.25, sin(c.sl * (0.013 + 0.004 * fi) + fi * 1.7));
		float l = lineaa(abs(c.ac - cc), 0.03, 0.11, c.fw) * LW[i] * pres;
		if (i < 4) { line += l * (1.0 - line); } else { alt += l * (1.0 - alt); }
	}
	float n_s1 = gd_noise3(vec3(c.sl * 0.035, 7.0, 1.0));
	line *= 0.6 + 0.4 * smoothstep(0.25, 0.6, n_s1);
	line = (line + alt * (1.0 - line)) * (1.0 - c.t_air) * c.tfk * P_LINES;
	float rag = (c.n0 - 0.5) * 0.3 + (c.n1 - 0.5) * 0.2;
	float drv = clamp(max(line, c.jm * 0.8 + line * 0.2) + rag * (1.0 - c.jm) * (0.25 + 0.75 * line), 0.0, 1.0);
	s.driven = smoothstep(0.08, 0.8, drv);
	float edge = smoothstep(0.15, 0.5, c.t) * (1.0 - smoothstep(0.75, 0.98, c.t));
	float shoulder = smoothstep(0.05, 0.3, line) * (1.0 - smoothstep(0.3, 0.8, line));
	s.loose = clamp((1.0 - s.driven) * (0.45 + 0.4 * shoulder + 0.5 * edge) * (1.0 - 0.6 * c.jm), 0.0, 1.0);
}

// three riders' tyre prints inside the line, with knob dimples
void layer_prints(inout Surf s, Ctx c) {
	float offb = c.off * 0.55 - 0.5, offc = c.off * 1.35 + 0.55;
	float m = 0.0;
	float kres = res(0.05, c.fw);   // knobs ~5 cm apart: their pattern averages out past that
	for (int i = 0; i < 3; i++) {
		float fi = float(i);
		float cc = (i == 0 ? c.off : (i == 1 ? offb : offc)) + (gd_noise3(vec3(c.sl * (0.05 + 0.023 * fi), fi * 13.1, 5.0)) - 0.5) * (0.34 + 0.3 * c.rd);
		float pres = smoothstep(0.48, 0.62, gd_noise3(vec3(c.sl * 0.03 + fi * 31.0, 2.0, fi * 7.0)));
		float d = abs(c.ac - cc);
		float knob = smoothstep(-0.3, 0.3, sin(c.sl * 58.0 + fi * 2.0) * sin((c.ac - cc) * 150.0 + c.sl * 20.0));
		float knobs = 0.6 + 0.4 * mix(0.5, knob, kres);
		m = max(m, lineaa(d, 0.018, 0.04, c.fw) * pres * knobs);
	}
	s.prints = m * (0.6 + 0.4 * s.driven) * (1.0 - c.t_air) * c.tfk * P_PRINTS;
}

// single faint lines down the trail anywhere across it
void layer_stray(inout Surf s, Ctx c, out float m_stray) {
	float reach = 0.95 + 0.9 * c.rd;
	m_stray = 0.0;
	for (int i = 0; i < 6; i++) {
		float fi = float(i);
		float cc = (sin(c.sl * (0.011 + 0.0037 * fi) + fi * 4.1) * 0.7 + sin(c.sl * (0.031 + 0.006 * fi) + fi * 1.3) * 0.3) * reach
			+ sin(c.sl * (0.17 + 0.02 * fi) + fi * 2.9) * 0.035;
		float pres = smoothstep(0.05, 0.45, sin(c.sl * (0.0083 + 0.0029 * fi) + fi * 2.3) + 0.25 * sin(c.sl * 0.047 + fi * 5.7));
		float wdt = 0.022 + 0.012 * fract(fi * 0.37);
		m_stray = max(m_stray, lineaa(abs(c.ac - cc), wdt, wdt + 0.035, c.fw) * pres * (0.55 + 0.45 * fract(fi * 0.61)));
	}
	m_stray *= (1.0 - 0.6 * c.jm) * (1.0 - 0.5 * s.driven) * (1.0 - c.t_air) * c.tfk * P_STRAY;
}

// people messing about: donut, figure of eight, slalom, skid arc in some 26 m stretches
float layer_play(Ctx c) {
	float ci = floor(c.sl / 26.0);
	vec3 ph = gd_hash3(vec2(ci, 71.0)), ph2 = gd_hash3(vec2(ci + 13.0, 193.0));
	if (ph.x >= P_PLAY) return 0.0;
	vec2 q = vec2(c.sl - (ci + 0.32 + 0.36 * ph.y) * 26.0, c.ac - (ph.z - 0.5) * (0.8 + 1.2 * c.rd));
	float r = (0.7 + 0.65 * ph2.x) * (1.0 + 0.5 * c.rd);
	float d;
	if (ph2.y < 0.38) {
		d = min(abs(length(q) - r), min(abs(length(q - vec2(0.13, 0.08)) - r * 0.93), abs(length(q + vec2(0.1, -0.07)) - r * 1.06)));
	} else if (ph2.y < 0.62) {
		d = min(abs(length(q - vec2(r, 0.0)) - r), abs(length(q + vec2(r, 0.0)) - r));
	} else if (ph2.y < 0.84) {
		float wv = 0.5 * r, wk = 1.25;
		d = abs(q.y - sin(q.x * wk) * wv) / sqrt(1.0 + pow(cos(q.x * wk) * wv * wk, 2.0))
			+ (1.0 - smoothstep(-6.5, -4.5, q.x) * (1.0 - smoothstep(4.5, 6.5, q.x))) * 9.0;
	} else {
		d = abs(length(q) - r * 1.7) + smoothstep(0.7, 1.0, abs(atan(q.y, q.x) - (ph2.z - 0.5) * 4.0)) * 9.0;
	}
	return lineaa(d, 0.022, 0.055, c.fw) * (0.6 + 0.4 * ph2.z) * (1.0 - c.jm) * (1.0 - c.t_air) * c.tfk;
}

// footprints of people who walked the trail (user, 2026-11-25): a shoe sole (ball + waist + heel, ~26 cm) pressed in,
// drawn in the trail's own frame (along / across, metres), filtered to the sample spacing like every mark
float footprint(vec2 q, float fw) {
	// q: metres from the print's middle, x along the step, y across. Ball (front) and heel, a narrow waist between
	vec2 b = (q - vec2(0.05, 0.0)) / vec2(0.085, 0.05);
	vec2 h = (q + vec2(0.085, 0.0)) / vec2(0.055, 0.042);
	vec2 m = q / vec2(0.13, 0.034);                          // the waist joining them
	float d = min(min(length(b), length(h)), length(m));
	float aa = fw / 0.04;
	return 1.0 - smoothstep(0.85 - aa, 1.05 + aa, d);
}
// many people over time, not one walker (user: "random, more faint, random people, totally random walk over time"):
// prints scattered in a jittered 0.55 m grid in the trail's frame, a share of the cells holding one; each its own
// direction (mostly along the trail either way, often turned, now and then any way) and age (old ones barely there),
// worn off the riders' line. Overlaps keep the clearest.
float layer_footprints(Ctx c, float line) {
	if (P_FOOTPRINTS <= 0.0 || c.t < 0.3) return 0.0;
	const float CELLF = 0.55;
	vec2 g = vec2(c.sl, c.ac) / CELLF;
	vec2 gi = floor(g);
	float fp = 0.0;
	for (int j = -1; j <= 1; j++) {
		for (int i = -1; i <= 1; i++) {
			vec2 cc = gi + vec2(float(i), float(j));
			vec3 h = gd_hash3(cc + 911.0);
			if (h.x > 0.22 * P_FOOTPRINTS) continue;
			vec3 h2 = gd_hash3(cc + 377.0);
			vec2 ctr = (cc + 0.15 + 0.7 * h2.xy) * CELLF;         // where in its cell
			// along the trail either way, spread ~+-35 deg; one in five turned any way
			float ang = (h.y < 0.5 ? 0.0 : 3.14159) + (h2.z - 0.5) * 1.2;
			if (h.z > 0.8) ang = h2.z * 6.28318;
			vec2 q = vec2(c.sl, c.ac) - ctr;
			q = vec2(q.x * cos(ang) + q.y * sin(ang), -q.x * sin(ang) + q.y * cos(ang));
			float age = gd_hash(vec3(cc, 5.3));                     // 0 fresh .. 1 old
			fp = max(fp, footprint(q, c.fw) * mix(0.75, 0.12, age * age));
		}
	}
	// riders wear them off their line; none on built jumps or where riders fly
	return fp * (1.0 - 0.7 * line) * (1.0 - c.jm) * (1.0 - c.t_air) * c.tfk;
}

// puddles + damp soil in a road's worn lines (ground.gdshader; "level ground" is applied by the ground shader)
void layer_puddles(inout Surf s, Ctx c, float line) {
	float zone = smoothstep(0.47, 0.62, gd_noise3(vec3(c.sl * 0.011, 21.0, 8.0)));
	zone = max(zone, P_PUDDLES - 1.0);
	float inrut = max(1.0 - smoothstep(0.15, 0.8, abs(c.ac - c.off)), line);
	float pn = gd_noise3(vec3(c.ac * 1.5, c.sl * 0.21, 13.0)) * (0.62 + 0.38 * inrut) + (c.n0 - 0.5) * 0.05 + (c.n1 - 0.5) * 0.025;
	float pk = c.tfk * zone * c.rd * (1.0 - c.jm) * (1.0 - smoothstep(0.3, 0.6, c.dry)) * smoothstep(0.85, 1.0, c.t) * min(P_PUDDLES, 1.0);
	float paa = c.fw * 2.0;
	s.wet = smoothstep(0.44 - paa, 0.56 + paa, pn) * pk;
	s.puddle = smoothstep(0.565 - paa, 0.59 + paa, pn) * pk;
}

// grit and small pebbles on the dirt (ground.gdshader gd_pebbles: ~6 cm cells, 1-3 cm stones)
void layer_pebbles(inout Surf s, Ctx c, out vec2 pb) {
	pb = pebbles(c.p * 16.0, 0.55, 0.07, 0.29, 0.0);
	float r = res(0.02, c.fw);
	// past what the samples resolve a pebble field is its average: ~12 % cover, mean shade 0.4
	pb = mix(vec2(0.12, 0.4), pb, r);
	s.peb = pb.x * P_PEBBLES;
}

// stones along the trail's edges (user, 2026-11-25: "more pebbles on edges"): where the dirt meets the land, and more on
// the loose shoulders, bigger and greyer than the grit; they stand a little proud (relief) and the ground shader paints
// them stone-coloured over dirt and grass alike
void layer_edge_stones(inout Surf s, Ctx c) {
	if (P_EDGE_STONES <= 0.0) { s.stones = 0.0; return; }
	float band = smoothstep(0.03, 0.22, c.t) * (1.0 - smoothstep(0.45, 0.8, c.t));   // the edge itself
	band = max(band, 0.45 * s.loose * (1.0 - smoothstep(0.85, 1.0, c.t)));   // the loose shoulder
	band *= (1.0 - c.jm) * (0.55 + 0.9 * gn(c.p, 0.12, 4.4));                 // in clusters along the trail
	if (band <= 0.001) { s.stones = 0.0; return; }
	float sz = max(P_EDGE_SIZE, 0.2);
	float dens = clamp(band * P_EDGE_STONES, 0.0, 1.0);
	// gravel (~4-12 cm) thick where the band is strong, and now and then a bigger stone (~10-30 cm)
	vec2 g1 = pebbles(c.p * (9.0 / sz), mix(0.92, 0.4, dens), 0.1, 0.34, 3.0);
	vec2 g2 = pebbles(c.p * (3.2 / sz), mix(0.985, 0.8, dens), 0.16, 0.42, 5.0);
	float cover = mix(0.2 * dens, max(g1.x, g2.x), res(0.04 * sz, c.fw));
	s.stones = clamp(cover * clamp(band * 1.6, 0.0, 1.0), 0.0, 1.0);
	s.hgt += s.stones * 0.022 * sz;
}

Surf surface(Ctx c) {
	Surf s;
	s.k = 1.0; s.hgt = 0.0; s.prints = 0.0; s.wet = 0.0; s.puddle = 0.0; s.driven = 0.0; s.loose = 0.0; s.stones = 0.0; s.peb = 0.0; s.skid = 0.0;
	vec2 pb;
	layer_pebbles(s, c, pb);
	bool on = c.t > 0.004 || c.tf2.a > 0.01;
	float line = 0.0, m_skid = 0.0, m_stray = 0.0, m_play = 0.0, m_foot = 0.0;
	if (on) {
		layer_skid(s, c, m_skid);
		s.skid = m_skid;
		layer_lines(s, c, line);
		layer_prints(s, c);
		layer_stray(s, c, m_stray);
		m_play = layer_play(c);
		m_foot = layer_footprints(c, line);
		layer_puddles(s, c, line);
		// tyres sweep the grit off the packed line: it lies thick on the loose shoulders, thin where they ride
		s.peb *= 0.25 + 0.75 * clamp(s.loose * 1.4, 0.0, 1.0);
	}
	layer_edge_stones(s, c);
	if (on) {
		// colour: all small steps (ground.gdshader)
		float streak = (gd_noise3(vec3(c.ac * 9.0, c.sl * 0.3, 2.0)) - 0.5) * c.tfk;
		float scuff = smoothstep(0.55, 0.8, gd_noise3(vec3(c.p * 0.55, 4.0)));
		float k = 1.0;
		k *= 1.0 + s.driven * (0.05 * c.dry - 0.03) + s.loose * 0.05;
		k *= 1.0 + streak * 0.09 * c.f2 * (0.35 + 0.65 * s.driven);
		k *= 1.0 + scuff * 0.045 * (1.0 - 0.5 * c.jm);
		k *= 1.0 + s.peb * 0.16 * pb.y * (0.25 + 0.75 * s.loose) + (c.n2 - 0.5) * 0.1 * c.f1 * (1.0 - 0.6 * s.driven);
		k *= 1.0 - P_GROOVE * line * (1.0 - c.jm);   // the worn line a touch darker (a racing game's groove)
		// (darker than the per-pixel path had them: there the lines showed mostly by their relief, lit per pixel; baked,
		// a 1-3 cm groove's two walls average out in the mips like real filtering does, so the line carries its own shade)
		k *= 1.0 - 0.15 * s.prints;
		k *= 1.0 - 0.24 * m_skid;
		k *= 1.0 - 0.11 * m_stray;
		k *= 1.0 - 0.11 * m_play;
		k *= 1.0 - 0.16 * m_foot;   // a footprint: the soil pressed a little darker
		// relief: worn lines below, prints / skids pressed in, grit proud, lumpy between the lines
		float lump = (gd_noise3(vec3(c.ac * 5.0, c.sl * 0.9, 6.0)) - 0.5) * 0.012 * c.tfk + (c.n1 - 0.5) * 0.006 * c.f2;
		float th = -0.03 * line * c.depth_k * (1.0 - 0.7 * c.jm) - 0.008 * s.prints * c.depth_k - 0.014 * m_skid - 0.006 * m_stray - 0.007 * m_play - 0.01 * m_foot
			+ (s.peb * (0.006 + 0.008 * pb.y) + lump) * (0.3 + 0.7 * s.loose) * (1.0 - 0.4 * c.jm);
		th *= 1.0 - s.puddle;
		k *= 1.0 + th * 2.2;
		k *= 1.0 + c.jm * 0.04;
		k = mix(k, 1.0 + (k - 1.0) * 0.8, c.jm);   // built jumps a touch more even (was 0.45: they read blurred)
		s.k = k;
		s.hgt += th;
	}
	return s;
}

void main() {
	ivec2 id = ivec2(gl_GlobalInvocationID.xy);
	if (id.x >= 64 || id.y >= 64) return;
	ivec2 dst = ivec2(pc.c.xy) + id;
	if (pc.a.w > 0.5) {   // clear: nothing baked here (the ground shader falls back to the next level)
		imageStore(out_a, dst, vec4(0.5, 0.0, 0.0, 0.0));
		imageStore(out_b, dst, vec4(0.0));
		imageStore(out_c, dst, vec4(0.0));
		return;
	}
	float cell = pc.a.z;
	int S = int(pc.c.z);
	float fw = cell / float(S);
	vec2 wt = pc.a.xy + vec2(id);          // world texel
	vec2 chunk = pc.b.xy;
	// sum over the S x S samples of the texel
	float k = 0.0, pr = 0.0, wet = 0.0, pud = 0.0, drv = 0.0, lse = 0.0, sto = 0.0, peb = 0.0;
	vec2 sl = vec2(0.0);
	float s2 = 0.0;
	float H[16];   // heights of the sample grid (S <= 4)
	for (int j = 0; j < S; j++) {
		for (int i = 0; i < S; i++) {
			vec2 P = (wt + (vec2(float(i), float(j)) + 0.5) / float(S)) * cell;
			vec2 UV = ((P - chunk + 24.0) / 0.5 + 0.5) / 97.0;
			Ctx c = context(P, UV, fw);
			Surf s = surface(c);
			k += s.k; pr += max(s.prints, s.skid); wet += s.wet; pud += s.puddle; drv += s.driven; lse += s.loose; sto += s.stones; peb += s.peb;
			H[j * 4 + i] = s.hgt;
		}
	}
	float n = float(S * S);
	// slopes from the sample grid (S >= 2): every neighbouring pair, their mean and mean square
	// (x pairs and z pairs counted apart: each is a slope component's own estimate)
	float cx = 0.0, cz = 0.0, sx2 = 0.0, sz2 = 0.0;
	for (int j = 0; j < S; j++) {
		for (int i = 0; i < S; i++) {
			if (i < S - 1) { float g = (H[j * 4 + i + 1] - H[j * 4 + i]) / fw; sl.x += g; sx2 += g * g; cx += 1.0; }
			if (j < S - 1) { float g = (H[(j + 1) * 4 + i] - H[j * 4 + i]) / fw; sl.y += g; sz2 += g * g; cz += 1.0; }
		}
	}
	sl /= vec2(max(cx, 1.0), max(cz, 1.0));
	s2 = sx2 / max(cx, 1.0) + sz2 / max(cz, 1.0);
	imageStore(out_a, dst, vec4(clamp(k / n * 0.5, 0.0, 1.0), pr / n, wet / n, pud / n));
	imageStore(out_b, dst, vec4(sl, s2, peb / n));
	imageStore(out_c, dst, vec4(1.0, drv / n, lse / n, sto / n));
}
