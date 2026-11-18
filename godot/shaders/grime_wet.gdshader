// Wet look after riding through water (port of src/grime.js): a thin film over each part -- darker
// (water fills the surface) and glossy, with drops beading and running down. Drawn as the last
// next_pass, only while something is wet. Premultiplied: the film darkens by its alpha but its
// highlights are added at full strength.
shader_type spatial;
render_mode blend_premul_alpha, depth_draw_never, cull_back, diffuse_burley, specular_schlick_ggx;

global uniform vec4 grime;   // x = mud, y = wet 0..1, z = time
global uniform mat4 grime_root;

varying vec3 v_local;
varying vec3 v_root;

float wt_hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

void vertex() {
	v_local = VERTEX;
	v_root = (grime_root * (MODEL_MATRIX * vec4(VERTEX, 1.0))).xyz;
	POSITION = PROJECTION_MATRIX * (MODELVIEW_MATRIX * vec4(VERTEX, 1.0));
	POSITION.z += 0.00008 * POSITION.w;
}

void fragment() {
	float w = grime.y;
	// running drops: columns of beads sliding down in bike-root space
	vec2 g = vec2(v_root.z + v_root.x * 0.6, v_root.y) * vec2(60.0, 18.0);
	float col = floor(g.x);
	float sp = 0.4 + wt_hash(vec2(col, 3.0)) * 1.2;
	float y = fract(g.y + grime.z * sp * 0.25 + wt_hash(vec2(col, 7.0)));
	float bead = smoothstep(0.35, 0.0, abs(fract(g.x) - 0.5)) * smoothstep(0.85, 0.95, y) * step(0.55, wt_hash(vec2(col, 11.0)));
	ALBEDO = vec3(0.0);
	ALPHA = clamp(w * (0.35 + bead * 0.3), 0.0, 1.0);
	ROUGHNESS = mix(0.18, 0.04, bead);
	SPECULAR = 0.5 + bead * 0.5;
	NORMAL = normalize(NORMAL + (VIEW_MATRIX * vec4(0.0, bead * 0.6, 0.0, 0.0)).xyz);
}
