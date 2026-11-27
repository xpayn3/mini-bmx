// Wooden fence parts (ranch / picket fences, billboard posts; MultiMesh lists "post", "rail", "picket"): the ambientCG
// Wood049 scan (assets/textures/wood_plank, CC0) box-mapped in metres on the scaled part, grain along `grain_axis`
// (rails: x, posts / pickets: y). The instance colour (MultiMesh custom data) decides the finish: brown = bare
// weathered wood keeping that colour's tone, near white = paint over the grain (picket fences) with worn patches
// and chips down to grey wood. Darker and damp at the foot. Same distance dissolve as the other decorations.
shader_type spatial;
render_mode cull_back;
#include "res://shaders/deco_fade.gdshaderinc"
instance uniform float fade_mode = 0.0;
uniform sampler2D wood_col : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D wood_nrm : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D wood_rgh : hint_roughness_gray, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grime_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform int grain_axis = 1;   // 0 = along the part's x, 1 = along its y
uniform float tile = 1.0;     // metres of wood per texture repeat along the grain
// broken pieces (TerrainDebris: rail halves, splinters) are plain MeshInstances with no instance data: their colour comes from here
uniform bool use_tint = false;
uniform vec3 tint = vec3(0.3, 0.2, 0.12);
const vec3 WOOD_MEAN = vec3(0.2023, 0.1249, 0.0732);   // Wood049's mean colour (linear)
varying flat vec3 v_origin;
varying vec3 v_m;     // position on the part in metres (part space)
varying vec3 v_n;     // its face normal (part space)
varying vec3 v_tint;
varying float v_y;    // world height

void vertex() {
	v_origin = MODEL_MATRIX[3].xyz;
	vec3 sc = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), length(MODEL_MATRIX[2].xyz));
	v_m = VERTEX * sc;
	v_n = NORMAL;
	v_tint = use_tint ? tint : INSTANCE_CUSTOM.rgb;
	v_y = (MODEL_MATRIX * vec4(VERTEX, 1.0)).y;
}

void fragment() {
	if (deco_cut(v_origin, fade_mode, FRAGCOORD.xy, PROJECTION_MATRIX[3][3] > 0.5)) discard;
	float seed = fract(sin(dot(floor(v_origin.xz * 2.0), vec2(12.9898, 78.233))) * 43758.5453);
	vec3 an = abs(v_n);
	// along = the grain axis, across = the other axis lying on this face; faces square to the grain = end grain
	float along = grain_axis == 0 ? v_m.x : v_m.y;
	float a_n = grain_axis == 0 ? an.x : an.y;
	float across;
	if (grain_axis == 0) across = an.y > an.z ? v_m.z : v_m.y;
	else across = an.x > an.z ? v_m.z : v_m.x;
	vec2 uv = a_n > 0.6 ? (grain_axis == 0 ? v_m.yz : v_m.xz) * 4.0 : vec2(along, across);
	uv = uv / tile + vec2(seed * 5.3, seed * 2.1);
	vec3 wood = texture(wood_col, uv).rgb;
	float rough = texture(wood_rgh, uv).r;
	vec3 nt = texture(wood_nrm, uv).rgb * 2.0 - 1.0;
	// finish from the instance colour: bare wood keeps the scan's grain at the colour's tone; white = painted
	float lum = dot(v_tint, vec3(0.3, 0.55, 0.15));
	float painted = smoothstep(0.35, 0.6, lum);
	vec3 bare = clamp(wood / WOOD_MEAN, vec3(0.55), vec3(1.45)) * v_tint;   // same average as the fence colour, the scan's light / dark grain
	float wl = dot(wood / WOOD_MEAN, vec3(0.33));
	vec3 paint = v_tint * (0.78 + 0.22 * clamp(wl, 0.0, 1.6));
	// worn paint: the grime scan decides where it has flaked to grey weathered wood
	float g = dot(texture(grime_tex, vec2(along, across) * 0.9 + seed).rgb, vec3(0.333));
	float flake = smoothstep(0.62, 0.42, g);
	vec3 grey_wood = vec3(dot(wood, vec3(0.33))) * 1.5 + vec3(0.04, 0.035, 0.03);
	vec3 col = mix(bare, mix(paint, grey_wood, flake), painted);
	rough = mix(rough, mix(0.7, rough, flake), painted);
	// damp, muddy foot
	float foot = 1.0 - smoothstep(0.0, 0.3, v_y - (v_origin.y - 0.5 * length(MODEL_MATRIX[1].xyz)) - 0.12);
	col *= mix(1.0, 0.6, foot * (grain_axis == 1 ? 1.0 : 0.0));
	// the scan's relief, axes from the part itself (the meshes have no tangents)
	vec3 ax_u = grain_axis == 0 ? vec3(1.0, 0.0, 0.0) : vec3(0.0, 1.0, 0.0);
	vec3 ax_v = an.x > 0.6 ? vec3(0.0, 0.0, 1.0) : (an.z > 0.6 ? vec3(1.0, 0.0, 0.0) : vec3(0.0, 0.0, 1.0));
	if (grain_axis == 0 && an.z > 0.6) ax_v = vec3(0.0, 1.0, 0.0);
	vec3 tu = normalize((VIEW_MATRIX * MODEL_MATRIX * vec4(ax_u, 0.0)).xyz);
	vec3 tv = normalize((VIEW_MATRIX * MODEL_MATRIX * vec4(ax_v, 0.0)).xyz);
	NORMAL = normalize(NORMAL + (tu * nt.x + tv * nt.y) * mix(0.8, 0.35, painted * (1.0 - flake)));
	ALBEDO = col;
	ROUGHNESS = rough;
	SPECULAR = 0.35;
}
