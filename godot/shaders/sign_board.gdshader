// The distance sign's plate (terrain_chunk_builder._dist_signs): the Figma "table sign" design printed on a thin
// board (assets/signs/distance_board.png: blue field + the DISTANCE strip; the km number is a Label3D on top).
// Same distance dissolve as the other streamed decorations.
shader_type spatial;
render_mode cull_back;
#include "res://shaders/deco_fade.gdshaderinc"
instance uniform float fade_mode = 0.0;
uniform sampler2D board_tex : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
varying flat vec3 v_origin;

void vertex() {
	v_origin = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
}

void fragment() {
	if (deco_cut(v_origin, fade_mode, FRAGCOORD.xy, PROJECTION_MATRIX[3][3] > 0.5)) discard;
	ALBEDO = texture(board_tex, UV).rgb;
	ROUGHNESS = 0.55;   // printed aluminium-composite sign: a little sheen
	SPECULAR = 0.4;
}
