// A pool of blood (fx/blood_pool.gd + BloodPoolSim.cs): a mesh draped on the ground reads the
// simulated blood DEPTH (m) from a float texture.
// Looks: blood is an opaque, very dark red liquid with a mirror-smooth surface: what you mostly see is
// the sky / scene reflected in it (sharp highlights, screen-space reflections when on) over a deep red;
// the edge is a rounded meniscus (from the depth's slope) that catches the light, the thin film at the
// rim shows a lighter red, and small bubbles (domed, glinting) sit near the edge, appear and pop.
// Drying: over DRY seconds it goes matt and brown, from the rim inwards.
// Opaque with an alpha cut-out (not blended) so it gets real reflections and sorts with the scene.
shader_type spatial;
render_mode depth_draw_opaque, cull_disabled, specular_schlick_ggx;

uniform sampler2D depth_tex : filter_linear, repeat_disable;
uniform float pool_t = 0.0;
uniform float seed = 0.0;
uniform float wipe_at = 1e9;
uniform float wipe_len = 4.0;
uniform float grid_m = 6.4;        // world size of the mask (blood_pool.gd N * CELL)
const float DRY = 90.0;

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

void fragment() {
	vec2 w = v_world.xz;
	float dep = depth_at(w, UV);
	float a = smoothstep(0.0009, 0.0014, dep + (bn(w * 25.0 + seed) - 0.5) * 0.0003);
	// the liquid surface tilts where the depth changes (the meniscus at the edge, lumps inside)
	float du = 0.02 / grid_m;          // 2 cm
	float gx = (depth_at(w, UV + vec2(du, 0.0)) - depth_at(w, UV - vec2(du, 0.0))) / 0.04;
	float gz = (depth_at(w, UV + vec2(0.0, du)) - depth_at(w, UV - vec2(0.0, du))) / 0.04;
	vec3 nb = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);   // the ground's tilt
	vec3 nw = normalize(nb - vec3(gx, 0.0, gz) * 1.2);
	float rim = 1.0 - smoothstep(0.0013, 0.0035, dep);     // 1 at the thin edge, 0 where it's deep
	float deep = smoothstep(0.002, 0.007, dep);
	float since = pool_t;

	// BUBBLES: maybe one per small cell, mostly near the fresh edge; each lives a while then pops
	vec2 bc = w * 55.0;                   // ~1.8 cm cells
	vec2 ci = floor(bc);
	vec2 cf = fract(bc) - 0.5;
	float hb = bh(ci + seed * 1.7);
	vec2 bo = (vec2(bh(ci + 4.1), bh(ci + 8.3)) - 0.5) * 0.5;
	float br = 0.12 + 0.28 * bh(ci + 2.2);
	float near_edge = rim;
	float fresh = 1.0 - smoothstep(2.0, 12.0, since);
	float density = 0.012 + 0.22 * near_edge * fresh + 0.03 * fresh;
	float life = fract(hb * 7.3 + pool_t * (0.05 + 0.1 * bh(ci + 6.6)));
	float alive = step(hb, density) * step(life, 0.75);
	vec2 bp = (cf - bo) / br;
	float bd = dot(bp, bp);
	float bub = alive * (1.0 - step(1.0, bd)) * step(0.5, a);
	if (bub > 0.0) {
		// a dome: its normal tilts out from the middle, glints sharp
		vec2 s = bp * 0.9;
		nw = normalize(vec3(s.x, sqrt(max(0.0, 1.0 - dot(s, s))), s.y));
	}

	float age = clamp(pool_t / DRY, 0.0, 1.0);
	float dry = clamp(age * 1.3 + rim * age * 0.6, 0.0, 1.0);   // the rim dries first
	vec3 film = vec3(0.26, 0.012, 0.006);       // thin layer at the rim: the red shows
	vec3 pooled = vec3(0.045, 0.0015, 0.001);   // deep blood: nearly black red
	vec3 dried = vec3(0.055, 0.014, 0.007);     // dried: dark brown
	vec3 col = mix(film, pooled, max(deep, 1.0 - rim));
	col = mix(col, vec3(0.12, 0.01, 0.006), bub * 0.6);   // a bubble's skin is a little lighter
	ALBEDO = mix(col, dried, dry);
	ROUGHNESS = mix(mix(0.04, 0.12, rim), 0.65, dry) * (1.0 - 0.5 * bub);
	SPECULAR = mix(0.5, 0.3, dry);
	METALLIC = 0.0;
	NORMAL = normalize((VIEW_MATRIX * vec4(nw, 0.0)).xyz);
	float wipe = 1.0 - smoothstep(0.0, wipe_len, pool_t - wipe_at);
	// cut-out edge (opaque inside); a respawn dissolves it with noise
	ALPHA = a * step(bh(floor(w * 120.0)) * 0.98 + 0.01, wipe);
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	ALPHA_ANTIALIASING_EDGE = 0.3;               // MSAA alpha-to-coverage: a smooth cut-out edge
	ALPHA_TEXTURE_COORDINATE = w * 25.0;
}
