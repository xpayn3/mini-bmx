shader_type spatial;
render_mode cull_disabled;
// Fine hair strands: a few dozen simulated "guide" locks (positions in a small float texture, one row per lock),
// hundreds of thin strands interpolated between the nearest guides here on the GPU, each drawn as a camera-facing
// ribbon. The sheen is a Kajiya-Kay highlight (a band across the strand, two lobes) so it reads as shiny hair.
//
// per-vertex data (see hair.gd): VERTEX = (guide a, b, c indices), CUSTOM0 = (weights a, b, c, phase),
// CUSTOM1 = (root offset in head space xyz, width), UV = (side -1/+1, f 0..1 along the strand), COLOR = (shade, shade, shade, length fraction)

uniform sampler2D guides : filter_nearest, repeat_disable;   // (SEG+1) x G, rgb = world position
uniform mat4 head_xf;
uniform int seg = 11;
uniform vec3 hair_col : source_color = vec3(0.29, 0.19, 0.13);
uniform vec3 key_dir = vec3(-0.45, 0.8, 0.55);                // the studio key, in view space (menus, garage)
// in a ride game.gd sets the real key light: the sun / moon, as a direction TOWARD it in world space + its colour
uniform float key_world_on = 0.0;
uniform vec3 key_world = vec3(0.0, 1.0, 0.0);
uniform vec3 key_col = vec3(1.0, 0.97, 0.92);
uniform float sheen = 0.16;

varying vec3 vT;
varying float vF;
varying float vShade;

vec3 gpos(int g, float u) {
	float k = clamp(u, 0.0, float(seg));
	int k0 = int(floor(k));
	int k1 = min(k0 + 1, seg);
	float fr = k - float(k0);
	return mix(texelFetch(guides, ivec2(k0, g), 0).xyz, texelFetch(guides, ivec2(k1, g), 0).xyz, fr);
}

vec3 strand(int ga, int gb, int gc, vec3 w, float u, vec3 off_w, float f) {
	vec3 p = w.x * gpos(ga, u) + w.y * gpos(gb, u) + w.z * gpos(gc, u);
	return p + off_w * (1.0 - 0.7 * f);   // strands start at their own spot on the scalp and gather into the lock
}

void vertex() {
	int ga = int(VERTEX.x + 0.5);
	int gb = int(VERTEX.y + 0.5);
	int gc = int(VERTEX.z + 0.5);
	vec3 w = CUSTOM0.xyz;
	float phase = CUSTOM0.w;
	vec3 off_w = (head_xf * vec4(CUSTOM1.xyz, 0.0)).xyz;
	float width = CUSTOM1.w;
	float side_s = UV.x;
	float f = UV.y;
	float lf = COLOR.a;
	float u = f * lf * float(seg);
	float du = 0.6;
	vec3 p = strand(ga, gb, gc, w, u, off_w, f);
	vec3 p0 = strand(ga, gb, gc, w, u - du, off_w, f);
	vec3 p1 = strand(ga, gb, gc, w, u + du, off_w, f);
	vec3 t = normalize(p1 - p0 + vec3(0.0, -1e-5, 0.0));
	vec3 to_cam = normalize(CAMERA_POSITION_WORLD - p);
	vec3 side = cross(t, to_cam);
	side = length(side) > 1e-4 ? normalize(side) : vec3(1.0, 0.0, 0.0);
	p += side * sin(f * 5.5 - TIME * 0.7 + phase) * 0.0035 * smoothstep(0.05, 0.5, f);   // a slow wave travelling down the strand
	float wd = width * (1.0 - 0.75 * f * f) * 0.5;
	vec3 wp = p + side * side_s * wd;
	VERTEX = (inverse(MODEL_MATRIX) * vec4(wp, 1.0)).xyz;
	vT = normalize((VIEW_MATRIX * vec4(t, 0.0)).xyz);
	vF = f;
	vShade = COLOR.r;
	NORMAL = (inverse(MODEL_MATRIX) * vec4(to_cam, 0.0)).xyz;
}

void fragment() {
	vec3 T = normalize(vT);
	vec3 V = normalize(VIEW);
	vec3 L = key_world_on > 0.5 ? normalize((VIEW_MATRIX * vec4(key_world, 0.0)).xyz) : normalize(key_dir);
	float tl = dot(T, L);
	float diff = sqrt(max(0.0, 1.0 - tl * tl));
	vec3 H = normalize(L + V);
	float th = dot(T, H);
	float s = sqrt(max(0.0, 1.0 - th * th));
	// two lobes, the second one shifted and tinted by the hair colour (the way real hair glows)
	float th2 = dot(normalize(T + vec3(0.0, 0.0, 0.12)), H);
	float s2 = sqrt(max(0.0, 1.0 - th2 * th2));
	float root = mix(0.45, 1.0, smoothstep(0.0, 0.3, vF));   // darker at the scalp
	vec3 base = hair_col * vShade * root;
	ALBEDO = base * (0.3 + 0.5 * diff);
	// a soft, narrow sheen only: calm, not glittery
	EMISSION = key_col * pow(s, 140.0) * sheen + hair_col * (key_col / vec3(1.0, 0.97, 0.92)) * 1.2 * pow(s2, 30.0) * sheen * 0.5;   // (the default key = the old look)
	ROUGHNESS = 0.9;
	SPECULAR = 0.0;
	METALLIC = 0.0;
}
