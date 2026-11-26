#[compute]
#version 450
// Camera / object motion blur (2026-11-26, fx/motion_blur.gd): each pixel is smeared along its own screen motion (Godot's
// motion vectors) over a shutter's share of the frame, before tonemapping. Pixels that barely move (the rider under a
// follow camera) are left alone, and samples that move much less than this pixel count little, so a sharp rider is not
// smeared over the streaking background. One pass, 12 taps, only where something moves.
layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;
layout(set = 0, binding = 0) uniform sampler2D src;   // a copy of the colour
layout(set = 0, binding = 1) uniform sampler2D vel;   // motion vectors
layout(rgba16f, set = 0, binding = 2) uniform restrict writeonly image2D dst;
layout(push_constant, std430) uniform Params {
	vec2 size;
	float shutter;   // share of the frame the shutter is open (0.5 = a 180 deg film shutter)
	float max_len;   // longest smear, pixels
} p;

const int TAPS = 12;

void main() {
	ivec2 px = ivec2(gl_GlobalInvocationID.xy);
	if (any(greaterThanEqual(px, ivec2(p.size)))) return;
	vec2 uv = (vec2(px) + 0.5) / p.size;
	vec2 v = texelFetch(vel, px, 0).xy * p.shutter;   // uv units
	float len = length(v * p.size);
	if (len < 1.5) return;   // (the colour stays as it is: small moves, e.g. the rider under a follow camera, stay sharp)
	if (len > p.max_len) { v *= p.max_len / len; len = p.max_len; }
	vec3 acc = texelFetch(src, px, 0).rgb;
	float wsum = 1.0;
	// a little per-pixel jitter on the tap positions turns banding into fine noise (TAA / the grain smooth it)
	float jit = fract(52.9829189 * fract(dot(vec2(px), vec2(0.06711056, 0.00583715)))) - 0.5;
	for (int i = 0; i < TAPS; i++) {
		float t = (float(i) + 0.5 + jit) / float(TAPS) - 0.5;
		vec2 suv = uv + v * t;
		float sl = length(textureLod(vel, suv, 0.0).xy * p.shutter * p.size);
		float w = mix(0.15, 1.0, smoothstep(0.25 * len, 0.6 * len, sl));   // slow samples (the rider) barely bleed in
		acc += textureLod(src, suv, 0.0).rgb * w;
		wsum += w;
	}
	imageStore(dst, px, vec4(acc / wsum, 1.0));
}
