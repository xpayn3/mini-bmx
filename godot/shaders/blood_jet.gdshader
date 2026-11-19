// Arterial blood jet from a torn-off limb (fx/blood.gd): each drop is a quad stretched along its velocity
// (blood.gd builds the transform: X = across, Y = along the flight, facing the camera), so the drops
// overlap into one continuous stream. UV.x across, UV.y along; rounded ends, glossy dark red.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, specular_schlick_ggx;

void fragment() {
	vec2 p = vec2(UV.x * 2.0 - 1.0, UV.y * 2.0 - 1.0);
	// a capsule: round at both ends
	float len_k = 0.75;
	float y = max(abs(p.y) - len_k, 0.0) / (1.0 - len_k);
	float d = length(vec2(p.x, y));
	float a = 1.0 - smoothstep(0.75, 1.0, d);
	if (a < 0.02) discard;
	// a bright core where it's thickest (fake depth of a round stream)
	float core = 1.0 - abs(p.x);
	ALBEDO = mix(vec3(0.05, 0.0, 0.0), vec3(0.16, 0.004, 0.004), core);
	ROUGHNESS = 0.18;
	SPECULAR = 0.5;
	ALPHA = a * 0.95;
}
