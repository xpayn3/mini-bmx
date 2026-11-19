#[compute]
#version 450
// Smoke sim step 1: semi-Lagrangian advection of the state (xyz = air velocity m/s, w = dust density),
// scrolled with the domain (integer voxel shift), relaxed toward the ambient wind, dust settling and
// fading, plus every source (wheel roost, landing puffs, the bike's wake) splatted in.
layout(local_size_x = 8, local_size_y = 4, local_size_z = 8) in;

layout(set = 0, binding = 0) uniform sampler3D src;
layout(set = 0, binding = 1, rgba16f) uniform restrict writeonly image3D dst;
struct Source { vec4 pos_r; vec4 vel_rate; vec4 misc; };   // grid pos + radius (m) | vel m/s + density/s | blend/s, radial m/s
layout(set = 0, binding = 2, std430) restrict readonly buffer Sources { Source s[]; } srcs;

layout(push_constant, std430) uniform Params {
	vec4 a;   // dt, h (m per voxel), shift x, shift z (voxels)
	vec4 b;   // wind x, wind z (m/s), source count, time
	vec4 c;   // density fade /s, velocity relax /s, settle m/s, edge width (voxels)
	vec4 d;   // world x, z of the grid corner (m), turbulence strength, turbulence scale (1/m)
	vec4 e;   // dispersal rate /s, dispersal reach (voxels), -, -
} pc;

// smooth value noise + its curl: a divergence-free swirl field (the gusty air the dust rolls in)
float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}
float vnoise(vec3 p) {
	vec3 i = floor(p), f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash13(i), hash13(i + vec3(1, 0, 0)), f.x), mix(hash13(i + vec3(0, 1, 0)), hash13(i + vec3(1, 1, 0)), f.x), f.y),
	           mix(mix(hash13(i + vec3(0, 0, 1)), hash13(i + vec3(1, 0, 1)), f.x), mix(hash13(i + vec3(0, 1, 1)), hash13(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}
vec3 pot(vec3 p) {
	return vec3(vnoise(p), vnoise(p + vec3(31.4, 7.1, 2.9)), vnoise(p + vec3(-5.3, 19.7, 11.1)));
}
vec3 curl_noise(vec3 p) {
	const float e = 0.35;
	vec3 dx = pot(p + vec3(e, 0, 0)) - pot(p - vec3(e, 0, 0));
	vec3 dy = pot(p + vec3(0, e, 0)) - pot(p - vec3(0, e, 0));
	vec3 dz = pot(p + vec3(0, 0, e)) - pot(p - vec3(0, 0, e));
	return vec3(dy.z - dz.y, dz.x - dx.z, dx.y - dy.x) / (2.0 * e);
}

void main() {
	ivec3 id = ivec3(gl_GlobalInvocationID);
	ivec3 N = imageSize(dst);
	if (any(greaterThanEqual(id, N))) return;
	float dt = pc.a.x, h = pc.a.y;
	vec3 inv = 1.0 / vec3(N);
	vec3 p = vec3(id) + 0.5;
	vec3 po = p + vec3(pc.a.z, 0.0, pc.a.w);   // where this cell was in last step's grid
	vec4 s0 = texture(src, po * inv);
	vec3 v = s0.xyz;
	// back-trace (midpoint) for the velocity, plus a settling drift for the dust
	vec3 mid = po - v * (0.5 * dt / h);
	vec3 vm = texture(src, mid * inv).xyz;
	vec4 s = texture(src, (po - vm * (dt / h)) * inv);
	vec3 bd = po - (vm + vec3(0.0, -pc.c.z, 0.0)) * (dt / h);
	float d = texture(src, bd * inv).w;
	// dispersal: the small eddies the grid can't hold mix the dust out into the air around it
	// (turbulent diffusion), so a fresh plume spreads and thins instead of staying a tube
	if (pc.e.x > 0.0) {
		float r = pc.e.y;
		float avg = (texture(src, (bd + vec3(r, 0, 0)) * inv).w + texture(src, (bd - vec3(r, 0, 0)) * inv).w
			+ texture(src, (bd + vec3(0, r, 0)) * inv).w + texture(src, (bd - vec3(0, r * 0.6, 0)) * inv).w
			+ texture(src, (bd + vec3(0, 0, r)) * inv).w + texture(src, (bd - vec3(0, 0, r)) * inv).w) / 6.0;
		d = mix(d, avg, 1.0 - exp(-pc.e.x * dt));
	}
	v = s.xyz;
	// the still air around: drift with the wind, swirls die down slowly
	vec3 wind = vec3(pc.b.x, 0.0, pc.b.y);
	v = mix(v, wind, 1.0 - exp(-pc.c.y * dt));
	if (id.y == 0) v.xz = mix(v.xz, wind.xz * 0.4, 1.0 - exp(-2.5 * dt));   // ground drag
	d *= exp(-pc.c.x * dt);
	// thin out toward the sides / top of the box so nothing ever ends in a hard wall
	float e = min(min(float(id.x), float(N.x - 1 - id.x)), min(float(id.z), float(N.z - 1 - id.z)));
	e = min(e, float(N.y - 1 - id.y) * 2.0);
	d *= mix(1.0 - 4.0 * dt, 1.0, clamp(e / pc.c.w, 0.0, 1.0));

	int n = int(pc.b.z);
	for (int i = 0; i < n; i++) {
		Source q = srcs.s[i];
		vec3 dv = (p - q.pos_r.xyz) * h;
		float r = q.pos_r.w;
		float dl = length(dv);
		if (dl >= r) continue;
		float f = 1.0 - dl / r;
		f = f * f * (3.0 - 2.0 * f);
		d += q.vel_rate.w * f * dt;
		vec3 tv = q.vel_rate.xyz + (dl > 1e-4 ? dv / dl : vec3(0.0)) * q.misc.y;
		v = mix(v, tv, 1.0 - exp(-q.misc.x * f * dt));
	}
	// turbulence: swirls stir wherever there is dust (strongest in fresh, thick dust)
	if (d > 0.003) {
		vec3 wp = vec3(pc.d.x, 0.0, pc.d.y) + p * h;
		float tt = pc.b.w;
		vec3 q = wp * pc.d.w + vec3(-pc.b.x, -0.6, -pc.b.y) * tt * pc.d.w;
		vec3 cn = curl_noise(q) + 0.5 * curl_noise(q * 2.3 + 17.0);
		v += cn * pc.d.z * (0.25 + min(d, 1.2)) * dt;
	}
	if (id.y == 0) v.y = max(v.y, 0.0);
	imageStore(dst, id, vec4(v, clamp(d, 0.0, 6.0)));
}
