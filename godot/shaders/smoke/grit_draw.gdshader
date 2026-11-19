// Draws one grit grain (shaders/smoke/grit.gdshader): a tiny round camera-facing speck, lit by the sun
// as it reaches the grain through the dust (the smoke sim's light volume) + sky; tumbling grains catch
// the sun and glint.
shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled;

uniform sampler3D light_tex : filter_linear, repeat_disable;   // r density, g sun through dust, b sky
uniform sampler2D hmap : filter_linear, repeat_disable;
uniform vec3 origin;
uniform vec3 size_m;
uniform float hm_cells = 32.0;
uniform vec3 sun_col = vec3(3.0, 2.8, 2.5);
uniform vec3 amb_col = vec3(0.45, 0.55, 0.75);

varying vec3 v_light;
varying float v_glint;

void vertex() {
	vec3 wp = MODEL_MATRIX[3].xyz;
	float s = length(MODEL_MATRIX[0].xyz);
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0] * s, INV_VIEW_MATRIX[1] * s, INV_VIEW_MATRIX[2] * s, vec4(wp, 1.0));
	vec2 g = (wp.xz - origin.xz) / size_m.xz;
	float gr = texture(hmap, (clamp(g, 0.0, 1.0) * hm_cells + 0.5) / (hm_cells + 1.0)).r;
	vec3 g3 = vec3(g.x, (wp.y - gr) / size_m.y, g.y);
	vec3 L = vec3(1.0, 1.0, 1.0);
	if (all(greaterThan(g3, vec3(0.0))) && all(lessThan(g3, vec3(1.0)))) L = texture(light_tex, g3).gbr;
	// a tumbling grain flashes when a facet faces the sun
	float ph = INSTANCE_CUSTOM.z * 61.0;
	v_glint = pow(max(0.0, sin(TIME * (9.0 + INSTANCE_CUSTOM.z * 14.0) + ph)), 24.0) * (1.0 - INSTANCE_CUSTOM.y);
	v_light = sun_col * L.x * (0.55 + 2.5 * v_glint) + amb_col * (0.35 + 0.65 * L.y);
}

void fragment() {
	vec2 q = UV - 0.5;
	if (dot(q, q) > 0.25) discard;   // round
	ALBEDO = COLOR.rgb * v_light;
}
