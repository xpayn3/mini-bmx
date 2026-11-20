// The grass carpet (scripts/world/grass_field.gd). Every blade is built here from its root on a fixed lattice:
// the window textures give the ground height, the land colour (the blade's tint, so its root melts into the
// ground) and how much grass grows there; a hash of the lattice cell gives its size, lean, curve and shade.
// Near ring: 3-part curved blades; mid ring: one wide triangle facing the camera. They cross-fade by
// distance and the mid ring shrinks into the ground at its edge. Wind + the bike parting it: shaders/atmos.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_lambert, specular_schlick_ggx, world_vertex_coords;
#include "res://shaders/atmos.gdshaderinc"

uniform sampler2D grass_col : source_color, filter_linear, repeat_disable;   // rgb land colour (sRGB bytes, baked AO), a density
uniform sampler2D grass_h : filter_linear, repeat_disable;     // ground height (m)
uniform vec2 win_origin;          // world xz of texel (0, 0)
uniform float texel = 0.5;
uniform float win_size = 481.0;
uniform float near_r = 16.0;
uniform float mid_r = 52.0;
uniform float near_spacing = 0.19;
uniform float mid_spacing = 0.48;
uniform float height_scale = 1.0;
uniform vec2 ring_centre;         // where the rings are centred: ahead of a high camera, at a low one

varying vec3 v_world;
varying vec3 v_col;
varying vec3 v_n;
varying float v_t;

vec2 win_uv(vec2 xz) { return ((xz - win_origin) / texel + 0.5) / win_size; }

vec4 g_hash4(vec2 p) {
	vec4 p4 = fract(vec4(p.xyxy) * vec4(0.1031, 0.1030, 0.0973, 0.1099));
	p4 += dot(p4, p4.wzxy + 33.33);
	return fract((p4.xxyz + p4.yzzw) * p4.zywx);
}
float g_noise(vec2 p) {
	vec2 i = floor(p), f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(g_hash4(i).x, g_hash4(i + vec2(1.0, 0.0)).x, f.x),
	           mix(g_hash4(i + vec2(0.0, 1.0)).x, g_hash4(i + vec2(1.0, 1.0)).x, f.x), f.y);
}

