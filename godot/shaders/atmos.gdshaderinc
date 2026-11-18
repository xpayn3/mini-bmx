// Weather every world shader shares (port of src/atmos.js on the three.js branch), driven by global
// shader uniforms (project.godot [shader_globals], set each frame by scripts/world/atmos.gd):
//  * atm_wind:   xy = direction, z = time, w = gust strength (0 = still air)
//  * atm_pusher: xyz = what parts the grass (the bike), w = strength
//  * atm_cloud:  xy = drift offset (m), z = shadow depth (0 = off), w = cloud shade at the rider
// Cloud shadows only dim the SUN: the sun light itself is dimmed by the shade at the rider (so the
// bike and rider go into shade too), and world shaders apply shade(here) / shade(rider) on top.

global uniform vec4 atm_wind;
global uniform vec4 atm_pusher;
global uniform vec4 atm_cloud;

// 0..1: how hard the gust is blowing at this spot. Long fronts travel downwind, broken up across it.
float wind_gust(vec2 p) {
	vec2 d = atm_wind.xy;
	float s = dot(p, d) * 0.11 - atm_wind.z * 0.9;
	float a = sin(s) * 0.5 + 0.5;
	float b = sin(s * 2.3 + 1.7 + dot(p, vec2(-d.y, d.x)) * 0.05) * 0.5 + 0.5;
	float g = a * 0.7 + b * 0.3;
	g *= 0.65 + 0.35 * sin(dot(p, vec2(-d.y, d.x)) * 0.045 + atm_wind.z * 0.21);
	return g * g * atm_wind.w;
}

// world-space offset of a point h metres up a plant rooted at base. stiff = 1 grass, less for stiffer
// plants. push = 1 lets the bike part it.
vec3 wind_bend(vec3 base, float h, float stiff, float push) {
	vec2 d = atm_wind.xy;
	float g = wind_gust(base.xz);
	float ph = base.x * 0.9 + base.z * 0.7;
	// fixed flutter rates; a gust only makes them bigger. (Scaling the RATE by g, as before, multiplied the
	// ever-growing time by a changing number: every passing gust front whipped the grass faster the longer
	// the ride went on.) The quicker partial fades in with the gust instead.
	float tw = atm_wind.z;
	float flutter = sin(tw * 3.1 + ph) * (0.25 + g * 0.35) + sin(tw * 4.7 + ph * 1.3) * g * 0.3
		+ sin(tw * 5.3 + ph * 1.7) * 0.15;
	vec2 off = d * (0.25 + g * 1.0 + flutter * 0.35) * step(0.001, atm_wind.w) + vec2(-d.y, d.x) * flutter * 0.25;
	vec3 o = vec3(off.x, 0.0, off.y) * h * h * stiff;
	vec2 aw = base.xz - atm_pusher.xz;
	float dd = length(aw);
	float k = (1.0 - smoothstep(0.25, 0.9, dd)) * step(abs(base.y - atm_pusher.y), 1.5) * atm_pusher.w * push;
	o.xz += aw / max(dd, 1e-3) * k * h * 0.9 * stiff;
	o.y -= dot(o.xz, o.xz) * 1.4 + k * h * 0.3 * stiff;   // bending, not stretching: the tip comes down
	return o;
}

// integer hash: the same bits on the GPU and in GDScript (atmos.gd), so the rider's shade matches
float cloud_hash(vec2 c) {
	uint h = uint(int(c.x)) * 1597334673u ^ uint(int(c.y)) * 3812015801u;
	h = (h ^ (h >> 16u)) * 2246822519u;
	h ^= h >> 13u;
	return float(h & 16777215u) / 16777215.0;
}
float cloud_noise(vec2 p) {
	vec2 i = floor(p), f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(cloud_hash(i), cloud_hash(i + vec2(1.0, 0.0)), f.x),
	           mix(cloud_hash(i + vec2(0.0, 1.0)), cloud_hash(i + vec2(1.0, 1.0)), f.x), f.y);
}
// 1 = full sun, lower = under a cloud
float cloud_shade(vec3 w) {
	if (atm_cloud.z <= 0.0) return 1.0;
	vec2 p = (w.xz + atm_cloud.xy) * 0.03;   // ~30 m clouds: their edges pass through the view often
	float n = cloud_noise(p) * 0.62 + cloud_noise(p * 2.2 + 5.3) * 0.28 + cloud_noise(p * 5.1 - 2.1) * 0.10;
	return 1.0 - atm_cloud.z * smoothstep(0.5, 0.66, n);
}
// what the sun light (already dimmed to the rider's shade) needs on top at this point
float cloud_ratio(vec3 w) {
	return cloud_shade(w) / max(atm_cloud.w, 0.05);
}

// Lambert lighting for world shaders with a light() function, with cloud shadows on the sun and
// (back > 0) light through thin leaves / blades from behind. Call from light():
//   DIFFUSE_LIGHT += atmos_diffuse(NORMAL, LIGHT, ATTENUATION * LIGHT_COLOR, LIGHT_IS_DIRECTIONAL, v_world, back);
vec3 atmos_light_col(vec3 att_col, bool directional, vec3 wpos) {
	return att_col / PI * (directional ? cloud_ratio(wpos) : 1.0);
}
vec3 atmos_diffuse(vec3 n, vec3 l, vec3 att_col, bool directional, vec3 wpos, float back) {
	vec3 lc = atmos_light_col(att_col, directional, wpos);
	return (clamp(dot(n, l), 0.0, 1.0) + clamp(dot(-n, l), 0.0, 1.0) * back) * lc;
}
