shader_type spatial;
// The helmets' goggle model (helmet_goggles in assets/helmets/*.glb, one textured mesh) with its lens recoloured:
// the lens is the magenta part of the model's texture; it becomes a mirrored lens in `lens_tint` (alpha < 1 = a clear
// lens: pale, glassy). Frame, foam and strap keep the texture. Used for the GOGGLES lens cards (GoggleLens.make_goggles).
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform vec4 lens_tint : source_color = vec4(1.0, 0.5, 0.2, 1.0);
uniform float frame_metal = 0.45;

void fragment() {
	vec3 c = texture(albedo_tex, UV).rgb;
	float lens = smoothstep(0.18, 0.34, min(c.r, c.b) - c.g);
	float clear = 1.0 - lens_tint.a;
	// a mirrored lens: the tint over a dark base, glossy; a clear lens: pale blue-white glass
	vec3 lens_c = mix(lens_tint.rgb * 0.62, vec3(0.78, 0.84, 0.9), clear);
	// a soft mirror gradient across the lens (lighter at the top), like a real iridium coat
	lens_c *= mix(0.75, 1.15, smoothstep(-0.03, 0.04, VERTEX.y));
	ALBEDO = mix(c, lens_c, lens);
	METALLIC = mix(frame_metal, mix(0.75, 0.15, clear), lens);
	ROUGHNESS = mix(0.62, 0.05, lens);
	SPECULAR = mix(0.4, 0.9, lens);
	CLEARCOAT = lens;
	CLEARCOAT_ROUGHNESS = 0.03;
}
