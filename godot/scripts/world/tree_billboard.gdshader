// Card trees' LOD2 in the world chunks (world/card_tree.gd): each tree crown as one quad turned to the camera about its
// upright axis, showing a crown-only cell of assets/textures/tree_cards/impostors.png (baked from the card trees by
// tools/bake_tree_impostors.tscn, white: tinted here by the instance's own colour, like the cards). Shares the crown
// list's instance buffer: the quad's place in the instance's own units comes from the cell (y0 / h / w, impostors.json).
// Lit with a rounded normal (out of the quad's middle, toward the camera, a little up). deco_fade.gdshaderinc mode 5.
shader_type spatial;
render_mode world_vertex_coords, cull_disabled, diffuse_burley, specular_schlick_ggx;
#include "res://shaders/atmos.gdshaderinc"
#include "res://shaders/deco_fade.gdshaderinc"
instance uniform float fade_mode = 5.0;
uniform sampler2D atlas : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform float cells = 8.0;
uniform float cell0 = 4.0;     // this kind's first crown cell
uniform float variants = 2.0;
uniform vec3 quad = vec3(0.0, 3.0, 1.5);   // y0, h (x the instance's y scale), w (x its x scale)
uniform float sway = 0.02;
varying flat vec3 v_origin;
varying flat float v_cell;
varying vec3 v_col;
varying vec3 v_right;
varying vec3 v_fwd;
varying vec3 v_world;
varying flat float v_snow;   // (deco_cards: the crown's snow, custom a < 0)

void vertex() {
	vec3 o = MODEL_MATRIX[3].xyz;
	v_origin = o;
	v_col = INSTANCE_CUSTOM.rgb;
	v_snow = clamp(-INSTANCE_CUSTOM.a, 0.0, 1.0);
	float sy = length(MODEL_MATRIX[1].xyz);
	float sx = length(MODEL_MATRIX[0].xyz);
	vec3 to = CAMERA_POSITION_WORLD - o;
	to.y = 0.0;
	vec3 f = normalize(to + vec3(1e-4, 0.0, 0.0));
	vec3 r = vec3(f.z, 0.0, -f.x);
	float y = quad.x * sy + (1.0 - UV.y) * quad.y * sy;
	VERTEX = o + r * (UV.x - 0.5) * quad.z * sx + vec3(0.0, y, 0.0);
	vec3 wb = wind_bend(o, 1.0, 1.0, 0.0);
	VERTEX.xz += wb.xz * max(y, 0.0) * sway;
	NORMAL = f;
	v_right = r;
	v_fwd = f;
	v_cell = cell0 + min(floor(fract(sin(dot(o.xz, vec2(12.9898, 78.233))) * 43758.5453) * variants), variants - 1.0);
	if (deco_fold(o, fade_mode, PROJECTION_MATRIX[3][3] > 0.5)) VERTEX = o;
	v_world = VERTEX;
}

void fragment() {
	if (deco_cut_pair(v_origin, fade_mode, FRAGCOORD.xy, PROJECTION_MATRIX[3][3] > 0.5)) discard;
	vec2 uv = vec2((v_cell + clamp(UV.x, 0.002, 0.998)) / cells, UV.y);
	vec4 t = texture(atlas, uv);
	float lod = textureQueryLod(atlas, uv).x;
	ALPHA = clamp(t.a * (1.0 + max(lod, 0.0) * 0.3), 0.0, 1.0);
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	ALBEDO = t.rgb * v_col;
	if (v_snow > 0.001) {   // (the near cards' snow, seen from afar: the crown's upper part, patchy by the baked picture)
		float k = smoothstep(0.85, 1.0, (1.0 - UV.y) * 0.6 + dot(t.rgb, vec3(0.3, 0.6, 0.1)) * 1.2);
		ALBEDO = mix(ALBEDO, vec3(0.78, 0.81, 0.85), k * 0.3 * smoothstep(0.2, 0.7, v_snow));
	}
	vec3 nw = normalize(v_right * (UV.x - 0.5) * 1.6 + v_fwd * 0.75 + vec3(0.0, 0.3, 0.0));
	NORMAL = normalize((VIEW_MATRIX * vec4(nw, 0.0)).xyz);
	ROUGHNESS = 0.85;
	SPECULAR = 0.1;
}

void light() {
	vec3 _lc = atmos_light_col(ATTENUATION * LIGHT_COLOR, LIGHT_IS_DIRECTIONAL, v_world);
	DIFFUSE_LIGHT += clamp(dot(NORMAL, LIGHT) * 0.8 + 0.2, 0.0, 1.0) * _lc;
}