void vertex() {
	bool near = INSTANCE_CUSTOM.x > 0.5;
	float sp = near ? near_spacing : mid_spacing;
	vec2 root0 = VERTEX.xz;                                   // world (tile origin + cell centre)
	vec2 cell = floor(root0 / sp);                            // whole numbers: the blade's identity
	vec4 h1 = g_hash4(cell + (near ? 0.0 : 517.0));
	vec4 h2 = g_hash4(cell * 1.37 + 91.0);
	vec2 root = (cell + 0.12 + 0.76 * h1.xy) * sp;            // jittered in its cell
	vec2 uvw = win_uv(root);
	vec4 gc = textureLod(grass_col, uvw, 0.0);
	float gy = textureLod(grass_h, uvw, 0.0).r;
	float inside = step(0.0, uvw.x) * step(uvw.x, 1.0) * step(0.0, uvw.y) * step(uvw.y, 1.0);
	// patches: thick meadow here, thin there; the density map says whether grass grows at all
	float patch = g_noise(root * 0.11) * 0.65 + g_noise(root * 0.43 + 7.0) * 0.35;
	float den = clamp(gc.a * 1.6, 0.0, 1.0) * inside * smoothstep(0.05, 0.4, patch * 0.6 + gc.a * 0.6);
	float grow = step(h1.z, den * 1.25);
	// distance fades (horizontal, from the camera); ragged by the blade's own hash
	float dist = length(root - ring_centre);
	float cdist = length(root - CAMERA_POSITION_WORLD.xz);
	float jit = (h2.w - 0.5) * 3.0;
	float fade = near ? 1.0 - smoothstep(near_r - 6.0, near_r - 1.0, dist + jit)
	                  : smoothstep(near_r - 6.0, near_r - 1.0, dist + jit) * (1.0 - smoothstep(mid_r - 16.0, mid_r - 1.0, dist + jit));
	float hgt = (0.2 + 0.36 * h1.w) * (0.6 + 0.6 * patch) * (0.6 + 0.4 * gc.a) * height_scale;
	hgt *= grow * fade;
	float wid = near ? (0.03 + 0.025 * h2.x) : (0.09 + 0.05 * h2.x);
	wid *= mix(0.4, 1.0, fade);
	// seen from above a thin blade is a sliver: the steeper the view, the wider (side views stay fine)
	float down = clamp((CAMERA_POSITION_WORLD.y - gy) / max(length(vec3(cdist, CAMERA_POSITION_WORLD.y - gy, 0.0)), 0.1), 0.0, 1.0);
	wid *= 1.0 + 1.8 * smoothstep(0.35, 0.9, down);
	// the blade's plane: random yaw near, turned to the camera far (a lone triangle edge-on vanishes)
	float yaw = h1.z * 37.0 + h2.y * 6.28318;
	vec2 dirv = vec2(cos(yaw), sin(yaw));
	vec2 to_cam = normalize(CAMERA_POSITION_WORLD.xz - root + 1e-4);
	if (!near) dirv = vec2(-to_cam.y, to_cam.x);
	vec3 side = vec3(dirv.x, 0.0, dirv.y);
	vec3 fwd = vec3(-dirv.y, 0.0, dirv.x);
	// shape: tapers to the tip, bows over towards its lean
	float t = UV.y;
	float taper = near ? (1.0 - t * 0.8) : 1.0 - t;
	float lean = (0.25 + 0.45 * h2.z) * (h2.y > 0.5 ? 1.0 : -1.0);
	vec3 base = vec3(root.x, gy - 0.04, root.y);
	vec3 p = base + side * UV.x * wid * 0.5 * taper + vec3(0.0, t * hgt, 0.0) + fwd * lean * t * t * hgt;
	p += wind_bend(base, t * hgt, 1.0, 1.0);
	// ground normal from the height window: the blades shade like the ground they cover (soft, no stripes)
	float e = texel;
	float hx = textureLod(grass_h, win_uv(root + vec2(e, 0.0)), 0.0).r - textureLod(grass_h, win_uv(root - vec2(e, 0.0)), 0.0).r;
	float hz = textureLod(grass_h, win_uv(root + vec2(0.0, e)), 0.0).r - textureLod(grass_h, win_uv(root - vec2(0.0, e)), 0.0).r;
	vec3 gn = normalize(vec3(-hx, 2.0 * e, -hz));
	vec3 bn = normalize(fwd + vec3(0.0, 0.35, 0.0));
	if (dot(bn.xz, to_cam) < 0.0) bn.xz = -bn.xz;
	v_n = normalize(mix(gn, bn, near ? 0.5 : 0.3) + vec3(0.0, t * 0.2, 0.0));
	// colour: the ground's own at the root, lighter and yellower to the tip
	// colour patches across the field (greener / sun-dried) and each blade a little its own
	float cp = g_noise(root * 0.07 + 31.0);
	vec3 c = gc.rgb * (0.82 + 0.36 * h2.x);
	c = mix(c, c * vec3(0.78, 1.08, 0.7), smoothstep(0.55, 0.85, cp) * 0.8);
	c = mix(c, c * vec3(1.12, 1.0, 0.72), smoothstep(0.45, 0.15, cp) * 0.6);
	vec3 tip = c * vec3(1.1, 1.16, 0.88);
	float far_k = smoothstep(near_r, mid_r, dist);
	v_col = mix(c * mix(0.42, 0.75, far_k), mix(tip, c, far_k * 0.5), smoothstep(0.0, 1.0, t));
	v_t = t;
	VERTEX = p;
	v_world = p;
}

void fragment() {
	ALBEDO = v_col;
	NORMAL = normalize((VIEW_MATRIX * vec4(v_n, 0.0)).xyz);
	ROUGHNESS = 0.72;
	SPECULAR = 0.22;
	AO = mix(0.55, 1.0, v_t);
	AO_LIGHT_AFFECT = 0.4;
}

void light() {
	DIFFUSE_LIGHT += atmos_diffuse(NORMAL, LIGHT, ATTENUATION * LIGHT_COLOR, LIGHT_IS_DIRECTIONAL, v_world, 0.2);
}
