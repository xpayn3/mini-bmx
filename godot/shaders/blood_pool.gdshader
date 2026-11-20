// A pool of blood (fx/blood_pool.gd + BloodPoolSim.cs): a mesh draped on the ground reads the
// simulated blood DEPTH (m) from a float texture.
// Looks: blood is an opaque, very dark red liquid with a mirror-smooth surface: what you mostly see is
// the sky / scene reflected in it (sharp highlights, screen-space reflections when on) over a deep red;
// the edge is a rounded meniscus (from the depth's slope) that catches the light, the thin film at the
// rim shows a lighter red.
// BUBBLES: thin-skinned domes in two sizes (a few mm, and a fine froth) where the blood runs in and in the
// shallows behind the edge. Each one swells up, sits breathing a little, then pops: the dome is gone in a
// blink and a ripple runs out from where it was. Nothing switches on or off in one frame.
// DRYING, by how thick the blood lies (thin dries first, so a front creeps in from the rim):
//   wet -> it clots (darker maroon, the mirror dulls to satin) -> dry: a thin film ends up matt rust brown
//   with a darker line along its outer edge, a thick layer near-black with a dull sheen. Kept plain on
//   purpose: no patchy noise, no cracks (the user found them noisy).
// Opaque with an alpha cut-out (not blended) so it gets real reflections and sorts with the scene.
shader_type spatial;
render_mode depth_draw_opaque, cull_disabled, specular_schlick_ggx;

uniform sampler2D depth_tex : filter_linear, repeat_disable;
uniform float pool_t = 0.0;
uniform float age_add = 0.0;       // tests: seconds added to the drying clock (BMX_POOL_AGE)
uniform float seed = 0.0;
uniform float wipe_at = 1e9;
uniform float wipe_len = 4.0;
uniform float grid_m = 6.4;        // world size of the mask (blood_pool.gd N * CELL)
const float DRY_THIN = 50.0;       // s until a film is dry (the pool is still spreading before that)
const float DRY_DEEP = 240.0;      // s until a centimetre of blood is a crust

varying vec3 v_world;

float bh(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float bn(vec2 p) {
	vec2 i = floor(p), f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(bh(i), bh(i + vec2(1, 0)), f.x), mix(bh(i + vec2(0, 1)), bh(i + vec2(1, 1)), f.x), f.y);
}

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	// pulled toward the camera, more further away: never flickers into the ground it's draped on
	vec3 view = (MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float vd = length(view);
	VERTEX = (inverse(MODELVIEW_MATRIX) * vec4(view - view / max(vd, 1e-3) * (0.05 + vd * 0.004), 1.0)).xyz;
}

// blood depth (m) at uv, warped a hair so the texel grid never shows
float depth_at(vec2 w, vec2 uv) {
	vec2 u = uv + (vec2(bn(w * 7.0 + seed), bn(w * 7.0 - seed + 3.0)) - 0.5) * 0.004;
	return texture(depth_tex, u).r;
}

