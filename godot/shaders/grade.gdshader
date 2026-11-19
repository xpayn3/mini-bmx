shader_type canvas_item;
// Post pass over the 3D view (one screen copy):
//  * colour grade from the web version: split tone (warm highlights, cool shadows) + vignette
//  * speed blur: radial streaks toward the screen edges, stronger the faster you go (the centre,
//    where the rider is, stays sharp)
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float grade_amt = 1.0;
uniform float blur = 0.0;      // 0..1
uniform float speed = 0.0;     // 0..1 speed feel: colour fringing, speed lines, tighter vignette
uniform vec2 focus = vec2(0.5, 0.52);

void fragment() {
	vec2 uv = SCREEN_UV;
	vec4 c = texture(screen_tex, uv);
	if (blur > 0.001) {
		vec2 d = uv - focus;
		float edge = smoothstep(0.12, 0.62, length(d * vec2(1.6, 1.0)));
		float k = blur * edge;
		if (k > 0.002) {
			vec3 acc = c.rgb;
			float jit = fract(sin(dot(FRAGCOORD.xy, vec2(12.9898, 78.233))) * 43758.5453);
			for (int i = 1; i <= 8; i++) {
				float s = (float(i) + jit) / 8.0;
				acc += textureLod(screen_tex, uv - d * s * k * 0.09, k * 1.5).rgb;
			}
			c.rgb = acc / 9.0;
		}
	}
	if (speed > 0.01) {
		vec2 d2 = uv - focus;
		float r2 = length(d2 * vec2(1.6, 1.0));
		float edge2 = smoothstep(0.25, 0.75, r2);
		// colour fringing toward the corners (red out, blue in), like a lens pushed hard
		vec2 ca = d2 * 0.0025 * speed * edge2 * edge2;
		c.r = texture(screen_tex, uv + ca).r;
		c.b = texture(screen_tex, uv - ca).b;
		// speed lines: thin streaks rushing outward from the rider, only in the outer ring of the frame
		float ang = atan(d2.y, d2.x);
		float lanes = 140.0;
		float lane = floor(ang / 6.2831853 * lanes);
		float h = fract(sin(lane * 91.17) * 43758.5453);
		if (h > 0.6) {
			float across = abs(fract(ang / 6.2831853 * lanes) - 0.5) * 2.0;
			float thin = pow(1.0 - across, 12.0);
			float seg = fract(r2 * (1.6 + h) - TIME * (1.4 + 2.2 * h) * (0.6 + speed));
			float streak = smoothstep(0.0, 0.08, seg) * smoothstep(0.55, 0.12, seg);
			float s_amt = thin * streak * smoothstep(0.38, 0.8, r2) * speed * speed * 0.42;
			c.rgb = mix(c.rgb, vec3(1.0, 0.98, 0.94), s_amt);
		}
	}
	float l = dot(c.rgb, vec3(0.299, 0.587, 0.114));
	c.rgb += (l - 0.45) * vec3(0.035, 0.012, -0.03) * grade_amt;
	vec2 v = SCREEN_UV - 0.5;
	c.rgb *= 1.0 - dot(v, v) * (0.6 * grade_amt + 0.55 * speed);   // the frame closes in at speed
	COLOR = vec4(c.rgb, 1.0);
}
