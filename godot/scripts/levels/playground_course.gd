class_name PlaygroundCourse
extends RefCounted
## The test playground's ground (LEVELS > TEST PLAYGROUND, BMX_LEVEL=playground): a flat plane (y = 0) with
## straight test lanes along +x, each a row of measured features with a flat run-in between them, plus berm
## bowls and open flat ground. Not part of the game world: it is for test riding the bike / rider code and
## for reference shots. Pure data + height function (no nodes), so headless tools can use it too.
##
## Every lane starts with the same roll-in (a 4 m deck, then 14 deg down: ~30 km/h at the bottom) and is a
## 1D profile (sampled every DU) along it; built features have side batters (SIDE). Feature ids (for
## BMX_PG_AT and the probe) are "<kind>_<size>", e.g. table_1.5, gap_7, drop_2, roller_0.6, slope_20.

const DU := 0.05          # profile sample spacing along a lane (m)
const SIDE := 1.0         # side batter of built dirt: metres down per metre out past the riding width
const X0 := -30.0         # every lane starts here (the roll-in deck)
const ROLLIN_H := 4.0     # roll-in deck height (m)
const ROLLIN_DEG := 14.0
const RUN := 32.0         # flat run between features (m): room to pedal back up / settle
const SNAP := 4.0         # region rectangles are snapped to this grid (the base plane is made of these cells)

