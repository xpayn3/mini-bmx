#[compute]
#version 450
// HQ still (fx/hq_still.gd): averages many renders of a still scene, each one shifted by a fraction of a
// pixel (and the shadow-casting lights wobbled a little), into one clean picture. Runs on the HDR colour
// before glow / tonemap, so the average is of the light itself, like an offline renderer's samples.
layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;
layout(set = 0, binding = 0, rgba16f) uniform restrict image2D color;   // this frame (written back: the average)
layout(set = 0, binding = 1, rgba32f) uniform restrict image2D accum;   // running sum of the samples
layout(push_constant, std430) uniform P {
	vec2 size;
	float n;      // samples already in the sum
	float mode;   // 0 = add this frame, 1 = only show the average
} p;

void main() {
	ivec2 px = ivec2(gl_GlobalInvocationID.xy);
	if (px.x >= int(p.size.x) || px.y >= int(p.size.y)) return;
	vec4 c = imageLoad(color, px);
	vec4 s;
	float k;
	if (p.mode < 0.5) {
		// a bad sample (NaN / inf from a shader) is left out rather than poisoning the whole sum
		vec3 cc = c.rgb;
		bool bad = any(isnan(cc)) || any(isinf(cc));
		s = p.n < 0.5 ? vec4(0.0) : imageLoad(accum, px);
		if (!bad) s += vec4(cc, 1.0);
		imageStore(accum, px, s);
	} else {
		s = imageLoad(accum, px);
	}
	if (s.a < 0.5) return;   // nothing good in it yet: leave the live frame
	imageStore(color, px, vec4(s.rgb / s.a, c.a));
}
