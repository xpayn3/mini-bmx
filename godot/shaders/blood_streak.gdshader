// Blood on the ground after a crash (fx/blood.gd): flat quads lying on the terrain, one MultiMesh.
// INSTANCE_CUSTOM = (seed, birth time, strength 0..1, kind: 0 = a smear dragged along the quad's
// length by a sliding body part, 1 = a splat where a part slammed down).
// UV.x across (0..1), UV.y along (0..1). Noise runs in world space so the smears join up seamlessly.
// Fresh blood is dark red and glossy; it darkens and goes matt as it dries (DRY seconds).
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, specular_schlick_ggx;

uniform float now = 0.0;          // blood.gd's clock (same one the birth times use)
uniform float wipe_t = -1e9;      // a respawn: blood born before this fades out over wipe_len seconds
uniform float wipe_len = 4.0;
uniform float fade_near = 50.0;
uniform float fade_far = 100.0;
const float DRY = 45.0;

varying vec4 v_c;
varying vec3 v_world;
varying vec2 v_size;              // metres across / along

float bh(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float bn(vec2 p) {
	vec2 i = floor(p), f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(bh(i), bh(i + vec2(1, 0)), f.x), mix(bh(i + vec2(0, 1)), bh(i + vec2(1, 1)), f.x), f.y);
}

void vertex() {
	v_c = INSTANCE_CUSTOM;
	v_size = vec2(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[2].xyz));
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	// pull a little toward the camera so it never flickers into the ground (as the tyre tracks)
	vec3 view = (MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	VERTEX = (inverse(MODELVIEW_MATRIX) * vec4(view - normalize(view) * 0.035, 1.0)).xyz;
}

void fragment() {
	float seed = v_c.x;
	float str = v_c.z;
	vec2 w = v_world.xz;
	float a;
	float thick;   // 0..1: pooled (darker, glossier) vs a thin film
	if (v_c.w < 0.5) {
		// smear: ragged edges, streaks dragged along, thinning out in gaps
		float u = UV.x * 2.0 - 1.0;
		float edge = 0.55 + 0.35 * bn(w * 9.0 + seed) - 0.25 * (1.0 - str);
		float band = 1.0 - smoothstep(edge - 0.18, edge, abs(u));
		// streak lines along the slide: noise across, stretched along (x in metres across the smear)
		float x = u * v_size.x * 0.5;
		float lines = bn(vec2(x * 60.0 + seed * 7.0, (UV.y * v_size.y) * 1.5 + seed));
		lines = lines * 0.6 + bn(vec2(x * 23.0 - seed, UV.y * v_size.y * 0.8)) * 0.4;
		float gaps = bn(w * 3.0 + seed * 3.1);
		float d = band * (0.35 + 0.9 * lines) * (0.55 + 0.6 * str) - (1.0 - str) * gaps * 0.6;
		a = smoothstep(0.32, 0.42, d);
		// soft ends so the joins between quads don't show
		float e = min(UV.y, 1.0 - UV.y) * v_size.y;
		a *= smoothstep(0.0, min(0.05, v_size.y * 0.25), e + 0.02);
		thick = smoothstep(0.5, 1.1, d);
	} else {
		// splat: a noisy blob with a few droplets thrown round it
		vec2 p = UV * 2.0 - 1.0;
		float r = length(p);
		float ang = atan(p.y, p.x);
		float edge = 0.38 + 0.22 * bn(vec2(ang * 2.2 + seed, seed)) + 0.12 * bn(w * 14.0 + seed);
		edge *= 0.7 + 0.3 * str;
		a = 1.0 - smoothstep(edge - 0.04, edge, r);
		// droplets: one maybe per small cell, more toward the middle
		vec2 cell = floor(w * 22.0);
		vec2 fc = fract(w * 22.0) - 0.5;
		float hsh = bh(cell + seed);
		vec2 off = (vec2(bh(cell + 3.1), bh(cell + 7.7)) - 0.5) * 0.5;
		float dr = 0.12 + 0.2 * bh(cell + 1.9);
		float drop = step(length(fc - off), dr) * step(1.0 - 0.55 * (1.0 - r) * str, hsh) * step(r, 0.98);
		a = max(a, drop);
		thick = 1.0 - smoothstep(0.0, edge, r) * 0.7;
	}
	float age = clamp((now - v_c.y) / DRY, 0.0, 1.0);
	vec3 fresh = vec3(0.16, 0.005, 0.005);
	vec3 dried = vec3(0.05, 0.008, 0.005);
	vec3 col = mix(fresh, dried, age) * (1.15 - 0.45 * thick);
	ALBEDO = col;
	ROUGHNESS = mix(mix(0.32, 0.14, thick), 0.75, age);
	SPECULAR = 0.55;
	float dist = length(VERTEX);
	float wipe = v_c.y < wipe_t ? 1.0 - smoothstep(0.0, wipe_len, now - wipe_t) : 1.0;
	ALPHA = a * (1.0 - smoothstep(fade_near, fade_far, dist)) * 0.96 * wipe;
}
