// Draws one grit grain (shaders/smoke/grit.gdshader): a tiny round camera-facing speck, lit by the sun
// as it reaches the grain through the dust (the smoke sim's light volume) + sky; tumbling grains catch
// the sun and glint.
shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled;

uniform sampler3D light_tex : filter_linear, repeat_disable;   // r density, g sun through dust, b sky
uniform sampler2D hmap : filter_linear, repeat_disable;
uniform vec3 origin;
uniform vec3 size_m;
uniform float hm_cells = 32.0;
uniform vec3 sun_col = vec3(3.0, 2.8, 2.5);
uniform vec3 amb_col = vec3(0.45, 0.55, 0.75);

varying vec3 v_light;
varying float v_glint;
varying float v_rnd;
varying vec3 v_sun;
uniform vec3 sun_dir = vec3(0.3, 0.8, 0.5);   // toward the sun, world

void vertex() {
	vec3 wp = MODEL_MATRIX[3].xyz;
	float s = length(MODEL_MATRIX[0].xyz);
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0] * s, INV_VIEW_MATRIX[1] * s, INV_VIEW_MATRIX[2] * s, vec4(wp, 1.0));
	vec2 g = (wp.xz - origin.xz) / size_m.xz;
	float gr = texture(hmap, (clamp(g, 0.0, 1.0) * hm_cells + 0.5) / (hm_cells + 1.0)).r;
	vec3 g3 = vec3(g.x, (wp.y - gr) / size_m.y, g.y);
	vec3 L = vec3(1.0, 1.0, 1.0);
	if (all(greaterThan(g3, vec3(0.0))) && all(lessThan(g3, vec3(1.0)))) L = texture(light_tex, g3).gbr;
	// a tumbling grain flashes when a facet faces the sun
	float ph = INSTANCE_CUSTOM.z * 61.0;
	v_glint = pow(max(0.0, sin(TIME * (9.0 + INSTANCE_CUSTOM.z * 14.0) + ph)), 24.0) * (1.0 - INSTANCE_CUSTOM.y);
	// lit like the ground it came from, not brighter: no glow (the old gain made the grains burn pale)
	v_light = (sun_col * L.x * (0.16 + 0.35 * v_glint) + amb_col * (0.30 + 0.5 * L.y)) * 0.62;
	v_rnd = INSTANCE_CUSTOM.z;
	v_sun = normalize((VIEW_MATRIX * vec4(sun_dir, 0.0)).xyz);
}

float h11(float x) { return fract(sin(x * 127.1) * 43758.5453); }
float h21(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p), f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h21(i), h21(i + vec2(1, 0)), f.x), mix(h21(i + vec2(0, 1)), h21(i + vec2(1, 1)), f.x), f.y);
}
// the chunk's height field: a lumpy dome with chips and pits (three octaves of noise, a different one per grain)
float hf(vec2 q, float seed, float dome) {
	vec2 p = q * 6.0 + vec2(seed * 13.0, seed * 7.0);
	float n = vnoise(p) * 0.55 + vnoise(p * 2.3 + 5.1) * 0.3 + vnoise(p * 5.1 + 9.7) * 0.15;
	// chips: the noise cut into flat facets
	n = mix(n, floor(n * 4.0) / 4.0, 0.45);
	return dome * 0.9 + n * 0.7;
}

void fragment() {
	float r0 = v_rnd * 97.0;
	float ang = h11(r0) * 6.2832;
	float aspect = mix(1.0, 2.1, h11(r0 + 1.3));
	vec2 q = UV - 0.5;
	q = vec2(cos(ang) * q.x + sin(ang) * q.y, -sin(ang) * q.x + cos(ang) * q.y);
	q.x /= aspect;
	// warp the outline with noise so the edge is never a clean polygon
	vec2 w = vec2(vnoise(q * 9.0 + r0), vnoise(q * 9.0 + r0 + 17.0)) - 0.5;
	q += w * 0.22;
	float a = atan(q.y, q.x);
	float edge = 0.30 + 0.20 * (
		0.45 * sin(a * 3.0 + h11(r0 + 2.1) * 6.28) +
		0.35 * sin(a * 5.0 + h11(r0 + 3.7) * 6.28) +
		0.20 * sin(a * 8.0 + h11(r0 + 5.9) * 6.28));
	float rr = length(q);
	if (rr > edge) discard;
	// bump map: the height field's slope is the surface normal, lit by the sun from this view
	float dome = sqrt(max(0.0, 1.0 - (rr / edge) * (rr / edge)));
	float e = 0.02;
	float h0 = hf(q, v_rnd, dome);
	float hx = hf(q + vec2(e, 0.0), v_rnd, dome);
	float hy = hf(q + vec2(0.0, e), v_rnd, dome);
	// back to the quad's screen axes (undo the turn + stretch), y flipped: UV.y runs down the screen
	vec2 g = vec2(hx - h0, hy - h0) / e * 0.09;
	vec2 gs = vec2(cos(ang) * g.x / aspect - sin(ang) * g.y, sin(ang) * g.x / aspect + cos(ang) * g.y);
	vec3 n = normalize(vec3(-gs.x, gs.y, 1.0));
	float diff = clamp(dot(n, v_sun) * 0.5 + 0.5, 0.0, 1.0);
	float pit = smoothstep(0.35, 0.0, h0 - dome * 0.9) * 0.35;   // crevices read darker
	float edge_dark = 1.0 - 0.35 * smoothstep(0.6, 1.0, rr / edge);
	float tone = (0.5 + 0.9 * diff) * (1.0 - pit) * edge_dark * (0.85 + 0.3 * h11(r0 + 7.7));
	ALBEDO = COLOR.rgb * v_light * tone * 1.15;
}
