#[compute]
#version 450
// Smoke sim: velocity divergence (the ground is solid, the sides and top are open air); also clears
// the pressure for this step's solve.
layout(local_size_x = 8, local_size_y = 4, local_size_z = 8) in;

layout(set = 0, binding = 0, rgba16f) uniform restrict readonly image3D st;
layout(set = 0, binding = 1, r32f) uniform restrict writeonly image3D div;
layout(set = 0, binding = 2, r32f) uniform restrict writeonly image3D pres;
layout(push_constant, std430) uniform Params { vec4 a; } pc;   // dt, h

void main() {
	ivec3 id = ivec3(gl_GlobalInvocationID);
	ivec3 N = imageSize(st);
	if (any(greaterThanEqual(id, N))) return;
	vec3 c = imageLoad(st, id).xyz;
	vec3 l = id.x > 0 ? imageLoad(st, id - ivec3(1, 0, 0)).xyz : c;
	vec3 r = id.x < N.x - 1 ? imageLoad(st, id + ivec3(1, 0, 0)).xyz : c;
	vec3 b = id.y > 0 ? imageLoad(st, id - ivec3(0, 1, 0)).xyz : vec3(c.x, -c.y, c.z);   // ground: no flow through
	vec3 t = id.y < N.y - 1 ? imageLoad(st, id + ivec3(0, 1, 0)).xyz : c;
	vec3 k = id.z > 0 ? imageLoad(st, id - ivec3(0, 0, 1)).xyz : c;
	vec3 f = id.z < N.z - 1 ? imageLoad(st, id + ivec3(0, 0, 1)).xyz : c;
	float d = ((r.x - l.x) + (t.y - b.y) + (f.z - k.z)) * 0.5 / pc.a.y;
	imageStore(div, id, vec4(d));
	imageStore(pres, id, vec4(0.0));
}
