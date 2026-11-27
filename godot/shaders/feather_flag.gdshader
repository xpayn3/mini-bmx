// Feather flags (scripts/world/checkpoint_flags.gd): the whole flag turns on its pole to stream downwind, the cloth
// ripples from the pole to the free edge, bellies out with the gusts and flutters at its edge, all from the shared wind
// globals (atmos.gdshaderinc). Nothing is stored per flag but a design row and a seed (INSTANCE_CUSTOM.xy).
// Mesh: cloth COLOR.a = 1, UV = the print (up, across the flag's box), UV2 = the grid (t up, s across); pole COLOR.a = 0, UV.y = 0.
shader_type spatial;
render_mode cull_disabled;
#include "res://shaders/atmos.gdshaderinc"

uniform sampler2D board_tex : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform float designs = 4.0;
uniform float cloth_w = 0.8;
uniform float pole_h = 3.8;   // CheckpointFlags.H_POLE
uniform float cloth_h = 2.8;

varying float v_kind;     // 1 cloth, 0 pole / cord
varying flat float v_row;
varying float v_fold;     // how much the cloth is turned away right here (darkens the folds)

// sideways offset (m) of the cloth point at (t, s) from its flat plane
float disp(float t, float s, float T, float g, float ws, float ph) {
	float x = s * cloth_w;
	float y = t * cloth_h;
	// held along the pole side (s = 0, the straight part and the arc), and at the top corner where both meet
	float w = pow(s, 1.2) * (1.0 - smoothstep(0.88, 1.0, t)) * mix(0.75, 1.0, smoothstep(0.0, 0.2, t));
	// fixed rates: a gust only makes the waves bigger (scaling the rate by the gust whips it faster as time grows)
	float a = 0.045 + 0.06 * ws + 0.1 * g;
	float wave = sin(7.0 * x - 6.3 * T + 1.6 * y + ph) + 0.45 * sin(12.5 * x + 3.1 * y - 10.7 * T + ph * 1.7)
		+ 0.25 * sin(19.0 * x - 2.0 * y - 15.3 * T + ph * 2.3) * s;
	float belly = (0.05 + 0.12 * g) * sin(3.14159 * clamp(t * 1.25, 0.0, 1.0));
	return w * (a * wave + belly);
}

void vertex() {
	vec3 base = MODEL_MATRIX[3].xyz;
	float ph = INSTANCE_CUSTOM.y * 6.2832;
	v_row = INSTANCE_CUSTOM.x;
	float T = atm_wind.z;
	float ws = atm_wind.w;
	float g = wind_gust(base.xz);
	float k = min(1.0, COLOR.a * 2.0);   // 0 = the pole and the cord's pole end: never moves
	v_kind = step(0.75, COLOR.a);
	vec3 p = VERTEX;
	vec3 n = NORMAL;
	v_fold = 0.0;
	if (k > 0.0) {
		float t = UV2.x;
		float s = UV2.y;
		float e = 0.02;
		float z = disp(t, s, T, g, ws, ph);
		float dzs = (disp(t, s + e, T, g, ws, ph) - z) / (e * cloth_w);
		float dzt = (disp(t + e, s, T, g, ws, ph) - z) / (e * cloth_h);
		p.z += z * k;
		// the cloth can't stretch: as it waves its free edge comes in a little towards the pole
		p.x -= abs(z) * 0.35 * s * k;
		if (v_kind > 0.5) {
			n = normalize(vec3(-dzs, -dzt, 1.0));
			v_fold = clamp(abs(dzs) * 0.6, 0.0, 1.0);
		}
	}
	// the fibreglass pole bows downwind (the cloth is on local +x = downwind): a cantilever bend, ~ height^2, more in
	// a gust, swaying back and forth a little as the gusts come and go; everything above moves with it
	float q = clamp(p.y / pole_h, 0.0, 1.0);
	float bend = (0.05 + 0.08 * ws + 0.3 * g) + 0.05 * (0.4 + g) * sin(T * 1.7 + ph * 1.3) + 0.02 * sin(T * 3.1 + ph);
	p.x += bend * q * q;
	p.y -= 0.45 * bend * bend * q * q * q / pole_h;   // (bending, not stretching: the tip comes down a little)
	// the whole flag swings round its pole to stream downwind (the cloth is on local +x), with a lazy wander
	float a = atan(atm_wind.y, atm_wind.x) + 0.22 * sin(T * 0.53 + ph) + 0.12 * g * sin(T * 1.9 + ph * 2.1);
	float ca = cos(a);
	float sa = sin(a);
	VERTEX = vec3(p.x * ca - p.z * sa, p.y, p.x * sa + p.z * ca);
	NORMAL = vec3(n.x * ca - n.z * sa, n.y, n.x * sa + n.z * ca);
}

void fragment() {
	if (v_kind > 0.5) {
		// this design's column in the atlas (drawn upright: pole left, top up), inset a hair so neighbours never bleed in
		vec2 uv = vec2((v_row + 0.004 + clamp(UV.y, 0.0, 1.0) * 0.992) / designs, 1.0 - UV.x);
		vec3 col = texture(board_tex, uv).rgb;
		col *= 1.0 - 0.25 * v_fold;
		ALBEDO = col;
		ROUGHNESS = 0.72;
		SPECULAR = 0.25;
		// thin polyester: light comes through it with the sun behind (its own colour)
		BACKLIGHT = col * 0.3;
	} else {
		ALBEDO = vec3(0.035, 0.036, 0.04);   // black powder-coated metal
		METALLIC = 0.6;
		ROUGHNESS = 0.42;
	}
}
