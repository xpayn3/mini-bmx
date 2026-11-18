// Torn race tape ribbons (tape.js STRIP_MAT): same foil look as the intact tape (tape.gdshader),
// vertex colours are linear like the intact tape's.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_burley, specular_schlick_ggx;

void fragment() {
	ALBEDO = COLOR.rgb;
	ROUGHNESS = 0.42;
	METALLIC = 0.05;
}
