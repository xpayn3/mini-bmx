#[compute]
#version 450
// Smoke sim: vorticity (curl of the velocity), xyz = curl, w = |curl|
layout(local_size_x = 8, local_size_y = 4, local_size_z = 8) in;

layout(set = 0, binding = 0, rgba16f) uniform restrict readonly image3D st;
layout(set = 0, binding = 1, rgba16f) uniform restrict writeonly image3D curl;
layout(push_constant, std430) uniform Params { vec4 a; } pc;   // dt, h

vec3 vel(ivec3 q, ivec3 N) { return imageLoad(st, clamp(q, ivec3(0), N - 1)).xyz; }

void main() {
	ivec3 id = ivec3(gl_GlobalInvocationID);
	ivec3 N = imageSize(st);
	if (any(greaterThanEqual(id, N))) return;
	vec3 l = vel(id - ivec3(1, 0, 0), N), r = vel(id + ivec3(1, 0, 0), N);
	vec3 b = vel(id - ivec3(0, 1, 0), N), t = vel(id + ivec3(0, 1, 0), N);
	vec3 k = vel(id - ivec3(0, 0, 1), N), f = vel(id + ivec3(0, 0, 1), N);
	float s = 0.5 / pc.a.y;
	vec3 w = vec3((t.z - b.z) - (f.y - k.y), (f.x - k.x) - (r.z - l.z), (r.y - l.y) - (t.x - b.x)) * s;
	imageStore(curl, id, vec4(w, length(w)));
}
