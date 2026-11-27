// Dust and mud on the bike and rider (port of src/grime.js), drawn as a next_pass over each part's own
// material so it works on every material (imported, car paint, the rider's). First a thin see-through
// film of dust (grime_dust.a), cloudy and thickest low down; the mud splotches (opaque) come later on top.
// Both start low down (tyres, chainstays, shoes) and creep up as they build;
// the noise lives in each part's own space, so mud sticks to the part (the tyre's mud turns with it).
// Globals (scripts/bike/grime.gd): grime.x = mud 0..1, grime.y = wet 0..1, mud_col, grime_root =
// world -> bike root (y = height above the ground), grime_wf / grime_wr = the tyres (axle, radius).
// Where it gathers (the dirt map): low down; in the spray off each tyre (fork arch + lowers, the down tube
// behind the front wheel, seat tube / stays round the rear, the shins); packed into crevices and joints
// (a baked 3D map of the bike, cav_tex); on undersides and forward faces (mud), on top faces (settling dust).
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

global uniform vec4 grime;
global uniform vec4 mud_col : source_color;       // the mud coming on now (the ground ridden now)
global uniform vec4 mud_col_old : source_color;   // the dried crust: the mud of ~a minute ago
global uniform mat4 grime_root;
global uniform vec4 grime_dust;   // rgb = dust colour, a = how dusty 0..1
global uniform vec4 grime_age;    // x = how dry the mud is 0 (fresh) .. 1 (crust), y = how much crust flaked off,
                                  // z = the mud level that is a dry crust (< 0: old look, one dryness for all)
global uniform vec4 grime_wf;     // front tyre: axle in bike-root space, radius
global uniform vec4 grime_wr;     // rear tyre
global uniform vec4 grime_wf0;    // the tyres where they were when the parts were pinned (w = 0: not yet):
global uniform vec4 grime_wr0;    // pinned parts measure the spray against these, so it stays put on them
uniform sampler3D cav_tex : filter_linear, repeat_disable;   // crevice map (grime.gd _cav_work)
uniform vec3 cav_min = vec3(0.0);
uniform vec3 cav_size = vec3(1.0);
uniform float cav_on = 0.0;
uniform bool debug_map = false;   // tests (BMX_GRIME_MAP): r = tyre spray, g = crevices, b = undersides / forward faces
uniform float bias = 1.0;   // how readily this part collects mud (tyres 1.8 .. helmet 0.5)
// rider parts move against the bike every frame (pedalling legs, a bending spine, ragdoll): grime.gd pins
// them so the mud stays put on the part. 0 = free (bike parts), 1 = pinned, 2 = pinned + skinned (the
// torso: noise from its rest shape in CUSTOM0, not the bent one). grime_hrow: height above the bike root
// as a fixed function of the part's own vertex (taken once from the riding pose).
// tyre: like a real knobby (2026-11-27): mud packs into the gaps between the knobs and round their bases first,
// creeps up the knob sides, and only cakes the knob tops in deep mud (the ground scrubs them); the sidewall gets
// dirty last, from the shoulder down, in clumps flung round it, cleanest at the rim. Where a point is on the tyre
// comes from the mesh's UV2 (WheelGen: x = knob base 0 .. tip 1, y = 0.001 + crown 0 .. bead 1); a tyre without it
// (an imported model) falls back to the normal. No height term on tyres: the mud doesn't swim as the wheel turns.
uniform bool tyre = false;
// wheel: rim / hub / spokes / rotor. No dirt map, no height (they turn): mud in a few clumps round the rim,
// more toward the tyre bead, dust in uneven drifts. Axle = local Z.
uniform bool wheel = false;
// decal: this pass follows a sticker (logo / lettering) so the dirt covers it; only where the sticker is
uniform bool decal = false;
uniform sampler2D decal_tex : source_color, filter_linear_mipmap;
instance uniform float grime_pin = 0.0;
instance uniform vec4 grime_hrow = vec4(0.0);
instance uniform vec4 grime_r0 = vec4(0.0);   // with grime_hrow and grime_r2: part -> bike root at pin time
instance uniform vec4 grime_r2 = vec4(0.0);

varying vec3 v_local;
varying vec3 v_p;       // where this point sits on the bike (bike-root space, rest pose)
varying vec3 v_n;       // its normal there
varying float v_sp;     // 1 = v_p / v_n are known (not the skinned torso / fingers)
varying float v_hgt;
varying vec2 v_tyre;    // tyre: x = how far up a knob (0 casing / base .. 1 tip), y = crown 0 .. bead 1
varying float v_rest;   // 1 = pinned: use the tyres as they were at pin time

