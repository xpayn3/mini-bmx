#[compute]
#version 450
// Dust compositor pass 1 (half resolution): raymarch the smoke sim's light volume for every half-res
// pixel; output the dust (premultiplied colour, alpha = how much of the scene it hides incl. its
// shadow) and the distances needed to reproject / upsample it. Same lighting as smoke_render.gdshader.
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

layout(set = 0, binding = 1) uniform sampler2D depth_tex;     // full-res scene depth (nearest)
layout(set = 0, binding = 2) uniform sampler3D smoke;         // r density, g sun through dust, b sky
layout(set = 0, binding = 3) uniform sampler3D colv;          // dust colour (premultiplied by a)
layout(set = 0, binding = 4) uniform sampler3D occ;           // occupancy bricks (nearest)
layout(set = 0, binding = 5) uniform sampler2D hmap;
layout(set = 0, binding = 6) uniform sampler3D detail;        // tiling noise (repeat)
layout(set = 0, binding = 7, rgba16f) uniform restrict writeonly image2D out_dust;
layout(set = 0, binding = 8, rgba16f) uniform restrict writeonly image2D out_dist;   // x: reprojection distance, y: surface distance

float hg(float c, float g) {
	float g2 = g * g;
	return (1.0 - g2) / pow(1.0 + g2 - 2.0 * g * c, 1.5);
}
float ground(vec2 g) {
	float hm = P.origin_hm.z;
	return texture(hmap, (g * hm + 0.5) / (hm + 1.0)).r;
}

