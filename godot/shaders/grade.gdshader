shader_type canvas_item;
// Post pass over the 3D view (one screen copy):
//  * colour grade from the web version: split tone (warm highlights, cool shadows) + vignette
//  * speed blur: radial streaks toward the screen edges, stronger the faster you go (the centre,
//    where the rider is, stays sharp)
// plain filtering: a mipmap sampler makes Godot build the screen's mip chain every frame. The speed blur needs the
// mips: game.gd swaps in a copy of this shader with filter_linear_mipmap here (GRADE_MIP_FROM / _TO) while blur > 0
uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform float grade_amt = 1.0;
uniform float blur = 0.0;      // 0..1
uniform float speed = 0.0;     // 0..1 speed feel: colour fringing, speed lines, tighter vignette
uniform vec2 focus = vec2(0.5, 0.52);
// photo mode (scripts/game/photo_mode.gd): filters, white balance, fade, vignette, grain, lens fringing, frame
uniform float photo = 0.0;
uniform int p_filter = 0;          // 0 none, 1 B&W, 2 sepia, 3 vintage, 4 teal & orange, 5 noir, 6 golden, 7 cross process, 8 bleach bypass
uniform float p_filter_amt = 1.0;
uniform float p_temp = 0.0;        // -1 cool .. 1 warm
uniform float p_tint = 0.0;        // -1 green .. 1 magenta
uniform float p_fade = 0.0;        // lifted blacks
uniform float p_vignette = 0.0;
uniform float p_grain = 0.0;
uniform float p_ca = 0.0;          // chromatic aberration toward the corners
uniform float p_aspect = 0.0;      // 0 = full screen, else width / height of the frame (black bars outside)

vec3 photo_filter(vec3 c, int f) {
	float l = dot(c, vec3(0.299, 0.587, 0.114));
	if (f == 1) return vec3(l);
	if (f == 2) return vec3(dot(c, vec3(0.393, 0.769, 0.189)), dot(c, vec3(0.349, 0.686, 0.168)), dot(c, vec3(0.272, 0.534, 0.131)));
	if (f == 3) {
		vec3 v = mix(vec3(l), c, 0.6) * vec3(1.06, 1.0, 0.86);
		return v * 0.86 + vec3(0.07, 0.06, 0.05);
	}
	if (f == 4) {
		vec3 sh = vec3(0.0, 0.07, 0.09);
		vec3 hi = vec3(0.09, 0.03, -0.06);
		return c + mix(sh, hi, smoothstep(0.15, 0.75, l));
	}
	if (f == 5) {
		float n = smoothstep(0.08, 0.82, l);
		return vec3(n * n * (3.0 - 2.0 * n));
	}
	if (f == 6) return c * vec3(1.12, 1.0, 0.8) + vec3(0.03, 0.015, 0.0);
	if (f == 7) {
		vec3 x = c;
		x.r = smoothstep(0.0, 1.0, x.r * 1.05);
		x.g = x.g * 1.04 + 0.01;
		x.b = x.b * 0.78 + 0.1;
		return x;
	}
	if (f == 8) {
		vec3 bl = vec3(l);
		vec3 ov = mix(2.0 * c * bl, 1.0 - 2.0 * (1.0 - c) * (1.0 - bl), step(0.5, bl));
		return mix(c, ov, 0.7) * 0.95;
	}
	return c;
}

