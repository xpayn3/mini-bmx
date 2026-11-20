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
varying float v_dim;
uniform float mote_size = 0.0045;   // the quad's size (m), set from the garage
uniform float min_px = 2.2;

float hash(float n) { return fract(sin(n * 12.9898) * 43758.5453); }

void vertex() {
	vec3 p = MODEL_MATRIX[3].xyz;   // the mote's world position
	// trace toward the sun to the door plane
	float t = (wall_z - p.z) / sun_dir.z;
	vec3 h = p + sun_dir * t;
	float in_x = smoothstep(door.x - edge, door.x + edge, h.x) * (1.0 - smoothstep(door.y - edge, door.y + edge, h.x));
	float in_y = smoothstep(door.z, door.z + edge, h.y) * (1.0 - smoothstep(door.w - edge, door.w + edge, h.y));
	v_lit = in_x * in_y * step(wall_z, p.z) * step(0.0, t);
	v_seed = hash(float(INSTANCE_ID) + 0.37);
	// face the camera, keep the particle's own scale; a mote smaller than ~2 px on screen is drawn 2 px
	// wide and dimmed by the area it gained (fine specks stay visible instead of dropping between pixels)
	float s = length(MODEL_MATRIX[0].xyz);
	float z = max(0.05, -(VIEW_MATRIX * vec4(p, 1.0)).z);
	float px = 2.0 * z / (PROJECTION_MATRIX[1][1] * VIEWPORT_SIZE.y);   // one pixel in metres at the mote
	float want = mote_size * s;
	float grow = max(1.0, min_px * px / want);
	v_dim = 1.0 / (grow * grow);
	s *= grow;
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0] * s, INV_VIEW_MATRIX[1] * s, INV_VIEW_MATRIX[2] * s, MODEL_MATRIX[3]);
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
}

void fragment() {
	float d = length(UV - 0.5) * 2.0;
	float a = pow(clamp(1.0 - d, 0.0, 1.0), 1.6);
	// flakes tumble: each catches the light now and then (a slow glint)
	float glint = 0.45 + 0.55 * pow(0.5 + 0.5 * sin(TIME * (0.6 + v_seed * 1.8) + v_seed * 40.0), 3.0);
	ALBEDO = tint * energy * v_lit * glint * a * COLOR.a * v_dim * 2.5;   // 2.5: a soft dot spread over ~2 px
}