float gr_hash(vec3 p) { p = fract(p * 0.3183099 + 0.1); p *= 17.0; return fract(p.x * p.y * p.z * (p.x + p.y + p.z)); }
float gr_noise(vec3 x) {
	vec3 i = floor(x), f = fract(x); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(gr_hash(i), gr_hash(i + vec3(1,0,0)), f.x), mix(gr_hash(i + vec3(0,1,0)), gr_hash(i + vec3(1,1,0)), f.x), f.y),
	           mix(mix(gr_hash(i + vec3(0,0,1)), gr_hash(i + vec3(1,0,1)), f.x), mix(gr_hash(i + vec3(0,1,1)), gr_hash(i + vec3(1,1,1)), f.x), f.y), f.z);
}

void vertex() {
	vec3 rest = (grime_pin > 1.5 && grime_pin < 2.5) ? CUSTOM0.xyz : VERTEX;
	v_local = rest;
	v_tyre = UV2.y > 0.0005 ? vec2(UV2.x, UV2.y - 0.001) : vec2(0.0, abs(normalize(NORMAL).z) * 0.8);
	v_hgt = grime_pin > 0.5 ? dot(grime_hrow, vec4(rest, 1.0)) : (grime_root * (MODEL_MATRIX * vec4(VERTEX, 1.0))).y;
	v_sp = 1.0;
	v_rest = (grime_pin > 0.5 && grime_wf0.w > 0.0) ? 1.0 : 0.0;
	if (grime_pin > 2.5) {
		// flapping parts, rebuilt every frame (race number, strap tails, hair): their vertices move, so the noise
		// comes from what stays the same on them (the vertex's index, its UV) and there is no dirt map at all
		float id = fract(sin(float(VERTEX_ID) * 12.9898) * 43758.5453);
		v_local = vec3(UV * 6.0, id * 2.0);
		v_hgt = 0.9; v_p = vec3(0.0, v_hgt, 0.0); v_n = vec3(0.0, 1.0, 0.0); v_sp = 0.0;
	} else if (grime_pin > 1.5) {
		v_p = vec3(0.0, v_hgt, 0.0); v_n = vec3(0.0, 1.0, 0.0); v_sp = 0.0;
	} else if (grime_pin > 0.5) {
		vec4 r4 = vec4(rest, 1.0);
		v_p = vec3(dot(grime_r0, r4), v_hgt, dot(grime_r2, r4));
		v_n = normalize(vec3(dot(grime_r0.xyz, NORMAL), dot(grime_hrow.xyz, NORMAL), dot(grime_r2.xyz, NORMAL)) + 1e-6);
	} else {
		v_p = (grime_root * (MODEL_MATRIX * vec4(VERTEX, 1.0))).xyz;
		v_n = normalize(mat3(grime_root) * (mat3(MODEL_MATRIX) * NORMAL) + 1e-6);
	}
	// drawn exactly over the part: nudge toward the camera so it wins the depth test (reverse Z)
	POSITION = PROJECTION_MATRIX * (MODELVIEW_MATRIX * vec4(VERTEX, 1.0));
	POSITION.z += 0.00004 * POSITION.w;
}

// how much of a tyre's spray reaches p: close round the tread (a fender-sized band), near the wheel's plane,
// more above the axle (it comes off the top), more on faces turned toward the tyre
float spray(vec4 wh, vec3 p, vec3 n) {
	if (wh.w <= 0.0) return 0.0;
	vec3 d = p - wh.xyz;
	float r = length(d.xy);
	float band = smoothstep(0.42, 0.04, max(r - wh.w, 0.0)) * smoothstep(wh.w * 0.45, wh.w * 0.85, r);
	float plane = smoothstep(0.3, 0.05, abs(d.z) - 0.04);
	float above = 0.4 + 0.6 * smoothstep(-0.3, 0.5, d.y / max(r, 1e-3));
	float face = clamp(0.35 - 0.65 * dot(n, vec3(d.xy / max(r, 1e-3), 0.0)), 0.0, 1.0);
	return band * plane * above * face;
}

// one noise octave, faded to its average where it gets finer than ~2 pixels (px = the pixel size in the part's
// own space): sub-pixel noise read at a different spot every frame is what made the mud shimmer as the camera moved
float gr_oct(vec3 p, float f, float px) {
	float k = 1.0 - smoothstep(0.25, 0.6, px * f);
	return k > 0.0 ? mix(0.5, gr_noise(p * f), k) : 0.5;
}

