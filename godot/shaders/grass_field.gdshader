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
uniform float height_scale = 0.8;   // 2026-11-24: grass a little shorter overall (was 1.0)
uniform vec2 ring_centre;         // where the rings are centred: ahead of a high camera, at a low one
// trampled trail (GrassField.trample): r = time pressed, g = direction pressed (rad), b = how hard
uniform sampler2D trample : filter_nearest, repeat_disable;
uniform vec2 trample_origin = vec2(1.0e7);
uniform float trample_span = 48.0;
uniform float trample_now = 0.0;
uniform float trample_hold = 2.5;  // s fully flat
uniform float trample_back = 28.0; // s until it stands again

varying vec3 v_world;
varying vec3 v_col;
varying vec3 v_n;
varying float v_t;
varying float v_gust;
varying float v_flat;
varying vec3 v_side;    // the blade's width axis (world): the fragment rounds the normal across it
varying float v_u;      // -1 .. 1 across the blade
varying float v_round;  // how much rounding (near blades close up; gone with distance: no far shimmer)

// (2026-11-24, grass research: Ghost of Tsushima GDC 2021, 2Retr0 GodotGrass, AMD mesh-shader grass) clumps, rounded
// normals, root self-shadow, edge-on blades turned to the camera, wrapped diffuse. `BMX_GRASS_OLD` = before (grass_field.gd)
uniform float look_v2 = 1.0;
const float CLUMP = 1.15;   // m: clump cell size (a tuft every ~1 m)

vec2 win_uv(vec2 xz) { return ((xz - win_origin) / texel + 0.5) / win_size; }

