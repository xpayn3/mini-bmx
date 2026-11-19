shader_type spatial;
render_mode cull_disabled;   // open shells: seen through a gap, the inside still draws (back faces lit the other way)
// Hard shell of the rider's knee pads (scripts/rider/knee_pad.gd). UV = the shell's own (s, t) in [0, 1]:
// s across the knee, t up the leg. mode 0 = the knee cap (chevron, pin line, vent slots, rivets),
// mode 1 = the small shin insert (stripe, pin line, two rivets), 2 = race cap (twin stripes, grille),
// 3 = race guards (ribs, stripe / logo, rivets), 4 = trail honeycomb foam (stitched edge, tab).
// Edges anti-aliased with fwidth. The wordmark (logo_*) goes over any of them.

uniform vec3 base_col : source_color = vec3(0.1, 0.105, 0.12);
uniform vec3 accent : source_color = vec3(1.0, 0.82, 0.12);
uniform int mode = 0;
uniform float sp = 2.4;   // the outline's superellipse power (as in knee_pad.gd)
// the brand wordmark (KneePad bakes it): white lettering on clear, printed in logo_col into logo_rect
// (centre xy, half size zw in the shell's -1..1 space); vertical = reading down the leg
uniform sampler2D logo_tex : source_color, filter_linear_mipmap, repeat_disable;
uniform float logo_on = 0.0;
uniform vec4 logo_rect = vec4(0.0, 0.5, 0.34, 0.11);
uniform bool logo_vertical = false;
uniform vec3 logo_col : source_color = vec3(0.95);

float cover(float d) {   // d < 0 inside -> 1, soft over one pixel
	float w = max(fwidth(d), 1e-5);
	return clamp(0.5 - d / w, 0.0, 1.0);
}

float rbox(vec2 p, vec2 b, float r) {
	vec2 q = abs(p) - b + r;
	return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

float logo_a(vec2 q) {
	vec2 l = q - logo_rect.xy;
	// seen from the front, +x runs to the viewer's left: flip so the lettering reads
	vec2 t = logo_vertical ? vec2(-l.y, -l.x) : vec2(-l.x, l.y);
	vec2 p = t / logo_rect.zw;
	if (abs(p.x) > 1.0 || abs(p.y) > 1.0) return 0.0;
	return texture(logo_tex, vec2(0.5 + 0.5 * p.x, 0.5 - 0.5 * p.y)).a * logo_on;
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
	} else if (mode == 2) {
		// race cap: twin racing stripes top to bottom, a grille of slots low down, a bold rim band
		float in_r = cover(n - 0.8);
		float stripes = cover(abs(abs(q.x) - 0.17) - 0.055) * in_r;
		col = mix(col, accent, stripes);
		float slot = 0.0;
		for (int k = 0; k < 4; k++) {
			float x = -0.39 + 0.26 * float(k);
			slot = max(slot, cover(rbox(q - vec2(x, -0.55), vec2(0.075, 0.13), 0.06)));
		}
		col = mix(col, vec3(0.018), slot);
		rough = mix(rough, 0.85, slot);
		coat *= 1.0 - slot;
		float rim = cover(abs(n - 0.885) - 0.04);
		col = mix(col, mix(base_col, accent, 0.8), rim);
		float rv = cover(length(q - vec2(0.0, 0.62)) - 0.07);
		col = mix(col, vec3(0.78, 0.79, 0.8), rv);
		metal = mix(metal, 1.0, rv);
		rough = mix(rough, 0.22, rv);
	} else if (mode == 3) {
		// race guards: moulded ribs across, one accent stripe down the middle, rivets in the corners
		float rib = cover(abs(fract(q.y * 2.0 + 0.5) - 0.5) - 0.06) * cover(n - 0.8) * step(0.2, abs(q.x));
		col = mix(col, base_col * 0.45, rib);
		rough = mix(rough, 0.6, rib);
		float stripe = cover(abs(q.x) - 0.11) * cover(n - 0.86) * (1.0 - step(0.5, logo_on));
		col = mix(col, accent, stripe);
		for (int k = 0; k < 4; k++) {
			vec2 c = vec2(k < 2 ? -0.66 : 0.66, (k % 2 == 0) ? -0.68 : 0.68);
			float rv = cover(length(q - c) - 0.075);
			col = mix(col, vec3(0.78, 0.79, 0.8), rv);
			metal = mix(metal, 1.0, rv);
			rough = mix(rough, 0.22, rv);
		}
		float pin = cover(abs(n - 0.9) - 0.018);
		col = mix(col, pin_col, pin);
	} else if (mode == 4) {
		// trail: soft foam moulded in a honeycomb, a stitched edge and a small accent tab
		vec2 p = q * vec2(4.2, 3.4);
		vec2 hs = vec2(1.0, 1.7320508);
		vec4 hc = floor(vec4(p, p - vec2(0.5, 0.866)) / hs.xyxy) + 0.5;
		vec4 h = vec4(p - hc.xy * hs, p - (hc.zw + 0.5) * hs);
		vec2 hp = dot(h.xy, h.xy) < dot(h.zw, h.zw) ? h.xy : h.zw;
		hp = abs(hp);
		float edge = 0.5 - max(dot(hp, hs * 0.5), hp.x);   // distance to the cell's edge
		float groove = cover(edge - 0.07) * cover(n - 0.86);
		col = mix(base_col * 1.25 + 0.02, base_col * 0.4, groove);
		rough = 0.82;
		coat = 0.0;
		float stitch = cover(abs(n - 0.92) - 0.012) * step(0.5, fract(atan(q.y, q.x) * 9.0));
		col = mix(col, accent, stitch);
		float tab = cover(rbox(q - vec2(0.0, 0.55), vec2(0.4, 0.15), 0.07));
		col = mix(col, accent, tab);
		rough = mix(rough, 0.5, tab);
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
	float lg = logo_a(q);
	col = mix(col, logo_col, lg);
	rough = mix(rough, 0.45, lg);
	ALBEDO = col;
	ROUGHNESS = rough;
	METALLIC = metal;
	CLEARCOAT = 0.6 * coat;
	CLEARCOAT_ROUGHNESS = 0.18;
}
