// Scanned rocks (2026-11-27, assets/rocks_scan: Poly Haven CC0 scans decimated by tools/make_scan_rocks.py): the scan's own UVs
// and textures (col: colour x AO, a = roughness; nrm), a per-rock tint from the instance's custom data (rgb), no moss.
// Same distance fade + LOD swap and camera-lens dither as rock.gdshader (deco_fade.gdshaderinc: mode 4 LOD0, 3 LOD1 + shadows).
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;
#include "res://shaders/atmos.gdshaderinc"
#include "res://shaders/deco_fade.gdshaderinc"
instance uniform float fade_mode = 0.0;

uniform sampler2D rock_col : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_nrm : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec3 tint = vec3(1.0);
uniform float saturation = 1.0;
uniform float mean_lum = 0.19;    // the colour map's own mean (linear): contrast is squeezed toward it
uniform float contrast = 0.6;     // (2026-11-27, user: "still dark"): the scans' deep cracks + baked shadow read as black patches
uniform float relief = 1.0;
uniform float specular = 0.3;
uniform bool use_instance = true;

varying vec3 v_col;
varying vec3 v_world;
varying flat vec3 v_origin;
global uniform vec4 cam_see;
global uniform vec4 cam_eye;

void vertex() {
	vec4 ic = use_instance ? INSTANCE_CUSTOM : vec4(1.0);
	v_col = ic.rgb * tint;
	v_origin = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	if (deco_fold(v_origin, fade_mode, PROJECTION_MATRIX[3][3] > 0.5)) VERTEX = vec3(0.0);
}

void fragment() {
	if (deco_cut_pair(v_origin, fade_mode, FRAGCOORD.xy, PROJECTION_MATRIX[3][3] > 0.5)) discard;
	if (cam_see.w > 0.0 && distance(CAMERA_POSITION_WORLD, cam_eye.xyz) < 0.5) {
		float cut = 1.0 - smoothstep(1.5, 3.0, distance(v_world, cam_eye.xyz));
		float n = fract(52.9829189 * fract(dot(FRAGCOORD.xy, vec2(0.06711056, 0.00583715))));
		if (n < cut * 0.95) discard;
	}
	vec4 c = texture(rock_col, UV);
	vec3 col = mix(vec3(dot(c.rgb, vec3(0.3, 0.59, 0.11))), c.rgb, saturation);
	col = max(vec3(mean_lum) + (col - vec3(mean_lum)) * contrast, vec3(0.0));
	ALBEDO = col * v_col;
	ROUGHNESS = clamp(c.a, 0.6, 1.0);   // (dry rock: rock_09's scan reads wet-shiny otherwise)
	SPECULAR = specular;
	NORMAL_MAP = texture(rock_nrm, UV).rgb;
	NORMAL_MAP_DEPTH = relief;
}

void light() {
	vec3 _lc = atmos_light_col(ATTENUATION * LIGHT_COLOR, LIGHT_IS_DIRECTIONAL, v_world);
	DIFFUSE_LIGHT += clamp(dot(NORMAL, LIGHT), 0.0, 1.0) * _lc;
	vec3 hv = normalize(VIEW + LIGHT);
	float sp = pow(clamp(dot(NORMAL, hv), 0.0, 1.0), mix(64.0, 4.0, ROUGHNESS)) * (1.0 - ROUGHNESS) * 0.5;
	SPECULAR_LIGHT += sp * _lc * clamp(dot(NORMAL, LIGHT), 0.0, 1.0);
}
