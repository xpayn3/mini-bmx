// The distance sign's plate (terrain_chunk_builder._dist_signs): the "table sign" printed per distance by SignTex
// on a thin board, weathered here so each sign has had a life beside the trail: sun-faded print, rough patchy paint,
// scratches and scuffs to bare aluminium, chipped edges, a dent or two, and mud flung up from the bottom (dried
// pale at the edges, darker and wetter low down). Real scans for the paint wear (below), seeded by the sign's place.
// Same distance dissolve as the other streamed decorations.
shader_type spatial;
render_mode cull_back;
#include "res://shaders/deco_fade.gdshaderinc"
instance uniform float fade_mode = 0.0;
uniform sampler2D board_tex : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform float wear = 1.0;   // 0 = mint
uniform sampler2D grime_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D dirt_tex : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grime_nrm : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
varying flat vec3 v_origin;
varying vec3 v_local;   // -0.5 .. 0.5 on the unit box
varying float v_retro;  // how much retroreflective sheeting shows here (0 under mud / on bare metal / on the back)
uniform float retro = 6.0;        // retroreflection strength (x a white diffuse surface, at the peak)
uniform float retro_sun = 0.12;   // the sun's share (a low sun behind you lights it a little, the bike lamp a lot)

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
	// plate coordinates in the board's own plane (x right, y up, 0..1), front and back alike
	vec2 q = vec2(v_local.x + 0.5, v_local.y + 0.5);
	bool front = v_local.z > 0.49;
	vec3 col = texture(board_tex, UV).rgb;
	float rough = 0.5;
	float metal = 0.0;
	float w = wear;

	// sun-faded print: a little paler / greyer towards the top
	col = mix(col, vec3(dot(col, vec3(0.3, 0.55, 0.15))), 0.12 * w * q.y);
	col *= 1.0 - 0.06 * w * q.y;
	// real wear from scans (ambientCG, CC0): SurfaceImperfections008 as a grime multiply map (white = clean) for
	// patchy weathered paint, SurfaceImperfections001 (lens_dirt.png G) for scuffs / scratches through to the metal,
	// Smear004 (lens_dirt.png R) for smeared dirt and rough patches. Each sign reads its own patch of them.
	vec2 off = vec2(h21(vec2(seed, 7.0)), h21(vec2(seed, 8.0)));
	vec3 grime = texture(grime_tex, q * 0.55 + off).rgb;
	float patch = dot(grime, vec3(0.333));
	col *= mix(vec3(1.0), grime, 0.75 * w);
	vec3 ld = texture(dirt_tex, q * vec2(0.42, 0.75) + off * 0.5).rgb;
	float smear = ld.r;
	col = mix(col, col * vec3(0.78, 0.72, 0.64), smoothstep(0.35, 0.8, smear) * 0.5 * w);
	rough += 0.3 * w * smoothstep(0.3, 0.8, smear) + 0.15 * w * (1.0 - patch);
	float scr = smoothstep(0.45, 0.75, ld.g) * (0.35 + 0.65 * (1.0 - q.y)) * w;
	// chipped edges: bare metal creeping in from the rim
	float edge = min(min(q.x, 1.0 - q.x), min(q.y, 1.0 - q.y));
	float chip = (1.0 - smoothstep(0.0, 0.02, edge - 0.035 * (fbm(q * 24.0 + seed) - 0.45))) * w;
	float bare = max(scr, chip);
	if (!front) bare = chip;
	col = mix(col, vec3(0.62, 0.63, 0.64), bare * 0.9);
	metal = mix(metal, 0.75, bare);
	rough = mix(rough, 0.35, bare);

	// mud flung up from the trail: dense at the bottom, ragged spatters thinning upwards, a few drips running down
	float up = q.y + 0.12 * (fbm(q * vec2(6.0, 3.0) + seed + 4.0) - 0.5);
	float band = 1.0 - smoothstep(0.03, 0.16 + 0.1 * h21(vec2(seed, 3.0)), up);
	float spat = smoothstep(0.66, 0.7, fbm(q * 22.0 + seed * 1.7)) * (1.0 - smoothstep(0.08, 0.42, q.y));
	float blob = smoothstep(0.6, 0.64, fbm(q * 9.0 + seed * 0.3)) * (1.0 - smoothstep(0.1, 0.3, q.y));
	float drip = smoothstep(0.93, 0.97, vn(vec2(q.x * 30.0 + seed, 0.0))) * (1.0 - smoothstep(0.05, 0.22 + 0.15 * h21(vec2(floor(q.x * 30.0), seed)), q.y));
	float mud = clamp(max(max(band * (0.55 + 0.45 * fbm(q * 14.0 + seed)), spat), max(blob, drip * 0.8)), 0.0, 1.0) * w;
	float dry = smoothstep(0.04, 0.3, q.y) + 0.25 * vn(q * 40.0 + seed);
	vec3 mud_c = mix(vec3(0.13, 0.08, 0.045), vec3(0.36, 0.25, 0.15), clamp(dry, 0.0, 1.0));
	col = mix(col, mud_c, mud * 0.92);
	rough = mix(rough, mix(0.45, 0.95, clamp(dry, 0.0, 1.0)), mud);
	metal *= 1.0 - mud;

	// dents: a couple of soft bowls bending the normal (a rock, a pedal)
	vec2 dc = vec2(h21(vec2(seed, 5.0)), 0.15 + 0.5 * h21(vec2(seed, 6.0)));
	vec2 dv = q - dc;
	float dent = exp(-dot(dv, dv) * 90.0) * w;
	vec2 g = dv * dent * 3.0 + (texture(grime_nrm, q * 0.55 + off).xy * 2.0 - 1.0) * 0.6 * w;
	vec3 tx = normalize((VIEW_MATRIX * MODEL_MATRIX * vec4(1.0, 0.0, 0.0, 0.0)).xyz);   // the mesh has no tangents
	vec3 ty = normalize((VIEW_MATRIX * MODEL_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);
	NORMAL = normalize(NORMAL + (tx * g.x + ty * g.y) * (front ? 1.0 : 0.0));

	v_retro = (front ? 1.0 : 0.0) * (1.0 - bare) * (1.0 - mud) * (0.75 + 0.25 * patch);
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
	float back = clamp(dot(LIGHT, VIEW), 0.0, 1.0);
	float lobe = pow(back, 48.0) + 0.25 * pow(back, 8.0);
	float k = retro * v_retro * lobe * (LIGHT_IS_DIRECTIONAL ? retro_sun : 1.0);
	DIFFUSE_LIGHT += k * clamp(dot(NORMAL, VIEW), 0.0, 1.0) * ATTENUATION * LIGHT_COLOR / PI;
}
