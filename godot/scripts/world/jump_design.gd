class_name JumpDesign
extends RefCounted
## Bike jumps built from the numbers, not by eye (after trailism.com/jump-design and the usual ski-jump landing
## maths). One recipe makes every built jump: the trail's (baked into TrailFeatures' knots by
## tools/bake_jumps.gd), the test playground's DESIGNED lane and the ramps placed with the ramp editor there.
##
##   take-off  a clothoid (Euler spiral: the curvature grows evenly from 0, so the bike is loaded gently, never a
##             "kink") from flat up to the lip angle, its tightest radius R = v^2 / (lip_g x g): the rider feels at
##             most lip_g g on it at the design speed (1.5 g is the comfortable number). Then a STRAIGHT lip lip_t
##             seconds long at the lip speed: both wheels leave on the same line, so the bike isn't pitched / bucked
##             (a lip that is still curving at its edge throws the front up: "kicky").
##   table     a flat deck from the lip to the knuckle (casing it is safe), gap = open ground and a landing mound.
##   landing   a rounded knuckle (knuckle_r), a straight landing slope, a bottom transition sized to the landing
##             speed (land_g). Auto (deck / gap 0): the deck is as long as the flight, so a rider at the design speed
##             comes down `aim` of the way down the landing slope; auto landing angle (land_deg 0): the slope there
##             matches the flight's own angle (minus LAND_SOFT), so the hit square to the ground is tiny.
##   EFH       equivalent fall height = (speed into the ground, square to it)^2 / 2g: what the legs must soak up.
##             Reported for a range of run-in speeds; 1.5 m is the most a landing should ever ask.
##
## Heights are over the ground the jump sits on, u along it from the start of the run-in flat.

const G := 9.81
const DS := 0.05            # sample spacing (m)
const RUN_IN := 1.0         # flat before the face
const LAND_MAX_DEG := 35.0 # steepest auto landing (steeper is short and leaves no room for a rider a bit fast)
const LAND_SOFT := 3.0      # deg: the auto landing slope this much flatter than the flight at the aim point
const EFH_MAX := 1.5        # m: what a landing should never ask more than
# (2026-11-23, measured on the playground's designed tables at their design speed, the game's physics, hands off:) the bike
# loses more on the face than the climb alone (suspension, tyres, the transition's load): v_lip^2 = v^2 - 2 g H - FACE_LOSS
# x H x v, within +-10 % on six tables 1.6-5.9 m; and it leaves TAKEOFF_EXTRA steeper than the lip (the rider's pop, the
# rear lifting off the lip). Both go into the flight the deck / landing are sized for and into predict()
const FACE_LOSS := 0.39
# (2026-11-24: 0. It was 8: the hands-off pop pushed square to the lip and the bike tipped up on its back wheel. Hands off
# he now rides WITH the lip (bike_physics _pop_along, lip loading): measured -1.2..+1.3 deg on five designed jumps)
const TAKEOFF_EXTRA := 0.0  # deg

const DEFAULTS := {
	"kind": "table",        # table | gap | kicker (the take-off alone, open back: you land on the flat)
	"build": "dirt",        # dirt (side batters) | wood (slats + plywood sides, square edges): placed ramps
	"v": 12.0,              # run-in speed at the foot of the face (m/s)
	"lip_deg": 26.0,        # lip angle
	"lip_g": 1.5,           # most g on the take-off curve at v (sets its radius)
	"lip_t": 0.25,          # s of straight lip at the lip speed (0.25-0.30 s: the "equilibration" length)
	"height": 0.0,          # 0 = what the curve + lip give; > 0 = this lip height (the radius follows)
	"deck": 0.0,            # table: lip -> knuckle (m); 0 = auto from the flight
	"gap": 0.0,             # gap: lip -> landing knuckle (m); 0 = auto
	"land_h": 0.0,          # gap: landing knuckle height (0 = the lip's)
	"fill": 0.0,            # gap: the gap's floor (m over the ground; > 0 = a rider short of it lands that much higher)
	"land_deg": 0.0,        # 0 = auto (matched to the flight)
	"land_g": 2.5,          # most g in the landing's bottom transition
	"knuckle_r": 2.5,       # m
	"aim": 0.2,             # where on the landing slope the design speed comes down (0 = knuckle, 1 = bottom)
	"width": 3.0,           # riding width (placed ramps; the trail's jumps take the trail's)
}


