// Wet look after riding through water (port of src/grime.js): a thin film over each part -- darker
// (water fills the surface) and glossy, with drops beading and running down. Drawn as the last
// next_pass, only while something is wet. Premultiplied: the film darkens by its alpha but its
// highlights are added at full strength.
shader_type spatial;
render_mode blend_premul_alpha, depth_draw_never, cull_back, diffuse_burley, specular_schlick_ggx;

global uniform vec4 grime;   // x = mud, y = wet 0..1, z = time
global uniform mat4 grime_root;
global uniform vec4 grime_wf;   // front axle in bike-root space (xyz) + tyre radius (w): the ground is y - w
global uniform float rider_trim;   // light match 0..1: how much of the roll-off below is applied
uniform sampler2D screen_tex : hint_screen_texture, filter_nearest;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
const float TRIM_KNEE = 0.45;     // scene-linear brightness (brightest channel) left alone
const float TRIM_SOFT = 0.5;      // how gently it rolls off above the knee (smaller = flatter)

global uniform vec4 grime_wf0;   // the front axle when the parts were pinned (w = 0: not yet)
// the same pinning as the mud pass (grime.gd _pin, shaders/grime_mud): the water line and the drop columns are
// measured where the point sat in the riding pose, so they stay on the leg / arm as it moves (they used to be
// worked out from where it is now: the line and the drops slid over the pedalling legs and the swinging fork)
instance uniform float grime_pin = 0.0;
instance uniform vec4 grime_hrow = vec4(0.0);
instance uniform vec4 grime_r0 = vec4(0.0);
instance uniform vec4 grime_r2 = vec4(0.0);

varying vec3 v_root;
varying float v_ground;

float wt_hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

void vertex() {
	vec4 live = grime_root * (MODEL_MATRIX * vec4(VERTEX, 1.0));
	v_root = live.xyz;
	v_ground = grime_wf.y - grime_wf.w;
	if (grime_pin > 2.5) {
		// flapping parts (race number, strap tails, hair): no fixed shape, a steady place from UV + vertex index
		float id = fract(sin(float(VERTEX_ID) * 12.9898) * 43758.5453);
		v_root = vec3(UV.x * 0.3, 1.2 + UV.y * 0.05, id * 0.4);
		v_ground = 0.0;
	} else if (grime_pin > 0.5) {
		vec3 rest = grime_pin > 1.5 ? CUSTOM0.xyz : VERTEX;
		vec4 r4 = vec4(rest, 1.0);
		float hy = dot(grime_hrow, r4);
		// skinned torso / fingers: only their height is known, the columns run on the rest shape
		v_root = grime_pin > 1.5 ? vec3(rest.x * 0.3, hy, rest.z * 0.3) : vec3(dot(grime_r0, r4), hy, dot(grime_r2, r4));
		if (grime_wf0.w > 0.0) v_ground = grime_wf0.y - grime_wf0.w;
	}
	POSITION = PROJECTION_MATRIX * (MODELVIEW_MATRIX * vec4(VERTEX, 1.0));
	POSITION.z += 0.00008 * POSITION.w;
}

void fragment() {
	// the water creeps up from the ground: grime.y is how far it has got (0..1 = ground .. above the helmet), and
	// it dries from the top down. Not the whole bike + rider at once (2026-11-23)
	float h = v_root.y - v_ground;
	float level = mix(-0.05, 1.95, grime.y);
	float w = clamp(grime.y * 1.6, 0.0, 1.0) * (1.0 - smoothstep(level - 0.3, level + 0.05, h));
	// running drops: columns of beads sliding down in bike-root space
	vec2 g = vec2(v_root.z + v_root.x * 0.6, v_root.y) * vec2(60.0, 18.0);
	float col = floor(g.x);
	float sp = 0.4 + wt_hash(vec2(col, 3.0)) * 1.2;
	float y = fract(g.y + grime.z * sp * 0.25 + wt_hash(vec2(col, 7.0)));
	float bead = smoothstep(0.35, 0.0, abs(fract(g.x) - 0.5)) * smoothstep(0.85, 0.95, y) * step(0.55, wt_hash(vec2(col, 11.0)));
	ALBEDO = vec3(0.0);
	float a_wet = clamp(w * (0.35 + bead * 0.3), 0.0, 1.0);
	// light match: a face turned to a low sun gets many times the light of the ground the picture is exposed for,
	// and bright kit colours burn out. Read how bright this pixel of the rider / bike came out and roll off what is
	// above the knee (dark parts and anything in shade stay as they are). No gloss of its own: the wet film's
	// highlights fade in with the water.
	vec3 lit = texture(screen_tex, SCREEN_UV).rgb;
	float lmax = max(max(lit.r, lit.g), max(lit.b, 1e-4));
	float over = max(lmax - TRIM_KNEE, 0.0);
	float kept = (min(lmax, TRIM_KNEE) + over / (1.0 + over / TRIM_SOFT)) / lmax;
	float trim = rider_trim * (1.0 - kept);
	// only on the surface that is seen: this pass is pulled towards the lens (POSITION.z above), so a part lying
	// just under another (elbow / shoulder balls inside the sleeves) drew its film too = dark discs on the joints
	vec4 scn = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, texture(depth_tex, SCREEN_UV).r, 1.0);
	if (-VERTEX.z + scn.z / scn.w > 0.001) trim = 0.0;
	ALPHA = 1.0 - (1.0 - a_wet) * (1.0 - trim);
	float wk = clamp(w * 4.0, 0.0, 1.0);
	ROUGHNESS = mix(1.0, mix(0.32, 0.1, bead), wk);   // wet, not a mirror (0.18 / 0.04 read as glass)
	SPECULAR = (0.35 + bead * 0.4) * wk;
	NORMAL = normalize(NORMAL + (VIEW_MATRIX * vec4(0.0, bead * 0.6, 0.0, 0.0)).xyz);
}
