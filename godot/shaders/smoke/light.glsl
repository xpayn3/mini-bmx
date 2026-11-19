#[compute]
#version 450
// Smoke sim: lighting volume for the renderer. r = dust density, g = sunlight reaching this voxel
// through the dust between it and the sun (self-shadowing), b = how open it is to the sky above.
layout(local_size_x = 8, local_size_y = 4, local_size_z = 8) in;

layout(set = 0, binding = 0) uniform sampler3D src;
layout(set = 0, binding = 1, rgba16f) uniform restrict writeonly image3D outv;
layout(push_constant, std430) uniform Params {
	vec4 sun;   // xyz = toward the sun (grid axes), w = extinction per density per metre
	vec4 a;     // h, -, -, -
} pc;

void main() {
	ivec3 id = ivec3(gl_GlobalInvocationID);
	ivec3 N = imageSize(outv);
	if (any(greaterThanEqual(id, N))) return;
	vec3 inv = 1.0 / vec3(N);
	vec3 p = vec3(id) + 0.5;
	float d = texture(src, p * inv).w;
	float h = pc.a.x;
	// toward the sun: 14 steps growing from half a voxel to ~2.5 voxels (~5 m)
	float acc = 0.0;
	float t = 0.5;
	for (int i = 0; i < 14; i++) {
		float st = 0.5 + float(i) * 0.15;
		t += st;
		acc += texture(src, (p + pc.sun.xyz * t) * inv).w * st;
	}
	float ts = exp(-acc * h * pc.sun.w);
	// up to the sky
	float au = 0.0;
	for (int i = 1; i <= 8; i++) au += texture(src, (p + vec3(0.0, float(i) * 1.5, 0.0)) * inv).w * 1.5;
	float tu = exp(-au * h * pc.sun.w * 0.6);
	imageStore(outv, id, vec4(d, ts, tu, 0.0));
}
