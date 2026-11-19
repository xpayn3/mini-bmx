// Draws the dust simulation (scripts/fx/smoke_sim.gd) by raymarching its 3D lighting volume.
// The box's back faces are drawn (so it still works with the camera inside it); each pixel marches
// from the camera (or where the ray enters the box) to the scene depth / box exit. The grid follows the
// ground: a voxel's height is measured from the terrain (heightmap), so dust hugs slopes.
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, depth_test_disabled, cull_front, shadows_disabled, fog_disabled;
#include "res://shaders/atmos.gdshaderinc"

uniform sampler3D smoke : filter_linear, repeat_disable;
uniform sampler2D hmap : filter_linear, repeat_disable;
uniform sampler3D occ : filter_nearest, repeat_disable;     // dust near this 1.6 m brick? (empty-space skipping)
uniform sampler3D detail : filter_linear, repeat_enable;   // tiling noise: billows the grid can't hold
uniform float detail_amt = 0.85;
uniform vec3 drift = vec3(0.0);   // m: how far the detail has drifted (wind + slow rise)
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
uniform vec3 origin;          // world x / z of the grid corner (y unused)
uniform vec3 size_m;          // grid size in metres (x, height, z)
uniform float hm_cells = 32.0;
uniform vec3 box_min;
uniform vec3 box_max;
uniform vec3 sun_dir = vec3(0.4, 0.8, 0.3);   // toward the sun
uniform vec3 sun_col = vec3(3.0, 2.8, 2.5);
uniform vec3 amb_col = vec3(0.45, 0.55, 0.75);
uniform vec3 dust_col = vec3(0.75, 0.62, 0.48);
uniform float ext = 4.0;      // extinction per unit density per metre
uniform float step_m = 0.08;
uniform int max_steps = 160;

float hg(float c, float g) {
	float g2 = g * g;
	return (1.0 - g2) / pow(1.0 + g2 - 2.0 * g * c, 1.5);   // * 1/(4 pi) left out: isotropic = 1
}

void fragment() {
	vec3 ro = CAMERA_POSITION_WORLD;
	vec3 rd = normalize((INV_VIEW_MATRIX * vec4(VERTEX, 0.0)).xyz);
	vec3 inv = 1.0 / rd;
	vec3 t0 = (box_min - ro) * inv, t1 = (box_max - ro) * inv;
	vec3 tn = min(t0, t1), tf = max(t0, t1);
	float ta = max(max(max(tn.x, tn.y), tn.z), 0.05);
	float tb = min(min(tf.x, tf.y), tf.z);
	float zd = textureLod(depth_tex, SCREEN_UV, 0.0).r;
	vec4 vp = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, zd, 1.0);
	tb = min(tb, length(vp.xyz / vp.w));
	if (tb <= ta) discard;

	float cth = dot(rd, sun_dir);
	float phase = mix(hg(cth, 0.55), hg(cth, -0.2), 0.35);
	vec3 col = vec3(0.0);
	float T = 1.0;
	float jit = fract(52.9829189 * fract(dot(FRAGCOORD.xy, vec2(0.06711056, 0.00583715))));
	float t = ta + step_m * jit;
	float cl = -1.0;
	for (int i = 0; i < max_steps; i++) {
		if (t >= tb) break;
		vec3 p = ro + rd * t;
		vec2 g = (p.xz - origin.xz) / size_m.xz;
		float ds = step_m * 2.5;
		if (all(greaterThan(g, vec2(0.0))) && all(lessThan(g, vec2(1.0)))) {
			float gr = texture(hmap, (g * hm_cells + 0.5) / (hm_cells + 1.0)).r;
			float gy = (p.y - gr) / size_m.y;
			if (gy > 0.0 && gy < 1.0 && texture(occ, vec3(g.x, gy, g.y)).r < 0.004) {
				ds = 1.2;   // clear air for at least a brick around: jump
			} else if (gy > 0.0 && gy < 1.0) {
				vec4 s = texture(smoke, vec3(g.x, gy, g.y));
				float d = s.r;
				float n = 0.5;
				if (d > 0.004) {
					// erode with two octaves of noise: thin dust tears into wisps, thick dust gets lumpy billows
					vec3 q = p - drift;
					n = texture(detail, q * 0.13 + 0.71).r * 0.4 + texture(detail, q * 0.37).r * 0.4 + texture(detail, q * 0.95 + 0.37).r * 0.2;
					d *= clamp(1.0 + (d * 1.6 - n) * 3.0 * detail_amt, 0.0, 2.2);
				}
				if (d > 0.004) {
					ds = step_m;
					if (cl < 0.0) cl = cloud_ratio(p);
					float a = 1.0 - exp(-d * ext * ds);
					// sun (self-shadowed through the dust, cloud shadows) + sky, a little ground bounce
					vec3 L = dust_col * (sun_col * (s.g * phase * cl * (1.25 - n * 0.7)) + amb_col * (0.12 + 0.88 * s.b * s.b) + sun_col * 0.04);
					col += T * a * L;
					T *= 1.0 - a;
					if (T < 0.01) break;
				}
			}
		}
		t += ds;
	}
	if (T > 0.995) discard;
	ALBEDO = col / (1.0 - T);   // straight (un-premultiplied) colour for blend_mix
	ALPHA = 1.0 - T;
}
