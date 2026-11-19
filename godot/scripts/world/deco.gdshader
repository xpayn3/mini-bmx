// Decorations (trees, rocks, sheds, fences, logs...): vertex colour x material colour x per-instance
// colour (MultiMesh custom data, linear RGB) -- the three.js vertexColors * color * instanceColor.
// sway > 0 (tree crowns, bushes, weeds): the wind nudges them, more the higher up. Cloud shadows drift over.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx, world_vertex_coords;
#include "res://shaders/atmos.gdshaderinc"

uniform vec3 albedo = vec3(1.0);
uniform float roughness = 0.85;
uniform float metallic = 0.0;
uniform bool use_instance = true;
uniform float sway = 0.0;      // m of sway per m of height in a full gust
uniform float backlight = 0.0;
uniform bool tint_own = false;   // cacti: UV.x = 1 keeps the vertex colour (spines, flowers, cut flesh)
varying vec3 v_col;
varying vec3 v_world;
// ride camera: anything between the camera and the rider dissolves (dither) so a tree never hides them.
// cam_see = rider (w = on), cam_eye = the ride camera (other passes, e.g. shadows, have another eye: untouched)
global uniform vec4 cam_see;
global uniform vec4 cam_eye;

void vertex() {
	vec3 ic = use_instance ? INSTANCE_CUSTOM.rgb : vec3(1.0);
	v_col = albedo * COLOR.rgb * ic;
	if (tint_own) v_col = mix(v_col, COLOR.rgb, clamp(UV.x, 0.0, 1.0));
	if (sway > 0.0) {
		vec3 base = MODEL_MATRIX[3].xyz;
		float h = max(VERTEX.y - base.y, 0.0);
		vec3 o = wind_bend(base, 1.0, 1.0, 0.0);
		VERTEX.xz += o.xz * h * sway;
	}
	v_world = VERTEX;
}

void fragment() {
	if (cam_see.w > 0.0 && distance(CAMERA_POSITION_WORLD, cam_eye.xyz) < 0.5) {
		vec3 c = cam_eye.xyz;
		vec3 seg = cam_see.xyz - c;
		float u = clamp(dot(v_world - c, seg) / max(dot(seg, seg), 1e-4), 0.0, 1.0);
		float d = length(v_world - (c + seg * u));
		float rad = mix(1.6, 3.2, u);   // a cone widening toward the rider
		float cut = (1.0 - smoothstep(rad * 0.5, rad, d)) * (1.0 - smoothstep(0.9, 1.0, u));
		cut = max(cut, 1.0 - smoothstep(1.5, 3.0, distance(v_world, c)));   // right in front of the lens
		float n = fract(52.9829189 * fract(dot(FRAGCOORD.xy, vec2(0.06711056, 0.00583715))));
		if (n < cut * 0.95) discard;
	}
	ALBEDO = v_col;
	ROUGHNESS = roughness;
	METALLIC = metallic;
	SPECULAR = 0.4;
}

void light() {
	vec3 _lc = atmos_light_col(ATTENUATION * LIGHT_COLOR, LIGHT_IS_DIRECTIONAL, v_world);
	DIFFUSE_LIGHT += (clamp(dot(NORMAL, LIGHT), 0.0, 1.0) + clamp(dot(-NORMAL, LIGHT), 0.0, 1.0) * backlight) * _lc;
	// a soft sheen so wet rock / painted wood still catch the sun
	vec3 hv = normalize(VIEW + LIGHT);
	float sp = pow(clamp(dot(NORMAL, hv), 0.0, 1.0), mix(64.0, 4.0, roughness)) * (1.0 - roughness) * 0.5;
	SPECULAR_LIGHT += sp * _lc * clamp(dot(NORMAL, LIGHT), 0.0, 1.0);
}