// One layer of bubbles, `sc` cells a metre, at most one bubble a cell and always wholly inside it (never cut
// by the cell's edge). `amount` 0..1 = how many cells have one. Returns xy = the dome's slope, z = how much of
// the pixel the dome covers, w = the ripple left by a pop (signed: crest / trough).
vec4 bubbles(vec2 p, float sc, float amount, float sd) {
	vec2 bc = p * sc;
	vec2 ci = floor(bc);
	vec2 cf = fract(bc) - 0.5;
	float h0 = bh(ci + sd);
	float rate = 0.05 + 0.07 * bh(ci + 6.6 + sd);          // lives a second: each lasts 8..20 s
	float ph = h0 * 7.3 + pool_t * rate;
	float cyc = floor(ph);
	float life = (ph - cyc) / rate;                          // seconds into this life
	vec2 cj = ci + cyc * vec2(17.0, 31.0) + sd;             // every life: a new place, size, luck
	float pick = bh(cj + 1.3);
	float on = smoothstep(pick, pick + 0.1, amount);        // fewer wanted: it shrinks away, never blinks out
	vec2 bo = (vec2(bh(cj + 4.1), bh(cj + 8.3)) - 0.5) * 0.3;
	float sz = bh(cj + 2.2);
	float r0 = 0.09 + 0.13 * sz * sz;
	float t_pop = (0.45 + 0.35 * bh(cj + 5.5)) / rate;      // pops somewhere in its life, then the cell rests
	float grow = smoothstep(0.0, 0.9 + 1.2 * sz, life);
	grow = grow * (1.0 + 0.12 * sin(grow * 3.14159));       // swells a touch past its size, settles
	float breathe = 1.0 + 0.04 * sin(pool_t * (1.3 + h0 * 1.5) + h0 * 40.0);
	float since_pop = life - t_pop;
	float pre = smoothstep(-0.25, 0.0, since_pop);          // the skin thins and stretches just before
	float R = r0 * on * grow * breathe * (1.0 + 0.1 * pre);
	vec2 q = cf - bo;
	float len = length(q);
	float aa = fwidth(len) + 1e-5;
	float gone = smoothstep(0.0, 0.05, since_pop);          // popped: the dome is gone in a blink
	float fine = 1.0 - smoothstep(0.35, 0.9, aa / max(R, 1e-4));   // smaller than a pixel: fades out, no sparkle
	float cover = (1.0 - smoothstep(R - aa, R + aa, len)) * (1.0 - gone) * step(1e-4, R) * fine;
	vec2 slope = q / max(R, 1e-4);
	// the ripple: a ring running out from the bubble's rim, dying in half a second
	float rr = R * (1.0 + 1.1 * smoothstep(0.0, 0.5, since_pop));
	float ring = sin(clamp((len - rr) / (R * 0.35 + 1e-4), -1.0, 1.0) * 3.14159);
	ring *= step(0.0, since_pop) * (1.0 - smoothstep(0.05, 0.5, since_pop)) * on * fine;
	return vec4(slope, cover, ring);
}

