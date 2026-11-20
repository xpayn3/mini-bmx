// The rider's trousers (rider/pants_look.gd): a scanned fabric (Poly Haven, CC0: weave colour as grey, normal,
// roughness, AO) tinted with the pants colour, and a printed pattern on top in a second colour. Everything is
// worked out from the mesh's own position in metres (object space x the node's scale: the leg tubes are unit
// cylinders stretched to the bone), so it moves with the leg and keeps its size whatever the bone length.
// The fabric wraps round the tube (u = angle, a whole number of tiles round so there's no seam); the patterns
// are 3D noise, so they have no seam either.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform vec4 base_col : source_color = vec4(0.11, 0.17, 0.39, 1.0);
uniform vec4 pat_col : source_color = vec4(0.9, 0.45, 0.1, 1.0);
uniform sampler2D fab_grey : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D fab_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D fab_rough : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D fab_ao : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float fabric = 1.0;        // 0 = plain dyed cloth (no scan)
uniform float tile = 0.18;         // m: one texture tile
uniform float grain = 1.0;         // contrast of the scan's light / dark in the colour (1 = as scanned)
uniform float rough_base = 0.85;
uniform float normal_k = 1.0;
uniform int pattern = 0;           // 0 none, 1 camo, 2 digital camo, 3 tiger, 4 zebra, 5 leopard, 6 checker, 7 tie-dye, 8 flames, 9 lightning
uniform float pat_scale = 1.0;     // > 1 = bigger shapes

varying vec3 v_p;
varying float v_r;

