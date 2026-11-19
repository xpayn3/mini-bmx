// Blood on the ground after a crash (fx/blood.gd): flat quads lying on the terrain, one MultiMesh.
// INSTANCE_CUSTOM = (seed, birth time, strength 0..1, kind: 0 = a smear dragged along the quad's
// length by a sliding body part, 1 = a splat where a part slammed down, 2 = a growing pool).
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
	float fresh_in;   // seconds to soak in after it's laid
	if (v_c.w < 0.5) {
		// smear: a body part dragged a thin film of blood along: fine streaks running the way it slid,
		// a fuzzy ragged band, broken up where there was little blood (dry-brush), the ground showing through
		float u = UV.x * 2.0 - 1.0;
		float x = u * v_size.x * 0.5;                    // metres across the smear
		float y = UV.y * v_size.y;                       // metres along
		float edge = 0.6 + 0.3 * bn(w * 7.0 + seed) - 0.3 * (1.0 - str);
		float band = 1.0 - smoothstep(edge - 0.35, edge, abs(u));
		// streaks: thin lines across, long along (cloth / skin dragging through it)
		float fine = bn(vec2(x * 140.0 + seed * 7.0, y * 0.9 + seed));
		float mid = bn(vec2(x * 45.0 - seed, y * 0.5));
		float lines = fine * 0.55 + mid * 0.45;
		// dry-brush: where there's little blood only the strongest streaks print
		float skip = bn(w * 4.0 + seed * 3.1);
		float d = band * (0.25 + 1.0 * lines) * (0.45 + 0.75 * str) - (1.0 - str) * (0.35 * skip + 0.25 * (1.0 - fine));
		a = smoothstep(0.22, 0.5, d);
		// soft ends so the joins between quads don't show
		float e = min(UV.y, 1.0 - UV.y) * v_size.y;
		a *= smoothstep(0.0, min(0.06, v_size.y * 0.3), e + 0.02);
		thick = smoothstep(0.55, 1.15, d);
		a *= mix(0.55, 1.0, thick);                      // a thin film is see-through
		fresh_in = 0.6;
	} else if (v_c.w < 1.5) {
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
		fresh_in = 0.15;
	} else {
		// pool (blood.gd grows the quad): a thick glossy puddle, lobed edge (it runs into the dips),
		// a thinner lighter rim where it's still spreading
		vec2 p = UV * 2.0 - 1.0;
		float r = length(p);
		float ang = atan(p.y, p.x);
		float edge = 0.72 + 0.14 * bn(vec2(ang * 1.6 + seed, seed)) + 0.1 * bn(w * 5.0 + seed) + 0.06 * bn(w * 19.0 - seed);
		a = 1.0 - smoothstep(edge - 0.03, edge, r);
		thick = 1.0 - smoothstep(edge - 0.18, edge, r) * 0.8;
		fresh_in = 0.3;
	}
	float age = clamp((now - v_c.y) / DRY, 0.0, 1.0);
	// thin film: a brighter red; pooled: deep, nearly black red; dried: brown
	vec3 film = vec3(0.30, 0.018, 0.008);
	vec3 pool = vec3(0.085, 0.002, 0.002);
	vec3 dried = vec3(0.06, 0.016, 0.008);
	vec3 col = mix(mix(film, pool, thick), dried, age);
	ALBEDO = col;
	ROUGHNESS = mix(mix(0.32, 0.14, thick), 0.75, age);
	SPECULAR = 0.55;
	float dist = length(VERTEX);
	float wipe = v_c.y < wipe_t ? 1.0 - smoothstep(0.0, wipe_len, now - wipe_t) : 1.0;
	float soak = smoothstep(0.0, fresh_in, now - v_c.y);   // fades in as it's laid
	ALPHA = a * soak * (1.0 - smoothstep(fade_near, fade_far, dist)) * 0.96 * wipe;
}