void fragment() {
	vec2 w = v_world.xz;
	float dep = depth_at(w, UV);
	// fade out before the grid's border (it never should get there, but never as a straight cut)
	vec2 eb = min(UV, 1.0 - UV);
	dep *= smoothstep(0.01, 0.05, min(eb.x, eb.y));
	float a = smoothstep(0.0009, 0.0014, dep + (bn(w * 25.0 + seed) - 0.5) * 0.0003);
	// the liquid surface tilts where the depth changes (the meniscus at the edge, lumps inside)
	float du = 0.02 / grid_m;          // 2 cm
	float gx = (depth_at(w, UV + vec2(du, 0.0)) - depth_at(w, UV - vec2(du, 0.0))) / 0.04;
	float gz = (depth_at(w, UV + vec2(0.0, du)) - depth_at(w, UV - vec2(0.0, du))) / 0.04;
	vec3 nb = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);   // the ground's tilt
	float rim = 1.0 - smoothstep(0.0015, 0.0045, dep);     // 1 at the thin edge, 0 where it's deep
	float deep = smoothstep(0.003, 0.009, dep);
	float thick = smoothstep(0.0019, 0.0042, dep);   // enough blood to leave a crust, not just a stain

	// ---- how far along the drying is here: thin blood first, so it dries smoothly from the rim inwards
	float t_dry = mix(DRY_THIN, DRY_DEEP, smoothstep(0.0012, 0.008, dep));
	float x = (pool_t + age_add) / t_dry;
	float clot = smoothstep(0.08, 0.5, x);
	float dry = smoothstep(0.5, 1.0, x);
	float wet = 1.0 - dry;

	vec3 slope = vec3(gx, 0.0, gz) * 1.2 * mix(1.0, 0.45, dry);   // a dried edge is flatter than a meniscus

	// ---- bubbles: where it runs in (the grid's middle) and in the shallows behind the edge, while it's fresh
	vec2 wr = vec2(w.x * 0.8 - w.y * 0.6, w.x * 0.6 + w.y * 0.8);   // turned: no rows along the world axes
	float shallows = smoothstep(0.0018, 0.003, dep) * (1.0 - smoothstep(0.004, 0.009, dep));
	float src = 1.0 - smoothstep(0.03, 0.3, length(UV - 0.5) * grid_m);
	float pouring = 1.0 - smoothstep(6.0, 30.0, pool_t);
	float clump = smoothstep(0.3, 0.75, bn(wr * 3.1 + seed * 0.7));   // patches with bare blood between
	float amount = (0.03 + 0.45 * shallows + 0.6 * src * pouring) * (0.1 + 1.2 * clump) * (1.0 - clot)
		* smoothstep(0.0016, 0.0026, dep);
	vec4 b1 = bubbles(wr, 30.0, amount, seed * 1.7);
	vec4 b2 = bubbles(wr + 0.37, 72.0, amount * 1.3, seed * 2.9 + 11.0);
	float bub = max(b1.z, b2.z);
	vec2 bs = b1.z >= b2.z ? b1.xy : b2.xy;
	slope -= vec3(bs.x, 0.0, bs.y) * (b1.w * 0.5 + b2.w * 0.35) * wet;   // the pop's ripple

	vec3 nw = normalize(nb - slope);
	if (bub > 0.0) {
		// a dome: its normal tilts out from the middle, glints sharp
		vec2 s = bs * 0.92;
		vec3 dome = normalize(vec3(s.x, sqrt(max(0.02, 1.0 - dot(s, s))), s.y));
		nw = normalize(mix(nw, dome, bub));
	}

	vec3 film = vec3(0.26, 0.012, 0.006);         // thin layer at the rim: the red shows
	vec3 pooled = vec3(0.045, 0.0015, 0.001);     // deep blood: nearly black red
	vec3 col = mix(film, pooled, max(deep, 1.0 - rim));
	col *= mix(1.0, 0.55, clot * rim);            // clotted: the bright film goes maroon
	// a bubble's skin is thin: lighter, and darker where it meets the blood
	float ring_d = smoothstep(0.7, 1.0, length(bs)) * bub;
	col = mix(col, vec3(0.13, 0.008, 0.005), bub * 0.55 * (1.0 - ring_d));
	vec3 dried = mix(vec3(0.085, 0.026, 0.012), vec3(0.018, 0.006, 0.004), thick);
	// the dried edge keeps a darker line (the solids are carried out to it as it dries)
	float line = smoothstep(0.0012, 0.0019, dep) * (1.0 - smoothstep(0.0022, 0.0036, dep));
	dried *= 1.0 - 0.45 * line;
	col = mix(col, dried, dry);
	ALBEDO = col;
	float rough_wet = mix(mix(0.04, 0.12, rim), 0.3, clot);
	float rough_dry = mix(0.88, 0.68, thick);       // a film: matt; a crust: a dull sheen
	ROUGHNESS = mix(rough_wet, rough_dry, dry) * (1.0 - 0.5 * bub);
	SPECULAR = mix(0.5, 0.22, dry);
	METALLIC = 0.0;
	NORMAL = normalize((VIEW_MATRIX * vec4(nw, 0.0)).xyz);
	float wipe = 1.0 - smoothstep(0.0, wipe_len, pool_t - wipe_at);
	// cut-out edge (opaque inside); a respawn dissolves it with noise
	ALPHA = a * step(bh(floor(w * 120.0)) * 0.98 + 0.01, wipe);
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	ALPHA_ANTIALIASING_EDGE = 0.3;               // MSAA alpha-to-coverage: a smooth cut-out edge
	ALPHA_TEXTURE_COORDINATE = w * 25.0;
}