static func params(p := {}) -> Dictionary:
	var out := DEFAULTS.duplicate()
	for k in p: out[k] = p[k]
	return out


## ∫0..1 sin(th u^2) du: a clothoid's rise per metre of its length, turning 0 -> th
static func _clo_rise(th: float) -> float:
	var s := 0.0
	var n := 64
	for i in n:
		var u := (i + 0.5) / n
		s += sin(th * u * u)
	return s / n


## the landing from a knuckle at height hk onto slope phi (rad) down to the ground: [P (aim point, relative to the
## knuckle's start), rk, rb, straight dx] (the radii shrink together when the landing is too low for them)
static func _landing(hk: float, phi: float, rk: float, rb: float, aim: float) -> Array:
	var k := 1.0 - cos(phi)
	var dk := rk * k
	var db := rb * k
	if dk + db > hk:
		var sc := hk / maxf(1e-4, dk + db)
		rk *= sc; rb *= sc; dk *= sc; db *= sc
	var ds := maxf(0.0, hk - dk - db)
	var sx := ds / tan(phi)
	var p := Vector2(rk * sin(phi) + aim * sx, hk - dk - aim * ds)
	if sx < 0.3:   # no straight to speak of: aim along the whole landing
		var tot := rk * sin(phi) + rb * sin(phi)
		p = Vector2(aim * tot, hk * (1.0 - aim))
	return [p, rk, rb, sx]


