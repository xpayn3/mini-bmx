// Wildflowers, grass clumps, ferns, mushrooms: instance colour only on the tinted parts (UV.x = tint).
// Wind gusts roll over them as waves and the bike parts them as it rides through (shaders/atmos);
// thin blades let a little sun through from behind, and cloud shadows drift over them.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_burley, specular_schlick_ggx, world_vertex_coords;
#include "res://shaders/atmos.gdshaderinc"

uniform float roughness = 0.55;
uniform float stiff = 1.0;
// golden-hour backlight: blades between the camera and a low sun glow in their own colour
uniform float scatter = 0.9;
varying vec3 v_col;
varying vec3 v_world;

void vertex() {
	v_col = COLOR.rgb * mix(vec3(1.0), INSTANCE_CUSTOM.rgb, UV.x);
	vec3 base = MODEL_MATRIX[3].xyz;
	VERTEX += wind_bend(base, max(VERTEX.y - base.y, 0.0), stiff, 1.0);
	v_world = VERTEX;
}

void fragment() {
	ALBEDO = v_col;
	ROUGHNESS = roughness;
	SPECULAR = 0.35;
}

void light() {
	DIFFUSE_LIGHT += atmos_diffuse(NORMAL, LIGHT, ATTENUATION * LIGHT_COLOR, LIGHT_IS_DIRECTIONAL, v_world, 0.35);
	if (scatter > 0.0 && LIGHT_IS_DIRECTIONAL) {
		float bl = clamp(dot(-VIEW, LIGHT), 0.0, 1.0);
		bl = bl * bl * bl;
		float sun_y = (INV_VIEW_MATRIX * vec4(LIGHT, 0.0)).y;
		float low = mix(0.25, 1.0, 1.0 - smoothstep(0.15, 0.75, sun_y));
		vec3 tint = ALBEDO / max(max(ALBEDO.r, max(ALBEDO.g, ALBEDO.b)), 0.04);
		DIFFUSE_LIGHT += bl * low * scatter * tint * atmos_light_col(ATTENUATION * LIGHT_COLOR, true, v_world);
	}
}
