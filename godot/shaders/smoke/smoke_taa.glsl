#[compute]
#version 450
// Dust compositor pass 2 (half resolution): blend this frame's dust with last frame's, reprojected to
// where it was on screen, clamped to this frame's neighbourhood (no smearing / ghosting). Averages the
// raymarch steps and the rotating sub-pixel over frames: smooth dust at a quarter of the cost.
layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;
// Shared by the dust compositor passes (smoke_march / smoke_taa / smoke_comp).
layout(set = 0, binding = 0, std140) uniform Params {
	mat4 inv_proj;      // camera projection inverse (RD convention: depth 0..1 reversed, y down)
	mat4 cam;           // camera -> world
	mat4 prev_vp;       // last frame's projection * view (RD convention)
	vec4 origin_hm;     // grid corner x, z (m), heightmap cells, frame number
	vec4 size_step;     // grid size m (x, y, z), march step (m)
	vec4 box_min;       // xyz, extinction
	vec4 box_max;       // xyz, shadow strength
	vec4 sun_dir;       // xyz toward the sun, detail amount
	vec4 sun_col;       // rgb, max steps
	vec4 amb_col;       // rgb, history blend (1 = no history)
	vec4 dust_col;      // rgb, w = fade-out 0 (drawn) .. 1 (gone)
	vec4 drift;         // xyz detail drift (m), time
	vec4 cloud;         // atm_cloud: drift xy, depth, shade at the rider
	vec4 sizes;         // full w, h, half w, h
} P;

// a full-res pixel centre (uv 0..1, top-left origin) + its depth -> view ray / view-space distance
vec3 view_pos(vec2 uv, float depth) {
	vec4 v = P.inv_proj * vec4(uv * 2.0 - 1.0, depth, 1.0);   // Godot's RD projection (depth-corrected)
	return v.xyz / v.w;
}
vec3 world_dir(vec2 uv) {
	vec3 v = view_pos(uv, 0.5);
	return normalize(mat3(P.cam) * v);
}
vec3 cam_pos() { return P.cam[3].xyz; }

float cloud_hash(vec2 c) {
	uint h = uint(int(c.x)) * 1597334673u ^ uint(int(c.y)) * 3812015801u;
	h = (h ^ (h >> 16u)) * 2246822519u;
	h ^= h >> 13u;
	return float(h & 16777215u) / 16777215.0;
}
float cloud_noise(vec2 p) {
	vec2 i = floor(p), f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(cloud_hash(i), cloud_hash(i + vec2(1.0, 0.0)), f.x),
	           mix(cloud_hash(i + vec2(0.0, 1.0)), cloud_hash(i + vec2(1.0, 1.0)), f.x), f.y);
}
float cloud_ratio(vec3 w) {
	if (P.cloud.z <= 0.0) return 1.0;
	vec2 p = (w.xz + P.cloud.xy) * 0.03;
	float n = cloud_noise(p) * 0.62 + cloud_noise(p * 2.2 + 5.3) * 0.28 + cloud_noise(p * 5.1 - 2.1) * 0.10;
	return (1.0 - P.cloud.z * smoothstep(0.5, 0.66, n)) / max(P.cloud.w, 0.05);
}

layout(set = 0, binding = 1, rgba16f) uniform restrict readonly image2D cur_dust;
layout(set = 0, binding = 2, rgba16f) uniform restrict readonly image2D cur_dist;
layout(set = 0, binding = 3) uniform sampler2D hist;            // last frame's result (linear)
layout(set = 0, binding = 4, rgba16f) uniform restrict writeonly image2D out_hist;

void main() {
	ivec2 hp = ivec2(gl_GlobalInvocationID.xy);
	ivec2 hs = ivec2(P.sizes.zw);
	if (any(greaterThanEqual(hp, hs))) return;
	vec4 c = imageLoad(cur_dust, hp);
	vec4 mn = c, mx = c;
	for (int y = -1; y <= 1; y++)
		for (int x = -1; x <= 1; x++) {
			vec4 n = imageLoad(cur_dust, clamp(hp + ivec2(x, y), ivec2(0), hs - 1));
			mn = min(mn, n); mx = max(mx, n);
		}
	float k = P.amb_col.w;   // weight of this frame (1 = no history)
	vec4 res = c;
	if (k < 0.999) {
		vec2 uv = (vec2(hp) + 0.5) / vec2(hs);
		float t = imageLoad(cur_dist, hp).x;
		vec3 w = cam_pos() + world_dir(uv) * t;
		vec4 pc = P.prev_vp * vec4(w, 1.0);
		vec2 puv = pc.xy / pc.w * 0.5 + 0.5;
		if (pc.w > 0.0 && all(greaterThan(puv, vec2(0.0))) && all(lessThan(puv, vec2(1.0)))) {
			vec4 h = clamp(textureLod(hist, puv, 0.0), mn, mx);
			res = mix(h, c, k);
		}
	}
	imageStore(out_hist, hp, res);
}
