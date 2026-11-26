// Leaf-card plants (bushes, card tree crowns: world/card_tree.gd): flat cards carrying a leaf-cluster texture with an alpha cut-out, normals bent
// toward a dome so the whole bush lights like one soft volume. Same fade / sway / glow as deco.gdshader.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_burley, specular_schlick_ggx, world_vertex_coords;
#include "res://shaders/atmos.gdshaderinc"
#include "res://shaders/deco_fade.gdshaderinc"
instance uniform float fade_mode = 0.0;

uniform sampler2D leaf_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
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
// a photo atlas' normal (RGB, OpenGL) + translucency (A) map in the leaf texture's layout (the beech card): the leaves'
// own veins / curl light up, and thin bright parts glow more against the sun
uniform bool use_nrm = false;
uniform sampler2D nrm_tex : filter_linear_mipmap_anisotropic, repeat_enable;
uniform float nrm_depth = 0.9;
varying float v_trans;
// > 0: the leaf picture covers this many metres of foliage, and each card repeats it by its real size (COLOR.a = the
// card's size in mesh units x the instance's scale), so leaves keep their real size on crowns of any size (leafy trees)
uniform float tile_m = 0.0;
// > 0: the cards were made for a tree this many metres tall (GrownTree's grown size); each card shrinks / grows about its
// anchor (CUSTOM0.xyz, mesh space) so it keeps that real size on a tree scaled to any height (needles / leaves stay real)
uniform float card_ref = 0.0;
varying flat float v_tile;
varying vec3 v_col;
varying flat vec3 v_origin;
varying vec3 v_world;
global uniform vec4 cam_see;
global uniform vec4 cam_eye;

void vertex() {
	v_col = albedo * COLOR.rgb * INSTANCE_CUSTOM.rgb;
	float sx = length(MODEL_MATRIX[0].xyz);
	if (card_ref > 0.0) {
		vec3 aw = (MODEL_MATRIX * vec4(CUSTOM0.xyz, 1.0)).xyz;
		VERTEX = aw + (VERTEX - aw) * (card_ref / max(sx, 0.001));
	}
	v_tile = tile_m > 0.0 ? max(1.0, round(COLOR.a * (card_ref > 0.0 ? card_ref : sx) / tile_m)) : 1.0;
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
	vec2 uv = UV * v_tile;
	vec4 t = texture(leaf_tex, uv);
	if (tile_m > 0.0) {
		// a repeated patch fills the whole card: give it a ragged oval outline (the patch's own leaves, read coarser)
		vec2 e = (UV - 0.5) * 2.0;
		float rag = texture(leaf_tex, UV * 0.53 + 0.31).a * 0.6 + texture(leaf_tex, UV * 1.37 + 0.13).a * 0.4;
		if (length(e) > 0.62 + 0.55 * (rag - 0.5)) discard;
	}
	ALPHA = t.a;
	ALPHA_SCISSOR_THRESHOLD = cutoff;
	if (cam_see.w > 0.0 && distance(CAMERA_POSITION_WORLD, cam_eye.xyz) < 0.5) {
		float cut = 1.0 - smoothstep(1.5, 3.0, distance(v_world, cam_eye.xyz));
		float n = fract(52.9829189 * fract(dot(FRAGCOORD.xy, vec2(0.06711056, 0.00583715))));
		if (n < cut * 0.95) discard;
	}
	ALBEDO = v_col * t.rgb;
	v_trans = 0.5;
	if (use_nrm) {
		vec4 nt = texture(nrm_tex, uv);
		NORMAL_MAP = nt.rgb;
		NORMAL_MAP_DEPTH = nrm_depth;
		v_trans = nt.a;
	}
	ROUGHNESS = roughness;
	SPECULAR = specular;
}

void light() {
	vec3 _lc = atmos_light_col(ATTENUATION * LIGHT_COLOR, LIGHT_IS_DIRECTIONAL, v_world);
	// two-sided cards: light the side that faces the sun, wrapped a little so the dome has no hard terminator
	float nl = dot(NORMAL, LIGHT);
	float tk = mix(0.4, 1.6, v_trans);   // (no map: 1)
	DIFFUSE_LIGHT += (clamp(nl * 0.8 + 0.2, 0.0, 1.0) + clamp(-nl, 0.0, 1.0) * backlight * tk) * _lc;
	if (scatter > 0.0 && LIGHT_IS_DIRECTIONAL) {
		float bl = clamp(dot(-VIEW, LIGHT), 0.0, 1.0);
		bl = bl * bl * bl;
		float sun_y = (INV_VIEW_MATRIX * vec4(LIGHT, 0.0)).y;
		float low = mix(0.25, 1.0, 1.0 - smoothstep(0.15, 0.75, sun_y));
		vec3 tint = ALBEDO / max(max(ALBEDO.r, max(ALBEDO.g, ALBEDO.b)), 0.04);
		DIFFUSE_LIGHT += bl * low * (0.55 + 0.45 * clamp(-nl + 0.4, 0.0, 1.0)) * scatter * tk * tint * _lc;
	}
}