void fragment() {
	vec2 uv = SCREEN_UV;
	vec4 c = texture(screen_tex, uv);
	if (photo > 0.5 && p_ca > 0.001) {
		vec2 dd = uv - 0.5;
		vec2 off = dd * dot(dd, dd) * 0.035 * p_ca;
		c.r = texture(screen_tex, uv + off).r;
		c.b = texture(screen_tex, uv - off).b;
	}
	float kb = 0.0;   // how much the speed blur smeared this pixel (the fringing below keeps it)
	if (blur > 0.001) {
		vec2 d = uv - focus;
		// only the left / right sides of the frame (NFS style): the road ahead (top middle with the trail camera) and
		// the rider stay sharp; it used to be an ellipse round the rider that reached the trail ahead
		float edge = smoothstep(0.33, 0.5, abs(uv.x - 0.5)) * (1.0 - 0.5 * smoothstep(0.1, 0.5, -(uv.y - 0.5)));
			edge *= 1.0 - 0.75 * smoothstep(0.55, 0.85, uv.y);   // 2026-11-24: outer sides only, lower frame (ground just ahead) stays sharp
		float k = blur * edge;
		if (k > 0.002) {
			vec3 acc = c.rgb;
			float jit = fract(sin(dot(FRAGCOORD.xy, vec2(12.9898, 78.233))) * 43758.5453);
			for (int i = 1; i <= 8; i++) {
				float s = (float(i) + jit) / 8.0;
				acc += textureLod(screen_tex, uv - d * s * k * 0.09, k * 1.0).rgb;
			}
			c.rgb = acc / 9.0;
			kb = k;
		}
	}
	if (speed > 0.01) {
		vec2 d2 = uv - focus;
		float r2 = length(d2 * vec2(1.6, 1.0));
		float edge2 = smoothstep(0.25, 0.75, r2);
		// colour fringing toward the corners (red out, blue in), like a lens pushed hard
		vec2 ca = d2 * 0.0025 * speed * edge2 * edge2;
		// added as the shifted-minus-centre difference so the blur above isn't thrown away on red / blue
		float lod = kb * 1.5;
		vec2 cc = textureLod(screen_tex, uv, lod).rb;
		c.r += textureLod(screen_tex, uv + ca, lod).r - cc.x;
		c.b += textureLod(screen_tex, uv - ca, lod).b - cc.y;
		// speed lines: thin streaks rushing outward from the rider, only in the outer ring of the frame
		float ang = atan(d2.y, d2.x);
		float lanes = 140.0;
		float lane = floor(ang / 6.2831853 * lanes);
		float h = fract(sin(lane * 91.17) * 43758.5453);
		if (h > 0.6) {
			float across = abs(fract(ang / 6.2831853 * lanes) - 0.5) * 2.0;
			float thin = pow(1.0 - across, 12.0);
			float seg = fract(r2 * (1.6 + h) - TIME * (1.4 + 2.2 * h) * (0.6 + speed));
			float streak = smoothstep(0.0, 0.08, seg) * smoothstep(0.55, 0.12, seg);
			float s_amt = thin * streak * smoothstep(0.38, 0.8, r2) * speed * speed * 0.42;
			c.rgb = mix(c.rgb, vec3(1.0, 0.98, 0.94), s_amt);
		}
	}
	float l = dot(c.rgb, vec3(0.299, 0.587, 0.114));
	c.rgb += (l - 0.45) * vec3(0.035, 0.012, -0.03) * grade_amt;
	vec2 v = SCREEN_UV - 0.5;
	c.rgb *= 1.0 - dot(v, v) * (0.6 * grade_amt + 0.55 * speed);   // the frame closes in at speed
	if (photo > 0.5) {
		c.rgb *= vec3(1.0 + 0.14 * p_temp, 1.0 + 0.02 * p_temp - 0.08 * p_tint, 1.0 - 0.16 * p_temp);
		c.rgb.rb *= 1.0 + 0.05 * p_tint;
		if (p_filter > 0) c.rgb = mix(c.rgb, photo_filter(max(c.rgb, vec3(0.0)), p_filter), p_filter_amt);
		c.rgb = mix(c.rgb, c.rgb * 0.82 + vec3(0.075, 0.07, 0.08), p_fade);
		vec2 ss = 1.0 / SCREEN_PIXEL_SIZE;
		float scr = ss.x / ss.y;
		vec2 fuv = SCREEN_UV;   // position inside the chosen frame
		vec2 half_ext = vec2(0.5);
		if (p_aspect > 0.01) {
			if (p_aspect < scr) half_ext.x = 0.5 * p_aspect / scr;
			else half_ext.y = 0.5 * scr / p_aspect;
		}
		vec2 q = (fuv - 0.5) / (half_ext * 2.0);   // -0.5..0.5 inside the frame
		float fa = (half_ext.x / half_ext.y) * scr;
		float vr = length(q * vec2(fa, 1.0)) / (0.5 * length(vec2(fa, 1.0)));   // 1 in the frame's corners
		c.rgb *= 1.0 - smoothstep(0.35, 1.05, vr) * p_vignette * 0.85;
		if (p_grain > 0.001) {
			float g = fract(sin(dot(FRAGCOORD.xy + fract(TIME * 7.13) * 431.0, vec2(12.9898, 78.233))) * 43758.5453);
			float g2 = fract(sin(dot(FRAGCOORD.xy * 0.5 + fract(TIME * 3.7) * 97.0, vec2(39.346, 11.135))) * 24634.6345);
			float l2 = dot(c.rgb, vec3(0.299, 0.587, 0.114));
			c.rgb += ((g + g2) - 1.0) * p_grain * 0.09 * (0.35 + 0.65 * (1.0 - abs(l2 - 0.5) * 2.0));
		}
		if (abs(q.x) > 0.5 || abs(q.y) > 0.5) c.rgb = vec3(0.012);
	}
	COLOR = vec4(c.rgb, 1.0);
}
