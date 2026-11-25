#[compute]
#version 450
// Road detail mip (world/road_detail.gd): one tile's next mip level, a 2 x 2 box of the one above. Every channel is a
// plain average: colour multiplier / masks average to their coverage, slopes to the mean slope, the mean squared slope
// keeps the bumpiness that the mean slope loses (the ground shader turns the difference into roughness).
layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(set = 0, binding = 0, rgba8) uniform restrict readonly image2D src_a;
layout(set = 0, binding = 1, rgba16f) uniform restrict readonly image2D src_b;
layout(set = 0, binding = 2, rgba8) uniform restrict readonly image2D src_c;
layout(set = 0, binding = 3, rgba8) uniform restrict writeonly image2D dst_a;
layout(set = 0, binding = 4, rgba16f) uniform restrict writeonly image2D dst_b;
layout(set = 0, binding = 5, rgba8) uniform restrict writeonly image2D dst_c;

layout(push_constant, std430) uniform Push {
	vec4 a;   // tile origin in the destination mip (x, y), tile size in the destination mip, unused
} pc;

void main() {
	ivec2 id = ivec2(gl_GlobalInvocationID.xy);
	int n = int(pc.a.z);
	if (id.x >= n || id.y >= n) return;
	ivec2 d = ivec2(pc.a.xy) + id;
	ivec2 s = d * 2;
	vec4 a = (imageLoad(src_a, s) + imageLoad(src_a, s + ivec2(1, 0)) + imageLoad(src_a, s + ivec2(0, 1)) + imageLoad(src_a, s + ivec2(1, 1))) * 0.25;
	vec4 b = (imageLoad(src_b, s) + imageLoad(src_b, s + ivec2(1, 0)) + imageLoad(src_b, s + ivec2(0, 1)) + imageLoad(src_b, s + ivec2(1, 1))) * 0.25;
	vec4 c = (imageLoad(src_c, s) + imageLoad(src_c, s + ivec2(1, 0)) + imageLoad(src_c, s + ivec2(0, 1)) + imageLoad(src_c, s + ivec2(1, 1))) * 0.25;
	imageStore(dst_a, d, a);
	imageStore(dst_b, d, b);
	imageStore(dst_c, d, c);
}
