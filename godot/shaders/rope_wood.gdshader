// Rope bridge wood: the deck planks (MultiMesh of unit boxes, grain along the plank = local z, tone from the instance
// colour) on the ambientCG Wood049 plank scan, and the bridge's log posts / braces / deck logs (meshes built round
// their local y, round in x z) on the Wood035 scan wrapped round the log a whole number of times (no seam).
// Mapped in metres on the part itself, so it moves with the swinging deck instead of swimming through it.
shader_type spatial;
render_mode cull_back;
uniform sampler2D wood_col : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D wood_nrm : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D wood_rgh : hint_roughness_gray, filter_linear_mipmap_anisotropic, repeat_enable;
uniform bool log_mode = false;   // false: planks (boxes, grain along z); true: round logs (grain along y)
uniform float tile = 0.9;        // metres of wood per texture repeat along the grain
uniform float log_r = 0.15;      // a log's radius (sets how many times the scan wraps round it)
uniform vec3 scan_mean = vec3(0.2022, 0.1272, 0.0773);   // the scan's mean colour (linear): the tint keeps its grain, sets its tone
varying vec3 v_m;
varying vec3 v_n;
varying vec3 v_tint;
varying flat float v_seed;
varying float v_foot;
varying vec3 v_sc;     // the part's size (m) along its own axes
uniform float edge_wear = 0.02;   // planks: how far in from an edge the wood looks rubbed (m)

void vertex() {
	vec3 sc = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), length(MODEL_MATRIX[2].xyz));
	v_m = VERTEX * sc;
	v_sc = sc;
	v_n = NORMAL;
	// planks: the mesh's normals are in metres; the MultiMesh turns them with its stretch, so divide it back out
	if (!log_mode) NORMAL = NORMAL / sc;
	v_tint = mix(COLOR.rgb / 12.92, pow((COLOR.rgb + 0.055) / 1.055, vec3(2.4)), step(0.04045, COLOR.rgb));   // the colours are sRGB
	v_foot = COLOR.a;
	v_seed = fract(float(INSTANCE_ID) * 0.6180339 + MODEL_MATRIX[3].x * 0.137 + MODEL_MATRIX[3].z * 0.291);
}

void fragment() {
	vec3 an = abs(v_n);
	vec2 uv;
	vec3 ax_u, ax_v;
	bool end_grain;
	if (log_mode) {
		float wraps = max(1.0, round(TAU * log_r / tile));
		float ang = atan(v_m.z, v_m.x) / TAU + 0.5;
		end_grain = an.y > 0.7;
		uv = end_grain ? v_m.xz * 3.0 : vec2(v_m.y / tile, ang * wraps);
		ax_u = vec3(0.0, 1.0, 0.0);
		ax_v = normalize(vec3(-v_m.z, 0.0, v_m.x) + 1e-5);
		if (end_grain) { ax_u = vec3(1.0, 0.0, 0.0); ax_v = vec3(0.0, 0.0, 1.0); }
	} else {
		end_grain = an.z > 0.6;
		float across = an.y > an.x ? v_m.x : v_m.y;
		uv = end_grain ? v_m.xy * 4.0 : vec2(v_m.z / tile, across / tile * 1.3);
		ax_u = vec3(0.0, 0.0, 1.0);
		ax_v = an.y > an.x ? vec3(1.0, 0.0, 0.0) : vec3(0.0, 1.0, 0.0);
		if (end_grain) { ax_u = vec3(1.0, 0.0, 0.0); ax_v = vec3(0.0, 1.0, 0.0); }
	}
	uv += vec2(v_seed * 5.3, v_seed * 2.7);
	vec3 wood = texture(wood_col, uv).rgb;
	float rough = texture(wood_rgh, uv).r;
	vec3 nt = texture(wood_nrm, uv).rgb * 2.0 - 1.0;
	vec3 col = clamp(wood / scan_mean, vec3(0.45), vec3(1.6)) * v_tint;
	if (end_grain) col *= 0.75;
	// weathered: silvery-grey where the grain is raised, a little greener grime toward a plank's ends / a log's foot
	float lum = dot(col, vec3(0.3, 0.55, 0.15));
	col = mix(col, vec3(lum) * vec3(1.02, 1.0, 0.96), log_mode ? 0.1 : 0.18);
	if (log_mode) {
		float foot = 1.0 - smoothstep(0.0, 0.4, v_m.y);
		col = mix(col, col * vec3(0.55, 0.5, 0.42), foot * v_foot);
	} else {
		float edge = smoothstep(0.75, 1.0, abs(v_m.z) / max(0.01, length(MODEL_MATRIX[2].xyz) * 0.5));
		col *= mix(1.0, 0.8, edge);
	}
	vec3 nbase = NORMAL;
	if (!log_mode) {
		// the mesh's rounded edges (RopeBridge._plank_mesh): rubbed, paler and drier along them
		vec3 half_ = v_sc * 0.5;
		float edge_k = 0.0;
		for (int i = 0; i < 3; i++) {
			if (abs(v_n[i]) > 0.9) continue;   // this face's own axis
			edge_k = max(edge_k, 1.0 - smoothstep(0.0, edge_wear, half_[i] - abs(v_m[i])));
		}
		col *= 1.0 + 0.18 * edge_k;
		rough = mix(rough, 0.85, edge_k * 0.5);
	}
	vec3 tu = normalize((VIEW_MATRIX * MODEL_MATRIX * vec4(ax_u, 0.0)).xyz);
	vec3 tv = normalize((VIEW_MATRIX * MODEL_MATRIX * vec4(ax_v, 0.0)).xyz);
	NORMAL = normalize(nbase + (tu * nt.x + tv * nt.y) * 0.8);
	ALBEDO = col;
	ROUGHNESS = clamp(rough * 1.1, 0.5, 1.0);
	SPECULAR = 0.3;
}
