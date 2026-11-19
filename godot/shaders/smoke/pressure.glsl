#[compute]
#version 450
// Smoke sim: one red-black Gauss-Seidel (over-relaxed) half-sweep of the pressure Poisson equation.
// Open air outside the sides/top (p = 0), solid ground below (dp/dn = 0).
layout(local_size_x = 8, local_size_y = 4, local_size_z = 8) in;

layout(set = 0, binding = 0, r32f) uniform restrict image3D pres;
layout(set = 0, binding = 1, r32f) uniform restrict readonly image3D div;
layout(push_constant, std430) uniform Params { vec4 a; } pc;   // parity, h, omega, -

void main() {
	ivec3 id = ivec3(gl_GlobalInvocationID);
	ivec3 N = imageSize(pres);
	if (any(greaterThanEqual(id, N))) return;
	if (((id.x + id.y + id.z) & 1) != int(pc.a.x)) return;
	float p = imageLoad(pres, id).x;
	float s = 0.0;
	s += id.x > 0 ? imageLoad(pres, id - ivec3(1, 0, 0)).x : 0.0;
	s += id.x < N.x - 1 ? imageLoad(pres, id + ivec3(1, 0, 0)).x : 0.0;
	s += id.y > 0 ? imageLoad(pres, id - ivec3(0, 1, 0)).x : p;
	s += id.y < N.y - 1 ? imageLoad(pres, id + ivec3(0, 1, 0)).x : 0.0;
	s += id.z > 0 ? imageLoad(pres, id - ivec3(0, 0, 1)).x : 0.0;
	s += id.z < N.z - 1 ? imageLoad(pres, id + ivec3(0, 0, 1)).x : 0.0;
	float h = pc.a.y;
	float pn = (s - imageLoad(div, id).x * h * h) / 6.0;
	imageStore(pres, id, vec4(mix(p, pn, pc.a.z)));
}
