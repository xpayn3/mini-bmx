// The distance sign's stick: a square wooden post (unit box, scaled per sign) wearing the ambientCG Wood035 scan
// (assets/textures/wood_post, CC0) with the grain running up the post, in metres whatever the scale; darker and
// muddier where it comes out of the ground. Same distance dissolve as the other streamed decorations.
shader_type spatial;
render_mode cull_back;
#include "res://shaders/deco_fade.gdshaderinc"
instance uniform float fade_mode = 0.0;
uniform sampler2D wood_col : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D wood_nrm : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D wood_rgh : hint_roughness_gray, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float tile = 0.7;   // metres of post per texture repeat
varying flat vec3 v_origin;
varying vec3 v_m;    // position on the post in metres (post space)
varying vec3 v_n;    // the face's normal (post space)

void vertex() {
	v_origin = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	vec3 sc = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), length(MODEL_MATRIX[2].xyz));
	v_m = VERTEX * sc;
	v_n = NORMAL;
}

void fragment() {
	if (deco_cut(v_origin, fade_mode, FRAGCOORD.xy, PROJECTION_MATRIX[3][3] > 0.5)) discard;
	float seed = fract(sin(dot(floor(v_origin.xz * 3.0), vec2(12.9898, 78.233))) * 43758.5453);
	// side faces: grain (the scan's u) up the post, across = the face's own horizontal; top / bottom: end grain-ish
	vec3 an = abs(v_n);
	float across = an.x > 0.5 ? v_m.z : v_m.x;
	vec2 uv = an.y > 0.5 ? v_m.xz * 3.0 : vec2(v_m.y, across + (an.x > 0.5 ? 0.37 : 0.0));
	uv = uv / tile + vec2(seed * 7.0, seed * 3.0);
	vec3 col = texture(wood_col, uv).rgb;
	float rough = texture(wood_rgh, uv).r;
	vec3 nt = texture(wood_nrm, uv).rgb * 2.0 - 1.0;
	// soaked and muddy at the foot (the post's base is ~0.15 m in the ground, its middle at v_m.y = 0)
	float foot = 1.0 - smoothstep(0.0, 0.35, v_m.y + 0.5 * length(MODEL_MATRIX[1].xyz) - 0.15);
	col = mix(col, col * vec3(0.55, 0.48, 0.42), foot);
	rough = mix(rough, 0.95, foot * 0.6);
	// normal: the scan's GL normal on the face, axes taken from the post itself (the box has no tangents)
	vec3 ax_u = an.y > 0.5 ? vec3(1.0, 0.0, 0.0) : vec3(0.0, 1.0, 0.0);
	vec3 ax_v = an.y > 0.5 ? vec3(0.0, 0.0, 1.0) : (an.x > 0.5 ? vec3(0.0, 0.0, 1.0) : vec3(1.0, 0.0, 0.0));
	vec3 tu = normalize((VIEW_MATRIX * MODEL_MATRIX * vec4(ax_u, 0.0)).xyz);
	vec3 tv = normalize((VIEW_MATRIX * MODEL_MATRIX * vec4(ax_v, 0.0)).xyz);
	NORMAL = normalize(NORMAL + (tu * nt.x + tv * nt.y) * 0.8);
	ALBEDO = col;
	ROUGHNESS = rough;
}