// tyre mud cover at mud level lvl (see `tyre` above). ty = v_tyre, side = the flung clumps round the wall
float tyre_cover(float lvl, vec2 ty, float side) {
	float band = 1.0 - smoothstep(0.45, 0.62, ty.y);              // the tread: crown + shoulder knobs
	float gaps = lvl * 1.8;                                       // between the knobs: packs first
	float tops = pow(lvl, 1.7) * 1.2;                             // knob tops: scrubbed, cake only when deep
	float tread = mix(gaps, tops, ty.x) * band;
	float wall = max(lvl - 0.18, 0.0) * 1.6 * (1.0 - smoothstep(0.45, 1.0, ty.y)) * side;
	return max(tread, wall);
}

vec3 gr_hash3(vec3 p) {
	p = vec3(dot(p, vec3(127.1, 311.7, 74.7)), dot(p, vec3(269.5, 183.3, 246.1)), dot(p, vec3(113.5, 271.9, 124.6)));
	return fract(sin(p) * 43758.5453);
}
// cells of a dry mud crust: x = distance to the nearest cell point, y = to the second (y - x small = a crack),
// z = a random number per cell (which plates dry / break off first)
vec3 gr_cells(vec3 p) {
	vec3 i = floor(p), f = fract(p);
	float d1 = 8.0, d2 = 8.0, id = 0.0;
	for (int z = -1; z <= 1; z++) for (int y = -1; y <= 1; y++) for (int x = -1; x <= 1; x++) {
		vec3 o = vec3(float(x), float(y), float(z));
		vec3 h = gr_hash3(i + o);
		float d = length(o + h * 0.85 - f);
		if (d < d1) { d2 = d1; d1 = d; id = h.x; } else if (d < d2) { d2 = d; }
	}
	return vec3(d1, d2, id);
}

