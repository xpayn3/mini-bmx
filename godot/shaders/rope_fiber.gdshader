// Rope bridge ropes (RopeBridgeSim.RopeMesh tubes, RopeBridge lashings / guy ropes): a three-strand twisted hemp rope
// drawn on the tube's UVs (UV.x = metres along / the tube's circumference, UV.y = round 0..1), so thick and thin
// ropes share one lay. Each strand is a rounded ridge (relief from screen-space derivatives: the tubes have no
// tangents) twisted the opposite way inside by its fibres; the grooves between strands are dark. Detail fades to
// its average once a strand is under ~2 px, so distant ropes don't shimmer.
shader_type spatial;
render_mode cull_disabled;
uniform vec3 hemp : source_color = vec3(0.6, 0.49, 0.33);
uniform float lay = 0.95;        // circumferences per strand turn (~3 diameters: a hawser-laid rope)
uniform float depth = 0.004;     // groove depth (m)
uniform float strands = 3.0;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p), f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

void fragment() {
	float t = UV.y + UV.x / lay;
	float sf = t * strands;
	float f = fract(sf);
	float sid = floor(sf);
	float px = fwidth(sf);
	float detail = 1.0 - smoothstep(0.25, 0.6, px);
	float ridge = sqrt(max(0.0, 1.0 - pow(2.0 * f - 1.0, 2.0)));
	float h = mix(0.75, ridge, detail);
	// fibres: fine lines laid the other way inside each strand, broken up by noise
	float fib = vnoise(vec2((UV.y - UV.x / lay * 0.6) * 90.0, UV.x * 6.0 + sid * 13.0));
	float fdet = 1.0 - smoothstep(0.05, 0.2, fwidth(UV.y * 90.0));
	// weathering along the rope: sun-bleached / grimy stretches, each strand its own shade
	float wear = vnoise(vec2(UV.x * 0.08, sid * 0.0 + 3.0));
	vec3 col = hemp * mix(0.78, 1.12, wear) * (0.92 + 0.16 * hash(vec2(mod(sid, strands), 7.0)) * detail);
	col *= mix(1.0, 0.82 + 0.36 * fib, fdet * detail);
	col *= mix(1.0, 0.38 + 0.62 * ridge, detail);   // dark grooves
	// relief: surface gradient from the height's screen derivatives
	vec3 dpx = dFdx(VERTEX), dpy = dFdy(VERTEX);
	float hm = h * depth + fib * 0.0006 * fdet;
	float dhx = dFdx(hm), dhy = dFdy(hm);
	vec3 n = NORMAL;
	vec3 r1 = cross(dpy, n), r2 = cross(n, dpx);
	float det = dot(dpx, r1);
	if (abs(det) > 1e-12) {
		vec3 grad = sign(det) * (dhx * r1 + dhy * r2);
		n = normalize(abs(det) * n - grad);
	}
	NORMAL = n;
	ALBEDO = col;
	ROUGHNESS = 0.92;
	SPECULAR = 0.25;
	AO = mix(1.0, 0.55 + 0.45 * ridge, detail);
}