class Lane:
	var id: String
	var title: String
	var z: float
	var hw: float = 3.0          # riding half width (the flat top of the features)
	var band: float = 8.0        # half width of its ground strip
	var h := PackedFloat32Array()
	var m := PackedByteArray()   # 1 = a jump / pump feature here (Terrain.jump_mask)
	var feats: Array = []        # {id, name, desc, u0, u1, lip (u or -1), top (max height), lane}
	var camber: Array = []       # [u0, u1, tan(angle)] tilts across the lane (uphill to +z)
	var skews: Array = []        # [u0, u1, tan(angle)] features turned to the lane (hips): the shape slides along u with v
	var surfs: Array = []        # [u0, u1, surface id] ground other than dirt (Terrain surface ids: 0 grass, 2 wet, 3 sand)
	var cones: Array = []        # [u, v] slalom cones (visual)
	var rect: Rect2              # snapped ground region (x, z)
	# the turtle that lays the profile out
	var y := 0.0
	var s := 0.0                 # slope angle (rad)
	var mask := 0
	var _f = null

	func u() -> float: return h.size() * DU
	func length() -> float: return h.size() * DU

	func _push() -> void:
		h.append(y); m.append(mask)

	func flat(L: float) -> void:
		s = 0.0
		for i in int(round(L / DU)): _push()

	func line(L: float) -> void:
		for i in int(round(L / DU)):
			y += tan(s) * DU; _push()

	## carry on at the current slope until the height reaches yt
	func line_to(yt: float) -> void:
		var t := tan(s)
		if absf(t) < 1e-6: return
		var guard := 0
		while ((t > 0.0 and y < yt) or (t < 0.0 and y > yt)) and guard < 200000:
			y += t * DU
			if (t > 0.0 and y > yt) or (t < 0.0 and y < yt): y = yt
			_push(); guard += 1

	## a circular arc (radius R, metres) from the current slope to `deg`
	func bend(deg: float, R: float, floor_y := -INF) -> void:
		var to := deg_to_rad(deg)
		var guard := 0
		while absf(s - to) > 1e-5 and guard < 200000:
			s = move_toward(s, to, DU / (R * maxf(0.2, cos(s))))
			y = maxf(floor_y, y + tan(s) * DU); _push(); guard += 1

	## from the current height down to 0: a knuckle (radius rk) onto a `deg` slope, then a transition (radius rt) to
	## the flat. Both radii shrink together when the height is too small for them (small tables / landings)
	func descend(deg: float, rk: float, rt: float) -> void:
		var k := 1.0 - cos(deg_to_rad(deg))
		var sc := minf(1.0, y / maxf(1e-4, (rk + rt) * k))
		rk *= sc; rt *= sc
		bend(-deg, maxf(0.05, rk), 0.0); line_to(rt * k); bend(0.0, maxf(0.05, rt), 0.0)
		y = 0.0

	## a vertical step to yt (a ledge / curb face)
	func wall_to(yt: float) -> void:
		y = yt; s = 0.0; _push()

	func begin(id_: String, name_: String, desc: String, jump := true) -> void:
		mask = 1 if jump else 0
		_f = {"id": id_, "name": name_, "desc": desc, "u0": u(), "u1": u(), "lip": -1.0, "top": 0.0, "lane": self.id,
			"lip_deg": 0.0, "land0": -1.0, "land1": -1.0, "jump": jump}   # land0..1: the landing slope / deck to aim for (jumps)

	func lip() -> void:
		if _f: _f.lip = u()

	func end() -> void:
		if _f == null: return
		_f.u1 = u()
		var top := 0.0
		for i in range(int(_f.u0 / DU), mini(h.size(), int(_f.u1 / DU) + 1)): top = maxf(top, absf(h[i]))
		_f.top = top
		feats.append(_f)
		_f = null
		mask = 0
		y = 0.0; s = 0.0

	# ---- features -------------------------------------------------------------------------------------
	func rollin() -> void:
		flat(0.0)
		begin("rollin_" + id, "ROLL-IN", "%.0f m deck, %.0f deg" % [ROLLIN_H, ROLLIN_DEG], false)
		y = ROLLIN_H; flat(10.0)
		bend(-ROLLIN_DEG, 6.0); line_to(8.0 * (1.0 - cos(deg_to_rad(ROLLIN_DEG)))); bend(0.0, 8.0)
		end()
		flat(RUN * 0.6)

	## a kicker with nothing after it (a hop) / the take-off of a gap: transition radius from h + lip angle
	func _kick(hh: float, deg: float) -> void:
		var a := deg_to_rad(deg)
		bend(deg, hh / maxf(0.01, 1.0 - cos(a)))
		lip()
		s = deg_to_rad(-50.0); line_to(0.0); s = 0.0

	func hop(hh: float, deg: float) -> void:
		begin("hop_%s" % _n(hh), "HOP", "%.2f m, %.0f deg lip" % [hh, deg])
		_kick(hh, deg); end(); flat(14.0)

	func table(hh: float, up: float, deck: float, down: float) -> void:
		begin("table_%s" % _n(hh), "TABLE %.1f m" % hh, "%.0f deg lip, deck %.0f m, %.0f deg landing" % [up, deck, down])
		var a := deg_to_rad(up)
		var rk := minf(2.0, 0.25 * hh / maxf(0.01, 1.0 - cos(a)))
		bend(up, 0.7 * hh / maxf(0.01, 1.0 - cos(a)))
		line_to(hh - rk * (1.0 - cos(a)))
		lip(); _f.lip_deg = up
		bend(0.0, rk); flat(deck)
		_f.land0 = u()
		descend(down, 2.0, 6.0)
		_f.land1 = u()
		end(); flat(RUN)

	## kicker (h, deg) -> gap (lip to the landing's knuckle, metres) -> landing (land_h, land_deg)
	func gap(hh: float, deg: float, gap_m: float, land_h: float, land_deg: float) -> void:
		begin("gap_%s" % _n(gap_m), "GAP %.0f m" % gap_m, "%.1f m kicker %.0f deg, landing %.1f m %.0f deg" % [hh, deg, land_h, land_deg])
		var a := deg_to_rad(deg)
		bend(deg, hh / maxf(0.01, 1.0 - cos(a)))
		lip(); _f.lip_deg = deg
		var ul := u()
		s = deg_to_rad(-50.0); line_to(0.0); s = 0.0
		flat(maxf(0.0, gap_m - (u() - ul) - land_h - 0.6))
		s = deg_to_rad(45.0); line_to(land_h); s = 0.0
		flat(0.6)
		_f.land0 = u()
		descend(land_deg, 2.0, 7.0)
		_f.land1 = u()
		end(); flat(RUN)

	## a ramp up at 8 deg to a deck at hh, 6 m of deck, then a sheer drop to the flat
	func drop(hh: float) -> void:
		begin("drop_%s" % _n(hh), "DROP %.1f m" % hh, "8 deg run-up, flat lip, to flat")
		bend(8.0, 10.0); line_to(hh - 10.0 * (1.0 - cos(deg_to_rad(8.0)))); bend(0.0, 10.0)
		y = hh; flat(6.0)
		lip()
		wall_to(0.0)
		end(); flat(RUN)

	## kicker -> a higher landing deck (step-up), 8 m of deck, roll back down at 15 deg
	func step_up(hh: float, deg: float, gap_m: float, up_h: float) -> void:
		begin("stepup_%s" % _n(up_h), "STEP-UP %.1f m" % up_h, "%.1f m kicker %.0f deg, deck %.0f m out" % [hh, deg, gap_m])
		var a := deg_to_rad(deg)
		bend(deg, hh / maxf(0.01, 1.0 - cos(a)))
		lip(); _f.lip_deg = deg
		var ul := u()
		s = deg_to_rad(-50.0); line_to(0.0); s = 0.0
		flat(maxf(0.0, gap_m - (u() - ul) - up_h))
		s = deg_to_rad(45.0); line_to(up_h); s = 0.0
		_f.land0 = u()
		flat(8.0)
		_f.land1 = u()
		descend(15.0, 3.0, 6.0)
		end(); flat(RUN)

	## n rollers of amplitude amp (crest height, m) and wavelength L
	func rollers(amp: float, L: float, n: int, id_ := "roller") -> void:
		begin("%s_%s" % [id_, _n(amp)], ("PUMP" if id_ == "pump" else "ROLLERS") + " %.1f m" % amp, "%d x %.0f m wavelength" % [n, L])
		var c := int(round(n * L / DU))
		for i in c:
			y = amp * 0.5 * (1.0 - cos(TAU * i * DU / L)); _push()
		end(); flat(RUN * 0.75)

	func curb(hh: float, L: float) -> void:
		begin("curb_%s" % _n(hh), "CURB %.0f cm" % (hh * 100.0), "square edge up, %.0f m, square edge down" % L, false)
		flat(0.5); wall_to(hh); flat(L); wall_to(0.0); flat(0.5)
		end(); flat(16.0)

	func pothole(depth: float, L: float) -> void:
		begin("hole_%s" % _n(depth), "POTHOLE %.0f cm" % (depth * 100.0), "%.1f m long, square edges" % L, false)
		flat(0.5); wall_to(-depth); flat(L); wall_to(0.0); flat(0.5)
		end(); flat(16.0)

	func washboard(amp: float, L: float, len_m: float) -> void:
		begin("wash_%s" % _n(amp), "WASHBOARD %.0f cm" % (amp * 100.0), "%.1f m wavelength, %.0f m long" % [L, len_m], false)
		for i in int(round(len_m / DU)):
			y = amp * 0.5 * (1.0 - cos(TAU * i * DU / L)); _push()
		end(); flat(RUN * 0.6)

	## random humps (seeded): rough ground
	func chatter(amp: float, len_m: float, seed_: int) -> void:
		begin("rough_%s" % _n(amp), "ROUGH %.0f cm" % (amp * 100.0), "random humps 0.3-1.5 m long, %.0f m" % len_m, false)
		var r := RandomNumberGenerator.new(); r.seed = seed_
		var left := 0; var L := 1.0; var a := 0.0; var k := 0
		for i in int(round(len_m / DU)):
			if left <= 0:
				L = r.randf_range(0.3, 1.5); a = amp * r.randf_range(0.3, 1.0); left = int(L / DU); k = 0
			y = a * 0.5 * (1.0 - cos(TAU * k / float(int(L / DU)))); _push()
			k += 1; left -= 1
		end(); flat(RUN * 0.6)

	## up at deg for len_m, an 8 m flat top, down at deg
	func slope(deg: float, len_m: float) -> void:
		begin("slope_%s" % _n(deg), "SLOPE %.0f deg" % deg, "%.0f%% grade, %.0f m up, 8 m top, down" % [tan(deg_to_rad(deg)) * 100.0, len_m], false)
		var R := 8.0
		bend(deg, R); line(len_m); bend(0.0, R); flat(8.0)
		bend(-deg, R); line_to(R * (1.0 - cos(deg_to_rad(deg)))); bend(0.0, R)
		end(); flat(RUN * 0.75)

	## the lane tilted across (uphill to +z) at deg for len_m, eased in / out over 6 m
	func tilt(deg: float, len_m: float) -> void:
		begin("camber_%s" % _n(deg), "CAMBER %.0f deg" % deg, "side slope, %.0f m long (high side left)" % len_m, false)
		var u0 := u()
		flat(len_m + 12.0)
		camber.append([u0, u0 + len_m + 12.0, tan(deg_to_rad(deg))])
		end(); flat(RUN * 0.5)

	## a kicker off a raised deck onto a landing lower than the take-off: run up 8 deg onto the deck, 6 m of deck,
	## the kicker (lip_h over the deck at deg), the gap, the landing (knuckle at land_h) down at land_deg
	func step_down(deck_h: float, lip_h: float, deg: float, gap_m: float, land_h: float, land_deg: float) -> void:
		begin("stepdown_%s" % _n(deck_h + lip_h - land_h), "STEP-DOWN %.1f m" % (deck_h + lip_h - land_h),
			"deck %.1f m, %.1f m kicker %.0f deg, %.0f m to a %.1f m landing" % [deck_h, lip_h, deg, gap_m, land_h])
		bend(8.0, 10.0); line_to(deck_h - 10.0 * (1.0 - cos(deg_to_rad(8.0)))); bend(0.0, 10.0)
		y = deck_h; flat(6.0)
		var a := deg_to_rad(deg)
		bend(deg, lip_h / maxf(0.01, 1.0 - cos(a)))
		lip(); _f.lip_deg = deg
		var ul := u()
		s = deg_to_rad(-50.0); line_to(0.0); s = 0.0
		flat(maxf(0.0, gap_m - (u() - ul) - land_h - 0.6))
		s = deg_to_rad(45.0); line_to(land_h); s = 0.0
		flat(0.6)
		_f.land0 = u()
		descend(land_deg, 2.0, 7.0)
		_f.land1 = u()
		end(); flat(RUN)

	## a drop off a flat lip onto a landing slope (not to flat): the landing's top is 25 % lower, just past the lip
	func drop_land(hh: float, land_deg: float) -> void:
		begin("dropland_%s" % _n(hh), "DROP TO LANDING %.1f m" % hh, "8 deg run-up, flat lip, onto a %.0f deg landing" % land_deg)
		bend(8.0, 10.0); line_to(hh - 10.0 * (1.0 - cos(deg_to_rad(8.0)))); bend(0.0, 10.0)
		y = hh; flat(6.0)
		lip(); _f.lip_deg = 0.0
		wall_to(hh * 0.75)
		_f.land0 = u()
		descend(land_deg, 1.0, 7.0)
		_f.land1 = u()
		end(); flat(RUN)

	## a table turned `turn` deg to the lane (a hip): ridden straight you take off and land across its faces
	func hip(hh: float, up: float, deck: float, down: float, turn: float) -> void:
		var n0 := feats.size()
		table(hh, up, deck, down)
		var f: Dictionary = feats[n0]
		f.id = "hip_%s" % _n(turn); f.name = "HIP %.0f deg" % turn
		f.desc = "%.1f m table turned %.0f deg to the lane" % [hh, turn]
		skews.append([f.u0, f.u1, tan(deg_to_rad(turn))])

	## a flat strip on one surface with a brake line in it: ride in at speed, brake at the line (`which`: both /
	## front / rear lever), the probe measures the stopping distance. surf: 0 grass, 1 dirt, 2 wet, 3 sand
	func brake_strip(surf: int, which: String) -> void:
		var sname: String = ["GRASS", "DIRT", "WET", "SAND"][clampi(surf, 0, 3)]
		var id_ := "brake_%s%s" % [sname.to_lower(), "" if which == "both" else "_" + which]
		begin(id_, "BRAKE %s%s" % [sname, "" if which == "both" else " · " + which.to_upper() + " ONLY"],
			"brake line at the post, stopping distance measured", false)
		var u0 := u()
		flat(4.0)
		lip()   # (the brake line: the probe and the test rider use f.lip)
		flat(26.0)
		_f.kind = "brake"; _f.which = which; _f.surf = surf
		if surf != 1: surfs.append([float(_f.lip) - 0.3, u() + 2.0, surf])   # (from the line: wet = the game's water surface, it drags)
		end(); flat(RUN * 0.6)

	## cones on the middle `gap` m apart: weave past them on alternate sides
	func slalom(n: int, gap: float) -> void:
		begin("slalom_%s" % _n(gap), "SLALOM %.0f m" % gap, "%d cones %.0f m apart, pass them on alternate sides" % [n, gap], false)
		flat(4.0)
		for i in n:
			cones.append([u(), 0.0])
			flat(gap)
		_f.kind = "slalom"; _f.gap = gap; _f.n = n
		end(); flat(RUN)

	# ---- rocks: the game's own rocks (same mesh, same collider / dome recipe as TerrainChunkBuilder._rock_gardens) ----
	var rock_specs: Array = []   # [u, v (across), sc, sx, sy, yaw] -> PlaygroundCourse.rocks

	## how high a rock of scale sc with height factor ky (sy = sc * ky) stands over the ground
	static func rock_top(sc: float, ky: float) -> float:
		return sc * (0.9 * ky - 0.3)

	## n rocks of one size in a row on the lane's middle, `gap` m apart (ride straight over them)
	func rock_row(sc: float, ky: float, n: int, gap: float) -> void:
		var hh := rock_top(sc, ky)
		begin("rock_%s" % _n(snappedf(hh * 100.0, 1.0)), "ROCK %.0f cm" % (hh * 100.0), "%d in a row, %.0f cm across, %.0f m apart" % [n, sc * 2.25 * 0.9 * 100.0, gap], false)
		flat(2.0)
		for i in n:
			rock_specs.append([u(), 0.0, sc, sc * 1.25, sc * ky, 0.7 * i])
			flat(gap)
		end(); flat(14.0)

	## a rock garden laid out like the trail's (4 rocks per 2 m of trail, sizes 13..47 cm scale); `clean` leaves
	## the trail's weaving clean line, else rocks everywhere
	func rock_garden(len_m: float, seed_: int, clean: bool) -> void:
		begin("garden_%s" % ("line" if clean else "full"), "ROCK GARDEN" + ("" if clean else " (no clean line)"), "like the trail's, %.0f m" % len_m, false)
		var r := RandomNumberGenerator.new(); r.seed = seed_
		var u0 := u()
		for i in int(len_m / 2.0):
			var line_a := sin(i * 0.23) * hw * 0.55
			for k in 4:
				var a := (r.randf() * 2.0 - 1.0) * (hw - 0.15)
				var du := r.randf() * 2.0
				if clean and absf(a - line_a) < 0.45 and r.randf() < 0.8: continue
				var r1 := r.randf()
				var sc := 0.13 + r1 * r1 * 0.34
				rock_specs.append([u0 + i * 2.0 + du, a, sc, sc * (1.0 + r.randf() * 0.5), sc * (0.5 + r.randf() * 0.35), r.randf() * TAU])
		flat(len_m)
		end(); flat(RUN * 0.6)

	static func _n(v: float) -> String:
		return str(snappedf(v, 0.01)).trim_suffix(".0")

	# ---- the surface ------------------------------------------------------------------------------------
	func profile(uu: float) -> float:
		if uu <= 0.0 or h.is_empty(): return 0.0
		var f := uu / DU
		var i := int(f)
		if i >= h.size() - 1: return h[h.size() - 1] if i == h.size() - 1 else 0.0
		return lerpf(h[i], h[i + 1], f - i)

	func tilt_at(uu: float) -> float:
		for c in camber:
			if uu > c[0] and uu < c[1]:
				return c[2] * smoothstep(c[0], c[0] + 6.0, uu) * (1.0 - smoothstep(c[1] - 6.0, c[1], uu))
		return 0.0

	## a hip: inside a skewed feature the shape lies along a line turned from square to the lane
	func skew_u(uu: float, v: float) -> float:
		for k in skews:
			if uu > k[0] - 4.0 and uu < k[1] + 4.0:
				return uu - clampf(v, -hw - 3.0, hw + 3.0) * k[2]
		return uu

	## height at (along, across); v = 0 is the lane's middle
	func at(uu: float, v: float) -> float:
		if not skews.is_empty(): uu = skew_u(uu, v)
		var p := profile(uu)
		var d := maxf(0.0, absf(v) - hw)
		var t := tilt_at(uu) if not camber.is_empty() else 0.0
		if t != 0.0:   # tilted: the low side (-z) at the base, rising across; outside the riding width it falls away
			var vv := clampf(v, -hw, hw)
			p += (vv + hw) * t
		if p >= 0.0: return maxf(0.0, p - d * SIDE)
		return minf(0.0, p + d * SIDE)

	func jump_at(uu: float, v: float) -> float:
		if not skews.is_empty(): uu = skew_u(uu, v)
		if uu <= 0.0 or absf(v) > hw + 2.0: return 0.0
		var i := int(uu / DU)
		return float(m[i]) if i < m.size() else 0.0


