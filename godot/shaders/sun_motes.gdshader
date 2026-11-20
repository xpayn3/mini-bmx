// Dust motes drifting in the garage's sun shaft. Each mote is a tiny soft billboard that only shows
// where the sun can reach it: traced back toward the sun, does the line pass through the doorway?
// Outside the shaft it is invisible (additive, so nothing is drawn).
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform vec3 sun_dir = vec3(-0.6, 0.5, -0.6);   // towards the sun (normalised)
uniform float wall_z = -4.2;                       // the plane of the door opening
uniform vec4 door = vec4(-1.8, 1.8, 0.0, 3.2);     // x0, x1, y0, y1 of the opening
uniform float edge = 0.18;                         // soft shaft edge (m)
uniform vec3 tint : source_color = vec3(1.0, 0.82, 0.58);
uniform float energy = 7.0;

varying float v_lit;
varying float v_seed;
varying float v_seed2;
varying float v_dim;
varying float v_clump;
uniform float mote_size = 0.0045;   // the quad's size (m), set from the garage
uniform float min_px = 2.2;
uniform float bokeh_near = 1.6;     // m: motes closer to the camera than this go soft and big (out of focus)

float hash(float n) { return fract(sin(n * 12.9898) * 43758.5453); }
float hash3(vec3 p) { return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453); }
// smooth value noise: slow drifting clumps of thicker dust
float vnoise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash3(i), hash3(i + vec3(1, 0, 0)), f.x), mix(hash3(i + vec3(0, 1, 0)), hash3(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(hash3(i + vec3(0, 0, 1)), hash3(i + vec3(1, 0, 1)), f.x), mix(hash3(i + vec3(0, 1, 1)), hash3(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

void vertex() {
	vec3 p = MODEL_MATRIX[3].xyz;   // the mote's world position
	// trace toward the sun to the door plane
	float t = (wall_z - p.z) / sun_dir.z;
	vec3 h = p + sun_dir * t;
	float in_x = smoothstep(door.x - edge, door.x + edge, h.x) * (1.0 - smoothstep(door.y - edge, door.y + edge, h.x));
	float in_y = smoothstep(door.z, door.z + edge, h.y) * (1.0 - smoothstep(door.w - edge, door.w + edge, h.y));
	v_lit = in_x * in_y * step(wall_z, p.z) * step(0.0, t);
	float id = float(INSTANCE_ID);
	v_seed = hash(id + 0.37);
	v_seed2 = hash(id * 1.71 + 5.3);
	// clumps: the air carries thicker and thinner patches of dust that drift slowly through the shaft
	float n = vnoise(p * 1.4 + vec3(TIME * 0.035, TIME * 0.012, -TIME * 0.025)) * 0.65
		+ vnoise(p * 3.7 - vec3(TIME * 0.05, 0.0, TIME * 0.04)) * 0.35;
	v_clump = smoothstep(0.28, 0.72, n);
	// face the camera, keep the particle's own scale; a mote smaller than ~2 px on screen is drawn 2 px
	// wide and dimmed by the area it gained (fine specks stay visible instead of dropping between pixels)
	float s = length(MODEL_MATRIX[0].xyz);
	s *= 0.45 + 0.75 * v_seed2 * v_seed2 + 2.6 * pow(hash(id * 3.1 + 1.0), 18.0);   // mostly fine specks, now and then a big flake
	float z = max(0.05, -(VIEW_MATRIX * vec4(p, 1.0)).z);
	float px = 2.0 * z / (PROJECTION_MATRIX[1][1] * VIEWPORT_SIZE.y);   // one pixel in metres at the mote
	float want = mote_size * s;
	float grow = max(1.0, min_px * px / want);
	// out of focus near the lens: a big soft disc, the same light spread thin
	grow *= 1.0 + 5.0 * (1.0 - smoothstep(0.35, bokeh_near, z));
	v_dim = 1.0 / (grow * grow);
	s *= grow;
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0] * s, INV_VIEW_MATRIX[1] * s, INV_VIEW_MATRIX[2] * s, MODEL_MATRIX[3]);
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
}

void fragment() {
	float d = length(UV - 0.5) * 2.0;
	float a = pow(clamp(1.0 - d, 0.0, 1.0), 1.6);
	// flakes tumble at their own uneven pace: mostly a dull glow, now and then a sharp glint as a face turns to the sun
	// (two unrelated waves multiplied: the bright moments come irregularly, never as a steady pulse)
	float t = TIME + v_seed * 97.0;
	float w = (0.5 + 0.5 * sin(t * (0.5 + v_seed * 1.7))) * (0.5 + 0.5 * sin(t * (1.3 + v_seed2 * 2.9) + v_seed2 * 21.0));
	float glint = 0.25 + 0.55 * w + 2.2 * pow(w, 9.0);
	float bright = 0.3 + 0.7 * v_seed2 * v_seed;   // some motes are just fainter
	vec3 col = tint * mix(vec3(1.0), vec3(1.06, 0.97, 0.86), v_seed);   // a little warmer or paler, speck to speck
	float dens = mix(0.18, 1.0, v_clump);
	// 2.5: a soft dot spread over ~2 px; 1.9: the variation above averages ~half, keep the shaft as bright overall
	ALBEDO = col * energy * v_lit * glint * bright * dens * a * COLOR.a * v_dim * 2.5 * 1.9;
}
