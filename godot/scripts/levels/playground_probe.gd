class_name PlaygroundProbe
extends Node
## The test playground's measuring kit (made by Game when it rides a PlaygroundTerrain):
## - every jump (> AIR_MIN s in the air) is measured: speed into the feature and off the lip, take-off angle,
##   air time, distance, peak height (over the lip / over the ground), where it landed (flat / deck / landing slope
##   / knuckle), the bike's pitch against the ground at touch-down, the landing jolt, and how it ended (CLEAN,
##   PERFECT, SKETCHY, CRASH <reason>). Shown on screen (left, under the jump card) and printed as `PG JUMP` lines.
## - tests: BMX_PG_SPEED=<km/h> holds that speed on the run-in to every feature (hands off from 1 m before it);
##   BMX_PG_SPEEDS=25,30,35 + BMX_PG_AT=<feature> rides that one feature again and again, one speed per try
##   (BMX_PG_TRIES = tries per speed, default 1), then quits; `PGSUM` lines at the end.
## Crash reasons come in from Game.start_crash (on_crash).

const AIR_MIN := 0.12          # s: shorter airs (rollers, chatter) aren't jumps
const BOUNCE_AIR := 0.3        # s: an air this short ...
const BOUNCE_T := 1.2          # ... within this long of a jump's landing is a bounce off it, not a new jump
const SETTLE := 0.7            # s after touch-down before a landing is called clean

var game                       # Game
var course: PlaygroundCourse
var speeds: Array = []         # km/h per try (BMX_PG_SPEEDS), or one (BMX_PG_SPEED)
var tries := 1
var target = null              # the feature the tries are on (BMX_PG_AT with BMX_PG_SPEEDS)
var _try := -1
var _try_t := 0.0
var _try_done := -1.0          # s since the try ended (wait a moment, then the next)
var results: Array = []
var jumps: Array = []          # every measured jump this ride

var _air := false
var _jump := {}                # the jump in progress (take-off -> settle)
var _feat_in = null            # feature whose run-in speed was taken
var _v_in := 0.0
var _land_t := -1.0
var _last_u := 0.0
var _since_land := 99.0
var _label: Label
var _layer: CanvasLayer
var _last := "no jumps yet"


func setup(g, c: PlaygroundCourse) -> void:
	game = g
	course = c
	if Env.s("BMX_PG_SPEEDS") != "":
		for s in Env.s("BMX_PG_SPEEDS").split(","): speeds.append(float(s))
	elif Env.s("BMX_PG_SPEED") != "":
		speeds.append(float(Env.s("BMX_PG_SPEED")))
	if Env.s("BMX_PG_TRIES") != "": tries = maxi(1, int(Env.s("BMX_PG_TRIES")))
	if Env.s("BMX_PG_AT") != "" and Env.s("BMX_PG_SPEEDS") != "":
		target = course.feature_by_id(Env.s("BMX_PG_AT"))
		if target != null: _try = 0
	_layer = CanvasLayer.new()
	_layer.layer = 3
	add_child(_layer)
	_label = Label.new()
	_label.position = Vector2(24, 250)
	_label.add_theme_font_size_override("font_size", 17)
	_label.add_theme_color_override("font_color", Color(1, 1, 1))
	_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_label.add_theme_constant_override("outline_size", 6)
	_layer.add_child(_label)


func target_speed() -> float:
	if speeds.is_empty(): return -1.0
	if _try >= 0: return speeds[mini(_try / tries, speeds.size() - 1)] / 3.6
	return speeds[0] / 3.6


## before the physics step: cruise control on the run-in (tests only)
func pre_step(_dt: float, inp: Dictionary) -> void:
	var T := target_speed()
	if T < 0.0: return
	var ph = game.phys
	if ph.crash_on: return
	if ph.air:   # hands off in the air: no pedal / brake (W / S tilt the bike there)
		inp.throttle = 0.0; inp.brake = 0.0; inp.sprint = false; inp.steer = 0.0; inp.hop = false
		inp.body_fwd = 0.0; inp.body_lean = 0.0
		return
	var f = _next_feature(ph.x, ph.z)
	if f == null: return
	var uu: float = ph.x - PlaygroundCourse.X0
	if uu < f.u0 - 1.0:
		ph.v = T
		inp.throttle = 0.0; inp.brake = 0.0; inp.sprint = false; inp.steer = 0.0; inp.hop = false
	else:
		inp.throttle = 0.0; inp.sprint = false; inp.brake = 0.0; inp.steer = 0.0


## the feature on this lane that starts ahead of (or at) x
func _next_feature(x: float, z: float):
	var l = course.lane_at(x, z)
	if l == null: return null
	var uu := x - PlaygroundCourse.X0
	for f in l.feats:
		if str(f.id).begins_with("rollin"): continue
		if f.u1 > uu: return f
	return null