class Bowl:
	var id: String
	var title: String
	var c: Vector2
	var R: float        # track centre radius
	var W: float        # banked width
	var tn: float       # tan(bank)
	var deg: float
	var open_dir := PI  # the gap you ride in through faces -x
	var rect: Rect2

	## a banked ring (flat inside, the bank rising outward, a batter outside) with a gap at open_dir
	func at(x: float, z: float) -> float:
		var dx := x - c.x; var dz := z - c.y
		var r := sqrt(dx * dx + dz * dz)
		var r0 := R - W * 0.5
		if r <= r0: return 0.0
		var top := W * tn
		var hh := (r - r0) * tn if r <= r0 + W else maxf(0.0, top - (r - r0 - W) * SIDE)
		var ang := absf(wrapf(atan2(dz, dx) - open_dir, -PI, PI))
		return hh * smoothstep(deg_to_rad(22.0), deg_to_rad(48.0), ang)


var lanes: Array = []
var bowls: Array = []
var feats: Array = []          # every lane feature + bowl, flat
var bounds := Rect2()          # the whole playground (x, z)
var rocks: Array = []          # {x, z, r, top, base, sx, sy, sc, yaw}: colliders as the ride's Terrain makes them
var _rock_cells := {}          # Vector2i (2 m cells) -> Array of rocks reaching into it
const ROCK_CELL := 2.0


