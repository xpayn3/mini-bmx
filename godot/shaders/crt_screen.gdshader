// The intro's old CRT TV (scripts/ui/crt_intro.gd, model assets/tv/tv.fbx): the model's own PBR maps, and on its
// glass (one UV island, rotated: UV.y runs left -> right, UV.x bottom -> top): live TV static that never settles
// (grain re-rolled every frame, drifting bands of heavier snow, a rolling bar) with the RUNOUT lettering (a baked
// texture, crt_tv.gd) coming through it, wobbling, jittering, slipping sync and splitting colour; scanlines, an RGB
// shadow mask, ghosting, and the power on / off: a white line that opens up, and on switch-off squeezes to a line,
// then a dot that fades.
shader_type spatial;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic;
uniform sampler2D orm_tex : hint_default_white, filter_linear_mipmap_anisotropic;   // R occlusion, G roughness, B metallic
uniform sampler2D text_tex : filter_linear_mipmap, repeat_disable;   // white lettering on black (R)
uniform vec4 text_box = vec4(0.07, 0.33, 0.93, 0.67);   // where it sits on the glass: x0 y0 x1 y1
uniform vec4 island = vec4(0.680, 0.334, 0.891, 0.607);   // glass UV box: x0 y0 x1 y1
uniform float vopen = 0.0;      // picture height 0..1 (tiny = the white line)
uniform float hopen = 1.0;      // picture width 0..1 (switch-off squeezes it to a dot)
uniform float bright = 0.0;     // picture brightness
uniform float flash = 0.0;      // white of the power line
uniform float snow = 0.0;       // static
uniform float glitch = 0.0;     // tearing + colour split
uniform float roll = 0.0;       // vertical hold slip
uniform float afterglow = 0.0;  // the dot left after switch-off
uniform float card_color = 0.0;   // 1: the picture is a colour card (studio / notice), drawn as it is
uniform float gain = 1.35;      // screen brightness (the outdoor TV needs more to read in daylight)