vec4 g_hash4(vec2 p) {
	vec4 p4 = fract(vec4(p.xyxy) * vec4(0.1031, 0.1030, 0.0973, 0.1099));
	p4 += dot(p4, p4.wzxy + 33.33);
	return fract((p4.xxyz + p4.yzzw) * p4.zywx);
}
// the ground's own off-trail colour patchiness (ground.gdshader `mac`, same noise, same world scale): the blades take the
// identical factor so grass and the floor under it are one colour field (2026-11-25, user: "uniform grass leaves with our new
// grass colour"). Keep the two in step.
float gm_hash(vec3 p) { p = fract(p * 0.1031); p += dot(p, p.zyx + 31.32); return fract((p.x + p.y) * p.z); }
float gm_noise3(vec3 p) {
	vec3 i = floor(p), f = fract(p), u = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(gm_hash(i), gm_hash(i + vec3(1, 0, 0)), u.x), mix(gm_hash(i + vec3(0, 1, 0)), gm_hash(i + vec3(1, 1, 0)), u.x), u.y),
	           mix(mix(gm_hash(i + vec3(0, 0, 1)), gm_hash(i + vec3(1, 0, 1)), u.x), mix(gm_hash(i + vec3(0, 1, 1)), gm_hash(i + vec3(1, 1, 1)), u.x), u.y), u.z);
}
uniform float ground_macro = 0.26;
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
	// clumps (GoT): the nearest of the 3 x 3 jittered clump centres round the root. Blades of one clump share a height,
	// a shade and lean out from its middle: the field reads as tufts, not noise
	vec2 ci = floor(root / CLUMP);
	float cbest = 1.0e9; vec2 cc = root; vec4 ch = vec4(0.5);
	for (int cy = -1; cy <= 1; cy++) {
		for (int cx = -1; cx <= 1; cx++) {
			vec2 id = ci + vec2(float(cx), float(cy));
			vec4 hh = g_hash4(id * 1.71 + 203.0);
			vec2 pt = (id + 0.15 + 0.7 * hh.xy) * CLUMP;
			float d2 = dot(pt - root, pt - root);
			if (d2 < cbest) { cbest = d2; cc = pt; ch = hh; }
		}
	}
	float cl_d = sqrt(cbest) / CLUMP;   // 0 at the clump's middle .. ~0.75 at its edge (cl_d)
	float clump_k = look_v2;
	// patches: thick meadow here, thin there; the density map says whether grass grows at all
	float patch = g_noise(root * 0.11) * 0.65 + g_noise(root * 0.43 + 7.0) * 0.35;
	float den = clamp(gc.a * 1.6, 0.0, 1.0) * inside * smoothstep(0.05, 0.4, patch * 0.6 + gc.a * 0.6);
	float grow = step(h1.z, den * 1.25);
	// distance fades (horizontal, from the camera); ragged by the blade's own hash
	float dist = length(root - ring_centre);
	float cdist = length(root - CAMERA_POSITION_WORLD.xz);
	float jit = (h2.w - 0.5) * 3.0;
	float fade = near ? 1.0 - smoothstep(near_r - 11.0, near_r - 1.0, dist + jit)
	                  : smoothstep(near_r - 11.0, near_r - 1.0, dist + jit) * (1.0 - smoothstep(mid_r - 16.0, mid_r - 1.0, dist + jit));
	float hgt = (0.2 + 0.36 * h1.w) * (0.6 + 0.6 * patch) * (0.6 + 0.4 * gc.a) * height_scale;
	// height variation: broad short / long swathes (~20 m) and a few stalks standing out above the rest
	hgt *= mix(0.86, 1.18, g_noise(root * 0.05 + 13.0));
	hgt *= h2.z > 0.96 ? 1.3 : 1.0;
	// a clump: its own height (0.75 .. 1.25), tallest in its middle
	hgt *= mix(1.0, mix(0.75, 1.25, ch.z) * (1.08 - 0.3 * smoothstep(0.15, 0.7, cl_d)), clump_k);
	hgt *= grow * fade;
	if (hgt <= 0.0) {   // no blade here (doesn't grow / faded out): collapse it, skip the wind, hashes and normal reads
		VERTEX = vec3(0.0, -1.0e5, 0.0);
		v_world = VERTEX; v_col = vec3(0.0); v_n = vec3(0.0, 1.0, 0.0); v_t = 0.0; v_gust = 0.0; v_flat = 0.0;
		v_side = vec3(1.0, 0.0, 0.0); v_u = 0.0; v_round = 0.0;
	} else {   // (Godot shaders don't allow return in vertex())
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
	else if (look_v2 > 0.5) {
		// seen edge-on a blade is a sliver (GoT / 2Retr0 "view-space thickening"): the closer to edge-on, the more it
		// turns to face the camera (up to 60 % of the way)
		vec2 face = vec2(-to_cam.y, to_cam.x);
		float edge = 1.0 - abs(dot(vec2(-dirv.y, dirv.x), to_cam));
		dirv = normalize(mix(dirv, face * sign(dot(dirv, face) + 1e-4), pow(edge, 4.0) * 0.6));
	}
	vec3 side = vec3(dirv.x, 0.0, dirv.y);
	vec3 fwd = vec3(-dirv.y, 0.0, dirv.x);
	// shape: tapers to the tip, bows over towards its lean
	float t = UV.y;
	float taper = near ? (1.0 - t * 0.8) : 1.0 - t;
	float lean = (0.25 + 0.45 * h2.z) * (h2.y > 0.5 ? 1.0 : -1.0);
	vec3 lean_dir = fwd * lean;
	if (near && clump_k > 0.0) {   // a tuft opens outwards: lean away from the clump's middle (plus a little of its own)
		vec2 away = root - cc;
		float al = length(away);
		if (al > 1e-3) lean_dir = mix(lean_dir, vec3(away.x / al, 0.0, away.y / al) * abs(lean) * (0.6 + 0.8 * cl_d), 0.65 * clump_k);
	}
	vec3 base = vec3(root.x, gy - 0.04, root.y);
	// trampled: laid over along the way it was pressed (a little fanned per blade), springing back slowly;
	// the blades stand up again one by one (own hash), stiff ones first
	float flat_k = 0.0;
	vec2 tdir = vec2(0.0);
	vec2 tuv = (root - trample_origin) / trample_span;
	if (tuv.x > 0.0 && tuv.x < 1.0 && tuv.y > 0.0 && tuv.y < 1.0) {
		vec4 tr = textureLod(trample, tuv, 0.0);
		float age = trample_now - tr.r;
		if (age >= 0.0) {
			float back = trample_back * (0.6 + 0.8 * h2.z);
			flat_k = tr.b * (1.0 - smoothstep(trample_hold, back, age));
			float ta = tr.g + (h1.y - 0.5) * 0.9;
			tdir = vec2(cos(ta), sin(ta));
		}
	}
	float up_k = 1.0 - 0.88 * flat_k;
	vec3 p = base + side * UV.x * wid * 0.5 * taper * (1.0 + 0.3 * flat_k)
		+ vec3(0.0, t * hgt * up_k, 0.0) + lean_dir * t * t * hgt * (1.0 - flat_k);
	p.xz += tdir * flat_k * hgt * (0.35 * t + 0.6 * t * t);
	p += wind_bend(base, t * hgt * up_k, 1.0, 1.0 - flat_k * 0.8);
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
	float gmac = gm_noise3(vec3(root * 0.04, 9.3)) * 0.6 + gm_noise3(vec3(root * 0.2, 2.2)) * 0.4;
	vec3 c = gc.rgb * (1.0 + (gmac - 0.5) * ground_macro) * (0.82 + 0.36 * h2.x);
	c *= mix(vec3(1.0), mix(vec3(0.9, 0.97, 0.88), vec3(1.07, 1.04, 0.93), ch.w), clump_k);   // each clump its own shade
	c = mix(c, c * vec3(0.86, 1.05, 0.82), smoothstep(0.55, 0.85, cp) * 0.5);
	c = mix(c, c * vec3(1.08, 1.0, 0.84), smoothstep(0.45, 0.15, cp) * 0.4);
	// a little richer than the land colour (it reads olive once the low sun warms it)
	float lum = dot(c, vec3(0.3, 0.55, 0.15));
	c = max(mix(vec3(lum), c, 1.18), vec3(0.0));
	vec3 tip = c * vec3(1.1, 1.16, 0.9);
	float far_k = smoothstep(near_r, mid_r, dist);
	// root = the floor under the grass (ground.gdshader shades it the same: x (0.66, 0.76, 0.56)), so blades
	// grow out of it without an edge; far away blades and floor both go back to the plain land colour
	vec3 root_c = c * mix(vec3(0.66, 0.76, 0.56) * 0.95, vec3(0.95), far_k);
	v_col = mix(root_c,mix(tip, c, far_k * 0.7), smoothstep(0.0, 1.0, t));
	// laid-down blades show their pale, shiny side: the trail reads as a lighter, silvery stripe
	vec3 pale = mix(c, vec3(dot(c, vec3(0.3, 0.55, 0.15))), 0.3) * vec3(1.5, 1.45, 1.15);
	v_col = mix(v_col, pale, flat_k * 0.9);
	// self-shadow down in the grass (AMD / 2Retr0: albedo x mix(dark, 1, h^1.5)): depth close up, faded out with
	// distance so the far field doesn't go dark; laid-down blades are in the open
	float ss = mix(0.58, 1.0, pow(t, 1.5));
	v_col *= mix(1.0, ss, look_v2 * (1.0 - smoothstep(8.0, near_r + 4.0, dist)) * (1.0 - flat_k));
	v_side = side; v_u = UV.x;
	v_round = near ? look_v2 * (1.0 - smoothstep(6.0, near_r, dist)) : 0.0;
	v_flat = flat_k;
	// wind waves: a gust bends the blades over and their paler undersides catch the light, so the gust
	// fronts roll across the field as lighter bands (the wind already moves them: wind_gust in atmos)
	float gust = wind_gust(root);
	v_col *= 1.0 + gust * vec3(0.32, 0.3, 0.18) * smoothstep(0.1, 0.9, t);
	v_gust = gust;	v_t = t;
	VERTEX = p;
	v_world = p;
	}
}

