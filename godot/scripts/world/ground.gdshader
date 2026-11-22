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
// the trail's own frame, baked per chunk (TerrainChunkBuilder): r = metres across from the centreline (signed),
// g = where the ridden line sits across it, b = metres along the trail, a = where a run-off skid sits across it
uniform sampler2D trail_tex : filter_linear, repeat_disable;
// r = road (wide, gravelly) 0..1, g = dry biome 0..1, b = built jump 0..1, a = run-off skid's strength
uniform sampler2D trail2_tex : filter_linear, repeat_disable;
// r = riders are in the air here (between a jump's lip and where they land): no ridden lines
uniform sampler2D trail3_tex : filter_linear, repeat_disable;
uniform float trail_fx = 0.0;      // 0 = plain trail colour (no frame bound)
// fine relief only (assets/textures/trail, Poly Haven CC0): normal xy + roughness of packed dirt / loose gravel.
// Colour, rider lines, wear and puddles are procedural, so nothing tiles and no scan edge can show.
uniform sampler2D tr_nr0 : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D tr_nr1 : filter_linear_mipmap_anisotropic, repeat_enable;
uniform float trail_bump = 0.9;
uniform float trail_relief = 1.0;   // depth of the worn lines / tyre prints / grit, x the real centimetres below
uniform float trail_play = 0.34;   // share of 26 m stretches with a playful mark (donut, figure of eight, slalom, skid arc); test: 1 = all
uniform float trail_puddles = 1.0;   // 0 = none, 1 = normal
uniform int trail_debug = 0;       // 1 = show the mask layers: r driven, g loose, b puddle (wet rim dimmer), white tyre prints, yellow run-off skids, magenta stray lines, cyan playful marks
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
// a relief scan at a world point: a = (cos, sin) of its turn, inv = 1 / its size in metres.
// xy = the surface normal's lean in world x / z, z = roughness
vec3 gd_relief(sampler2D nt, vec2 p, vec2 dx, vec2 dy, vec2 a, float inv) {
	vec2 b = vec2(-a.y, a.x);
	vec2 uv = vec2(dot(p, a), dot(p, b)) * inv;
	vec2 gx = vec2(dot(dx, a), dot(dx, b)) * inv, gy = vec2(dot(dy, a), dot(dy, b)) * inv;
	vec3 n = textureGrad(nt, uv, gx, gy).rgb;
	n.xy = n.xy * 2.0 - 1.0;
	return vec3(a * n.x - b * n.y, n.z);
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
	// fine noise only where it still shows: every use is mix(0.5, n, f) or (n - 0.5) * f, so 0.5 = faded out
	float n0 = gd_noise3(P * 2.3 + 3.3), n1 = 0.5, n2 = 0.5;
	if (f2 > 0.0) n1 = gd_noise3(P * 9.0);
	if (f1 > 0.0) n2 = gd_noise3(P * 23.0 + 7.1);
	float hG = mix(0.5, n1, f2) * 0.55 + mix(0.5, n2, f1) * 0.25 + n0 * 0.2;
	// fine grit: ~6 cm cells, pebbles ~1-3 cm across. Gone before a pebble is ~2 px (past that they were
	// single-pixel salt-and-pepper dots), and not worked out at all there
	float peb_f = 1.0 - smoothstep(0.003, 0.009, gpx);
	vec2 pb = vec2(0.0);
	if (peb_f > 0.0) pb = gd_pebbles(P.xz * 16.0);
	float peb = pb.x * peb_f;
	float hD = peb * 0.6 + gd_noise3(P * 3.1 + 11.0) * 0.45 + gd_noise3(P * 0.9 + 2.0) * 0.3;
	float a1 = (1.0 - t) + hG * 0.75, a2 = t + hD * 0.75;
	float m = max(a1, a2) - 0.28;
	float b1 = max(a1 - m, 0.0), b2 = max(a2 - m, 0.0);
	float wd = mix(t, b2 / max(b1 + b2, 1e-4), f3);
	// ---- the trail's surface, from mask layers in the trail's own frame (across / along) ----
	//   m_driven  where tyres have packed it: every rider's own narrow line (most on the racing line), jumps
	//   m_loose   what the tyres throw aside: grit beside the line and along the edges
	//   m_tracks  single tyre prints of riders before you, wandering inside the line
	//   m_skid    a rider who braked too late: a locked-wheel skid straight on off the outside of a corner
	//   m_wet     damp soil round a puddle      m_puddle  standing water in a road's worn lines
	vec3 tcol = vec3(1.0);
	vec2 tslope = vec2(0.0);
	float trough = 0.95, tbump = 0.0;
	float thgt = 0.0;   // the trail surface's own height (m): worn lines sit lower, grit and the ground between them higher
	float m_driven = 0.0, m_loose = 0.0, m_tracks = 0.0, m_wet = 0.0, m_puddle = 0.0, m_skid = 0.0, m_stray = 0.0, m_play = 0.0, jm = 0.0;
	vec2 pdx = dFdx(P.xz), pdy = dFdy(P.xz);
	vec4 tf = texture(trail_tex, UV);
	vec4 tf2 = texture(trail2_tex, UV);
	float t_air = texture(trail3_tex, UV).r * trail_fx;
	float tnear = (1.0 - smoothstep(0.25, 0.7, gpx)) * trail_fx;   // far off it all averages out to the plain colour
	if ((t > 0.004 || tf2.a > 0.01) && tnear > 0.0) {
		float ac = tf.r, off = tf.g, sl = tf.b, rd = tf2.r, dry = tf2.g;
		jm = tf2.b;
		// the run-off skid: two locked tyres' streaks, a little unsteady, cut into the grass past the trail's edge
		float skf = (1.0 - smoothstep(0.06, 0.22, gpx)) * tf2.a;
		if (skf > 0.0) {
			float sd = ac - tf.a + (gd_noise3(vec3(sl * 0.7, 31.0, 4.0)) - 0.5) * 0.1;
			float sk = max(1.0 - smoothstep(0.025, 0.06, abs(sd)), 0.6 * (1.0 - smoothstep(0.02, 0.05, abs(sd - 0.13))));
			m_skid = sk * skf * (0.65 + 0.35 * gd_noise3(vec3(sl * 2.3, ac * 30.0, 9.0)));
			wd = max(wd, m_skid * 0.8 * f3);
		}
		float n_s1 = gd_noise3(vec3(sl * 0.035, 7.0, 1.0));
		// the ridden lines: not one band but each rider's own narrow line. Most sit on the racing line (baked: wide in,
		// apex, wide out) within a few cm of each other, so that is where the ground is worn most; a few ride it a bit
		// tighter or a bit wider, one cuts the corners near the middle, one runs wide. LG = how far each follows the
		// racing line's swing, LD = its own place beside it (m), LW = how many riders use it. The outer ones wander
		// more and come and go in stretches. Bikes only: never two parallel wheel ruts
		const float LG[9] = float[9](1.0, 1.0, 1.0, 1.0, 0.9, 1.15, 0.8, 0.55, 1.35);
		const float LD[9] = float[9](0.0, 0.06, -0.07, 0.13, 0.22, 0.3, -0.28, -0.5, 0.55);
		const float LW[9] = float[9](0.9, 0.8, 0.8, 0.65, 0.5, 0.5, 0.5, 0.4, 0.35);
		float line = 0.0, alt = 0.0;
		for (int i = 0; i < 9; i++) {
			float fi = float(i);
			float loose_k = abs(LD[i]) + abs(LG[i] - 1.0);
			float wob = (sin(sl * (0.047 + 0.011 * fi) + fi * 2.4) + sin(sl * (0.021 + 0.007 * fi) + fi * 5.1)) * (0.02 + 0.3 * loose_k);
			float c = off * LG[i] + LD[i] * (1.0 + 0.5 * rd) + wob;
			float pres = i < 4 ? 1.0 : smoothstep(-0.25, 0.25, sin(sl * (0.013 + 0.004 * fi) + fi * 1.7));
			float l = (1.0 - smoothstep(0.03, 0.11, abs(ac - c))) * LW[i] * pres;
			if (i < 4) { line += l * (1.0 - line); } else { alt += l * (1.0 - alt); }
		}
		line *= 0.6 + 0.4 * smoothstep(0.25, 0.6, n_s1);
		line = (line + alt * (1.0 - line)) * (1.0 - t_air);   // nobody's tyres touch between the lip and the landing
		float offb = off * 0.55 - 0.5, offc = off * 1.35 + 0.55;
		// ragged edge, so the band is never a ruler line
		float rag = (n0 - 0.5) * 0.3 + (mix(0.5, n1, f2) - 0.5) * 0.2;
		m_driven = clamp(max(line, jm * 0.8 + line * 0.2) + rag * (1.0 - jm) * (0.25 + 0.75 * line), 0.0, 1.0);
		m_driven = smoothstep(0.08, 0.8, m_driven);
		float edge = smoothstep(0.15, 0.5, t) * (1.0 - smoothstep(0.75, 0.98, t));
		float shoulder = smoothstep(0.05, 0.3, line) * (1.0 - smoothstep(0.3, 0.8, line));   // just beside the line
		m_loose = clamp((1.0 - m_driven) * (0.45 + 0.4 * shoulder + 0.5 * edge) * (1.0 - jm), 0.0, 1.0);
		// tyre prints: three riders' tracks, each its own slow wander and its own stretches
		float trk_fade = 1.0 - smoothstep(0.02, 0.07, gpx);
		if (trk_fade > 0.0) {
			for (int i = 0; i < 3; i++) {
				float fi = float(i);
				// one print on the racing line, one on each of the sloppier lines
				float c = (i == 0 ? off : (i == 1 ? offb : offc)) + (gd_noise3(vec3(sl * (0.05 + 0.023 * fi), fi * 13.1, 5.0)) - 0.5) * (0.34 + 0.3 * rd);
				float pres = smoothstep(0.48, 0.62, gd_noise3(vec3(sl * 0.03 + fi * 31.0, 2.0, fi * 7.0)));
				float d = abs(ac - c);
				float knobs = 0.6 + 0.4 * smoothstep(-0.3, 0.3, sin(sl * 58.0 + fi * 2.0) * sin((ac - c) * 150.0 + sl * 20.0)) * f1 + 0.4 * (1.0 - f1) * 0.5;
				m_tracks = max(m_tracks, (1.0 - smoothstep(0.018, 0.04, d)) * pres * knobs);
			}
			m_tracks *= trk_fade * (0.6 + 0.4 * m_driven) * (1.0 - t_air);
		}
		// stray lines: single faint tyre lines running down the trail anywhere across it, nothing to do with the racing
		// line (someone rolling down the side, drifting across, pulling over). Each wanders on its own, swaps sides,
		// and comes and goes; seen from further off than the prints, much fainter than the ridden lines
		float stray_fade = 1.0 - smoothstep(0.05, 0.2, gpx);
		if (stray_fade > 0.0) {
			float reach = 0.95 + 0.9 * rd;
			for (int i = 0; i < 6; i++) {
				float fi = float(i);
				float c = (sin(sl * (0.011 + 0.0037 * fi) + fi * 4.1) * 0.7 + sin(sl * (0.031 + 0.006 * fi) + fi * 1.3) * 0.3) * reach
					+ sin(sl * (0.17 + 0.02 * fi) + fi * 2.9) * 0.035;
				float pres = smoothstep(0.05, 0.45, sin(sl * (0.0083 + 0.0029 * fi) + fi * 2.3) + 0.25 * sin(sl * 0.047 + fi * 5.7));
				float wdt = 0.022 + 0.012 * fract(fi * 0.37);
				m_stray = max(m_stray, (1.0 - smoothstep(wdt, wdt + 0.035, abs(ac - c))) * pres * (0.55 + 0.45 * fract(fi * 0.61)));
			}
			m_stray *= stray_fade * (1.0 - 0.6 * jm) * (1.0 - 0.5 * m_driven) * (1.0 - t_air);
			// people messing about: in about a third of the 26 m stretches one mark, drawn in the trail's own frame
			// (along / across), kept inside its stretch so nothing is cut at a border
			float ci = floor(sl / 26.0);
			vec3 ph = gd_hash3(vec2(ci, 71.0)), ph2 = gd_hash3(vec2(ci + 13.0, 193.0));
			if (ph.x < trail_play) {
				vec2 q = vec2(sl - (ci + 0.32 + 0.36 * ph.y) * 26.0, ac - (ph.z - 0.5) * (0.8 + 1.2 * rd));
				float r = (0.7 + 0.65 * ph2.x) * (1.0 + 0.5 * rd);
				float d;
				if (ph2.y < 0.38) {            // a donut: a few laps, none quite on the last
					d = min(abs(length(q) - r), min(abs(length(q - vec2(0.13, 0.08)) - r * 0.93), abs(length(q + vec2(0.1, -0.07)) - r * 1.06)));
				} else if (ph2.y < 0.62) {     // a figure of eight
					d = min(abs(length(q - vec2(r, 0.0)) - r), abs(length(q + vec2(r, 0.0)) - r));
				} else if (ph2.y < 0.84) {     // a slalom: a few quick swerves down the trail
					float wv = 0.5 * r, wk = 1.25;
					d = abs(q.y - sin(q.x * wk) * wv) / sqrt(1.0 + pow(cos(q.x * wk) * wv * wk, 2.0))
						+ (1.0 - smoothstep(-6.5, -4.5, q.x) * (1.0 - smoothstep(4.5, 6.5, q.x))) * 9.0;
				} else {                       // a skid arc: a rider swinging the back wheel round
					d = abs(length(q) - r * 1.7) + smoothstep(0.7, 1.0, abs(atan(q.y, q.x) - (ph2.z - 0.5) * 4.0)) * 9.0;
				}
				m_play = (1.0 - smoothstep(0.022, 0.055, d)) * (0.6 + 0.4 * ph2.z) * stray_fade * (1.0 - jm) * (1.0 - t_air);
			}
		}
		// puddles: only on roads, in the worn lines (the lowest ground), on level ground, not in dry country; they come in stretches
		float lvl = smoothstep(0.988, 0.998, normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz).y);
		float zone = smoothstep(0.47, 0.62, gd_noise3(vec3(sl * 0.011, 21.0, 8.0)));
		zone = max(zone, trail_puddles - 1.0);   // > 1 (tests): puddles on every wet road
		float inrut = max(1.0 - smoothstep(0.15, 0.8, abs(ac - off)), line);
		float pn = gd_noise3(vec3(ac * 1.5, sl * 0.21, 13.0)) * (0.62 + 0.38 * inrut) + (n0 - 0.5) * 0.05 + (mix(0.5, n1, f2) - 0.5) * 0.025;
		float pk = zone * rd * lvl * (1.0 - jm) * (1.0 - smoothstep(0.3, 0.6, dry)) * smoothstep(0.85, 1.0, t) * (1.0 - smoothstep(0.3, 0.7, gpx)) * min(trail_puddles, 1.0);
		// the edges widen to at least ~1.5 pixels of the noise (no shimmering 1-pixel rim from afar / at grazing views).
		// The width comes from the pixel's size: fwidth() isn't defined in this per-pixel branch
		float paa = gpx * 1.6;
		m_wet = smoothstep(0.44 - paa, 0.56 + paa, pn) * pk;
		m_puddle = smoothstep(0.565 - paa, 0.59 + paa, pn) * pk;
		// fine relief from the scans: packed dirt at two sizes / turns mixed by a slow noise (no tile to see), gravel where it's loose
		vec3 r0 = gd_relief(tr_nr0, P.xz, pdx, pdy, vec2(0.955, 0.296), 1.0 / 1.7);
		vec3 r1 = gd_relief(tr_nr0, P.xz + 37.0, pdx, pdy, vec2(-0.416, 0.909), 1.0 / 2.9);
		vec3 r2 = gd_relief(tr_nr1, P.xz, pdx, pdy, vec2(-0.904, 0.427), 1.0 / 2.6);
		vec3 rl = mix(r0, r1, smoothstep(0.35, 0.65, gd_noise3(vec3(P.xz * 0.11, 1.7))));
		rl = mix(rl, r2, clamp(m_loose * 1.2 + rd * 0.35, 0.0, 1.0) * (1.0 - m_driven));
		float rfade = 1.0 - smoothstep(0.08, 0.35, gpx);
		tbump = (1.0 - 0.6 * m_driven) * (1.0 - 0.8 * jm) * rfade * tnear;
		tslope = rl.xy * tbump;
		// colour: all small steps. Driven dirt is tighter and a touch paler when dry (polished hardpack); loose grit is paler
		// and speckled; streaks run along the trail; old scuffed patches; tyre prints press a little darker
		float streak = gd_noise3(vec3(ac * 9.0, sl * 0.3, 2.0)) - 0.5;
		float scuff = smoothstep(0.55, 0.8, gd_noise3(vec3(P.xz * 0.55, 4.0)));
		float k = 1.0;
		k *= 1.0 + m_driven * (0.05 * dry - 0.03) + m_loose * 0.05;
		k *= 1.0 + streak * 0.09 * f2 * (0.35 + 0.65 * m_driven);
		k *= 1.0 + scuff * 0.045 * (1.0 - jm);
		k *= 1.0 + peb * 0.16 * pb.y * (0.25 + 0.75 * m_loose) + (n2 - 0.5) * 0.1 * f1 * (1.0 - 0.6 * m_driven);
		k *= 1.0 - 0.1 * length(rl.xy) * tbump;          // the relief's hollows sit a little darker
		k *= 1.0 - 0.11 * m_tracks;
		k *= 1.0 - 0.24 * m_skid;
		k *= 1.0 - 0.055 * m_stray;
		k *= 1.0 - 0.075 * m_play;
		// relief: each ridden line is a shallow groove (deepest where most riders go), tyre prints and skids are pressed
		// into it, loose grit and pebbles stand proud, and the unridden ground between the lines is slightly lumpy
		float lump = (gd_noise3(vec3(ac * 5.0, sl * 0.9, 6.0)) - 0.5) * 0.012 + (n1 - 0.5) * 0.006 * f2;
		thgt = -0.03 * line * (1.0 - 0.7 * jm) - 0.008 * m_tracks - 0.014 * m_skid - 0.006 * m_stray - 0.007 * m_play
			+ (peb * (0.006 + 0.008 * pb.y) + lump) * (0.3 + 0.7 * m_loose) * (1.0 - 0.8 * jm);
		thgt *= (1.0 - smoothstep(0.04, 0.16, gpx)) * tnear * (1.0 - m_puddle);
		k *= 1.0 + thgt * 2.2;                           // hollows hold a little shade, high spots catch light
		k *= 1.0 + jm * 0.04;                            // built jumps: raked, packed clay, more even
		k = mix(k, 1.0 + (k - 1.0) * 0.45, jm);
		tcol = vec3(mix(1.0, k, tnear));
		// dry dirt stays matte (>= 0.9 = no sun glint in light()): packed lines / prints at 0.74-0.8 glinted, so with a
		// low sun the whole trail looked polished / wet (user: "why such a glossy track"). Only damp soil + puddles shine.
		trough = mix(0.95, max(mix(rl.z, 0.8, 0.5 * m_driven + 0.3 * jm) - 0.06 * m_tracks, 0.9), rfade * tnear);
		// damp soil, then water
		tcol *= mix(vec3(1.0), vec3(0.6, 0.58, 0.56), m_wet);
		// (damp soil only darkens: no gloss. Only standing water shines; a shiny damp rim spread over the whole road)
	}
	// slow light / dark drifts along the trail, so a long straight never reads as one flat band
	float drift = 1.0 + (gd_noise3(vec3(P.xz * 0.05, 4.2)) - 0.5) * 0.1;
	vec3 col = mix(gA.rgb, gB.rgb * tcol * drift, wd);
	float rkw = rockW * (1.0 - wd) * f3;
	if (rkw > 0.001) {
		float rk = gd_noise3(P * 4.3 + 5.0) * 0.6 + (f2 > 0.0 ? gd_noise3(P * 13.0) * 0.4 * f2 : 0.0);
		col *= mix(1.0, 0.78 + 0.44 * rk, rkw);
	}
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
	float pud = m_puddle * wd;
	// a puddle: murky water over the soil, level, mirror-smooth (the sky shows in it), with the lightest wind ripple.
	// Not a perfect mirror: the sun's glint on 0.04 was smaller than a pixel and sparkled; it also goes duller with
	// the pixel's footprint (far off / grazing), where one pixel covers many ripples
	col = mix(col, gB.rgb * vec3(0.3, 0.29, 0.27), pud * 0.85);
	ALBEDO = col;
	float pud_r = mix(0.075, 0.22, smoothstep(0.02, 0.25, gpx));
	ROUGHNESS = mix(mix(0.95, trough, wd), pud_r, pud);
	// soil reflects almost no sky: at 0.3 a low sun's sky lit the whole road white at grazing angles (Fresnel)
	SPECULAR = mix(0.12, 0.6, pud);
	// screen derivatives here, in uniform control flow: inside the branch below they are undefined wherever the
	// branch differs between neighbouring pixels (trail / puddle edges), which flickered in 2x2 blocks
	float hh = thgt * wd * trail_relief;
	vec3 dpx = dFdx(P), dpy = dFdy(P);
	float dhx = dFdx(hh), dhy = dFdy(hh);
	if (wd * tbump > 0.0 || pud > 0.0 || thgt != 0.0) {
		vec3 nw = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
		nw = normalize(nw + vec3(tslope.x, 0.0, tslope.y) * (wd * trail_bump));
		// the height above as a real slope of the surface (its screen-space gradient turned into the world)
		vec3 r1 = cross(dpy, nw), r2 = cross(nw, dpx);
		float det = dot(dpx, r1);
		if (abs(det) > 1e-12) {
			vec3 grad = (dhx * r1 + dhy * r2) / det;
			nw = normalize(nw - clamp(grad, vec3(-1.2), vec3(1.2)));
		}
		vec2 rip = (vec2(gd_noise3(vec3(P.xz * 7.0 + TIME * 0.35, 1.0)), gd_noise3(vec3(P.xz * 7.0 - TIME * 0.3, 6.0))) - 0.5) * 0.02 * f2;
		nw = normalize(mix(nw, vec3(rip.x, 1.0, rip.y), pud));
		NORMAL = normalize((VIEW_MATRIX * vec4(nw, 0.0)).xyz);
	}
	// specular anti-aliasing (Tokuyoshi & Kaplanyan): a normal that changes fast across the pixel widens the
	// highlight instead of sparkling. Matters on the smooth parts (puddles, damp soil, packed lines)
	vec3 dnx = dFdx(NORMAL), dny = dFdy(NORMAL);
	float nvar = 0.25 * (dot(dnx, dnx) + dot(dny, dny));
	float ra = ROUGHNESS * ROUGHNESS;
	ROUGHNESS = sqrt(sqrt(clamp(ra * ra + min(2.0 * nvar, 0.18), 0.0, 1.0)));
	if (trail_debug == 1) {
		ALBEDO = vec3(m_driven, m_loose, max(m_puddle, m_wet * 0.4)) * wd + vec3(m_tracks) * 0.5 + vec3(m_skid, m_skid, 0.0) + vec3(m_stray, 0.0, m_stray) * wd + vec3(0.0, m_play, m_play) * wd;
		ROUGHNESS = 1.0;
	}
}

// lit by hand only so cloud shadows can dim the sun here (shaders/atmos); land is matte (roughness .95),
// packed lines / damp soil / puddles on the trail get a sun glint
void light() {
	vec3 lc = atmos_light_col(ATTENUATION * LIGHT_COLOR, LIGHT_IS_DIRECTIONAL, v_world);   // cloud shade once
	DIFFUSE_LIGHT += clamp(dot(NORMAL, LIGHT), 0.0, 1.0) * lc;
	if (ROUGHNESS < 0.9) {
		vec3 hv = normalize(LIGHT + VIEW);
		float nl = clamp(dot(NORMAL, LIGHT), 0.0, 1.0), nh = clamp(dot(NORMAL, hv), 0.0, 1.0), lh = max(dot(LIGHT, hv), 0.2);
		float a2 = ROUGHNESS * ROUGHNESS; a2 *= a2;
		float dd = nh * nh * (a2 - 1.0) + 1.0;
		float sp = a2 / (PI * dd * dd) * 0.04 / (4.0 * lh * lh);
		SPECULAR_LIGHT += lc * PI * nl * min(sp, 4.0) * (0.9 - ROUGHNESS) / 0.9;
	}
}
