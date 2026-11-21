// Wet look after riding through water (port of src/grime.js): a thin film over each part -- darker
// (water fills the surface) and glossy, with drops beading and running down. Drawn as the last
// next_pass, only while something is wet. Premultiplied: the film darkens by its alpha but its
// highlights are added at full strength.
shader_type spatial;
render_mode blend_premul_alpha, depth_draw_never, cull_back, diffuse_burley, specular_schlick_ggx;

global uniform vec4 grime;   // x = mud, y = wet 0..1, z = time
global uniform mat4 grime_root;
global uniform float rider_trim;   // light match 0..1: how much of the roll-off below is applied
uniform sampler2D screen_tex : hint_screen_texture, filter_nearest;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
const float TRIM_KNEE = 0.45;     // scene-linear brightness (brightest channel) left alone
const float TRIM_SOFT = 0.5;      // how gently it rolls off above the knee (smaller = flatter)

varying vec3 v_local;
varying vec3 v_root;

float wt_hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

void vertex() {
	v_local = VERTEX;
	v_root = (grime_root * (MODEL_MATRIX * vec4(VERTEX, 1.0))).xyz;
	POSITION = PROJECTION_MATRIX * (MODELVIEW_MATRIX * vec4(VERTEX, 1.0));
	POSITION.z += 0.00008 * POSITION.w;
}

void fragment() {
	float w = grime.y;
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
	ROUGHNESS = mix(1.0, mix(0.18, 0.04, bead), wk);
	SPECULAR = (0.5 + bead * 0.5) * wk;
	NORMAL = normalize(NORMAL + (VIEW_MATRIX * vec4(0.0, bead * 0.6, 0.0, 0.0)).xyz);
}