func _init() -> void:
	_build()


func _lane(id: String, title: String, z: float, band := 8.0, hw := 3.0) -> Lane:
	var l := Lane.new()
	l.id = id; l.title = title; l.z = z; l.band = band; l.hw = hw
	lanes.append(l)
	l.rollin()
	return l


func _build() -> void:
	var l: Lane
	l = _lane("tables", "TABLES", 0.0)
	for t in [[0.6, 25, 2, 25], [1.0, 30, 3, 28], [1.5, 32, 4, 30], [2.0, 35, 5, 32], [2.5, 38, 6, 35], [3.0, 40, 7, 38]]:
		l.table(t[0], t[1], t[2], t[3])
	l = _lane("gaps", "GAPS", 20.0)
	for g in [[0.8, 30, 3, 0.9, 30], [1.2, 33, 5, 1.3, 32], [1.6, 35, 7, 1.7, 35], [2.2, 38, 9, 2.3, 38], [2.8, 40, 12, 3.0, 40]]:
		l.gap(g[0], g[1], g[2], g[3], g[4])
	l = _lane("hops", "HOPS & ROLLERS", 40.0)
	for hp in [[0.25, 20], [0.4, 25], [0.6, 30], [0.8, 35]]:
		l.hop(hp[0], hp[1])
	l.flat(RUN * 0.5)
	l.rollers(0.3, 4.0, 6); l.rollers(0.6, 6.0, 5); l.rollers(1.0, 8.0, 4)
	l.rollers(0.8, 5.0, 8, "pump")
	l = _lane("drops", "DROPS & STEP-UPS", 60.0)
	for d in [0.5, 1.0, 1.5, 2.0, 3.0]:
		l.drop(d)
	l.step_up(0.8, 30, 3.0, 1.0); l.step_up(1.2, 35, 4.0, 1.6)
	l = _lane("bumps", "BUMPS & EDGES", 80.0)
	for c in [0.1, 0.2, 0.3, 0.45]:
		l.curb(c, 3.0)
	l.pothole(0.15, 1.0); l.pothole(0.3, 1.5)
	l.washboard(0.05, 0.5, 30.0); l.washboard(0.12, 1.2, 30.0)
	l.chatter(0.15, 40.0, 11); l.chatter(0.3, 40.0, 23)
	l = _lane("slopes", "SLOPES", 102.0, 10.0)
	for sl in [[5, 30], [10, 24], [15, 18], [20, 14], [25, 11], [30, 9], [40, 5.5]]:
		l.slope(sl[0], sl[1])
	l = _lane("camber", "CAMBER", 126.0, 12.0, 4.0)
	for cb in [5, 10, 15, 20, 25, 30, 35]:
		l.tilt(cb, 24.0)
	# the trail's rocks: single sizes from a pebble to one too tall to roll over, then two rock gardens
	l = _lane("rocks", "ROCKS", -24.0)
	for rk in [[0.13, 0.6, 5, 3.0], [0.22, 0.65, 5, 3.0], [0.3, 0.7, 4, 4.0], [0.38, 0.75, 4, 4.0], [0.47, 0.8, 3, 5.0], [0.47, 0.85, 3, 5.0], [0.8, 0.8, 1, 5.0]]:
		l.rock_row(rk[0], rk[1], rk[2], rk[3])
	l.rock_garden(40.0, 7, true); l.rock_garden(40.0, 19, false)
	l = _lane("stepdowns", "STEP-DOWNS, DROPS & HIPS", -48.0)
	l.step_down(1.2, 0.6, 28, 4.0, 0.8, 30); l.step_down(2.0, 0.8, 32, 6.0, 1.0, 34)
	l.drop_land(1.5, 30); l.drop_land(2.5, 34)
	l.hip(1.5, 32, 4, 30, 20); l.hip(1.5, 32, 4, 30, 35)
	l = _lane("brakes", "BRAKES, SURFACES & SLALOM", -72.0)
	l.brake_strip(1, "both"); l.brake_strip(1, "front"); l.brake_strip(1, "rear")
	l.brake_strip(0, "both"); l.brake_strip(2, "both"); l.brake_strip(3, "both")
	l.slalom(8, 8.0); l.slalom(8, 6.0)
	for ln in lanes:
		(ln as Lane).flat(20.0)
		ln.rect = _snap(Rect2(X0, ln.z - ln.band, ln.length(), ln.band * 2.0))
		for f in ln.feats: feats.append(f)
	# berm bowls: ride in through the gap on the -x side and round the bank
	var bz := 175.0
	for b in [["berm_20", "BERM R18 · 20 deg", 0.0, 18.0, 6.0, 20.0], ["berm_30", "BERM R10 · 30 deg", 60.0, 10.0, 5.0, 30.0],
			["berm_45", "BERM R13 · 45 deg", 110.0, 13.0, 5.0, 45.0], ["berm_60", "WALL R9 · 60 deg", 160.0, 9.0, 3.5, 60.0]]:
		var bw := Bowl.new()
		bw.id = b[0]; bw.title = b[1]; bw.R = b[3]; bw.W = b[4]; bw.deg = b[5]; bw.tn = tan(deg_to_rad(b[5]))
		var reach: float = bw.R + bw.W * 0.5 + bw.W * bw.tn / SIDE + 1.0
		bw.c = Vector2(b[2] + reach, bz)
		bw.rect = _snap(Rect2(bw.c.x - reach, bw.c.y - reach, reach * 2.0, reach * 2.0))
		bowls.append(bw)
		feats.append({"id": bw.id, "name": bw.title, "desc": "banked ring, %.0f m wide, ride in from the west" % bw.W, "bowl": bw,
			"lane": "", "u0": 0.0, "u1": 0.0, "lip": -1.0, "top": bw.W * bw.tn})
	for ln in lanes:
		for s in (ln as Lane).rock_specs:
			var sc: float = s[2]
			var rk := {"x": X0 + s[0], "z": ln.z + s[1], "r": (s[3] + sc) * 0.45, "base": 0.0, "top": -sc * 0.3 + s[4] * 0.9, "sink": sc * 0.3,
				"sx": s[3], "sy": s[4], "sc": sc, "yaw": s[5]}
			rocks.append(rk)
			for gx in range(floori((rk.x - rk.r) / ROCK_CELL), floori((rk.x + rk.r) / ROCK_CELL) + 1):
				for gz in range(floori((rk.z - rk.r) / ROCK_CELL), floori((rk.z + rk.r) / ROCK_CELL) + 1):
					var key := Vector2i(gx, gz)
					if not _rock_cells.has(key): _rock_cells[key] = []
					_rock_cells[key].append(rk)
	bounds = Rect2(X0 - 40.0, -60.0, 700.0, 300.0)
	for ln in lanes: bounds = bounds.merge(ln.rect.grow(20.0))
	for bw in bowls: bounds = bounds.merge(bw.rect.grow(20.0))
	bounds = _snap(bounds)


