shader_type sky;
// Real sky: a Poly Haven HDRI (equirect), turned so its sun sits where the game's sun light is.
// The sun disc is clamped in the lighting passes: the DirectionalLight3D already carries the sun,
// so the sky must not light the scene with it a second time.
// golden > 0 (title screen): a golden-hour sky. The clear part of the HDRI is replaced by a warm
// gradient with a glow round the low sun; its clouds are kept and re-lit in sunset colours.
uniform sampler2D hdri : filter_linear, repeat_enable;
uniform float rotation = 0.0;        // radians about +Y
// second HDRI, crossfaded in by mix_b (the ride picks the photo by the sun's height)
uniform sampler2D hdri_b : filter_linear, repeat_enable;
uniform float rotation_b = 0.0;
uniform float mix_b = 0.0;
uniform float energy = 1.0;          // sky brightness in the view
uniform float light_energy = 1.0;    // sky brightness in ambient / reflections
uniform float sun_clamp = 6.0;       // cap on radiance in the lighting passes (kills the double sun)
uniform vec3 tint : source_color = vec3(1.0);
uniform float golden = 0.0;
uniform float sunny = 0.0;            // ride: white bright clouds, a richer blue (what you see only)
uniform vec3 gold_zenith : source_color = vec3(0.25, 0.39, 0.62);
uniform vec3 gold_horizon : source_color = vec3(1.0, 0.66, 0.40);
uniform vec3 gold_sun : source_color = vec3(1.0, 0.56, 0.24);
// night > 0: a dark blue sky with stars, the HDRI's clouds dimmed, and the moon where the light is
// (at night the DirectionalLight3D is the moon)
uniform float night = 0.0;

float hash3(vec3 p) {
	p = fract(p * vec3(443.897, 441.423, 437.195));
	p += dot(p, p.yzx + 19.19);
	return fract((p.x + p.y) * p.z);
}

float vnoise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash3(vec3(i, 7.0)), b = hash3(vec3(i + vec2(1.0, 0.0), 7.0));
	float c = hash3(vec3(i + vec2(0.0, 1.0), 7.0)), e = hash3(vec3(i + vec2(1.0), 7.0));
	return mix(mix(a, b, f.x), mix(c, e, f.x), f.y);
}

// the moon's face: a disc of radius MOON_R (rad) round md, grey maria (dark seas), a few bright craters,
// darker towards the rim. Returns rgb (0 outside), alpha in .a
const float MOON_R = 0.026;
vec4 moon_disc(vec3 d, vec3 md) {
	float mu = dot(d, md);
	if (mu < cos(MOON_R * 1.05)) return vec4(0.0);
	vec3 t = normalize(cross(md, abs(md.y) > 0.95 ? vec3(1.0, 0.0, 0.0) : vec3(0.0, 1.0, 0.0)));
	vec3 b = cross(md, t);
	vec2 q = vec2(dot(d, t), dot(d, b)) / MOON_R;   // -1..1 across the disc
	float r = length(q);
	float edge = 1.0 - smoothstep(0.96, 1.02, r);
	float limb = sqrt(max(1.0 - r * r, 0.0));
	float maria = vnoise(q * 2.2 + 3.1) * 0.6 + vnoise(q * 5.0 + 9.7) * 0.4;
	float seas = smoothstep(0.42, 0.68, maria);
	float spots = smoothstep(0.78, 0.95, vnoise(q * 11.0 + 1.3));
	vec3 col = vec3(0.92, 0.93, 0.95) * mix(1.0, 0.58, seas) + vec3(0.12) * spots;
	col *= 0.55 + 0.45 * limb;
	return vec4(col, edge);
}

vec3 night_sky(vec3 d, vec3 hd) {
	float up = clamp(d.y, 0.0, 1.0);
	// a moonlit night: deep blue overhead, a lighter blue band along the horizon (never pitch black)
	vec3 sky = mix(vec3(0.085, 0.11, 0.19), vec3(0.018, 0.03, 0.075), pow(up, 0.5));
	vec3 md = normalize(LIGHT0_DIRECTION);
	float mu = dot(d, md);
	sky += vec3(0.07, 0.1, 0.2) * pow(max(mu, 0.0), 22.0) * 0.6;    // the sky lit round the moon
	sky += vec3(0.5, 0.55, 0.7) * pow(max(mu, 0.0), 900.0) * 0.6;     // halo close round the disc
	// stars: one candidate per cell of a direction grid, most cells empty
	vec3 g = d * 220.0;
	vec3 cell = floor(g);
	float h = hash3(cell);
	if (h > 0.985 && d.y > 0.02) {
		vec3 sp = cell + vec3(hash3(cell + 1.7), hash3(cell + 3.1), hash3(cell + 5.3));
		float dist = length(g - sp);
		float b = smoothstep(0.55, 0.0, dist) * (h - 0.985) / 0.015;
		sky += vec3(0.85, 0.9, 1.0) * b * 2.2 * smoothstep(0.02, 0.25, d.y);
	}
	// clouds from the HDRI, dark and faintly moonlit
	float blue = clamp((hd.b - hd.r) / max(hd.b, 1e-3), 0.0, 1.0);
	float cloud = (1.0 - smoothstep(0.08, 0.32, blue)) * smoothstep(0.0, 0.06, d.y);
	float lum = dot(hd, vec3(0.3, 0.59, 0.11));
	vec3 cloud_c = vec3(0.06, 0.07, 0.1) * (0.6 + lum * 0.25) + vec3(0.14, 0.16, 0.24) * pow(max(mu, 0.0), 14.0);
	sky = mix(sky, cloud_c, cloud * 0.85);
	sky = mix(sky, vec3(0.05, 0.065, 0.11), smoothstep(0.0, -0.08, d.y));
	return sky;
}

