shader_type spatial;
// Hard shell of the rider's knee pads (scripts/rider/knee_pad.gd). UV = the shell's own (s, t) in [0, 1]:
// s across the knee, t up the leg. mode 0 = the knee cap (chevron, pin line, vent slots, rivets),
// mode 1 = the small shin insert (stripe, pin line, two rivets). Edges anti-aliased with fwidth.

uniform vec3 base_col : source_color = vec3(0.1, 0.105, 0.12);
uniform vec3 accent : source_color = vec3(1.0, 0.82, 0.12);
uniform int mode = 0;
uniform float sp = 2.4;   // the outline's superellipse power (as in knee_pad.gd)

float cover(float d) {   // d < 0 inside -> 1, soft over one pixel
	float w = max(fwidth(d), 1e-5);
	return clamp(0.5 - d / w, 0.0, 1.0);
}

float rbox(vec2 p, vec2 b, float r) {
	vec2 q = abs(p) - b + r;
	return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

void fragment() {
	vec2 q = UV * 2.0 - 1.0;
	float n = pow(pow(abs(q.x), sp) + pow(abs(q.y), sp), 1.0 / sp);
	vec3 col = base_col;
	float rough = 0.32;
	float metal = 0.0;
	float coat = 1.0;
	vec3 pin_col = mix(base_col, vec3(1.0), 0.45);
	if (mode == 0) {
		// a chevron pointing down the leg, in the kit's accent colour
		float chev = cover(abs(q.y - (-0.12 + 0.78 * abs(q.x))) - 0.105) * cover(n - 0.8);
		// a thin dark keyline either side of it
		float key = cover(abs(abs(q.y - (-0.12 + 0.78 * abs(q.x))) - 0.125) - 0.012) * cover(n - 0.8);
		col = mix(col, accent, chev);
		col = mix(col, base_col * 0.35, key);
		// three vent slots under it, getting shorter toward the shin
		float slot = 0.0;
		for (int k = 0; k < 3; k++) {
			float y = -0.42 - 0.16 * float(k);
			slot = max(slot, cover(rbox(q - vec2(0.0, y), vec2(0.36 - 0.08 * float(k), 0.042), 0.04)));
		}
		col = mix(col, vec3(0.018), slot);
		rough = mix(rough, 0.85, slot);
		coat *= 1.0 - slot;
		// rivets at the top corners
		for (int sx = -1; sx <= 1; sx += 2) {
			float rv = cover(length(q - vec2(float(sx) * 0.56, 0.5)) - 0.065);
			col = mix(col, vec3(0.78, 0.79, 0.8), rv);
			metal = mix(metal, 1.0, rv);
			rough = mix(rough, 0.22, rv);
		}
		// moulded pin line round the edge
		float pin = cover(abs(n - 0.9) - 0.016);
		col = mix(col, pin_col, pin);
	} else {
		float stripe = cover(abs(q.y + 0.05) - 0.14) * cover(n - 0.82);
		col = mix(col, accent, stripe);
		for (int sx = -1; sx <= 1; sx += 2) {
			float rv = cover(length(q - vec2(float(sx) * 0.62, 0.55)) - 0.09);
			col = mix(col, vec3(0.78, 0.79, 0.8), rv);
			metal = mix(metal, 1.0, rv);
			rough = mix(rough, 0.22, rv);
		}
		float pin = cover(abs(n - 0.88) - 0.022);
		col = mix(col, pin_col, pin);
	}
	ALBEDO = col;
	ROUGHNESS = rough;
	METALLIC = metal;
	CLEARCOAT = 0.6 * coat;
	CLEARCOAT_ROUGHNESS = 0.18;
}
