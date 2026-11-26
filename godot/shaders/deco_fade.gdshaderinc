// Distance fade for the streamed decorations, so nothing pops in while riding (2026-11-22).
// The real trees / rocks / sheds / fences dissolve out between deco_fade.z and .w metres from the rider (by each
// instance's own base, not its chunk), and the far backdrop's trees (world/far_hills.gd) dissolve IN over the same
// band; small ground clutter (pebbles, flowers, sticks: only built in the 3x3 chunks round the rider, at least
// 48 m out) fades between SMALL_IN and SMALL_OUT. The chunks round the rider are loaded >= 144 m out, so a chunk
// arriving or its clutter switching on is always past the fade. Same in the shadow pass (no shadow pops either).
global uniform vec4 deco_fade;   // xy = rider xz, z = full until (m), w = gone by (m); w <= 0: off (garage etc.)
const float SMALL_IN = 30.0;
const float SMALL_OUT = 44.0;

// the sun's shadow pass keeps the world decorations casting further out than they are drawn: a low sun throws a tree's
// shadow 100+ m, so a tree past the band still darkens the trail in view. Still inside the always-loaded 144 m.
const float SHADOW_EXTRA_IN = 6.0;
const float SHADOW_EXTRA_OUT = 20.0;

// 1 = drawn, 0 = gone: mode 1 world decorations, 2 small clutter, -1 the far backdrop (the other side of the band)
float deco_keep(vec3 origin, float mode, bool shadow_pass) {
	if (deco_fade.w <= 0.0 || mode == 0.0) return 1.0;
	float d = distance(origin.xz, deco_fade.xy);
	if (mode > 1.5) return 1.0 - smoothstep(SMALL_IN, SMALL_OUT, d);
	if (shadow_pass && mode > 0.0) return 1.0 - smoothstep(deco_fade.w + SHADOW_EXTRA_IN, deco_fade.w + SHADOW_EXTRA_OUT, d);
	float k = smoothstep(deco_fade.z, deco_fade.w, d);
	return mode < 0.0 ? k : 1.0 - k;
}
// dissolve: each instance gets its own offset into the screen-space pattern, so neighbours don't fade in lockstep
bool deco_cut(vec3 origin, float mode, vec2 frag, bool shadow_pass) {
	float a = deco_keep(origin, mode, shadow_pass);
	if (a >= 1.0) return false;
	if (a <= 0.0) return true;
	float h = fract(sin(dot(floor(origin.xz * 4.0), vec2(12.9898, 78.233))) * 43758.5453);
	float n = fract(52.9829189 * fract(dot(frag, vec2(0.06711056, 0.00583715))) + h);
	return n >= a;
}

// Card trees (2026-11-26, world/card_tree.gd): every tree crown is drawn twice from the same instances: mode 4 = its
// leaf-card crown, only near the rider (full to CARD_IN, gone by CARD_OUT), mode 3 = the solid low-poly crown, the rest
// of the way out. In the band the two use the SAME dither value per pixel, so each pixel shows exactly one of them. The
// solid crown always casts the sun shadow (cheap: no alpha cut-out in the shadow pass); the card crown casts none.
// No fade band (deco_fade.w <= 0: garage, editor): solid crowns only.
const float CARD_IN = 36.0;
const float CARD_OUT = 48.0;

// 0 = solid crown, 1 = card crown at this tree
float deco_cardness(vec3 origin) {
	if (deco_fade.w <= 0.0) return 0.0;
	return 1.0 - smoothstep(CARD_IN, CARD_OUT, distance(origin.xz, deco_fade.xy));
}
float deco_dither(vec3 origin, vec2 frag) {
	float h = fract(sin(dot(floor(origin.xz * 4.0), vec2(12.9898, 78.233))) * 43758.5453);
	return fract(52.9829189 * fract(dot(frag, vec2(0.06711056, 0.00583715))) + h);
}
// the pair's own cut (modes 3 / 4), on top of deco_cut's far fade (mode 3 is a mode 1 decoration out there)
bool deco_cut_pair(vec3 origin, float mode, vec2 frag, bool shadow_pass) {
	if (mode < 2.5) return deco_cut(origin, mode, frag, shadow_pass);
	if (mode < 3.5) {
		if (deco_cut(origin, 1.0, frag, shadow_pass)) return true;
		if (shadow_pass) return false;
		float c = deco_cardness(origin);
		return c > 0.0 && deco_dither(origin, frag) < c;
	}
	float c = deco_cardness(origin);
	return c <= 0.0 || deco_dither(origin, frag) >= c;
}
// a whole instance that can't show in this pass: its vertices are folded onto its base (no pixels to shade at all)
bool deco_fold(vec3 origin, float mode, bool shadow_pass) {
	if (mode < 2.5 || deco_fade.w <= 0.0 && mode < 3.5) return false;
	float c = deco_cardness(origin);
	if (mode > 3.5) return c <= 0.0;
	return !shadow_pass && c >= 1.0;
}