## after the physics step: take-off / landing bookkeeping
func post_step(dt: float) -> void:
	var ph = game.phys
	var uu: float = ph.x - PlaygroundCourse.X0
	_since_land += dt
	if uu < _last_u - 3.0: _feat_in = null   # put back (bail tap, the test rider's next run): this run-in counts afresh
	_last_u = uu
	# speed into the feature: as the bike reaches its start
	var nf = _next_feature(ph.x, ph.z)
	if nf != null and nf != _feat_in and uu >= nf.u0 - 0.3 and uu < nf.u1:
		_feat_in = nf; _v_in = ph.v
	if ph.air and not _air and not ph.crash_on and _jump.is_empty():   # (a bounce while a landing settles belongs to it)
		var f = course.feature_at(ph.x, ph.z)
		_jump = {"feat": f.id if f != null else "-", "fname": f.name if f != null else "flat",
			"v_in": _v_in * 3.6 if f != null and f == _feat_in else ph.v * 3.6,
			"lip": sqrt(ph.v * ph.v + ph.vy * ph.vy) * 3.6, "ang": rad_to_deg(atan2(ph.vy, ph.v)),
			"x0": ph.x, "z0": ph.z, "y0": ph.y, "t": 0.0, "peak": 0.0, "clear": 0.0, "result": ""}
		_land_t = -1.0
	if ph.air and not _jump.is_empty() and _land_t < 0.0:
		_jump.t += dt
		_jump.peak = maxf(_jump.peak, ph.y - _jump.y0)
		_jump.clear = maxf(_jump.clear, ph.y - course.height(ph.x, ph.z))
	if not ph.air and _air and not _jump.is_empty() and _land_t < 0.0:
		if _jump.t < AIR_MIN or (_jump.t < BOUNCE_AIR and _since_land < BOUNCE_T):
			_jump = {}   # too short to be a jump, or the bike bouncing off the landing of the last one
		else:
			var sl := (course.height(ph.x + 0.3, ph.z) - course.height(ph.x - 0.3, ph.z)) / 0.6
			var gh := course.height(ph.x, ph.z)
			var spot := "flat"
			if sl < -0.08: spot = "landing"
			elif gh > 0.1 and absf(sl) < 0.04: spot = "deck"
			elif gh > 0.1 and sl < -0.02: spot = "knuckle"
			elif sl > 0.08: spot = "upslope"
			_jump.dist = Vector2(ph.x - _jump.x0, ph.z - _jump.z0).length()
			_jump.spot = spot
			_jump.slope = rad_to_deg(atan(sl))
			_jump.pitch_err = rad_to_deg(wrapf(ph.pitch - atan(sl), -PI, PI))
			_jump.jolt = ph.land_jolt
			_jump.v_land = ph.v * 3.6
			_jump.u_land = uu
			_land_t = 0.0
			_since_land = 0.0
	if _land_t >= 0.0 and not _jump.is_empty() and _jump.result == "":
		_land_t += dt
		if ph.air and _land_t < 0.15:
			pass
		elif _land_t >= SETTLE:
			_jump.result = "PERFECT" if ph.land_perfect > 0.0 or _jump.get("perfect", false) else "CLEAN"
			_finish()
		elif ph.land_perfect >= 0.99:
			_jump.perfect = true
	if _trace and (ph.air or _land_t >= 0.0 and _land_t < 0.4 or (f_here_is_jump(ph))):
		print("PGTRACE u=%.2f y=%.3f gy=%.3f v=%.2f vy=%.2f pitch=%.3f gp=%.3f air=%s cf=%s cr=%s body_y=%.3f throw=%.2f crash=%s" % [
			uu, ph.y, course.height(ph.x, ph.z), ph.v, ph.vy, ph.pitch, ph._g_pitch, ph.air, ph.c_f, ph.c_r, ph.body_y - ph.y, ph.throw_v, ph.crash_pending])
	_air = ph.air
	_tries_step(dt)
	_draw_label()


var _trace := Env.s("BMX_PG_TRACE") != ""   # tests: every physics step on a jump feature / in the air (PGTRACE lines)

func f_here_is_jump(ph) -> bool:
	return course.jump_mask(ph.x, ph.z) > 0.0


func on_crash(reason: String) -> void:
	if not _jump.is_empty() and _jump.result == "":
		if _land_t < 0.0:   # crashed in the air (or at touch-down before it was seen)
			_jump.dist = Vector2(game.phys.x - _jump.x0, game.phys.z - _jump.z0).length()
			_jump.u_land = game.phys.x - PlaygroundCourse.X0
			_jump.spot = "?"; _jump.slope = 0.0; _jump.pitch_err = 0.0; _jump.jolt = game.phys.land_jolt; _jump.v_land = 0.0
		_jump.result = "CRASH " + reason
		_finish()
	else:
		print("PG CRASH (on the ground) %s at u=%.1f v=%.1f" % [reason, game.phys.x - PlaygroundCourse.X0, game.phys.v * 3.6])
		_try_crash = reason


