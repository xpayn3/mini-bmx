// Grit: thousands of sand grains and specks thrown out with the dust, carried by the smoke sim's own
// air (scripts/fx/smoke_sim.gd writes the air velocity into vel_tex every frame). Each grain has a size:
// fine ones ride the air like the dust, coarse ones fly out ballistic and drop. They land and lie a moment,
// then fade. Emitted from up to 8 points this frame (tyre patches, landings, crash impacts).
shader_type particles;
render_mode disable_force, disable_velocity;

uniform sampler3D vel_tex : filter_linear, repeat_disable;   // air velocity (m/s) + density
uniform sampler2D hmap : filter_linear, repeat_disable;
uniform vec3 origin;
uniform vec3 size_m;
uniform float hm_cells = 32.0;
uniform vec4 em_pos[8];    // xyz, w = cumulative weight (0..1)
uniform vec4 em_vel[8];    // xyz throw velocity, w = spread (m/s)
uniform vec4 em_col[8];    // rgb colour (linear)
uniform int em_count = 0;

float rnd(inout uint s) {
	s = s * 747796405u + 2891336453u;
	uint w = ((s >> ((s >> 28u) + 4u)) ^ s) * 277803737u;
	return float((w >> 22u) ^ w) / 4294967295.0;
}

float ground_at(vec3 p, out vec3 g3) {
	vec2 g = (p.xz - origin.xz) / size_m.xz;
	float gr = texture(hmap, (clamp(g, 0.0, 1.0) * hm_cells + 0.5) / (hm_cells + 1.0)).r;
	g3 = vec3(g.x, (p.y - gr) / size_m.y, g.y);
	return gr;
}

void start() {
	uint s = NUMBER * 1973u + RANDOM_SEED * 9277u + 1u;
	float pick = rnd(s);
	int k = 0;
	for (int i = 0; i < 8; i++) {
		if (i >= em_count) break;
		k = i;
		if (pick <= em_pos[i].w) break;
	}
	vec3 dir = normalize(vec3(rnd(s) - 0.5, rnd(s) - 0.5, rnd(s) - 0.5) + vec3(0.0, 1e-3, 0.0));
	vec3 p = em_pos[k].xyz + dir * 0.12 * rnd(s);
	float size = rnd(s);
	size *= size;   // mostly fine grains, a few coarse bits
	VELOCITY = em_vel[k].xyz * (0.6 + 0.8 * rnd(s)) + dir * em_vel[k].w * (0.4 + rnd(s))
		+ vec3(0.0, (0.5 + rnd(s) * 1.5) * (0.4 + size), 0.0);
	TRANSFORM = mat4(1.0);
	TRANSFORM[3].xyz = p;
	CUSTOM = vec4(size, 0.0, rnd(s), 0.0);   // x: size 0..1, y: landed, z: random (glint phase)
	COLOR = vec4(em_col[k].rgb * (0.75 + 0.5 * rnd(s)), 1.0);
	if (em_count == 0) ACTIVE = false;
}

void process() {
	float size = CUSTOM.x;
	vec3 p = TRANSFORM[3].xyz;
	vec3 g3;
	float gr = ground_at(p, g3);
	if (CUSTOM.y < 0.5) {
		// the air it's in (zero outside the box)
		vec3 air = vec3(0.0);
		if (all(greaterThan(g3, vec3(0.0))) && all(lessThan(g3, vec3(1.0)))) air = texture(vel_tex, g3).xyz;
		// fine grains follow the air almost at once, coarse ones barely
		float tau = 0.04 + size * 0.9;
		VELOCITY += (air - VELOCITY) * (1.0 - exp(-DELTA / tau));
		VELOCITY.y -= 9.81 * DELTA * (0.08 + size * 0.92);
		p += VELOCITY * DELTA;
		if (p.y < gr + 0.01) {   // landed
			p.y = gr + 0.01;
			VELOCITY = vec3(0.0);
			CUSTOM.y = 1.0;
		}
	}
	TRANSFORM[3].xyz = p;
	// tiny: 5 mm fine grains .. 3 cm clods; shrink away at the end of life
	float life = clamp(CUSTOM.w / max(LIFETIME, 1e-3), 0.0, 1.0);
	CUSTOM.w += DELTA;
	float sc = mix(0.005, 0.028, size) * (1.0 - smoothstep(0.75, 1.0, life));
	TRANSFORM[0].xyz = vec3(sc, 0.0, 0.0);
	TRANSFORM[1].xyz = vec3(0.0, sc, 0.0);
	TRANSFORM[2].xyz = vec3(0.0, 0.0, sc);
}