void fragment() {
	// the pixel's footprint on the part (its own units): every pattern below is filtered against it
	float px = max(length(fwidth(v_local)), 1e-7);
	float hgt = clamp(v_hgt / 1.5, 0.0, 1.0);
	// the dirt map
	vec3 sn = normalize(v_n);
	vec4 wf = v_rest > 0.5 ? grime_wf0 : grime_wf;
	vec4 wr = v_rest > 0.5 ? grime_wr0 : grime_wr;
	float spr = v_sp * max(spray(wf, v_p, sn), spray(wr, v_p, sn));
	vec3 uvw = (v_p + sn * 0.07 - cav_min) / cav_size;
	float inside = step(0.0, min(uvw.x, min(uvw.y, uvw.z))) * step(max(uvw.x, max(uvw.y, uvw.z)), 1.0);
	float cav = v_sp * cav_on * inside * smoothstep(0.2, 0.65, texture(cav_tex, clamp(uvw, 0.0, 1.0)).r);
	float lowk = smoothstep(0.9, 0.15, v_hgt);
	float fwd_ax = sign(wf.x - wr.x + 1e-4);
	float under = v_sp * max(-sn.y, 0.0) * lowk;
	float front = v_sp * max(sn.x * fwd_ax, 0.0) * lowk;
	float top = v_sp * max(sn.y, 0.0);
	// wheels: clumps by angle round the axle (a few big ones + smaller), heavier out at the bead
	float clump = 0.0, bead = 0.0;
	if (wheel || tyre) {
		float ang = atan(v_local.y, v_local.x);
		vec3 ring = vec3(cos(ang), sin(ang), 0.0);
		clump = gr_noise(ring * 2.2 + vec3(0.0, 0.0, 3.1)) * 0.65 + gr_noise(ring * 5.5 + vec3(7.0)) * 0.35;
		bead = smoothstep(0.18, 0.31, length(v_local.xy));
	}
	if (wheel) { spr = 0.0; cav = 0.0; under = 0.0; front = 0.0; top = 0.0; }
	// colour variation over the part (clay-red .. grey silt, lighter / darker patches), shared by dust and mud
	float vb = gr_oct(v_local + vec3(11.3, 2.7, 5.1), 3.1, px), vc = gr_oct(v_local + vec3(4.2, 8.8, 1.9), 11.0, px);
	vec3 tint = mix(vec3(1.09, 0.97, 0.86), vec3(0.9, 0.96, 1.03), smoothstep(0.25, 0.75, vb)) * (0.84 + 0.32 * vc);
	// dust film: soft clouds, thickest low down, grainy up close; wet = darker (dust turns to a muddy wash)
	float dn = gr_oct(v_local, 7.0, px) * 0.55 + gr_oct(v_local, 23.0, px) * 0.3 + gr_oct(v_local, 130.0, px) * 0.15;
	vec2 ty = decal ? vec2(0.0, 0.7) : v_tyre;   // tyre lettering sits on the sidewall (no UV2 of its own)
	// tyre dust: a film on the sidewall, thinner toward the rim; the knob tops are rolled clean
	// 2026-11-27 (user: the bike went one beige blob): the film is patchy and stays low, the tyre's sidewall keeps
	// most of its black, and it never covers more than ~25 % (was an even 60 % veil over everything: tyres,
	// stanchions, stickers, kit all turned ground-coloured within 20 s). The mud keeps its own strength.
	float dlow = tyre ? 0.45 * mix(mix(0.75, 0.25, ty.x), 1.05, smoothstep(0.45, 0.62, ty.y)) * (1.0 - 0.35 * smoothstep(0.75, 1.0, ty.y))
		: clamp(1.15 - hgt * 1.6, 0.06, 1.15);
	if (wheel) dlow = (0.25 + 0.6 * bead) * smoothstep(0.25, 0.75, clump) * 1.4;
	float dmap = dlow + 0.4 * cav + 0.25 * top + 0.3 * spr;
	float da = clamp(grime_dust.a * min(bias, 1.2) * dmap * (0.1 + 0.9 * smoothstep(0.35, 0.8, dn)), 0.0, 0.25);
	// the dust is the ground colour, but on the bike it sits in full sun with no grass / shade / relief over it:
	// a shade darker than the raw ground colour or it reads chalky bright
	vec3 dc = grime_dust.rgb * 0.74 * tint * (0.9 + 0.2 * gr_oct(v_local, 41.0, px));
	float w = grime.y;
	float m = 0.0;
	vec3 mc = vec3(0.0);
	float t = 0.0, ld = 0.0, rough_m = 0.6, spec_m = 0.45;
	// the mud itself (splotches, bump, drying crust) only once there is any: a dust-only bike stops here.
	// grime.x is a uniform, so the derivatives below stay in uniform control flow.
	if (grime.x > 0.001) {
		// mud: crisp splotches laid over the dust, thicker toward their middles
		float mmap = (1.05 - hgt * 1.4) + 1.1 * spr + 0.8 * cav + 0.45 * under + 0.35 * front + 0.2 * (1.0 - v_sp);
		if (wheel) mmap = (0.1 + 0.9 * bead) * smoothstep(0.35, 0.8, clump) * 1.5;
		// tyre: the tread fills first; the sidewalls take clumps flung round them (by angle, so they turn with it)
		float side = 0.3 + 0.9 * smoothstep(0.3, 0.75, clump);
		float cmul = bias * mmap;
		float cover = tyre ? tyre_cover(grime.x, ty, side) : grime.x * cmul;
		float n = gr_oct(v_local, 26.0, px) * 0.6 + gr_oct(v_local, 71.0, px) * 0.4;
		// flecks (~5 mm beads): only while they are bigger than a pixel or so; further off they just go
		float fleck = gr_noise(v_local * 190.0) * (1.0 - smoothstep(0.25, 0.6, px * 190.0));
		float edge = 1.0 - cover;
		float fthr = 1.0 - cover * 0.35;
		// the splotch edge antialiased over one pixel (it was a hard step: crawling stairs as the view moved)
		float fwn = max(fwidth(n), 1e-4), fwf = max(fwidth(fleck), 1e-4);
		m = max(smoothstep(edge + 0.04 - fwn, edge + 0.04 + fwn, n), smoothstep(fthr - fwf, fthr + fwf, fleck));
		// bump: a height field for the mud (metres): a rounded rise from the splotch edge, lumpy clods on top,
		// flecks as little beads; the normal is bent by its screen-space slope (the passes have no UVs / tangents)
		t = smoothstep(edge, edge + 0.2, n);
		float fl = smoothstep(fthr, 1.0 - cover * 0.2, fleck);
		// off the splotches (t = fl = 0, so m = 0 too) the lumps, the crust and its cracks change nothing: skip them
		bool on = t > 0.0 || fl > 0.0;
		float lump = 0.5;
		// drying, layer by layer: the splotches that were already there at the dried mud level (grime_age.z) are an
		// old crust, what came on since is fresh wet mud (the newest at the splotch edges and in new splotches);
		// a dried thick crust cracks into ~2 cm plates, and knocked-off plates (grime_age.y) are gone along those
		// cracks, leaving a faint stain
		float crack = 0.0, gone = 0.0, old = 0.0;
		if (grime_age.z >= 0.0) {
			float co = tyre ? tyre_cover(grime_age.z, ty, side) : grime_age.z * cmul, eo = 1.0 - co;
			old = max(smoothstep(eo + 0.02, eo + 0.16, n), smoothstep(1.0 - co * 0.35, 1.0 - co * 0.28, fleck));
		}
		if (on) {
			lump = gr_oct(v_local, 140.0, px) * 0.6 + gr_oct(v_local, 330.0, px) * 0.4;
			bool drying = grime_age.z >= 0.0 ? old > 0.0 : grime_age.x > 0.01;
			if (drying) {
				vec3 c = gr_cells(v_local * 55.0);
				if (grime_age.z >= 0.0)
					// a crust dries from its thin rim inward, plate by plate
					ld = clamp(old * 1.25 - 0.15 + (1.0 - t) * 0.3 + (c.z - 0.5) * 0.35, 0.0, 1.0) * step(0.001, old);
				else
					ld = clamp(grime_age.x * 1.7 - 0.7 + (1.0 - t) * 0.55 + (c.z - 0.5) * 0.5, 0.0, 1.0);
				// crack lines no thinner than a pixel, gone once a whole plate is a few pixels
				float cpx = px * 55.0;
				crack = 0.75 * (1.0 - smoothstep(0.012, 0.05 + cpx * 0.6, c.y - c.x)) * (1.0 - smoothstep(0.12, 0.35, cpx))
					* smoothstep(0.6, 0.95, ld) * smoothstep(0.45, 0.8, t);
				gone = m * step(c.z, grime_age.y * smoothstep(0.4, 0.9, ld));
			}
		}
		float h = (max(t, fl * 0.6) * (0.5 + 0.5 * lump * (1.0 - 0.5 * ld))) * (0.0018 + 0.0035 * grime.x) - crack * 0.0014;
		vec3 dpdx = dFdx(VERTEX), dpdy = dFdy(VERTEX);
		vec3 r1 = cross(dpdy, NORMAL), r2 = cross(NORMAL, dpdx);
		float det = dot(dpdx, r1);
		vec3 grad = sign(det) * (dFdx(h) * r1 + dFdy(h) * r2);
		// never bend it past ~55 deg: a slope worked out from 2x2 pixels can spike, and a spike is a sparkle
		float gl = length(grad), gmax = abs(det) * 1.4;
		if (gl > gmax) grad *= gmax / gl;
		m *= 1.0 - gone;
		vec3 bumped = normalize(abs(det) * NORMAL - grad + 1e-9);
		NORMAL = normalize(mix(NORMAL, bumped, m));
		// fresh: wet, dark, a little glossy, thick middles darkest; the colour of the ground ridden now
		vec3 fresh = mud_col.rgb * (0.58 + 0.3 * gr_oct(v_local, 9.0, px)) * mix(1.05, 0.72, t) * (0.9 + 0.2 * lump);
		// dried: lighter, matte, toward the dust; the colour of the mud as it was laid
		vec3 base_old = grime_age.z >= 0.0 ? mud_col_old.rgb : mud_col.rgb;
		vec3 dried = mix(base_old * 1.3, grime_dust.rgb * 0.85, 0.35) * (0.85 + 0.3 * lump);
		mc = mix(fresh, dried, ld) * tint * (1.0 - crack * 0.45);
		rough_m = mix(mix(0.55, 0.3, t), 0.97, ld);
		spec_m = mix(0.5, 0.25, ld);
		// specular antialiasing: where the bent normal changes a lot within the pixel, roughen it (Kaplanyan)
		vec3 dnn = fwidth(NORMAL);
		rough_m = sqrt(min(rough_m * rough_m + min(2.0 * dot(dnn, dnn), 0.3), 1.0));
		da = max(da, gone * 0.45);   // a flaked plate leaves a stain
		dc = mix(dc, base_old * 1.1, gone * 0.6);
	}
	ALBEDO = mix(dc * (1.0 - w * 0.5), mc * (1.0 - w * 0.43), m);
	ROUGHNESS = mix(mix(0.97, 0.45, w), mix(rough_m, 0.3, w), m);
	SPECULAR = mix(0.2, spec_m, m);
	ALPHA = max(m, da);
	if (decal) ALPHA *= texture(decal_tex, UV).a;
	if (debug_map) { ALBEDO = vec3(spr, cav, under + front); ALPHA = 1.0; NORMAL = normalize(v_n * 0.0 + NORMAL); }
}
