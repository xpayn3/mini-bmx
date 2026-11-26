// Rocks (2026-11-26, world/rock_gen.gd shapes): a photographed rock scan (assets/textures/rock, Poly Haven CC0) mapped
// triplanar in world metres (rocks never move, so the texture stays put and is the same real size on every rock), its
// normal map blended "whiteout" style per axis; the mesh's vertex colour is baked cavity AO.
// Moss (forest / wet / green land): a second scan (mossy_rock) on the faces that look up, in patches, by the instance's
// custom data alpha (TerrainChunkBuilder: from the biome); rgb = a small per-rock brightness / tint.
// Same distance fade + LOD swap as the other decorations (deco_fade.gdshaderinc: mode 4 LOD0, 3 LOD1 + shadows, 2 pebbles).
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx, world_vertex_coords;
#include "res://shaders/atmos.gdshaderinc"
#include "res://shaders/deco_fade.gdshaderinc"
instance uniform float fade_mode = 0.0;

uniform sampler2D rock_col : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_nrm : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_rgh : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D moss_col : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D moss_nrm : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D moss_rgh : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec3 tint = vec3(1.0);
uniform float saturation = 1.0;   // the scan's own colour kept (granite: a brown rock face greyed out)
uniform vec3 moss_tint = vec3(0.8, 1.08, 0.55);
uniform float tile = 1.6;         // m of rock per texture tile (the scans are 3 m; a bit tighter reads better on boulders)
uniform float relief = 1.0;
uniform float moss_tile = 1.1;
uniform float moss_k = 1.0;       // x the instance's moss amount
uniform float rough_k = 1.0;
uniform bool use_instance = true;
uniform float specular = 0.35;

varying vec3 v_col;
varying vec3 v_wn;
varying vec3 v_world;
varying flat vec3 v_origin;
varying flat float v_moss;
global uniform vec4 cam_see;
global uniform vec4 cam_eye;

void vertex() {
	vec4 ic = use_instance ? INSTANCE_CUSTOM : vec4(1.0, 1.0, 1.0, 0.0);
	v_col = COLOR.rgb * ic.rgb * tint;
	v_moss = clamp(ic.a * moss_k, 0.0, 1.0);
	v_origin = MODEL_MATRIX[3].xyz;
	v_wn = normalize(NORMAL);
	if (deco_fold(v_origin, fade_mode, PROJECTION_MATRIX[3][3] > 0.5)) VERTEX = v_origin;
	v_world = VERTEX;
}

