// Tyre tracks (fx.gd ring-buffer ribbon): the tread pressed into the ground.
// UV.x: across the track (-1..1; +-2 = a skid smear), UV.y: metres along it. COLOR: ground colour
// (sRGB) + strength in alpha. Lit like the ground, with the knob dimples bump-mapped so they catch
// the sun; soft edges with a lighter lip of pushed-out soil; fades out in the distance.
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, specular_schlick_ggx;

const float ROW = 0.024;     // metres between knob rows (fx.gd wraps the distance on 2 rows)

uniform float bump = 9.0;   // x the real dimple depth (4 mm), to read at riding distance
uniform float fade_near = 55.0;
uniform float fade_far = 110.0;

varying float v_smear;

// the imprint of one knob: a rounded rectangle, 1 inside fading to 0 over its edge
float knob(vec2 p, vec2 half_size, float soft) {
	vec2 d = abs(p) - half_size;
	float sd = length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
	return 1.0 - smoothstep(-soft, soft, sd);
}

// depth of the tread at (across u in -1..1, along v metres): 0 = flat packed soil, 1 = bottom of a dimple.
// Two alternating rows like a downhill tyre: a pair of centre knobs, then a centre knob + shoulder knobs.
float tread(float u, float v) {
	float r = floor(v / ROW);
	float f = (fract(v / ROW) - 0.5) * ROW;          // metres from the row centre
	float x = u * 0.5;                                // across, as a fraction of the track width (-0.5..0.5)
	float h = 0.0;
	if (mod(r, 2.0) < 1.0) {
		h = max(knob(vec2(x - 0.17, f), vec2(0.09, 0.006), 0.012),
		        knob(vec2(x + 0.17, f), vec2(0.09, 0.006), 0.012));
	} else {
		h = knob(vec2(x, f), vec2(0.08, 0.007), 0.012);
		h = max(h, knob(vec2(abs(x) - 0.38, f + 0.004), vec2(0.07, 0.005), 0.012));
	}
	return h;
}

void vertex() {
	v_smear = step(1.5, abs(UV.x));
	UV.x = UV.x / mix(1.0, 2.0, v_smear);
	NORMAL = vec3(0.0, 1.0, 0.0);   // lie flat on the ground (the node sits unrotated in the world)
	// pull a little toward the camera instead of floating high above the ground
	vec3 view = (MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	VERTEX = (inverse(MODELVIEW_MATRIX) * vec4(view - normalize(view) * 0.04, 1.0)).xyz;
}

void fragment() {
	float u = UV.x;
	float v = UV.y;
	float au = abs(u);
	// the band: soft sides, and a lip where the tyre pushed soil out
	float band = 1.0 - smoothstep(0.3, 1.0, au);   // fades out gently towards the sides
	float lip = smoothstep(0.75, 0.92, au) * (1.0 - smoothstep(0.92, 1.0, au));
	float h;
	if (v_smear > 0.5) {
		// skid: no knobs, streaks dragged along the track
		h = 0.35 + 0.35 * sin(u * 23.0 + sin(v * 3.0)) * sin(u * 9.0 + 1.3);
	} else {
		h = tread(u, v);
	}
	// bump: tilt the normal by the screen-space slope of the dimple depth (dimples are holes: -h)
	float hh = -h * 0.004;
	vec3 dpdx = dFdx(VERTEX);
	vec3 dpdy = dFdy(VERTEX);
	vec3 r1 = cross(dpdy, NORMAL);
	vec3 r2 = cross(NORMAL, dpdx);
	float det = dot(dpdx, r1);
	vec3 grad = sign(det) * (dFdx(hh) * r1 + dFdy(hh) * r2);
	NORMAL = normalize(abs(det) * NORMAL - grad * bump);

	vec3 ground = pow(COLOR.rgb, vec3(2.2));           // sRGB -> linear
	// pressed soil is darker; the bottoms of the dimples darker still; the pushed-out lip a bit lighter
	vec3 col = ground * (0.9 - 0.27 * h) + ground * 0.4 * lip;   // (was 0.78 - 0.42 h: too dark; a smidget darker than 0.92 - 0.2 h)
	ALBEDO = col;
	ROUGHNESS = 0.92 - 0.12 * h;
	SPECULAR = 0.25;
	float dist = length(VERTEX);
	float fade = 1.0 - smoothstep(fade_near, fade_far, dist);
	ALPHA = COLOR.a * max(band, lip) * fade * (0.72 + 0.2 * h);
}