func _finish() -> void:
	var j := _jump
	jumps.append(j)
	_last = "%s [%s]\nin %.0f km/h · lip %.0f km/h @ %.0f°\nair %.2f s · %.1f m · peak +%.2f m (%.2f m up)\nlanded %s %.0f° · pitch %+.0f° · jolt %.1f\n%s" % [
		j.fname, j.feat, j.v_in, j.lip, j.ang, j.t, j.dist, j.peak, j.clear, j.spot, j.slope, j.pitch_err, j.jolt, j.result]
	print("PG JUMP feat=%s v_in=%.1f lip=%.1f ang=%.1f air=%.2f dist=%.2f peak=%.2f clear=%.2f land=%s slope=%.1f pitch_err=%.1f jolt=%.2f v_land=%.1f result=%s" % [
		j.feat, j.v_in, j.lip, j.ang, j.t, j.dist, j.peak, j.clear, j.spot, j.slope, j.pitch_err, j.jolt, j.v_land, j.result.replace(" ", "_")])
	if target != null and _try >= 0 and _try_done < 0.0: _try_jumps.append(j)
	_jump = {}
	_land_t = -1.0


var _try_jumps: Array = []     # jumps measured in this try
var _try_crash := ""           # a crash on the ground this try
var _still := 0.0

## BMX_PG_SPEEDS tries: a try ends on a crash, once the bike is well past the feature, or when it has stood still
## for 1.5 s (rolled back into a gap...); then its result (the first jump on the target feature, else the crash,
## else NO JUMP) is kept and the next try starts from the run-in
func _tries_step(dt: float) -> void:
	if target == null or _try < 0: return
	var ph = game.phys
	_try_t += dt
	var uu: float = ph.x - PlaygroundCourse.X0
	_still = _still + dt if absf(ph.v) < 0.3 else 0.0
	var busy := not _jump.is_empty()
	if _try_done < 0.0 and _try_t > 1.0 and not busy and (ph.crash_on or uu > target.u1 + 12.0 or _still > 1.5):
		var r := {"try": _try, "kmh": target_speed() * 3.6, "result": "NO JUMP", "feat": "-"}
		for j in _try_jumps:   # the biggest jump on the feature (a crash on any of them wins)
			if j.feat != target.id: continue
			if r.feat == "-" or j.t > r.air or str(j.result).begins_with("CRASH"):
				r = {"try": _try, "kmh": target_speed() * 3.6, "result": j.result, "feat": j.feat, "dist": j.dist, "air": j.t, "spot": j.spot, "lip": j.lip, "n": 0}
				if str(j.result).begins_with("CRASH"): break
		for j in _try_jumps: if j.feat == target.id: r.n = int(r.get("n", 0)) + 1
		if r.result == "NO JUMP" and _try_crash != "": r.result = "CRASH " + _try_crash
		if r.result == "NO JUMP" and _still > 1.5: r.result = "STOPPED"
		results.append(r)
		_try_done = 0.0
	if _try_done >= 0.0:
		_try_done += dt
		if _try_done > (2.0 if ph.crash_on else 0.6):
			_try += 1
			_try_done = -1.0
			_try_t = 0.0
			_try_jumps = []; _try_crash = ""; _still = 0.0; _feat_in = null; _jump = {}; _land_t = -1.0
			if _try >= speeds.size() * tries:
				_summary()
				_try = -1
				GameState.quit()
				return
			game.level_reset_to(course.spawn_for(target, float(Env.s("BMX_PG_BACK")) if Env.s("BMX_PG_BACK") != "" else 25.0))
			game.phys.v = target_speed()


func _draw_label() -> void:
	if _label == null: return
	_label.visible = game.hud != null and game.hud.visible
	if not _label.visible: return
	var ph = game.phys
	var f = course.feature_at(ph.x, ph.z)
	var here := ("%s  [%s]" % [f.name, f.id]) if f != null else "-"
	var T := target_speed()
	_label.text = "PLAYGROUND  ·  %s  ·  %.0f km/h%s\nLAST JUMP: %s" % [here, ph.v * 3.6, ("  · cruise %.0f" % (T * 3.6)) if T >= 0.0 else "", _last]


func _summary() -> void:
	for r in results:
		print("PGSUM try=%d kmh=%.0f lip=%.0f feat=%s result=%s dist=%.2f air=%.2f land=%s airs=%d" % [r.try, r.kmh, r.get("lip", 0.0), r.feat, str(r.result).replace(" ", "_"), r.get("dist", 0.0), r.get("air", 0.0), r.get("spot", "-"), r.get("n", 0)])


func _exit_tree() -> void:
	if target == null and not jumps.is_empty():
		var clean := 0
		for j in jumps: if not str(j.result).begins_with("CRASH"): clean += 1
		print("PGSUM jumps=%d clean=%d crashed=%d" % [jumps.size(), clean, jumps.size() - clean])
