// Blood on the rider and bike: stains drawn as a next_pass over each part's own material (same trick as
// grime_mud.gdshader, and chained after it by scripts/bike/grime.gd). Solid-edged (but drawn see-through,
// after the stickers, so it covers logos too: `decal` masks it by the sticker's alpha), glossy dark
// red patches picked from the part's own space, so they stay put on the part (pinned rider parts use the
// rest shape like the mud). grime.w = how much blood 0..1 (it builds with every crash and stays until a
// death + revive). Tyres carry none.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

global uniform vec4 grime;
uniform float bias = 1.0;
uniform bool tyre = false;
uniform bool decal = false;
uniform sampler2D decal_tex : source_color, filter_linear_mipmap;
instance uniform float grime_pin = 0.0;

varying vec3 v_local;

float bl_hash(vec3 p) { p = fract(p * 0.3183099 + 0.7); p *= 17.0; return fract(p.x * p.y * p.z * (p.x + p.y + p.z)); }
float bl_noise(vec3 x) {
	vec3 i = floor(x), f = fract(x); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(bl_hash(i), bl_hash(i + vec3(1,0,0)), f.x), mix(bl_hash(i + vec3(0,1,0)), bl_hash(i + vec3(1,1,0)), f.x), f.y),
	           mix(mix(bl_hash(i + vec3(0,0,1)), bl_hash(i + vec3(1,0,1)), f.x), mix(bl_hash(i + vec3(0,1,1)), bl_hash(i + vec3(1,1,1)), f.x), f.y), f.z);
}

void vertex() {
	v_local = grime_pin > 1.5 ? CUSTOM0.xyz : VERTEX;
	POSITION = PROJECTION_MATRIX * (MODELVIEW_MATRIX * vec4(VERTEX, 1.0));
	POSITION.z += 0.00006 * POSITION.w;   // over the mud pass
}

void fragment() {
	float c = tyre ? 0.0 : clamp(grime.w * bias, 0.0, 1.0);
	// big blotches + smaller spatter + fine flecks
	float n = bl_noise(v_local * 26.0) * 0.6 + bl_noise(v_local * 71.0) * 0.4;
	// the noise sits around 0.5: light blood = a few spots (threshold ~0.85), heavy = most of the body (~0.3)
	float thr = mix(0.85, 0.30, c);
	float m = c > 0.002 ? smoothstep(thr, thr + 0.06, n) : 0.0;
	float shade = 0.7 + 0.5 * bl_noise(v_local * 9.0);   // darker clots, brighter wet red
	ALBEDO = vec3(0.34, 0.015, 0.02) * shade;
	ROUGHNESS = 0.32;
	SPECULAR = 0.6;
	ALPHA = step(0.5, m);
	if (decal) ALPHA *= texture(decal_tex, UV).a;
}
