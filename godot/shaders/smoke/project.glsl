#[compute]
#version 450
// Smoke sim: subtract the pressure gradient -> divergence-free (incompressible) air.
layout(local_size_x = 8, local_size_y = 4, local_size_z = 8) in;

layout(set = 0, binding = 0, rgba16f) uniform restrict image3D st;
layout(set = 0, binding = 1, r32f) uniform restrict readonly image3D pres;
layout(push_constant, std430) uniform Params { vec4 a; } pc;   // dt, h

void main() {
	ivec3 id = ivec3(gl_GlobalInvocationID);
	ivec3 N = imageSize(st);
	if (any(greaterThanEqual(id, N))) return;
	float p = imageLoad(pres, id).x;
	float l = id.x > 0 ? imageLoad(pres, id - ivec3(1, 0, 0)).x : 0.0;
	float r = id.x < N.x - 1 ? imageLoad(pres, id + ivec3(1, 0, 0)).x : 0.0;
	float b = id.y > 0 ? imageLoad(pres, id - ivec3(0, 1, 0)).x : p;
	float t = id.y < N.y - 1 ? imageLoad(pres, id + ivec3(0, 1, 0)).x : 0.0;
	float k = id.z > 0 ? imageLoad(pres, id - ivec3(0, 0, 1)).x : 0.0;
	float f = id.z < N.z - 1 ? imageLoad(pres, id + ivec3(0, 0, 1)).x : 0.0;
	vec4 s = imageLoad(st, id);
	s.xyz -= vec3(r - l, t - b, f - k) * 0.5 / pc.a.y;
	if (id.y == 0) s.y = max(s.y, 0.0);
	imageStore(st, id, s);
}
