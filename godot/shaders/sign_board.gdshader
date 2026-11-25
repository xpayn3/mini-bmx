// Printed signs (SignTex): the distance sign's plate, the roadside billboards, the gantry banners. A unit box scaled
// to the board; the print (board_tex) is on +Z (and on -Z too, read the right way round, when `both_sides`). Weathered
// per sign, seeded by its place, so each has had a life beside the trail: real scans for the paint (ambientCG, CC0:
// SurfaceImperfections008 grime + its normal, Smear004 smears = lens_dirt R, SurfaceImperfections001 scuffs = lens_dirt G),
// sun fade, chipped edges, a dent, mud flung up from the bottom. `wood_mix` > 0 = paint on wooden planks (Wood049 grain
// through the paint, `planks` seams, bare wood where it chips); 0 = paint / sheeting on aluminium (bare metal under it).
// Retroreflection (`retro`) in light(). Same distance dissolve as the other streamed decorations.
shader_type spatial;
render_mode cull_back;
#include "res://shaders/deco_fade.gdshaderinc"
instance uniform float fade_mode = 0.0;
uniform sampler2D board_tex : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D grime_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grime_nrm : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D dirt_tex : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D wood_col : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D wood_nrm : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec2 plate_m = vec2(0.8, 0.8);   // the board's size in metres (scans are laid on in metres)
uniform float wear = 1.0;      // 0 = mint
uniform float mud_amt = 1.0;   // mud flung up from the trail (0 high up on a gantry)
uniform float wood_mix = 0.0;  // 1 = painted wooden planks
uniform float planks = 0.0;    // plank count across the height (seams), 0 = one sheet
uniform bool both_sides = false;
uniform float retro = 6.0;        // retroreflection strength (x a white diffuse surface, at the peak); 0 = plain paint
uniform float retro_sun = 0.12;   // the sun's share (a low sun behind you lights it a little, the bike lamp a lot)
varying flat vec3 v_origin;
varying vec3 v_local;   // -0.5 .. 0.5 on the unit box
varying float v_retro;  // how much retroreflective sheeting shows here (0 under mud / on bare metal / on the back)

float h21(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vn(vec2 p) {
	vec2 i = floor(p), f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h21(i), h21(i + vec2(1, 0)), f.x), mix(h21(i + vec2(0, 1)), h21(i + vec2(1, 1)), f.x), f.y);
}
float fbm(vec2 p) { return vn(p) * 0.5 + vn(p * 2.03 + 7.1) * 0.27 + vn(p * 4.1 + 3.3) * 0.15 + vn(p * 8.3 + 1.7) * 0.08; }

void vertex() {
	v_origin = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	v_local = VERTEX;
}

