#[compute]
#version 450
// Smoke sim: coarse occupancy for empty-space skipping in the renderer. One cell per 8x8x8 voxel
// brick, holding the most dust in that brick and the bricks around it (dilated), so a ray in an
// empty cell can safely jump a whole brick.
layout(local_size_x = 4, local_size_y = 4, local_size_z = 4) in;

layout(set = 0, binding = 0) uniform sampler3D src;
layout(set = 0, binding = 1, r16f) uniform restrict writeonly image3D occ;
layout(push_constant, std430) uniform Params { vec4 a; } pc;   // x: scale

void main() {
	ivec3 id = ivec3(gl_GlobalInvocationID);
	ivec3 M = imageSize(occ);
	if (any(greaterThanEqual(id, M))) return;
	ivec3 N = textureSize(src, 0);
	ivec3 B = N / M;   // voxels per brick
	ivec3 lo = max(id * B - B, ivec3(0));
	ivec3 hi = min(id * B + 2 * B, N);
	float m = 0.0;
	// every second voxel of the brick and its neighbours (linear filtering covers the gaps)
	for (int z = lo.z; z < hi.z; z += 2)
		for (int y = lo.y; y < hi.y; y += 2)
			for (int x = lo.x; x < hi.x; x += 2)
				m = max(m, texture(src, (vec3(x, y, z) + 1.0) / vec3(N)).w);
	imageStore(occ, id, vec4(m * pc.a.x));
}