float hash(vec2 p) {   // sin-free: no diagonal patterns at large inputs
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float vnoise(float x) { float i = floor(x); float f = fract(x); f = f * f * (3.0 - 2.0 * f); return mix(hash(vec2(i, 0.3)), hash(vec2(i + 1.0, 0.3)), f); }

// the lettering: white-hot at the top of the letters to deep red below, faint halo
vec3 picture(vec2 p, float lod) {
	vec2 q = (p - text_box.xy) / (text_box.zw - text_box.xy);
	if (q.y < 0.0 || q.y > 1.0 || q.x < 0.0 || q.x > 1.0) return vec3(0.0);
	if (card_color > 0.5) {
		vec3 cc = textureLod(text_tex, q, min(lod, 2.0)).rgb;
		return cc * 1.5 + textureLod(text_tex, q, min(lod, 2.0) + 3.0).rgb * 0.35;
	}
	float a = textureLod(text_tex, q, lod).r;
	float halo = textureLod(text_tex, q, lod + 3.0).r;
	vec3 hot = mix(vec3(1.0, 0.82, 0.74), vec3(0.85, 0.06, 0.04), smoothstep(0.15, 0.62, q.y));
	return hot * a + vec3(0.6, 0.04, 0.02) * halo * 0.6;
}

// TV snow: new grain every frame, heavier in bands that drift and change, grain size flickers between two scales
float static_at(vec2 g, float t) {
	float fr = mod(floor(t * 30.0), 997.0);
	float cell = hash(vec2(fr, 7.1)) > 0.5 ? 1.0 : 1.6;
	vec2 px = floor(g * vec2(320.0, 240.0) / cell);
	float n = hash(px + vec2(fr * 13.1, fr * 7.7));
	float bands = vnoise(g.y * 9.0 + t * 1.7) * 0.6 + vnoise(g.y * 31.0 - t * 4.3) * 0.4;
	float streak = hash(vec2(floor(g.y * 240.0), fr));   // single bright / dark lines
	n = n * (0.55 + 0.6 * bands) + (streak > 0.985 ? 0.5 : 0.0) - (streak < 0.02 ? 0.3 : 0.0);
	return clamp(n, 0.0, 1.0);
}

void fragment() {
	vec3 orm = texture(orm_tex, UV).rgb;
	ALBEDO = texture(albedo_tex, UV).rgb;
	NORMAL_MAP = texture(normal_tex, UV).rgb;
	AO = orm.r;
	ROUGHNESS = orm.g;
	METALLIC = orm.b;
	vec2 g = vec2((UV.y - island.y) / (island.w - island.y), 1.0 - (UV.x - island.x) / (island.z - island.x));
	float lod = max(0.0, log2(max(length(dFdx(g)), length(dFdy(g))) * 1024.0));   // picture mip (outside the branch)
	if (g.x > -0.02 && g.x < 1.02 && g.y > -0.02 && g.y < 1.02) {
		vec2 c = g - 0.5;
		vec2 b = c * (1.0 + 0.28 * dot(c, c));                   // barrel: the picture curves with the tube
		vec2 p = b / vec2(max(hopen, 1e-3), max(vopen, 1e-3));
		float inside = step(abs(p.x), 0.5) * step(abs(p.y), 0.5);
		p += 0.5;
		// sync trouble: the picture slips sideways in bands (always a little, hard while glitching), wobbles line by
		// line, and now and then jumps vertically
		float t = TIME;
		float band = floor(p.y * 14.0 + floor(t * 9.0) * 3.1);
		float tear = (0.25 + glitch) * 0.07 * (hash(vec2(band, floor(t * 18.0))) - 0.5) * step(0.82 - glitch * 0.3, hash(vec2(band * 0.37, floor(t * 9.0))));
		float wave = 0.004 * sin(p.y * 38.0 + t * 7.0) * vnoise(t * 0.8) + 0.0016 * sin(p.y * 260.0 + t * 50.0) * (0.5 + 3.0 * glitch);
		float hjump = step(0.93, hash(vec2(floor(t * 6.0), 2.0))) * (hash(vec2(floor(t * 6.0), 5.0)) - 0.5) * 0.05;
		vec2 tp = p + vec2(tear + wave + hjump, step(0.95, hash(vec2(floor(t * 4.0), 9.0))) * 0.03);
		tp.y = fract(tp.y + roll);
		float ca = 0.003 + glitch * 0.014 + abs(hjump) * 0.2;
		vec3 col;
		col.r = picture(tp + vec2(ca, 0.0), lod).r;
		col.g = picture(tp, lod).g;
		col.b = picture(tp - vec2(ca, 0.0), lod).b;
		col += 0.22 * picture(tp - vec2(0.018, 0.0), lod) * vec3(0.6, 0.7, 1.0);   // ghost
		col *= 0.75 + 0.35 * vnoise(t * 11.0);                                  // the signal breathes
		float st = static_at(vec2(p.x + tear * 0.5, p.y), t);
		float lvl = 0.22 + snow;
		col = col * (1.15 - 0.4 * lvl) + vec3(st) * lvl * vec3(0.85, 0.9, 1.0);
		col += vec3(0.010, 0.014, 0.020);                          // a lit tube's black is never black
		col *= 0.58 + 0.42 * pow(sin(p.y * PI * 240.0) * 0.5 + 0.5, 0.7);   // scanlines
		float m = mod(floor(g.x * 620.0), 3.0);                               // shadow mask
		col *= vec3(m == 0.0 ? 1.0 : 0.7, m == 1.0 ? 1.0 : 0.7, m == 2.0 ? 1.0 : 0.7) * 1.2;
		float bar = exp(-pow((fract(g.y * 0.6 - TIME * 0.11) - 0.5) * 5.0, 2.0));   // rolling hum bar
		col *= 1.0 + 0.22 * bar;
		col *= smoothstep(0.80, 0.30, length(c * vec2(1.05, 1.15)));            // darker tube edges
		col *= bright * inside;
		col += inside * flash * vec3(0.85, 0.92, 1.0) * 3.0;
		col += afterglow * exp(-dot(c, c) * 1400.0) * vec3(0.8, 0.9, 1.0) * 6.0;
		ALBEDO *= 0.35;                 // dark phosphor glass
		ROUGHNESS = 0.08;
		METALLIC = 0.0;
		SPECULAR = 0.7;
		EMISSION = col * gain;
	}
}