void fragment() {
	if (deco_cut(v_origin, fade_mode, FRAGCOORD.xy, PROJECTION_MATRIX[3][3] > 0.5)) discard;
	float seed = h21(floor(v_origin.xz * 3.0)) * 91.0;
	bool front = v_local.z > 0.49;
	bool back = v_local.z < -0.49;
	bool face = front || (back && both_sides);
	// q = 0..1 across the board as seen from its own side (x mirrored on the back), m = the same in metres
	vec2 q = vec2(back ? 0.5 - v_local.x : v_local.x + 0.5, v_local.y + 0.5);
	vec2 m = q * plate_m;
	vec2 qn = m / 0.8;   // noise space: the procedural bits are sized for a 0.8 m plate, kept that size on bigger boards
	vec3 col = texture(board_tex, front ? UV : (face ? vec2(q.x, 1.0 - q.y) : vec2(0.5, 0.995))).rgb;
	float rough = 0.5;
	float metal = 0.0;
	float w = wear;
	vec2 off = vec2(h21(vec2(seed, 7.0)), h21(vec2(seed, 8.0)));

	// wooden planks: the grain shows through the paint, a dark seam between planks
	vec2 wuv = vec2(m.x, m.y) * 0.9 + off;
	vec3 wood = texture(wood_col, wuv).rgb;
	float wl = dot(wood, vec3(0.6, 0.3, 0.1)) / 0.1663;   // ~1 on average (Wood049's mean, linear)
	col *= mix(1.0, (0.7 + 0.3 * wl) * 0.72, wood_mix);   // paint soaked into weathered wood: duller than a printed sheet
	float seam = 0.0;
	if (planks > 0.5) {
		float py = fract(q.y * planks);
		seam = (1.0 - smoothstep(0.0, 0.012 * planks, min(py, 1.0 - py))) * step(0.5, wood_mix);
		col *= 1.0 - 0.65 * seam;
	}
	rough += 0.2 * wood_mix;

	// sun-faded print: a little paler / greyer towards the top
	col = mix(col, vec3(dot(col, vec3(0.3, 0.55, 0.15))), 0.12 * w * q.y);
	col *= 1.0 - 0.06 * w * q.y;
	// real wear: grime multiply map (white = clean), smeared dirt, scuffs
	vec3 grime = texture(grime_tex, m * 0.7 + off).rgb;
	float patch = dot(grime, vec3(0.333));
	col *= mix(vec3(1.0), grime, 0.75 * w);
	vec3 ld = texture(dirt_tex, m * vec2(0.52, 0.94) + off * 0.5).rgb;
	float smear = ld.r;
	col = mix(col, col * vec3(0.78, 0.72, 0.64), smoothstep(0.35, 0.8, smear) * 0.5 * w);
	rough += 0.3 * w * smoothstep(0.3, 0.8, smear) + 0.15 * w * (1.0 - patch);
	float scr = smoothstep(0.45, 0.75, ld.g) * (0.35 + 0.65 * (1.0 - q.y)) * w;

	// chipped edges, scuffs: what's under the paint shows (aluminium, or bare grey wood)
	float edge = min(min(m.x, plate_m.x - m.x), min(m.y, plate_m.y - m.y)) / 0.8;
	float chip = (1.0 - smoothstep(0.0, 0.02, edge - 0.035 * (fbm(qn * 24.0 + seed) - 0.45))) * w;
	float bare = max(scr, chip);
	if (!face) bare = chip;
	vec3 under = mix(vec3(0.62, 0.63, 0.64), wood * 1.3, wood_mix);
	col = mix(col, under, bare * 0.9);
	metal = mix(metal, 0.75 * (1.0 - wood_mix), bare);
	rough = mix(rough, mix(0.35, 0.85, wood_mix), bare);

	// mud flung up from the trail: dense at the bottom, ragged spatters thinning upwards, a few drips running down
	float hy = m.y / 0.8;   // height up the board in plate units: mud reaches the same height on any board
	float up = hy + 0.12 * (fbm(qn * vec2(6.0, 3.0) + seed + 4.0) - 0.5);
	float band = 1.0 - smoothstep(0.03, 0.16 + 0.1 * h21(vec2(seed, 3.0)), up);
	float spat = smoothstep(0.66, 0.7, fbm(qn * 22.0 + seed * 1.7)) * (1.0 - smoothstep(0.08, 0.42, hy));
	float blob = smoothstep(0.6, 0.64, fbm(qn * 9.0 + seed * 0.3)) * (1.0 - smoothstep(0.1, 0.3, hy));
	float drip = smoothstep(0.93, 0.97, vn(vec2(qn.x * 30.0 + seed, 0.0))) * (1.0 - smoothstep(0.05, 0.22 + 0.15 * h21(vec2(floor(qn.x * 30.0), seed)), hy));
	float mud = clamp(max(max(band * (0.55 + 0.45 * fbm(qn * 14.0 + seed)), spat), max(blob, drip * 0.8)), 0.0, 1.0) * w * mud_amt;
	float dry = smoothstep(0.04, 0.3, hy) + 0.25 * vn(qn * 40.0 + seed);
	vec3 mud_c = mix(vec3(0.13, 0.08, 0.045), vec3(0.36, 0.25, 0.15), clamp(dry, 0.0, 1.0));
	col = mix(col, mud_c, mud * 0.92);
	rough = mix(rough, mix(0.45, 0.95, clamp(dry, 0.0, 1.0)), mud);
	metal *= 1.0 - mud;

	// a dent (a rock, a pedal), the grime scan's relief, the wood's grain
	vec2 dc = vec2(h21(vec2(seed, 5.0)), 0.15 + 0.5 * h21(vec2(seed, 6.0)));
	vec2 dv = (q - dc) * plate_m / 0.8;
	float dent = exp(-dot(dv, dv) * 90.0) * w * (1.0 - wood_mix);
	vec2 g = dv * dent * 3.0 + (texture(grime_nrm, m * 0.7 + off).xy * 2.0 - 1.0) * 0.6 * w;
	g += (texture(wood_nrm, wuv).xy * 2.0 - 1.0) * 0.5 * wood_mix;
	g.y += seam * 0.6;
	vec3 tx = normalize((VIEW_MATRIX * MODEL_MATRIX * vec4(back ? -1.0 : 1.0, 0.0, 0.0, 0.0)).xyz);   // the mesh has no tangents
	vec3 ty = normalize((VIEW_MATRIX * MODEL_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);
	NORMAL = normalize(NORMAL + (tx * g.x + ty * g.y) * (face ? 1.0 : 0.0));

	v_retro = (front ? 1.0 : 0.0) * (1.0 - bare) * (1.0 - mud) * (0.75 + 0.25 * patch) * (1.0 - wood_mix);
	ALBEDO = col;
	ROUGHNESS = clamp(rough, 0.0, 1.0);
	METALLIC = metal;
	SPECULAR = 0.4;
}

// standard-ish lighting (Lambert + GGX-like lobe), plus retroreflection: sheeting full of tiny glass beads sends light
// back towards the light, so it blazes when the light sits near your eye (a lamp on the bike, a sun behind you)
void light() {
	float nl = clamp(dot(NORMAL, LIGHT), 0.0, 1.0);
	DIFFUSE_LIGHT += nl * ATTENUATION * LIGHT_COLOR / PI;
	vec3 hv = normalize(LIGHT + VIEW);
	float a = max(ROUGHNESS * ROUGHNESS, 0.002);
	float nh = clamp(dot(NORMAL, hv), 0.0, 1.0);
	float d = a * a / (PI * pow(nh * nh * (a * a - 1.0) + 1.0, 2.0));
	SPECULAR_LIGHT += d * nl * 0.25 * ATTENUATION * LIGHT_COLOR * SPECULAR_AMOUNT;
	float bk = clamp(dot(LIGHT, VIEW), 0.0, 1.0);
	float lobe = pow(bk, 48.0) + 0.25 * pow(bk, 8.0);
	float k = retro * v_retro * lobe * (LIGHT_IS_DIRECTIONAL ? retro_sun : 1.0);
	DIFFUSE_LIGHT += k * clamp(dot(NORMAL, VIEW), 0.0, 1.0) * ATTENUATION * LIGHT_COLOR / PI;
}
