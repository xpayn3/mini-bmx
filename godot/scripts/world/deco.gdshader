// Decorations (trees, rocks, sheds, fences, logs...): vertex colour x material colour x per-instance
// colour (MultiMesh custom data, linear RGB) -- the three.js vertexColors * color * instanceColor.
// sway > 0 (tree crowns, bushes, weeds): the wind nudges them, more the higher up. Cloud shadows drift over.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx, world_vertex_coords;
#include "res://shaders/atmos.gdshaderinc"
#include "res://shaders/deco_fade.gdshaderinc"
instance uniform float fade_mode = 0.0;   // deco_fade.gdshaderinc: 1 world decorations, 2 small clutter (Terrain sets it)

uniform vec3 albedo = vec3(1.0);
uniform float roughness = 0.85;
uniform float metallic = 0.0;
// how much sky the faces mirror: leaves / cacti almost none (big flat low-poly faces read as glossy plastic)
uniform float specular = 0.4;
uniform bool use_instance = true;
uniform float sway = 0.0;      // m of sway per m of height in a full gust
uniform float backlight = 0.0;
// golden-hour translucency: sun shining through the crown towards the camera (view dependent, strongest
// with a low sun behind the plant; the shadowed side facing the camera glows in the leaves' own colour)
uniform float scatter = 0.0;
uniform float scatter_rim = 0.0;   // > 0: only the silhouette glows (thick cactus bodies)
// dappled shadows: in the sun's shadow pass the crown has holes (fraction 0..1, noise in the crown's own
// space so the flecks move with the swaying leaves + a little flutter), so sun flecks fall through it
uniform float dapple = 0.0;
uniform float dapple_size = 0.55;  // m, the size of a gap in the leaves
uniform bool tint_own = false;   // cacti: UV.x = 1 keeps the vertex colour (spines, flowers, cut flesh)
// tree trunks (2026-11-25): a bark scan (assets/textures/bark, CC0) wrapped round the upright trunk at real size: u round it in
// whole tiles (no seam: the count comes from the instance's girth), v up it; its normal map lights the grooves
uniform bool bark = false;
uniform sampler2D bark_col : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D bark_nrm : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D bark_rgh : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float bark_tile = 0.8;     // m of bark per tile
uniform float bark_relief = 0.9;
uniform bool bark_uv = false;   // roots (lying down): the mesh's own UV (round it, along it in its lengths) instead of the wrap
varying flat float v_bark_n;   // tiles round the trunk
varying flat float v_len;      // (bark_uv) the instance's length along its x
varying vec3 v_col;
varying flat vec3 v_origin;   // the instance's base (distance fade)
varying vec3 v_world;
varying vec3 v_rest;   // world position before the wind sway (dapple holes ride with the leaves)
// ride camera: trees / rocks right at the lens dissolve (dither) so they never fill the screen.
// cam_see = rider (w = on), cam_eye = the ride camera (other passes, e.g. shadows, have another eye: untouched)
global uniform vec4 cam_see;
global uniform vec4 cam_eye;

void vertex() {
	vec3 ic = use_instance ? INSTANCE_CUSTOM.rgb : vec3(1.0);
	v_col = albedo * COLOR.rgb * ic;
	if (tint_own) v_col = mix(v_col, COLOR.rgb, clamp(UV.x, 0.0, 1.0));
	v_rest = VERTEX;
	v_origin = MODEL_MATRIX[3].xyz;
	// the trunk mesh's mean radius is 0.13 m at scale 1: whole tiles round it, so u meets itself
	v_bark_n = max(1.0, round(TAU * 0.13 * length(MODEL_MATRIX[0].xyz) / bark_tile));
	v_len = length(MODEL_MATRIX[0].xyz);   // (roots: UV.y is metres of the 2 m mesh; this is its stretch)
	if (sway > 0.0) {
		vec3 base = MODEL_MATRIX[3].xyz;
		float h = max(VERTEX.y - base.y, 0.0);
		vec3 o = wind_bend(base, 1.0, 1.0, 0.0);
		VERTEX.xz += o.xz * h * sway;
	}
	v_world = VERTEX;
}

