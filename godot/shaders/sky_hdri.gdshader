shader_type sky;
// Real sky: a Poly Haven HDRI (equirect), turned so its sun sits where the game's sun light is.
// The sun disc is clamped in the lighting passes: the DirectionalLight3D already carries the sun,
// so the sky must not light the scene with it a second time.
uniform sampler2D hdri : filter_linear, repeat_enable;
uniform float rotation = 0.0;        // radians about +Y
uniform float energy = 1.0;          // sky brightness in the view
uniform float light_energy = 1.0;    // sky brightness in ambient / reflections
uniform float sun_clamp = 6.0;       // cap on radiance in the lighting passes (kills the double sun)
uniform vec3 tint : source_color = vec3(1.0);

void sky() {
	vec3 d = normalize(EYEDIR);
	float lon = atan(d.x, -d.z) - rotation;
	vec2 uv = vec2(fract(lon / TAU + 0.5), acos(clamp(d.y, -1.0, 1.0)) / PI);
	vec3 c = texture(hdri, uv).rgb * tint;
	if (AT_CUBEMAP_PASS) {
		c = min(c, vec3(sun_clamp)) * light_energy;
	} else {
		c *= energy;
	}
	COLOR = c;
}
