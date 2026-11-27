// Snow glitter + crust (2026-11-27, ground.gdshader's snow layer and snow_patch.gdshader share it).
// Glints: ice facets each turned its own way, lit when it mirrors the sun into the eye (snow_glint_light in light()).
// Two sizes of cell: 3 cm up close, 8 cm further out (each faded out before its specks get smaller than ~1 px: drawn wider
// and dimmer as the pixel grows, so they never flicker as single sub-pixel dots), ~14 % of cells hold one.
// Crust: the snow's own surface (wind crust ~17 cm, grain ~4 cm), a slope to tilt the normal; grain fades with distance.

// integer hash (a sin() hash of big coordinates rounds differently on each side of a cell edge and draws lines there)
float sg_hashi(ivec2 c, int salt) {
	uvec2 q = uvec2(c + ivec2(salt * 7919, salt * 104729));
	q *= uvec2(1597334673u, 3812015801u);
	uint n = (q.x ^ q.y) * 1597334673u;
	n ^= n >> 16u;
	return float(n) * (1.0 / 4294967296.0);
}
float sg_noise(vec2 p) {
	vec2 fl = floor(p), f = p - fl;
	ivec2 i = ivec2(fl);
	f = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);   // (quintic: no crease in the light at the cell edges)
	return mix(mix(sg_hashi(i, 0), sg_hashi(i + ivec2(1, 0), 0), f.x), mix(sg_hashi(i + ivec2(0, 1), 0), sg_hashi(i + ivec2(1, 1), 0), f.x), f.y);
}

// one layer: cells per metre k, returns (facet normal world, strength). Each speck is round ON SCREEN (its distance
// measured in pixels through the pixel footprint ji = inverse of [dFdx(xz) dFdy(xz)]): a round dot on the ground seen at a
// grazing angle stretched into a long dash. At least ~0.8 px across; dimmer the smaller its world size is next to that
vec4 sg_layer(vec2 xz, vec3 wn, mat2 ji, float gmin, float k, float salt) {
	vec2 gc = floor(xz * k);
	ivec2 ic = ivec2(gc);
	int sa = int(salt);
	float h0 = sg_hashi(ic, sa + 1), h1 = sg_hashi(ic, sa + 2), h2 = sg_hashi(ic, sa + 3);
	if (h0 > 0.14) return vec4(0.0);
	vec2 cen = (gc + 0.2 + 0.6 * vec2(h1, h2)) / k;
	float r0 = 0.15 / k;
	float rpx = max(0.8, r0 / max(gmin, 1e-5));
	float dpx = length(ji * (xz - cen));
	float sd = 1.0 - smoothstep(rpx * 0.45, rpx, dpx);
	float w = min(1.0, pow(r0 / (rpx * max(gmin, 1e-5)), 2.0));
	vec3 gn = normalize(wn + vec3(h1 - 0.5, 0.0, h2 - 0.5) * 0.7);
	return vec4(gn, sd * w * (0.6 + 0.8 * fract(h0 * 37.0)));
}

// both layers; dx / dy = dFdx / dFdy of xz taken in uniform control flow by the caller. Returns the facet normal in VIEW
// space + strength (0 = none)
vec4 snow_glint(vec2 xz, vec3 wn, vec2 dx, vec2 dy, mat4 view) {
	mat2 J = mat2(dx, dy);
	float det = determinant(J);
	if (abs(det) < 1e-12) return vec4(0.0);
	mat2 ji = inverse(J);
	float gmin = min(length(dx), length(dy));
	float gpx = max(length(dx), length(dy));
	float kn = 1.0 - smoothstep(0.008, 0.02, gmin);
	float kf = smoothstep(0.006, 0.016, gmin) * (1.0 - smoothstep(0.03, 0.06, gmin));
	kn *= 1.0 - smoothstep(0.08, 0.2, gpx);   // (very grazing: none)
	kf *= 1.0 - smoothstep(0.15, 0.4, gpx);
	vec4 g = vec4(0.0);
	if (kn > 0.0) { g = sg_layer(xz, wn, ji, gmin, 33.0, 0.0); g.w *= kn; }
	if (kf > 0.0) {
		vec4 f = sg_layer(xz, wn, ji, gmin, 12.0, 91.0);
		f.w *= kf;
		if (f.w > g.w) g = f;
	}
	if (g.w <= 0.0) return vec4(0.0);
	return vec4(normalize((view * vec4(g.xyz, 0.0)).xyz), g.w);
}

// the light: a glint flares inside ~20 deg of the mirror direction; strength x7
vec3 snow_glint_light(vec4 g, vec3 L, vec3 V, vec3 lc) {
	if (g.w <= 0.0) return vec3(0.0);
	float gr = dot(reflect(-L, g.xyz), V);
	return lc * smoothstep(0.94, 0.99, gr) * g.w * 9.0;
}

// the crust's slope (world xz) at a point; fine grain x fine (0 far off)
vec2 snow_crust(vec2 xz, float fine) {
	const float SG_E = 0.01;
	float h0 = (sg_noise(xz * 6.0) - 0.5) * 0.012 + (sg_noise(xz * 24.0 + 5.0) - 0.5) * 0.003 * fine;
	float hx = (sg_noise((xz + vec2(SG_E, 0.0)) * 6.0) - 0.5) * 0.012 + (sg_noise((xz + vec2(SG_E, 0.0)) * 24.0 + 5.0) - 0.5) * 0.003 * fine;
	float hz = (sg_noise((xz + vec2(0.0, SG_E)) * 6.0) - 0.5) * 0.012 + (sg_noise((xz + vec2(0.0, SG_E)) * 24.0 + 5.0) - 0.5) * 0.003 * fine;
	return vec2(hx - h0, hz - h0) / SG_E;
}
