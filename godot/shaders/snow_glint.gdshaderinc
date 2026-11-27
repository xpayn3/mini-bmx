// Snow glitter + crust (2026-11-27, ground.gdshader's snow layer and snow_patch.gdshader share it).
// Glints: ice facets each turned its own way, lit when it mirrors the sun into the eye (snow_glint_light in light()).
// Two sizes of cell: 3 cm up close, 8 cm further out (each faded out before its specks get smaller than ~1 px: drawn wider
// and dimmer as the pixel grows, so they never flicker as single sub-pixel dots), ~14 % of cells hold one.
// Crust: the snow's own surface (wind crust ~25 cm, grain ~5 cm), a slope to tilt the normal; grain fades with distance.

float sg_hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float sg_noise(vec2 p) {
	vec2 i = floor(p), f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(sg_hash(i), sg_hash(i + vec2(1, 0)), f.x), mix(sg_hash(i + vec2(0, 1)), sg_hash(i + vec2(1, 1)), f.x), f.y);
}

// one layer: cells per metre k, returns (facet normal world, strength)
vec4 sg_layer(vec2 xz, vec3 wn, float gpx, float k, float salt) {
	vec2 gc = floor(xz * k);
	float h0 = sg_hash(gc + salt), h1 = sg_hash(gc + 17.3 + salt), h2 = sg_hash(gc + 41.7 + salt);
	if (h0 > 0.14) return vec4(0.0);
	vec2 cen = (gc + 0.2 + 0.6 * vec2(h1, h2)) / k;
	float r0 = 0.15 / k;
	float rr = max(r0, gpx * 0.9);
	float sd = 1.0 - smoothstep(rr * 0.4, rr, length(xz - cen));
	vec3 gn = normalize(wn + vec3(h1 - 0.5, 0.0, h2 - 0.5) * 0.7);
	return vec4(gn, sd * (r0 * r0) / (rr * rr) * (0.6 + 0.8 * fract(h0 * 37.0)));
}

// both layers; returns the facet normal in VIEW space + strength (0 = none)
vec4 snow_glint(vec2 xz, vec3 wn, float gpx, mat4 view) {
	float kn = 1.0 - smoothstep(0.008, 0.02, gpx);
	float kf = smoothstep(0.006, 0.016, gpx) * (1.0 - smoothstep(0.03, 0.06, gpx));
	vec4 g = vec4(0.0);
	if (kn > 0.0) { g = sg_layer(xz, wn, gpx, 33.0, 0.0); g.w *= kn; }
	if (kf > 0.0) {
		vec4 f = sg_layer(xz, wn, gpx, 12.0, 91.0);
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
	const float SG_E = 0.03;
	float h0 = (sg_noise(xz * 4.0) - 0.5) * 0.03 + (sg_noise(xz * 18.0 + 5.0) - 0.5) * 0.006 * fine;
	float hx = (sg_noise((xz + vec2(SG_E, 0.0)) * 4.0) - 0.5) * 0.03 + (sg_noise((xz + vec2(SG_E, 0.0)) * 18.0 + 5.0) - 0.5) * 0.006 * fine;
	float hz = (sg_noise((xz + vec2(0.0, SG_E)) * 4.0) - 0.5) * 0.03 + (sg_noise((xz + vec2(0.0, SG_E)) * 18.0 + 5.0) - 0.5) * 0.006 * fine;
	return vec2(hx - h0, hz - h0) / SG_E;
}