void fragment() {
	ALBEDO = v_col;
	// rounded across the width (GoT): the normal tilts out towards each edge, so a flat blade shades like a curved one
	vec3 wn = normalize(v_n + v_side * v_u * 0.6 * v_round);
	NORMAL = normalize((VIEW_MATRIX * vec4(wn, 0.0)).xyz);
	ROUGHNESS = 0.72 - 0.2 * v_gust * v_t - 0.3 * v_flat;   // gust-bent / laid-down blades: a soft sheen
	AO = mix(mix(0.72, 1.0, v_t), 1.0, v_flat);
	SPECULAR = 0.22;
	AO_LIGHT_AFFECT = 0.4;
}

void light() {
	vec3 lc = atmos_light_col(ATTENUATION * LIGHT_COLOR, LIGHT_IS_DIRECTIONAL, v_world);   // cloud shade once
	// wrapped diffuse (2Retr0: light wraps round a thin blade, no flat black backs); the old one with look_v2 = 0
	float nl = dot(NORMAL, LIGHT);
	float dif = mix(clamp(nl, 0.0, 1.0) + clamp(-nl, 0.0, 1.0) * 0.2, clamp((nl + 0.35) / 1.35, 0.0, 1.0) + clamp(-nl, 0.0, 1.0) * 0.12, look_v2);
	DIFFUSE_LIGHT += dif * lc;
	// backlit glow: sun behind the blade, camera in front -> the thin tip lights up in its own colour (low sun = strong)
	if (LIGHT_IS_DIRECTIONAL) {
		float facing = clamp(dot(-VIEW, LIGHT), 0.0, 1.0);          // looking towards the light
		float glow = pow(facing, 3.0) * smoothstep(0.25, 1.0, v_t); // tips only
		DIFFUSE_LIGHT += glow * lc * v_col * vec3(1.5, 1.35, 0.8) * 2.2;
	}
}