void main() {
	ivec2 hp = ivec2(gl_GlobalInvocationID.xy);
	ivec2 hs = ivec2(P.sizes.zw);
	if (any(greaterThanEqual(hp, hs))) return;
	vec2 full = P.sizes.xy;
	// which of the 4 full-res pixels this half-res pixel stands for rotates every frame (the temporal
	// pass gathers them)
	int fr = int(P.origin_hm.w);
	ivec2 sub = ivec2(fr & 1, (fr >> 1) & 1);
	vec2 uv = (vec2(hp * 2 + sub) + 0.5) / full;
	float zd = textureLod(depth_tex, uv, 0.0).r;
	float tsurf = length(view_pos(uv, zd));
	vec3 ro = cam_pos();
	vec3 rd = world_dir(uv);
	vec3 inv = 1.0 / rd;
	vec3 t0 = (P.box_min.xyz - ro) * inv, t1 = (P.box_max.xyz - ro) * inv;
	vec3 tn = min(t0, t1), tf = max(t0, t1);
	float ta = max(max(max(tn.x, tn.y), tn.z), 0.05);
	float tb = min(min(tf.x, tf.y), tf.z);
	vec3 origin = vec3(P.origin_hm.x, 0.0, P.origin_hm.y);
	vec3 size_m = P.size_step.xyz;
	float step_m = P.size_step.w;
	float ext = P.box_min.w;
	float detail_amt = P.sun_dir.w;
	vec3 sun_dir = P.sun_dir.xyz;
	vec3 drift = P.drift.xyz;

	// dust shadow on the surface behind
	float shf = 1.0;
	if (tsurf < tb && P.box_max.w > 0.0) {
		vec3 sp = ro + rd * tsurf;
		vec2 g = (sp.xz - origin.xz) / size_m.xz;
		if (all(greaterThan(g, vec2(0.0))) && all(lessThan(g, vec2(1.0)))) {
			float gy = clamp((sp.y + 0.06 - ground(g)) / size_m.y, 0.5 / 32.0, 1.0);
			if (gy < 1.0) shf = 1.0 - P.box_max.w * (1.0 - texture(smoke, vec3(g.x, gy, g.y)).g);
		}
	}
	tb = min(tb, tsurf);
	vec3 col = vec3(0.0);
	float T = 1.0;
	float tw = 0.0, wsum = 0.0;   // where along the ray the dust is (for reprojection)
	if (tb > ta) {
		float cth = dot(rd, sun_dir);
		// interleaved gradient noise, moved on every frame: the temporal pass averages the steps away
		float jit = fract(52.9829189 * fract(dot(vec2(hp) + float(fr % 64) * vec2(5.588238, 5.588238), vec2(0.06711056, 0.00583715))));
		float t = ta + step_m * jit;
		float cl = -1.0;
		int maxs = int(P.sun_col.w);
		for (int i = 0; i < maxs; i++) {
			if (t >= tb) break;
			vec3 p = ro + rd * t;
			vec2 g = (p.xz - origin.xz) / size_m.xz;
			float ds = step_m * 2.5;
			if (all(greaterThan(g, vec2(0.0))) && all(lessThan(g, vec2(1.0)))) {
				float gr = ground(g);
				float gy = (p.y - gr) / size_m.y;
				if (gy >= 1.0) {
					// above the ground-following grid: no dust up here
					if (rd.y >= 0.0) {
						// rising: it can only come back into the grid where the land climbs faster than the ray;
						// a steep ray, or one already over the whole grid's top, never does
						if (rd.y > 0.3 || p.y > P.box_max.y - 0.3) break;
					} else {
						// descending: head for the grid top, half the way at a time (the land under it may rise)
						ds = max(ds, (gy - 1.0) * size_m.y / -rd.y * 0.5);
					}
				} else if (gy > 0.0 && texture(occ, vec3(g.x, gy, g.y)).r < 0.004) {
					ds = 1.2;
				} else if (gy > 0.0 && gy < 1.0) {
					vec4 s = texture(smoke, vec3(g.x, gy, g.y));
					float d = s.r;
					float n = 0.5;
					if (d > 0.004) {
						vec3 q = p - drift;
						n = texture(detail, q * 0.13 + 0.71).r * 0.36 + texture(detail, q * 0.37).r * 0.34
							+ texture(detail, q * 0.95 + 0.37).r * 0.18 + texture(detail, q * 2.3 + 0.19).r * 0.12;
						d *= clamp(1.0 + (d * 1.6 - n) * 3.0 * detail_amt, 0.0, 2.2);
					}
					if (d > 0.004) {
						ds = step_m;
						if (cl < 0.0) cl = cloud_ratio(p);
						float a = 1.0 - exp(-d * ext * ds);
						vec3 ps = p + sun_dir * 0.28;
						vec2 gs = (ps.xz - origin.xz) / size_m.xz;
						float dsn = texture(smoke, vec3(gs.x, (ps.y - gr) / size_m.y, gs.y)).r;
						vec3 qs = ps - drift;
						float ns = texture(detail, qs * 0.37).r * 0.6 + texture(detail, qs * 0.95 + 0.37).r * 0.4;
						dsn *= clamp(1.0 + (dsn * 1.6 - ns) * 3.0 * detail_amt, 0.0, 2.2);
						float occl = exp(-dsn * ext * 0.45);
						float powder = mix(1.0, 1.0 - exp(-d * 3.0), 0.45);
						vec4 cv = texture(colv, vec3(g.x, gy, g.y));
						vec3 dcol = mix(P.dust_col.rgb, cv.rgb / max(cv.a, 1e-3), clamp(cv.a, 0.0, 1.0));
						float ts = s.g * occl;
						float ms = 0.0;
						float oa = 1.0, ob = 1.0, oc = 1.0;
						for (int o = 0; o < 3; o++) {
							ms += oa * pow(ts, ob) * mix(hg(cth, 0.55 * oc), hg(cth, -0.2 * oc), 0.35);
							oa *= 0.38; ob *= 0.45; oc *= 0.5;
						}
						vec3 L = dcol * (P.sun_col.rgb * (ms * cl * powder * (1.25 - n * 0.7)) + P.amb_col.rgb * (0.3 + 0.7 * s.b) + P.sun_col.rgb * 0.04);
						col += T * a * L;
						tw += T * a * t; wsum += T * a;
						T *= 1.0 - a;
						if (T < 0.01) break;
					}
				}
			}
			t += ds;
		}
	}
	float keep = T * shf;
	imageStore(out_dust, hp, vec4(col, 1.0 - keep));
	float trep = wsum > 0.05 ? tw / wsum : tsurf;
	imageStore(out_dist, hp, vec4(min(trep, 6e4), min(tsurf, 6e4), 0.0, 0.0));
}
