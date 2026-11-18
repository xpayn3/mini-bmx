shader_type sky;
// Real sky: a Poly Haven HDRI (equirect), turned so its sun sits where the game's sun light is.
// The sun disc is clamped in the lighting passes: the DirectionalLight3D already carries the sun,
// so the sky must not light the scene with it a second time.
// golden > 0 (title screen): a golden-hour sky. The clear part of the HDRI is replaced by a warm
// gradient with a glow round the low sun; its clouds are kept and re-lit in sunset colours.
uniform sampler2D hdri : filter_linear, repeat_enable;
uniform float rotation = 0.0;        // radians about +Y
uniform float energy = 1.0;          // sky brightness in the view
uniform float light_energy = 1.0;    // sky brightness in ambient / reflections
uniform float sun_clamp = 6.0;       // cap on radiance in the lighting passes (kills the double sun)
uniform vec3 tint : source_color = vec3(1.0);
uniform float golden = 0.0;
uniform vec3 gold_zenith : source_color = vec3(0.25, 0.39, 0.62);
uniform vec3 gold_horizon : source_color = vec3(1.0, 0.66, 0.40);
uniform vec3 gold_sun : source_color = vec3(1.0, 0.56, 0.24);

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
	if (AT_CUBEMAP_PASS) {
		c = min(c, vec3(sun_clamp)) * light_energy;
	} else {
		c *= energy;
	}
	COLOR = c;
}