## the whole jump from its parameters (see DEFAULTS) -> {h, slope, length, lip_u, lip_h, ..., pred}
static func build(p_in := {}) -> Dictionary:
	var p := params(p_in)
	var th := deg_to_rad(clampf(float(p.lip_deg), 5.0, 60.0))
	var v: float = maxf(2.0, float(p.v))
	var R := v * v / (maxf(0.3, float(p.lip_g)) * G)
	var rise := _clo_rise(th)
	# lip speed (after climbing the face) and the straight lip: iterate, they depend on the height
	var H := 0.0
	var Ls := 0.0
	var vl := v
	for it in 3:
		Ls = maxf(0.0, float(p.lip_t)) * vl
		if float(p.height) > 0.0:
			H = float(p.height)
			R = maxf(1.0, (H - Ls * sin(th)) / maxf(1e-4, 2.0 * th * rise))
			if H - Ls * sin(th) < 0.05:   # too low for that straight: shorten it
				Ls = maxf(0.0, (H - 0.05) / sin(th)); R = maxf(1.0, 0.05 / (2.0 * th * rise))
		else:
			H = 2.0 * th * R * rise + Ls * sin(th)
		vl = sqrt(maxf(1.0, v * v - 2.0 * G * H - FACE_LOSS * H * v))
	var gap_kind := str(p.kind) == "gap"
	if str(p.kind) == "kicker": return _kicker(p, th, R, H, Ls, vl, v)
	var hk: float = H if not gap_kind or float(p.land_h) <= 0.0 else float(p.land_h)
	var rk: float = maxf(0.2, float(p.knuckle_r))
	var vb := sqrt(vl * vl + 2.0 * G * H)
	var rb := vb * vb / (maxf(0.5, float(p.land_g)) * G)
	var aim := clampf(float(p.aim), 0.0, 1.0)
	# the flight: from the lip at the measured take-off angle (lip + TAKEOFF_EXTRA)
	var thf := th + deg_to_rad(TAKEOFF_EXTRA)
	var vx := vl * cos(thf)
	var vy := vl * sin(thf)
	# auto deck / gap and landing angle: the flight from the lip meets the aim point
	var phi := deg_to_rad(float(p.land_deg)) if float(p.land_deg) > 0.0 else th + deg_to_rad(6.0)
	var D: float = float(p.deck) if not gap_kind else float(p.gap)
	var auto_d := D <= 0.0
	var auto_phi := float(p.land_deg) <= 0.0
	var lnd: Array = []
	for it in (6 if auto_phi else 1):
		lnd = _landing(hk, phi, rk, rb, aim)
		var P: Vector2 = lnd[0]
		var dy := P.y - H                               # aim point below the lip (-)
		# y(x) = x tan th - g x^2 / (2 vx^2) = dy  ->  the far root
		var a := G / (2.0 * vx * vx)
		var disc := tan(thf) * tan(thf) - 4.0 * a * dy
		var xt := (tan(thf) + sqrt(maxf(0.0, disc))) / (2.0 * a)
		if auto_d:
			D = xt - P.x - (0.0 if not gap_kind else 0.0)
		var x_hit := D + P.x
		var slope_t := tan(thf) - 2.0 * a * x_hit     # flight's slope there (-)
		if auto_phi:
			phi = clampf(-atan(slope_t) - deg_to_rad(LAND_SOFT), deg_to_rad(12.0), deg_to_rad(LAND_MAX_DEG))
	D = maxf(0.6, D)
	lnd = _landing(hk, phi, rk, rb, aim)
	rk = lnd[1]; rb = lnd[2]
	# ---- lay it out ------------------------------------------------------------------------------------------
	var t := _Turtle.new()
	t.flat(RUN_IN)
	var face_u := t.u()
	t.knot()
	t.clothoid(th, R)
	t.knot()
	t.straight_to(H)
	var lip_u := t.u()
	t.knot_kink(0.0 if not gap_kind else -deg_to_rad(50.0))   # (a gap's backside angle is set again below)
	var land0 := 0.0
	if not gap_kind:
		t.flat(D)
	else:
		var fl := clampf(float(p.fill), 0.0, minf(H, hk) - 0.1)
		# (the backside and the landing mound's face are squeezed steeper when the gap is short, so the landing's knuckle
		# really is D past the lip: at their 50 / 35 deg a short gap pushed the mound further out and the design speed
		# came down in the gap / on the mound's face)
		var bk_a := deg_to_rad(50.0)
		var up := deg_to_rad(35.0)
		var need := (H - fl) / tan(bk_a) + (hk - fl) / tan(up) + 0.6
		if need > D:
			bk_a = deg_to_rad(70.0); up = deg_to_rad(70.0)
		t.a = -bk_a
		t.knots[t.knots.size() - 1][3] = tan(t.a)   # (the lip knot's slope out = the backside's)
		t.straight_to(fl)
		t.knot_kink(0.0)
		var run := D - (t.u() - lip_u) - (hk - fl) / tan(up) - 0.6
		t.flat(maxf(0.0, run))
		t.knot_kink(up)
		t.straight_to(hk)
		t.knot_kink(0.0)
		t.flat(0.6)
	land0 = t.u()
	t.knot()
	t.arc(-phi, rk)
	t.knot()
	t.straight_to(rb * (1.0 - cos(phi)))
	t.knot()
	t.arc(0.0, rb)
	t.y = 0.0
	var land1 := t.u()
	t.knot()
	t.flat(1.0)
	t.knot()
	var out := {
		"p": p, "h": t.h, "slope": t.s, "length": t.u(), "knots": t.knots,
		"face_u": face_u, "lip_u": lip_u, "lip_h": H, "lip_deg": rad_to_deg(th), "R": R, "Ls": Ls,
		"lip_gs": v * v / R / G, "v_lip": vl, "deck": D, "land0": land0, "land1": land1, "land_deg": rad_to_deg(phi),
		"land_h": hk, "rk": rk, "rb": rb, "kind": "gap" if gap_kind else "table",
	}
	out["pred"] = [predict(out, v * 0.85), predict(out, v), predict(out, v * 1.15)]
	return out