static func _snap(r: Rect2) -> Rect2:
	var x0 := floorf(r.position.x / SNAP) * SNAP
	var z0 := floorf(r.position.y / SNAP) * SNAP
	var x1 := ceilf(r.end.x / SNAP) * SNAP
	var z1 := ceilf(r.end.y / SNAP) * SNAP
	return Rect2(x0, z0, x1 - x0, z1 - z0)


## the ground's surface id at (x, z) where a lane strip sets one (brake strips), else -1
func surface_at(x: float, z: float) -> int:
	var l := lane_at(x, z)
	if l == null or absf(z - l.z) > l.hw + 1.0: return -1
	var uu := x - X0
	for sf in l.surfs:
		if uu >= sf[0] and uu <= sf[1]: return int(sf[2])
	return -1


## the lane whose strip (x, z) is on, or null
func lane_at(x: float, z: float) -> Lane:
	for l in lanes:
		if absf(z - l.z) <= l.band and x >= X0 and x <= X0 + l.length():
			return l
	return null


func lane_by_id(id: String) -> Lane:
	for l in lanes:
		if l.id == id: return l
	return null


func height(x: float, z: float) -> float:
	for l in lanes:
		if absf(z - l.z) <= l.band:
			return l.at(x - X0, z - l.z)
	for b in bowls:
		if (b as Bowl).rect.has_point(Vector2(x, z)):
			return b.at(x, z)
	return 0.0


