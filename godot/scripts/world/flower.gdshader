// Wildflowers, grass clumps, ferns, mushrooms: instance colour only on the tinted parts (UV.x = tint),
// and a gentle breeze bends the heads (base planted), each plant on its own phase.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform float u_time = 0.0;
uniform float roughness = 0.55;
varying vec3 v_col;

void vertex() {
	v_col = COLOR.rgb * mix(vec3(1.0), INSTANCE_CUSTOM.rgb, UV.x);
	float ph = MODEL_MATRIX[3].x * 0.9 + MODEL_MATRIX[3].z * 0.7;
	float bend = VERTEX.y * VERTEX.y * 9.0;
	VERTEX.x += (sin(u_time * 1.6 + ph) * 0.6 + sin(u_time * 2.7 + ph * 1.3) * 0.25) * 0.02 * bend;
	VERTEX.z += sin(u_time * 1.3 + ph * 0.8) * 0.015 * bend;
}

void fragment() {
	ALBEDO = v_col;
	ROUGHNESS = roughness;
	SPECULAR = 0.35;
}
