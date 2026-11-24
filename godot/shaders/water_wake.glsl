#[compute]
#version 450
// Water wake: a height-field wave equation on a torus of N x N cells that follows the rider (world-anchored: the
// texel for world cell (i, j) is (i mod N, j mod N), so nothing is copied when the window moves; a texel that now
// stands for another place is cleared, and a sponge layer at the window's edge eats the waves before they wrap).
//   texel = (height m, vertical speed m/s, foam 0..1, unused)
//   one step:  v += c^2 * laplacian(h) * dt   (symplectic Euler: stable for c dt / dx < 0.7)
//              v *= damping, h += v * dt, then the sources push the surface down in a gaussian
layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(set = 0, binding = 0, rgba16f) uniform restrict readonly image2D src;
layout(set = 0, binding = 1, rgba16f) uniform restrict writeonly image2D dst;
layout(set = 0, binding = 2, std430) restrict readonly buffer Srcs { vec4 s[]; } srcs;   // x, z (world m), radius m, amount (m/s of push, negative = up)
layout(push_constant, std430) uniform Params {
	vec4 a;   // dt, wave coefficient c^2 / cell^2, damping per second, number of sources
	vec4 b;   // old window centre cell (x, z), new window centre cell (x, z)
} pc;

const float CELL = 0.15;
const float FOAM_K = 5.0;       // foam laid per unit of push
const float FOAM_FADE = 0.5;    // foam lives ~2 s

// d wrapped to -n/2 .. n/2 - 1
ivec2 wrapd(ivec2 d, int n) {
	ivec2 x = d + n / 2;
	ivec2 q = ivec2(floor(vec2(x) / float(n)));
	return x - q * n - n / 2;
}

void main() {
	ivec2 id = ivec2(gl_GlobalInvocationID.xy);
	int N = imageSize(src).x;
	if (id.x >= N || id.y >= N) return;
	ivec2 co = ivec2(pc.b.xy);
	ivec2 cn = ivec2(pc.b.zw);
	ivec2 wo = co + wrapd(id - co, N);   // the world cell this texel stood for
	ivec2 wn = cn + wrapd(id - cn, N);   // ... and stands for now
	float dt = pc.a.x;
	vec4 s0 = imageLoad(src, id);
	if (wo != wn) s0 = vec4(0.0);
	float h = s0.x, v = s0.y, f = s0.z;
	float hl = imageLoad(src, (id + ivec2(-1, 0) + N) % N).x;
	float hr = imageLoad(src, (id + ivec2(1, 0)) % N).x;
	float hd = imageLoad(src, (id + ivec2(0, -1) + N) % N).x;
	float hu = imageLoad(src, (id + ivec2(0, 1)) % N).x;
	float lap = hl + hr + hd + hu - 4.0 * h;
	v += pc.a.y * lap * dt;
	vec2 e = abs(vec2(wn - cn)) / (0.5 * float(N));
	float sponge = smoothstep(0.72, 1.0, max(e.x, e.y));
	v *= exp(-(pc.a.z + sponge * 9.0) * dt);
	h *= 1.0 - sponge * 6.0 * dt;
	f *= exp(-(FOAM_FADE + sponge * 4.0) * dt);
	vec2 wp = (vec2(wn) + 0.5) * CELL;
	int n = int(pc.a.w);
	for (int i = 0; i < n; i++) {
		vec4 q = srcs.s[i];
		vec2 d = wp - q.xy;
		float r2 = dot(d, d) / (q.z * q.z);
		float g = exp(-r2);
		// pushed down in the middle, a lip of the same volume round it: the crests run out as rings, not a blob
		v -= (g - 0.25 * exp(-r2 * 0.25)) * q.w * 1.6;
		f = max(f, g * clamp(abs(q.w) * FOAM_K, 0.0, 1.0));
	}
	h += v * dt;
	imageStore(dst, id, vec4(h, v, f, 0.0));
}
