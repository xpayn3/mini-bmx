// Decorations (trees, rocks, sheds, fences, logs...): vertex colour x material colour x per-instance
// colour (MultiMesh custom data, linear RGB) -- the three.js vertexColors * color * instanceColor.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform vec3 albedo = vec3(1.0);
uniform float roughness = 0.85;
uniform float metallic = 0.0;
uniform bool use_instance = true;
varying vec3 v_col;

void vertex() {
	vec3 ic = use_instance ? INSTANCE_CUSTOM.rgb : vec3(1.0);
	v_col = albedo * COLOR.rgb * ic;
}

void fragment() {
	ALBEDO = v_col;
	ROUGHNESS = roughness;
	METALLIC = metallic;
	SPECULAR = 0.4;
}