## the rocks reaching into (x, z)'s cell (Terrain.colliders_near)
func rocks_near(x: float, z: float) -> Array:
	return _rock_cells.get(Vector2i(floori(x / ROCK_CELL), floori(z / ROCK_CELL)), [])


## the ground with a dome over every rock: exactly Terrain.height()'s formula
func height_rocks(x: float, z: float) -> float:
	var g := height(x, z)
	for c in rocks_near(x, z):
		var dx: float = x - c.x
		var dz: float = z - c.z
		var q: float = (dx * dx + dz * dz) / (c.r * c.r)
		if q < 1.0:
			var hh: float = Terrain.dome_h(c.base, c.top, c.sink, q)
			if hh > g: g = hh
	return g


func jump_mask(x: float, z: float) -> float:
	for l in lanes:
		if absf(z - l.z) <= l.band:
			return l.jump_at(x - X0, z - l.z)
	return 0.0


## built ground (dirt): lanes' riding width + every raised / dug bit, the bowls' banks
func is_dirt(x: float, z: float) -> bool:
	for l in lanes:
		if absf(z - l.z) <= l.band:
			return absf(z - l.z) <= l.hw + 0.6 or absf(height(x, z)) > 0.01
	for b in bowls:
		if (b as Bowl).rect.has_point(Vector2(x, z)):
			return b.at(x, z) > 0.01
	return false


