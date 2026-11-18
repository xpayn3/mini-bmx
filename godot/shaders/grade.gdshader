shader_type canvas_item;
// Colour grade from the web version: split tone (warm highlights, cool shadows) + vignette.
uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
void fragment() {
	vec4 c = texture(screen_tex, SCREEN_UV);
	float l = dot(c.rgb, vec3(0.299, 0.587, 0.114));
	c.rgb += (l - 0.45) * vec3(0.035, 0.012, -0.03);
	vec2 d = SCREEN_UV - 0.5;
	c.rgb *= 1.0 - dot(d, d) * 0.6;
	COLOR = vec4(c.rgb, 1.0);
}
