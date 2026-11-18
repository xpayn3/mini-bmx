shader_type canvas_item;
// Post pass over the 3D view (one screen copy):
//  * colour grade from the web version: split tone (warm highlights, cool shadows) + vignette
//  * speed blur: radial streaks toward the screen edges, stronger the faster you go (the centre,
//    where the rider is, stays sharp)
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float grade_amt = 1.0;
uniform float blur = 0.0;      // 0..1
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
	float l = dot(c.rgb, vec3(0.299, 0.587, 0.114));
	c.rgb += (l - 0.45) * vec3(0.035, 0.012, -0.03) * grade_amt;
	vec2 v = SCREEN_UV - 0.5;
	c.rgb *= 1.0 - dot(v, v) * 0.6 * grade_amt;
	COLOR = vec4(c.rgb, 1.0);
}
