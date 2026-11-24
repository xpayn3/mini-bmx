// Water and dirt on the camera lens (included by grade.gdshader, fed by scripts/fx/lens_fx.gd).
// Skipped by uniform tests when the glass is clean, so it costs nothing then.
//
// Water: fx/LensDropsCs.cs simulates the drops (pinning, gravity, the air pushing them outward at speed,
// merging, beads + rivulets left behind) and lens_fx.gd draws them into `lens_map`, a half-resolution
// normal map of the water on the glass (shaders/lens_drop.gdshader; premultiplied: rg slope, b height,
// a coverage). Here the scene is refracted through it: a drop is a tiny lens, the scene inside it is the
// flipped view of what is round it, out of focus (millimetres from the glass), dark rim, highlights.
// The front element is curved: drops toward the rim are squeezed (read further out), and the glass's own
// slope tilts every drop's highlight, so the window light slides across the lens as drops run.
// Dirt: assets/textures/lens/lens_dirt.png (4K, tools/make_lens_dirt.py: R smears = ambientCG Smear004, G
// smudges / dried splashes = ambientCG SurfaceImperfections001, both CC0; B fine specks + fibres, generated),
// one screen's worth, fading in layer by layer with `lens_dust`,
// only toward the corners (an old CRT's dirty rounded corners), each layer its own colour, varying over the glass.

uniform float lens_water = 0.0;      // 1 = read lens_map
uniform sampler2D lens_map : filter_linear;
uniform float lens_dust = 0.0;       // dust on the glass, 0 clean .. 1 filthy
uniform vec3 lens_dust_col = vec3(0.62, 0.55, 0.45);
uniform sampler2D lens_dust_tex : filter_linear_mipmap;   // lens_dirt.png (see above)

float lh21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

vec3 lh13(float p) {
	vec3 p3 = fract(vec3(p) * vec3(0.1031, 0.11369, 0.13787));
	p3 += dot(p3, p3.yzx + 19.19);
	return fract(vec3((p3.x + p3.y) * p3.z, (p3.x + p3.z) * p3.y, (p3.y + p3.z) * p3.x));
}

float lvn(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(lh21(i), lh21(i + vec2(1.0, 0.0)), f.x), mix(lh21(i + vec2(0.0, 1.0)), lh21(i + vec2(1.0, 1.0)), f.x), f.y);
}

// uv = screen uv. ofs = where to read the scene from instead (aspect units), wet = water cover (softens the
// read), spec / rim = highlight / dark edge.
void lens_water_read(vec2 uv, float aspect, out vec2 ofs, out float wet, out float spec, out float rim) {
	ofs = vec2(0.0); wet = 0.0; spec = 0.0; rim = 0.0;
	vec2 c = (uv - 0.5) * vec2(aspect, 1.0);
	float rr = dot(c, c);
	vec4 lm = texture(lens_map, 0.5 + (uv - 0.5) * (1.0 + 0.1 * rr));   // curved glass: squeezed toward the rim
	if (lm.a < 0.004) return;
	vec3 e = lm.rgb / lm.a;
	vec2 n = e.xy * 2.0 - 1.0;
	float h = e.z;
	ofs = -n * h * 0.2;      // flipped view of what is round it (a drop of radius r: ~2 r)
	wet = lm.a;
	vec2 gn = c * 0.55;      // the dome's own slope
	vec3 nn = normalize(vec3(n + gn, sqrt(max(1.0 - dot(n, n), 0.0)) + 0.2));
	spec = (pow(max(dot(nn, normalize(vec3(-0.35, -0.75, 0.55))), 0.0), 40.0) * 0.9      // the sun / a window: sharp glint
		+ pow(max(dot(nn, normalize(vec3(0.0, -0.6, 0.8))), 0.0), 6.0) * 0.1             // the sky: soft sheen on top
		+ smoothstep(0.35, 0.9, abs(n.x + n.y * 0.3)) * 0.12) * lm.a;                     // a bright line down each side of a rivulet
	rim = smoothstep(0.5, 1.0, length(n)) * lm.a;
}

// Dirt on the lens. cov = how much of the pixel is dirty, blur_k = how much it smears the view (grease / smears
// scatter most), tint = its colour. Layers come in one after another as the glass gets dirtier: dust specks
// first, then smears + haze, then dried water rings.
void lens_dirt(vec2 uv, float aspect, out float cov, out float blur_k, out vec3 tint) {
	float d = lens_dust;
	vec3 t = texture(lens_dust_tex, uv).rgb;
	// the scans are whole-screen maps: each layer creeps in from its own threshold (heaviest parts first)
	float du = t.b * smoothstep(0.0, 0.3, d);                                  // specks first
	float sp = smoothstep(0.75 - 0.6 * d, 1.0 - 0.45 * d, t.g) * t.g * smoothstep(0.05, 0.5, d);   // smudges
	float sm = smoothstep(0.7 - 0.55 * d, 1.0 - 0.4 * d, t.r) * t.r * smoothstep(0.15, 0.65, d);   // smears
	// the colours: smears = the ground's dust, a little greasy-dark; specks paler; water rings chalky white;
	// a slow warm / cool drift over the glass so it is never one flat tint
	float v = lvn(vec2(uv.x * aspect, uv.y) * 2.2 + 7.3) * 0.7 + lvn(vec2(uv.x * aspect, uv.y) * 6.0) * 0.3;
	vec3 var = mix(vec3(1.06, 0.98, 0.9), vec3(0.92, 0.97, 1.05), v);
	vec3 c_sm = lens_dust_col * vec3(0.85, 0.82, 0.78) * var;
	vec3 c_du = mix(lens_dust_col, vec3(0.93, 0.91, 0.86), 0.5) * var;
	vec3 c_sp = mix(lens_dust_col, vec3(0.88, 0.86, 0.8), 0.3) * var;   // dried splashes: dusty, a touch chalky
	sm *= 1.0; du *= 0.5; sp *= 0.85;
	float sum = sm + du + sp;
	tint = sum > 1e-4 ? (c_sm * sm + c_du * du + c_sp * sp) / sum : lens_dust_col;
	// only toward the corners, like an old CRT's rounded screen; the dirtier, the further in it creeps
	vec2 e = abs(uv - 0.5) * 2.0;
	float r = pow(pow(e.x, 4.0) + pow(e.y, 4.0), 0.25);
	float corner = smoothstep(0.42 - 0.2 * d, 1.0, r);
	cov = clamp(sum, 0.0, 1.0) * corner;
	blur_k = clamp(sm * 1.2 + sp * 0.7 + du * 0.2, 0.0, 1.0) * corner;
}