## the take-off alone (a mini kicker): run-in, clothoid, straight lip, then its open back straight down; you land
## on the flat after it, so the EFH is the real one of a kicker to flat
static func _kicker(p: Dictionary, th: float, R: float, H: float, Ls: float, vl: float, v: float) -> Dictionary:
	var t := _Turtle.new()
	t.flat(RUN_IN)
	var face_u := t.u()
	t.knot()
	t.clothoid(th, R)
	t.knot()
	t.straight_to(H)
	var lip_u := t.u()
	t.knot_kink(0.0)
	t.y = 0.0; t._push()
	t.knot_kink(0.0)
	t.flat(16.0)
	t.knot()
	var out := {
		"p": p, "h": t.h, "slope": t.s, "length": t.u(), "knots": t.knots,
		"face_u": face_u, "lip_u": lip_u, "lip_h": H, "lip_deg": rad_to_deg(th), "R": R, "Ls": Ls,
		"lip_gs": v * v / R / G, "v_lip": vl, "deck": 0.0, "land0": lip_u, "land1": lip_u, "land_deg": 0.0,
		"land_h": 0.0, "rk": 0.0, "rb": 0.0, "kind": "kicker",
	}
	out["pred"] = [predict(out, v * 0.85), predict(out, v), predict(out, v * 1.15)]
	return out


## a rider at run-in speed vr (point mass, no pop / pump / drag) over the built shape: where he lands, how hard
static func predict(d: Dictionary, vr: float) -> Dictionary:
	var H: float = d.lip_h
	var th := deg_to_rad(float(d.lip_deg) + TAKEOFF_EXTRA)
	var vl := sqrt(maxf(0.1, vr * vr - 2.0 * G * H - FACE_LOSS * H * vr))
	var vx := vl * cos(th)
	var vy0 := vl * sin(th)
	var hs: PackedFloat32Array = d.h
	var u0: float = d.lip_u
	var tt := 0.0
	var dt := 0.004
	var top := H
	while tt < 6.0:
		tt += dt
		var uu := u0 + vx * tt
		var y := H + vy0 * tt - 0.5 * G * tt * tt
		top = maxf(top, y)
		var g := sample(hs, uu)
		if uu > u0 + 0.15 and y <= g:
			var sl := (sample(hs, uu + 0.1) - sample(hs, uu - 0.1)) / 0.2
			var vyl := vy0 - G * tt
			var n := Vector2(-sl, 1.0).normalized()
			var vn := -(vx * n.x + vyl * n.y)
			var spot := "flat"
			if uu < float(d.land0) - 0.05: spot = "deck" if str(d.kind) == "table" else "gap"
			elif uu < float(d.land0) + float(d.rk) * sin(deg_to_rad(float(d.land_deg))): spot = "knuckle"
			elif uu <= float(d.land1): spot = "landing"
			return {"v": vr, "u": uu, "dist": uu - u0, "air": tt, "apex": top - H, "efh": vn * vn / (2.0 * G),
				"spot": spot, "v_land": sqrt(vx * vx + vyl * vyl)}
	return {"v": vr, "u": INF, "dist": INF, "air": tt, "apex": top - H, "efh": INF, "spot": "?", "v_land": 0.0}


static func sample(hs: PackedFloat32Array, uu: float) -> float:
	if uu <= 0.0 or hs.is_empty(): return 0.0
	var f := uu / DS
	var i := int(f)
	if i >= hs.size() - 1: return hs[hs.size() - 1] if i == hs.size() - 1 else 0.0
	return lerpf(hs[i], hs[i + 1], f - i)


## one line for signs / the editor
static func describe(d: Dictionary) -> String:
	if d.kind == "kicker":
		return "%.2f m kicker %.0f° · R %.1f m (%.1f g) · straight %.1f m · to flat" % [d.lip_h, d.lip_deg, d.R, d.lip_gs, d.Ls]
	return "%.2f m lip %.0f° · R %.1f m (%.1f g) · straight %.1f m · %s %.1f m · landing %.0f°" % [
		d.lip_h, d.lip_deg, d.R, d.lip_gs, d.Ls, "deck" if d.kind == "table" else "gap", d.deck, d.land_deg]


