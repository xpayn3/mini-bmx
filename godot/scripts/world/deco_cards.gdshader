// Leaf-card plants (bushes, card tree crowns: world/card_tree.gd): flat cards carrying a leaf-cluster texture with an alpha cut-out, normals bent
// toward a dome so the whole bush lights like one soft volume. Same fade / sway / glow as deco.gdshader.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_burley, specular_schlick_ggx, world_vertex_coords;
#include "res://shaders/atmos.gdshaderinc"
#include "res://shaders/deco_fade.gdshaderinc"
instance uniform float fade_mode = 0.0;

uniform sampler2D leaf_tex : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform vec3 albedo = vec3(1.0);
uniform float roughness = 0.8;
uniform float specular = 0.1;
uniform float sway = 0.035;
uniform float backlight = 0.35;
uniform float scatter = 0.9;
uniform float cutoff = 0.5;
// card trees: light the crown as one volume from both sides (Godot flips NORMAL on back faces of a two-sided card,
// which turned the dome's normals inside out on every card seen from behind)
uniform bool volume_normals = false;
uniform float flutter = 0.012;
varying vec3 v_col;
varying flat vec3 v_origin;
varying vec3 v_world;
global uniform vec4 cam_see;
global uniform vec4 cam_eye;

void vertex() {
	v_col = albedo * COLOR.rgb * INSTANCE_CUSTOM.rgb;
	v_origin = MODEL_MATRIX[3].xyz;
	vec3 base = MODEL_MATRIX[3].xyz;
	float h = max(VERTEX.y - base.y, 0.0);
	vec3 o = wind_bend(base, 1.0, 1.0, 0.0);
	// leaves flutter a little on top of the bush's sway
	float fl = sin(atm_wind.z * 3.1 + VERTEX.x * 5.0 + VERTEX.z * 4.0) * flutter * h;
	VERTEX.xz += o.xz * h * sway + vec2(fl);
	if (deco_fold(v_origin, fade_mode, PROJECTION_MATRIX[3][3] > 0.5)) VERTEX = v_origin;   // (card tree out of its band)
	v_world = VERTEX;
}

void fragment() {
	if (deco_cut_pair(v_origin, fade_mode, FRAGCOORD.xy, PROJECTION_MATRIX[3][3] > 0.5)) discard;
	if (volume_normals && !FRONT_FACING) NORMAL = -NORMAL;
	vec4 t = texture(leaf_tex, UV);
	ALPHA = t.a;
	ALPHA_SCISSOR_THRESHOLD = cutoff;
	if (cam_see.w > 0.0 && distance(CAMERA_POSITION_WORLD, cam_eye.xyz) < 0.5) {
		float cut = 1.0 - smoothstep(1.5, 3.0, distance(v_world, cam_eye.xyz));
		float n = fract(52.9829189 * fract(dot(FRAGCOORD.xy, vec2(0.06711056, 0.00583715))));
		if (n < cut * 0.95) discard;
	}
	ALBEDO = v_col * t.rgb;
	ROUGHNESS = roughness;
	SPECULAR = specular;
}

void light() {
	vec3 _lc = atmos_light_col(ATTENUATION * LIGHT_COLOR, LIGHT_IS_DIRECTIONAL, v_world);
	// two-sided cards: light the side that faces the sun, wrapped a little so the dome has no hard terminator
	float nl = dot(NORMAL, LIGHT);
	DIFFUSE_LIGHT += (clamp(nl * 0.8 + 0.2, 0.0, 1.0) + clamp(-nl, 0.0, 1.0) * backlight) * _lc;
	if (scatter > 0.0 && LIGHT_IS_DIRECTIONAL) {
		float bl = clamp(dot(-VIEW, LIGHT), 0.0, 1.0);
		bl = bl * bl * bl;
		float sun_y = (INV_VIEW_MATRIX * vec4(LIGHT, 0.0)).y;
		float low = mix(0.25, 1.0, 1.0 - smoothstep(0.15, 0.75, sun_y));
		vec3 tint = ALBEDO / max(max(ALBEDO.r, max(ALBEDO.g, ALBEDO.b)), 0.04);
		DIFFUSE_LIGHT += bl * low * (0.55 + 0.45 * clamp(-nl + 0.4, 0.0, 1.0)) * scatter * tint * _lc;
	}
}