## the feature (dict) under / around (x, z): on a lane the one whose span (+ 6 m before, + 10 m after) holds x
func feature_at(x: float, z: float):
	var l := lane_at(x, z)
	if l != null:
		var uu := x - X0
		for f in l.feats:
			if uu >= f.u0 - 6.0 and uu <= f.u1 + 10.0: return f
		return null
	for f in feats:
		if f.has("bowl") and (f.bowl as Bowl).rect.has_point(Vector2(x, z)): return f
	return null


func feature_by_id(id: String):
	for f in feats:
		if f.id == id: return f
	return null


## where to stand to ride feature f: (x, heading, z) like Game.respawn takes it. Lane features: `back` m before it
func spawn_for(f, back := 25.0) -> Vector3:
	if f.has("bowl"):
		var b: Bowl = f.bowl
		return Vector3(b.c.x - b.R - b.W - 14.0, 0.0, b.c.y)
	var l := lane_by_id(f.lane)
	var uu: float = maxf(4.0, f.u0 - back) if not str(f.id).begins_with("rollin") else 4.0
	return Vector3(X0 + uu, 0.0, l.z)


## the start: top of the TABLES roll-in, (x, heading, z)
func default_spawn() -> Vector3:
	return Vector3(X0 + 4.0, 0.0, 0.0)