float rk_hash(vec3 p) {
	p = fract(p * 0.3183099 + vec3(0.71, 0.113, 0.419));
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}
float rk_noise(vec3 x) {
	vec3 i = floor(x), f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(rk_hash(i), rk_hash(i + vec3(1, 0, 0)), f.x), mix(rk_hash(i + vec3(0, 1, 0)), rk_hash(i + vec3(1, 1, 0)), f.x), f.y),
	           mix(mix(rk_hash(i + vec3(0, 0, 1)), rk_hash(i + vec3(1, 0, 1)), f.x), mix(rk_hash(i + vec3(0, 1, 1)), rk_hash(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

// triplanar: colour, roughness and the world normal of one scan
void tri(sampler2D col, sampler2D nrm, sampler2D rgh, vec3 p, vec3 n, vec3 w, out vec3 c, out float r, out vec3 wn) {
	vec2 ux = p.zy, uy = p.xz, uz = p.xy;
	c = texture(col, ux).rgb * w.x + texture(col, uy).rgb * w.y + texture(col, uz).rgb * w.z;
	r = texture(rgh, ux).r * w.x + texture(rgh, uy).r * w.y + texture(rgh, uz).r * w.z;
	vec3 tx = texture(nrm, ux).rgb * 2.0 - 1.0;
	vec3 ty = texture(nrm, uy).rgb * 2.0 - 1.0;
	vec3 tz = texture(nrm, uz).rgb * 2.0 - 1.0;
	tx.xy *= relief; ty.xy *= relief; tz.xy *= relief;
	// whiteout blend (Golus, "Normal Mapping for a Triplanar Shader")
	tx = vec3(tx.xy + n.zy, abs(tx.z) * n.x);
	ty = vec3(ty.xy + n.xz, abs(ty.z) * n.y);
	tz = vec3(tz.xy + n.xy, abs(tz.z) * n.z);
	wn = normalize(tx.zyx * w.x + ty.xzy * w.y + tz.xyz * w.z);
}

void fragment() {
	if (deco_cut_pair(v_origin, fade_mode, FRAGCOORD.xy, PROJECTION_MATRIX[3][3] > 0.5)) discard;
	if (cam_see.w > 0.0 && distance(CAMERA_POSITION_WORLD, cam_eye.xyz) < 0.5) {
		float cut = 1.0 - smoothstep(1.5, 3.0, distance(v_world, cam_eye.xyz));
		float n = fract(52.9829189 * fract(dot(FRAGCOORD.xy, vec2(0.06711056, 0.00583715))));
		if (n < cut * 0.95) discard;
	}
	vec3 n = normalize(v_wn);
	vec3 w = pow(abs(n), vec3(4.0));
	w /= (w.x + w.y + w.z);
	vec3 c; float r; vec3 wn;
	// each rock its own offset into the scan (no two boulders show the same patch)
	vec3 off = vec3(rk_hash(floor(v_origin * 3.1)), rk_hash(floor(v_origin * 2.7) + 5.0), rk_hash(floor(v_origin * 1.9) + 9.0)) * 7.0;
	tri(rock_col, rock_nrm, rock_rgh, v_world / tile + off, n, w, c, r, wn);
	c = mix(vec3(dot(c, vec3(0.3, 0.59, 0.11))), c, saturation);
	if (v_moss > 0.001) {
		vec3 mc; float mr; vec3 mn;
		tri(moss_col, moss_nrm, moss_rgh, v_world / moss_tile + off.zxy, n, w, mc, mr, mn);
		// moss on what looks up (and a little down the sides), in patches, with a crisp edge from the moss scan's own detail
		float up = clamp(wn.y * 0.8 + n.y * 0.4, -1.0, 1.0);
		float patchy = rk_noise(v_world * 1.7 + off) * 0.6 + rk_noise(v_world * 4.3) * 0.4;
		float lum = dot(mc, vec3(0.3, 0.6, 0.1));
		mc *= moss_tint;
		float s = up * 0.6 + patchy * 0.55 + lum * 0.6;
		// 0.15 (green hills): a few patches on the tops, 0.5: the tops, 1 (forest floor): most of the rock
		float k = smoothstep(1.6 - v_moss * 1.2, 1.75 - v_moss * 1.2, s);
		c = mix(c, mc, k);
		r = mix(r, mr, k);
		wn = normalize(mix(wn, mn, k));
	}
	ALBEDO = c * v_col;
	ROUGHNESS = clamp(r * rough_k, 0.05, 1.0);
	SPECULAR = specular;
	NORMAL = normalize((VIEW_MATRIX * vec4(wn, 0.0)).xyz);
}

void light() {
	vec3 _lc = atmos_light_col(ATTENUATION * LIGHT_COLOR, LIGHT_IS_DIRECTIONAL, v_world);
	DIFFUSE_LIGHT += clamp(dot(NORMAL, LIGHT), 0.0, 1.0) * _lc;
	vec3 hv = normalize(VIEW + LIGHT);
	float sp = pow(clamp(dot(NORMAL, hv), 0.0, 1.0), mix(64.0, 4.0, ROUGHNESS)) * (1.0 - ROUGHNESS) * 0.5;
	SPECULAR_LIGHT += sp * _lc * clamp(dot(NORMAL, LIGHT), 0.0, 1.0);
}