float h31(vec3 p) {
	p = fract(p * vec3(0.1031, 0.1030, 0.0973));
	p += dot(p, p.yxz + 33.33);
	return fract((p.x + p.y) * p.z);
}
vec3 h33(vec3 p) {
	return vec3(h31(p), h31(p + 17.3), h31(p + 41.7));
}
float vnoise(vec3 p) {
	vec3 i = floor(p), f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(h31(i), h31(i + vec3(1, 0, 0)), f.x), mix(h31(i + vec3(0, 1, 0)), h31(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(h31(i + vec3(0, 0, 1)), h31(i + vec3(1, 0, 1)), f.x), mix(h31(i + vec3(0, 1, 1)), h31(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}
float fbm(vec3 p) {
	float a = 0.5, s = 0.0;
	for (int i = 0; i < 4; i++) { s += a * vnoise(p); p = p * 2.03 + 7.1; a *= 0.5; }
	return s;
}
// distance to the nearest / second nearest feature point (cells of size 1) + that point's id
vec3 voronoi(vec3 p) {
	vec3 i = floor(p);
	float d1 = 9.0, d2 = 9.0, id = 0.0;
	for (int x = -1; x <= 1; x++) for (int y = -1; y <= 1; y++) for (int z = -1; z <= 1; z++) {
		vec3 c = i + vec3(float(x), float(y), float(z));
		vec3 q = c + h33(c) * 0.8 + 0.1;
		float d = length(p - q);
		if (d < d1) { d2 = d1; d1 = d; id = h31(c + 3.7); } else if (d < d2) { d2 = d; }
	}
	return vec3(d1, d2, id);
}

void vertex() {
	vec3 sc = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), length(MODEL_MATRIX[2].xyz));
	v_p = VERTEX * sc;
	v_r = max(length(v_p.xz), 0.02);
	// tangent frame for the wrapped fabric: u round the tube (+angle), v along it
	vec3 t = normalize(vec3(-VERTEX.z, 0.0, VERTEX.x) + vec3(1e-5, 0.0, 0.0));
	TANGENT = t;
	BINORMAL = normalize(cross(NORMAL, t));
}

// the print: 0..1 = how much of the pattern colour, w = extra (tone for camo etc.), out c = final colour
vec3 print_col(vec3 p, vec3 a, vec3 b) {
	vec3 q = p / pat_scale;
	if (pattern == 1) {   // woodland camo: three tones in soft blobs
		float n1 = fbm(q * 7.0), n2 = fbm(q * 7.0 + 19.1), n3 = fbm(q * 9.0 + 7.7);
		vec3 c = a;
		c = mix(c, b, smoothstep(0.52, 0.55, n1));
		c = mix(c, mix(a, b, 0.45) * 0.55, smoothstep(0.56, 0.59, n2));
		c = mix(c, a * 0.45, smoothstep(0.6, 0.63, n3));
		return c;
	} else if (pattern == 2) {   // digital camo: the same blobs, sampled on 1.2 cm pixels
		vec3 g = floor(q / 0.012) * 0.012;
		float n1 = fbm(g * 7.0), n2 = fbm(g * 7.0 + 19.1), n3 = fbm(g * 11.0 + 3.3);
		vec3 c = a;
		c = mix(c, b, step(0.53, n1));
		c = mix(c, mix(a, b, 0.5) * 0.6, step(0.57, n2));
		c = mix(c, a * 0.5, step(0.6, n3));
		return c;
	} else if (pattern == 3) {   // tiger: thin dark tapering stripes round the leg on the base colour
		float w = q.y * 16.0 + fbm(q * 5.0) * 5.0 + sin(atan(q.z, q.x) * 2.0) * 0.6;
		float s = abs(sin(w));
		float taper = fbm(q * 9.0 + 4.0);
		return mix(a, b, smoothstep(0.86 - 0.2 * taper, 0.9 - 0.2 * taper, s));
	} else if (pattern == 4) {   // zebra: bold even black / white bands, wavy
		float w = q.y * 11.0 + fbm(q * 3.5) * 6.0;
		return mix(a, b, smoothstep(-0.08, 0.08, sin(w)));
	} else if (pattern == 5) {   // leopard: rosettes (a ring of the pattern colour, a darker base middle)
		vec3 v = voronoi(q * 22.0 + fbm(q * 9.0) * 1.2);
		float ring = smoothstep(0.22, 0.28, v.x) * (1.0 - smoothstep(0.42, 0.5, v.x));
		vec3 c = mix(a, a * 0.7, 1.0 - smoothstep(0.2, 0.3, v.x));
		return mix(c, b, ring * step(0.25, v.z));
	} else if (pattern == 6) {   // checker: 4 cm squares round the tube
		float u = (atan(q.z, q.x) / 6.2831853 + 0.5) * max(2.0, floor(6.2831853 * v_r / 0.04 / pat_scale + 0.5));
		float k = mod(floor(u) + floor(q.y / 0.04), 2.0);
		return mix(a, b, k);
	} else if (pattern == 7) {   // tie-dye: spirals of the rainbow over the two colours
		float t = fbm(q * 3.0) * 2.5 + q.y * 5.0 + atan(q.z, q.x) * 0.35;
		vec3 rb = 0.5 + 0.5 * cos(6.2831853 * (t + vec3(0.0, 0.33, 0.67)));
		return mix(mix(a, b, 0.5 + 0.5 * sin(t * 6.2831853 * 0.5)), rb, 0.55);
	} else if (pattern == 8) {   // flames: long streaky tongues (noise stretched along the leg), a hot core
		vec3 s = vec3(q.x * 9.0, q.y * 2.2, q.z * 9.0);
		float n = fbm(s + fbm(s * 1.7 + 3.0) * 1.4);
		float f = smoothstep(0.56, 0.59, n);
		float core = smoothstep(0.64, 0.74, n);
		vec3 hot = mix(b, mix(b, vec3(1.0, 0.85, 0.3), 0.75), core);
		return mix(a, hot, f);
	} else if (pattern == 9) {   // lightning: bright jagged cracks (ridges of turbulent noise)
		float n = abs(fbm(q * 6.0) * 2.0 - 1.0);
		float n2 = abs(fbm(q * 13.0 + 5.0) * 2.0 - 1.0);
		float bolt = 1.0 - smoothstep(0.0, 0.035, n) + (1.0 - smoothstep(0.0, 0.02, n2)) * 0.6;
		return mix(a, b, clamp(bolt, 0.0, 1.0));
	}
	return a;
}

void fragment() {
	// fabric wrapped round the tube: a whole number of tiles round so it has no seam
	float ang = atan(v_p.z, v_p.x) / 6.2831853 + 0.5;
	float nround = max(1.0, floor(6.2831853 * v_r / tile + 0.5));
	vec2 uv = vec2(ang * nround, v_p.y / tile);
	vec3 a = base_col.rgb;
	vec3 b = pat_col.rgb;
	vec3 c = print_col(v_p, a, b);
	// the grey scan is normalised to a mean of 0.88: its light / dark around that, scaled by grain
	float g = mix(1.0, clamp(1.0 + (texture(fab_grey, uv).r / 0.88 - 1.0) * grain, 0.25, 1.6), fabric);
	ALBEDO = c * g;
	ROUGHNESS = clamp(rough_base * mix(1.0, texture(fab_rough, uv).r / 0.75, fabric), 0.0, 1.0);
	AO = mix(1.0, texture(fab_ao, uv).r, fabric);
	AO_LIGHT_AFFECT = 0.25;
	NORMAL_MAP = mix(vec3(0.5, 0.5, 1.0), texture(fab_normal, uv).rgb, fabric);
	NORMAL_MAP_DEPTH = normal_k;
	SPECULAR = 0.3;
}
