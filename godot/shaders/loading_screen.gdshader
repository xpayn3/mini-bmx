shader_type canvas_item;
// the loading screen's backdrop (ui/loading_screen.gd): the sky of the picked hour, a sun or moon, and layers of
// mountain ridges with pines sliding past, nearer ones faster. t is fed from the script (it runs on real time).

uniform float t = 0.0;
uniform float aspect = 1.7778;
uniform float seed = 0.0;
uniform vec3 sky_top : source_color = vec3(0.08, 0.11, 0.24);
uniform vec3 sky_low : source_color = vec3(0.98, 0.55, 0.28);
uniform vec3 ridge_far : source_color = vec3(0.55, 0.34, 0.38);
uniform vec3 ridge_near : source_color = vec3(0.035, 0.04, 0.065);
uniform vec3 sun_col : source_color = vec3(1.0, 0.82, 0.5);
uniform vec2 sun_pos = vec2(0.68, 0.5);
uniform float stars = 0.0;
uniform float reveal = 1.0;   // 1 = covering the screen; down to 0 = wiped away on a slant

float hash(float n) { return fract(sin(n * 127.1 + seed) * 43758.5453); }
float noise(float x) {
	float i = floor(x);
	float f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(hash(i), hash(i + 1.0), f);
}
float ridge(float x) {
	float v = 0.0;
	float a = 0.55;
	for (int i = 0; i < 5; i++) {
		float n = noise(x);
		v += a * (1.0 - abs(n * 2.0 - 1.0));
		x = x * 2.13 + 7.3;
		a *= 0.46;
	}
	return v;
}
// a row of pines on a ridge: the height they add at x
float pines(float x, float h) {
	float c = floor(x);
	float f = fract(x) - 0.5;
	float k = hash(c * 3.7);
	float tall = h * (0.45 + 0.55 * k) * step(0.28, hash(c * 9.1));
	float body = max(0.0, 1.0 - abs(f) * 2.3);
	return tall * body * (0.82 + 0.18 * abs(fract(body * 4.0) - 0.5) * 2.0);
}

void fragment() {
	vec2 uv = UV;
	float x = uv.x * aspect;
	float up = 1.0 - uv.y;
	vec3 col = mix(sky_low, sky_top, smoothstep(0.22, 0.95, up));
	vec2 d = vec2((uv.x - sun_pos.x) * aspect, uv.y - sun_pos.y);
	float r = length(d);
	col += sun_col * (exp(-r * 4.5) * 0.45 + exp(-r * 22.0) * 0.5);
	col = mix(col, sun_col, smoothstep(0.062, 0.058, r));
	// stars twinkle high up at night
	vec2 g = floor(vec2(x, uv.y) * 150.0);
	float s = hash(g.x + g.y * 311.0);
	col += vec3(step(0.9925, s) * stars * smoothstep(0.35, 0.7, up) * (0.5 + 0.5 * sin(t * 2.5 + s * 900.0)));
	// long thin clouds
	float cl = noise(x * 2.2 - t * 0.05 + noise(uv.y * 38.0) * 2.0) * noise(uv.y * 26.0 + 4.0);
	col = mix(col, mix(sun_col, sky_low, 0.5), smoothstep(0.42, 0.75, cl) * 0.35 * smoothstep(0.25, 0.5, up) * (1.0 - stars));
	for (int i = 0; i < 5; i++) {
		float k = float(i) / 4.0;
		float px = x * mix(1.5, 0.8, k) + t * mix(0.012, 0.2, k * k) + float(i) * 13.7;
		float h = mix(0.43, 0.1, k) + (ridge(px) - 0.5) * mix(0.34, 0.17, k);
		if (i > 1) h += pines(px * mix(55.0, 24.0, k), mix(0.016, 0.075, k * k));
		float m = smoothstep(h + 0.0015, h - 0.0015, up);
		vec3 rc = mix(ridge_far, ridge_near, pow(k, 0.7));
		rc = mix(rc, sky_low, (1.0 - k) * 0.35 * smoothstep(h - 0.16, h, up) + (1.0 - k) * 0.2);   // haze in the valleys
		rc = mix(rc, mix(rc, sky_low, 0.35), smoothstep(h - 0.12, h - 0.3, up) * (1.0 - k));
		col = mix(col, rc, m);
	}
	// shade for the type: the left side and the foot of the screen, a soft vignette
	col *= 1.0 - 0.5 * smoothstep(0.62, 0.0, uv.x);
	col *= 1.0 - 0.45 * smoothstep(0.74, 1.0, uv.y);
	col *= 1.0 - 0.3 * smoothstep(0.55, 1.1, length(uv - 0.5));
	col += (fract(sin(dot(FRAGCOORD.xy + vec2(t * 60.0), vec2(12.9898, 78.233))) * 43758.5453) - 0.5) * 0.018;
	// leaving: a slanted edge sweeps across, a yellow stripe on it
	float edge = uv.x - uv.y * 0.22 + 0.22;
	float cut = (1.0 - reveal) * 1.34 - 0.06;
	float a = smoothstep(cut - 0.001, cut + 0.001, edge);
	float stripe = (1.0 - smoothstep(cut + 0.045, cut + 0.047, edge)) * step(0.0001, 1.0 - reveal);
	col = mix(col, vec3(1.0, 0.824, 0.122), stripe);
	COLOR = vec4(col, a);
}
