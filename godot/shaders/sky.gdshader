shader_type sky;
// Outdoor sky dome (port of the PMREM dome in main.js): deep blue overhead, hazy bright horizon,
// warm glow round the sun, earthy bounce below. Also drives ambient light and reflections.
uniform vec3 sun_dir = vec3(-0.55, 1.0, 0.42);
uniform vec3 zenith : source_color = vec3(0.16, 0.36, 0.78);
uniform vec3 horizon : source_color = vec3(0.78, 0.86, 0.9);
uniform vec3 ground : source_color = vec3(0.28, 0.25, 0.17);
uniform vec3 backdrop : source_color = vec3(0.663, 0.839, 0.918);

void sky() {
	vec3 d = normalize(EYEDIR);
	float y = d.y;
	vec3 c = mix(horizon, zenith, smoothstep(0.0, 0.65, y));
	c = mix(ground, c, smoothstep(-0.12, 0.02, y));
	float s = max(dot(d, normalize(sun_dir)), 0.0);
	c += vec3(1.0, 0.82, 0.55) * (pow(s, 6.0) * 0.55 + pow(s, 60.0) * 1.5);
	// what the camera sees behind the diorama is the soft pale-blue backdrop of the web version;
	// lighting / reflections use the full dome
	COLOR = AT_CUBEMAP_PASS ? c : mix(backdrop, c, 0.35);
}
