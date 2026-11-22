#[compute]
#version 450
// Dust compositor pass 3 (full resolution): upsample the half-res dust with weights that respect depth
// (so it doesn't bleed over the bike / rider edges), then lay it over the scene: dust in front, the scene
// behind it showing through, darkened by the dust's shadow.
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

layout(set = 0, binding = 1) uniform sampler2D depth_tex;
layout(set = 0, binding = 2) uniform sampler2D dust;              // half-res result (after the temporal pass)
layout(set = 0, binding = 3, rgba16f) uniform restrict readonly image2D dist;   // half-res distances
layout(set = 0, binding = 4, rgba16f) uniform restrict image2D color;          // the scene

void main() {
	ivec2 fp = ivec2(gl_GlobalInvocationID.xy);
	ivec2 fs = ivec2(P.sizes.xy);
	if (any(greaterThanEqual(fp, fs))) return;
	ivec2 hs = ivec2(P.sizes.zw);
	vec2 uv = (vec2(fp) + 0.5) / vec2(fs);
	float z = length(view_pos(uv, textureLod(depth_tex, uv, 0.0).r));
	vec2 hpf = (vec2(fp) + 0.5) * 0.5 - 0.5;
	ivec2 b = ivec2(floor(hpf));
	vec2 f = hpf - vec2(b);
	vec4 acc = vec4(0.0);
	float ws = 0.0;
	vec4 best = vec4(0.0);
	float bestd = 1e9;
	for (int j = 0; j < 2; j++)
		for (int i = 0; i < 2; i++) {
			ivec2 q = clamp(b + ivec2(i, j), ivec2(0), hs - 1);
			float zh = imageLoad(dist, q).y;
			vec4 v = texelFetch(dust, q, 0);
			float bw = (i == 0 ? 1.0 - f.x : f.x) * (j == 0 ? 1.0 - f.y : f.y);
			float dz = abs(zh - z);
			float w = bw / (0.001 + dz / (0.04 + 0.02 * z));
			acc += v * w; ws += w;
			if (dz < bestd) { bestd = dz; best = v; }
		}
	vec4 d = ws > 1e-4 ? acc / ws : best;
	d *= 1.0 - P.dust_col.w;   // fading out before the sim stops (smoke_sim.gd): premultiplied, so all of it
	if (d.a < 0.002) return;
	vec4 sc = imageLoad(color, fp);
	imageStore(color, fp, vec4(d.rgb + sc.rgb * (1.0 - d.a), sc.a));
}
