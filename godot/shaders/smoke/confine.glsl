#[compute]
#version 450
// Smoke sim: vorticity confinement — puts back the small swirls the coarse grid smooths away, which
// is what makes dust roll and billow. Stronger where there is dust.
layout(local_size_x = 8, local_size_y = 4, local_size_z = 8) in;

layout(set = 0, binding = 0, rgba16f) uniform restrict image3D st;
layout(set = 0, binding = 1, rgba16f) uniform restrict readonly image3D curl;
layout(push_constant, std430) uniform Params { vec4 a; } pc;   // dt, h, eps, -

float wl(ivec3 q, ivec3 N) { return imageLoad(curl, clamp(q, ivec3(0), N - 1)).w; }

void main() {
	ivec3 id = ivec3(gl_GlobalInvocationID);
	ivec3 N = imageSize(st);
	if (any(greaterThanEqual(id, N))) return;
	vec3 g = vec3(wl(id + ivec3(1, 0, 0), N) - wl(id - ivec3(1, 0, 0), N),
	              wl(id + ivec3(0, 1, 0), N) - wl(id - ivec3(0, 1, 0), N),
	              wl(id + ivec3(0, 0, 1), N) - wl(id - ivec3(0, 0, 1), N));
	float gl = length(g);
	if (gl < 1e-5) return;
	vec4 s = imageLoad(st, id);
	vec3 w = imageLoad(curl, id).xyz;
	float eps = pc.a.z * (0.35 + min(s.w, 1.5));
	vec3 f = eps * pc.a.y * cross(g / gl, w);
	s.xyz += f * pc.a.x;
	imageStore(st, id, s);
}