vec3 golden_sky(vec3 d, vec3 hd) {
	vec3 sd = normalize(LIGHT0_DIRECTION);
	float mu = dot(d, sd);
	float up = clamp(d.y, 0.0, 1.0);
	float hz = pow(1.0 - up, 5.0);
	// side of the sky the sun is on: warmer, brighter
	float toward = clamp(dot(normalize(d.xz + vec2(1e-4)), normalize(sd.xz + vec2(1e-4))) * 0.5 + 0.5, 0.0, 1.0);
	vec3 horizon = mix(vec3(0.86, 0.58, 0.55), gold_horizon, toward * toward);
	vec3 sky = mix(gold_zenith, horizon, hz);
	sky += gold_sun * (pow(max(mu, 0.0), 8.0) * 0.55 + pow(max(mu, 0.0), 90.0) * 1.6) * (0.4 + hz);
	// clouds from the HDRI: clear sky is blue, clouds are grey/white
	float lum = dot(hd, vec3(0.3, 0.59, 0.11));
	float blue = clamp((hd.b - hd.r) / max(hd.b, 1e-3), 0.0, 1.0);
	float cloud = (1.0 - smoothstep(0.06, 0.3, blue)) * smoothstep(0.0, 0.06, d.y);
	float lit = clamp(lum / (lum + 0.9), 0.0, 1.0);
	vec3 cloud_c = mix(vec3(0.42, 0.33, 0.42), mix(vec3(0.98, 0.62, 0.48), vec3(1.0, 0.78, 0.5), toward), lit);
	cloud_c *= 0.55 + 0.9 * lit + pow(max(mu, 0.0), 6.0) * 1.2;
	sky = mix(sky, cloud_c, cloud * 0.85);
	// below the horizon: a warm haze (seen only past the far hills)
	sky = mix(sky, horizon * 0.8, smoothstep(0.0, -0.08, d.y));
	return sky;
}

void sky() {
	vec3 d = normalize(EYEDIR);
	float lon = atan(d.x, -d.z) - rotation;
	vec2 uv = vec2(fract(lon / TAU + 0.5), acos(clamp(d.y, -1.0, 1.0)) / PI);
	vec3 hd = texture(hdri, uv).rgb;
	if (mix_b > 0.0) {
		float lon_b = atan(d.x, -d.z) - rotation_b;
		vec2 uv_b = vec2(fract(lon_b / TAU + 0.5), uv.y);
		hd = mix(hd, texture(hdri_b, uv_b).rgb, mix_b);
	}
	vec3 c = hd * tint;
	if (golden > 0.0) {
		vec3 g = golden_sky(d, min(hd, vec3(3.0)));
		if (!AT_CUBEMAP_PASS) {
			// the sun disc itself
			float mu = dot(d, normalize(LIGHT0_DIRECTION));
			g += vec3(1.0, 0.8, 0.55) * smoothstep(0.99955, 0.9998, mu) * 14.0;
		}
		c = mix(c, g, golden);
	}
	if (night > 0.0) {
		vec3 n = night_sky(d, min(hd, vec3(3.0)));
		if (!AT_CUBEMAP_PASS) {
			// the moon itself, bright enough to bloom; clouds pass in front of it
			vec4 m = moon_disc(d, normalize(LIGHT0_DIRECTION));
			float blue = clamp((hd.b - hd.r) / max(hd.b, 1e-3), 0.0, 1.0);
			float cl = (1.0 - smoothstep(0.08, 0.32, blue)) * 0.75;
			n = mix(n, m.rgb * 7.0, m.a * (1.0 - cl));
		}
		c = mix(c, n, night);
	}
	if (sunny > 0.0 && !AT_CUBEMAP_PASS && d.y > -0.02) {
		// keep the photo's brightness, swap its colour: clear patches deep blue, clouds clean white
		vec3 lw = vec3(0.2126, 0.7152, 0.0722);
		float lum = dot(hd, lw);
		float blue = clamp((hd.b - hd.r) / max(hd.b, 1e-3), 0.0, 1.0);
		float cloud = 1.0 - smoothstep(0.08, 0.32, blue);
		float up = clamp(d.y, 0.0, 1.0);
		vec3 bc = mix(vec3(0.50, 0.72, 1.0), vec3(0.16, 0.40, 0.95), pow(up, 0.55));
		vec3 clear_c = bc * (lum * 1.15 / max(dot(bc, lw), 1e-3));
		vec3 cloud_c = vec3(1.0, 0.99, 0.97) * (lum * 1.35 + 0.08);
		c = mix(c, mix(clear_c, cloud_c, cloud), sunny);
	}
	if (AT_CUBEMAP_PASS) {
		c = min(c, vec3(sun_clamp)) * light_energy;
	} else {
		c *= energy;
	}
	COLOR = c;
}
