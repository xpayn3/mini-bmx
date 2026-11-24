shader_type canvas_item;
render_mode unshaded, blend_mix;
// One water drop (or one stretch of a rivulet) on the lens, drawn into the lens normal map (fx/lens_fx.gd,
// instances from fx/LensDropsCs.cs). Output, premultiplied by coverage: rg = the water surface's slope in
// screen space (0.5 = flat), b = its height (how far it bends the view), a = coverage.
// grade.gdshader decodes it (rgb / a) and refracts the scene through it.
// INSTANCE_CUSTOM: x = 0 round .. 1 drawn-out running drop, 2 = rivulet; y = height; zw = heading (cos, sin).

varying vec4 cd;

void vertex() {
	cd = INSTANCE_CUSTOM;
}

void fragment() {
	vec2 q = UV * 2.0 - 1.0;    // x along the heading (+ = front), y across
	bool riv = cd.x > 1.5;
	float a = q.x;
	float hw;
	if (riv) {
		hw = 1.0 - 0.15 * a * a;   // a channel; neighbouring segments overlap into one line
	} else {
		hw = sqrt(max(1.0 - a * a, 0.0));
		if (a < 0.0) hw *= mix(1.0, 1.0 + a * 0.85, cd.x);   // round head in front, a tail behind it
	}
	if (hw <= 0.001) discard;
	float u = q.y / hw;
	float cover = smoothstep(1.0, 0.72, abs(u));
	if (cover <= 0.0) discard;
	// the dome's slope: across the drop, and (for drops) front / back
	vec2 n = riv ? vec2(0.0, u) : vec2(a * (1.0 - 0.6 * cd.x), u);
	n /= max(1.0, length(n));
	float h = sqrt(max(1.0 - u * u, 0.0)) * (riv ? 1.0 : hw);
	vec2 ns = n.x * cd.zw + n.y * vec2(-cd.w, cd.z);
	COLOR = vec4(ns * 0.5 + 0.5, cd.y * h, cover * (riv ? 0.85 : 1.0));
}