## Hermite knots [[u, h, slope_in, slope_out], ...] for TrailFeatures (the trail's jump profiles), rounded to 0.1 mm so
## the GDScript and C# copies are the same numbers
static func knots(d: Dictionary) -> Array:
	var out := []
	for k in d.knots:
		out.append([snappedf(k[0], 0.0001), snappedf(k[1], 0.0001), snappedf(k[2], 0.0001), snappedf(k[3], 0.0001)])
	out[0] = [0.0, 0.0, 0.0, 0.0]
	return out


## the AIR span for the ground shader (lip -> 2 m past where the design speed lands)
static func air_span(d: Dictionary) -> Array:
	var pr: Dictionary = d.pred[1]
	return [snappedf(float(d.lip_u), 0.01), snappedf(minf(float(d.land1), float(pr.u) + 2.0), 0.01)]


## lays the profile out at DS steps (like the playground lane's turtle) and keeps Hermite knots: at every piece's
## ends (with the slope in / out, a kink keeps both) and every KNOT_EVERY m along curves
class _Turtle:
	const KNOT_EVERY := 0.8
	var h := PackedFloat32Array()
	var s := PackedFloat32Array()
	var knots: Array = []
	var y := 0.0
	var a := 0.0          # angle (rad)
	var _last_knot := -1.0

	func u() -> float: return h.size() * JumpDesign.DS

	func _push() -> void:
		h.append(y); s.append(tan(a))

	func knot() -> void:
		if absf(u() - _last_knot) < 1e-6 and not knots.is_empty():
			knots[knots.size() - 1] = [u(), y, knots[knots.size() - 1][2], tan(a)]
		else:
			knots.append([u(), y, tan(a), tan(a)])
		_last_knot = u()

	## a corner: the angle changes here at once (the lip's edge, a gap's backside)
	func knot_kink(to: float) -> void:
		var si := tan(a)
		a = to
		if absf(u() - _last_knot) < 1e-6 and not knots.is_empty():
			knots[knots.size() - 1][3] = tan(a)
		else:
			knots.append([u(), y, si, tan(a)])
		_last_knot = u()

	func _curve_knot() -> void:
		if u() - _last_knot >= KNOT_EVERY: knot()

	func flat(L: float) -> void:
		a = 0.0
		for i in int(round(L / JumpDesign.DS)): _push()

	func straight_to(yt: float) -> void:
		var t := tan(a)
		if absf(t) < 1e-6: return
		var guard := 0
		while ((t > 0.0 and y < yt) or (t < 0.0 and y > yt)) and guard < 100000:
			y += t * JumpDesign.DS
			if (t > 0.0 and y > yt) or (t < 0.0 and y < yt): y = yt
			_push(); guard += 1

	## circular arc to angle `to` (rad), radius R
	func arc(to: float, R: float) -> void:
		var guard := 0
		while absf(a - to) > 1e-6 and guard < 100000:
			var ds := JumpDesign.DS / maxf(0.2, cos(a))
			a = move_toward(a, to, ds / maxf(0.05, R))
			y = maxf(0.0, y + tan(a) * JumpDesign.DS); _push(); guard += 1
			_curve_knot()

	## Euler spiral from the current angle (flat) to `to`, the curvature growing evenly to 1 / R at its end
	func clothoid(to: float, R: float) -> void:
		var L := 2.0 * absf(to - a) * R    # arc length: the angle turned = L / (2 R)
		var s0 := 0.0
		var a0 := a
		var guard := 0
		while s0 < L and guard < 100000:
			var ds := JumpDesign.DS / maxf(0.2, cos(a))
			var sm := minf(L, s0 + ds * 0.5)
			s0 = minf(L, s0 + ds)
			a = a0 + signf(to - a0) * s0 * s0 / (2.0 * R * L)
			y += tan(a0 + signf(to - a0) * sm * sm / (2.0 * R * L)) * JumpDesign.DS
			_push(); guard += 1
			_curve_knot()
		a = to