float dap_hash(vec3 p) {
	p = fract(p * 0.3183099 + vec3(0.71, 0.113, 0.419));
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}
float dap_noise(vec3 x) {
	vec3 i = floor(x), f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(dap_hash(i), dap_hash(i + vec3(1, 0, 0)), f.x), mix(dap_hash(i + vec3(0, 1, 0)), dap_hash(i + vec3(1, 1, 0)), f.x), f.y),
	           mix(mix(dap_hash(i + vec3(0, 0, 1)), dap_hash(i + vec3(1, 0, 1)), f.x), mix(dap_hash(i + vec3(0, 1, 1)), dap_hash(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

void fragment() {
	if (deco_cut(v_origin, fade_mode, FRAGCOORD.xy, PROJECTION_MATRIX[3][3] > 0.5)) discard;   // ortho = the sun's shadow pass
	// the sun's shadow pass (orthographic; every view camera is perspective): leaf gaps. Only within ~40 m of
	// the ride camera (cam_eye): further out the flecks are below a shadow texel of the far cascades, and the
	// discard + noise ran for every crown in every cascade
	if (dapple > 0.0 && PROJECTION_MATRIX[3][3] > 0.5 && distance(v_rest, cam_eye.xyz) < 40.0) {
		vec3 p = v_rest / dapple_size;
		float t = atm_wind.z;
		float g = wind_gust(v_rest.xz);
		p += vec3(sin(t * 1.7 + p.y * 0.9), sin(t * 1.3 + p.x * 0.7) * 0.5, cos(t * 1.5 + p.z * 0.8)) * (0.06 + 0.22 * g);
		float n = dap_noise(p) * 0.65 + dap_noise(p * 2.37 + 11.3) * 0.35;
		n = (n - 0.5) * 2.6 + 0.5;   // stretched so dapple ~ the share of the crown that is gaps
		if (n < dapple) discard;
	}
	if (cam_see.w > 0.0 && distance(CAMERA_POSITION_WORLD, cam_eye.xyz) < 0.5) {
		// only what is right at the camera lens dissolves; everything around the rider stays
		float cut = 1.0 - smoothstep(1.5, 3.0, distance(v_world, cam_eye.xyz));
		float n = fract(52.9829189 * fract(dot(FRAGCOORD.xy, vec2(0.06711056, 0.00583715))));
		if (n < cut * 0.95) discard;
	}
	ALBEDO = v_col;
	ROUGHNESS = roughness;
	METALLIC = metallic;
	SPECULAR = specular;
	if (bark && bark_uv) {
		vec2 uv = vec2(UV.x, UV.y * v_len / bark_tile);
		ALBEDO = v_col * texture(bark_col, uv).rgb;
		ROUGHNESS = texture(bark_rgh, uv).r;
		NORMAL_MAP = texture(bark_nrm, uv).rgb;
		NORMAL_MAP_DEPTH = bark_relief;
	} else if (bark) {
		vec2 rel = v_world.xz - v_origin.xz;
		float ang = atan(rel.y, rel.x);
		vec2 uv = vec2(ang / TAU * v_bark_n, (v_world.y - v_origin.y) / bark_tile);
		// the gradients from whichever of two cuts round the trunk is away from this pixel (atan jumps at -pi)
		vec2 uv2 = vec2(fract(ang / TAU + 0.5) * v_bark_n, uv.y);
		vec2 gx = dFdx(uv), gy = dFdy(uv);
		vec2 gx2 = dFdx(uv2), gy2 = dFdy(uv2);
		if (abs(gx2.x) + abs(gy2.x) < abs(gx.x) + abs(gy.x)) { gx = gx2; gy = gy2; }
		ALBEDO = v_col * textureGrad(bark_col, uv, gx, gy).rgb;
		ROUGHNESS = textureGrad(bark_rgh, uv, gx, gy).r;
		vec3 nt = textureGrad(bark_nrm, uv, gx, gy).rgb * 2.0 - 1.0;
		vec3 tv = (VIEW_MATRIX * vec4(-sin(ang), 0.0, cos(ang), 0.0)).xyz;   // round the trunk
		vec3 bv = (VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz;               // up it (the image runs down: -y)
		NORMAL = normalize(NORMAL + (tv * nt.x - bv * nt.y) * bark_relief);
	}
}

void light() {
	vec3 _lc = atmos_light_col(ATTENUATION * LIGHT_COLOR, LIGHT_IS_DIRECTIONAL, v_world);
	DIFFUSE_LIGHT += (clamp(dot(NORMAL, LIGHT), 0.0, 1.0) + clamp(dot(-NORMAL, LIGHT), 0.0, 1.0) * backlight) * _lc;
	if (scatter > 0.0 && LIGHT_IS_DIRECTIONAL) {
		// sun behind the plant as seen from here (VIEW -> camera, LIGHT -> sun)
		float bl = clamp(dot(-VIEW, LIGHT), 0.0, 1.0);
		bl = bl * bl * bl;
		float sun_y = (INV_VIEW_MATRIX * vec4(LIGHT, 0.0)).y;
		float low = mix(0.25, 1.0, 1.0 - smoothstep(0.15, 0.75, sun_y));
		float rim = 1.0 - clamp(abs(dot(NORMAL, VIEW)), 0.0, 1.0);
		float shape = mix(0.45 + 0.55 * clamp(dot(-NORMAL, LIGHT) + 0.4, 0.0, 1.0) + 0.5 * rim, 1.6 * rim * rim, scatter_rim);
		// the leaves' own colour, saturated (light that went through them)
		vec3 tint = ALBEDO / max(max(ALBEDO.r, max(ALBEDO.g, ALBEDO.b)), 0.04);
		DIFFUSE_LIGHT += bl * low * shape * scatter * tint * _lc;
	}
	// a soft sheen so wet rock / painted wood still catch the sun
	vec3 hv = normalize(VIEW + LIGHT);
	float sp = pow(clamp(dot(NORMAL, hv), 0.0, 1.0), mix(64.0, 4.0, roughness)) * (1.0 - roughness) * 0.5;
	SPECULAR_LIGHT += sp * _lc * clamp(dot(NORMAL, LIGHT), 0.0, 1.0);
}
