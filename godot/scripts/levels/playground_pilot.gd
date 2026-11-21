class_name PlaygroundPilot
extends DemoPilot
## The test playground's test rider (F2 there, or the TEST RIDER buttons on the dev view): rides the lane you're on
## at a set speed while you move sliders, so every run is the same ride and only your change differs.
## Like the trail's demo rider it only produces the input dictionary the keys / pad do: the physics is the real one.
## - holds the lane's centre line (pure pursuit), pedals / brakes to `speed` on the run-in, hands off from
##   LET_GO m before a feature to its landing (never a fresh pedal / brake press near a lip: that throws a flip);
##   `pump` = it pumps the lips like the demo rider (hop held while the legs load, ph.prep)
## - `mode` "feature": after the feature (or a crash) back to RUNUP m before the same feature, at `speed`,
##   again and again; "lane": rides on through the whole lane, then back to the lane's start
## - it starts on the feature ahead of where you are when you hand over (`target`)
## - `auto` (default on): jumps with a landing to aim for (tables, gaps, step-ups: `land0..land1` in the feature) are
##   ridden at the speed they need: first estimated from the shape (projectile from the lip at its angle to 35 % down
##   the landing, + the climb up the kicker), then corrected after every run from where it really landed
##   (`_learn`: short = faster, long = slower, a crash short = +0.8 m/s). It keeps learning, so after a slider change it
##   finds the jump's speed again; that speed (`auto_v`, shown on the bar) is itself a measurement. - / + nudge it.
##   Other features (hops, drops, rollers, bumps, slopes) use the set speed. `PG AUTO` lines per correction.
## Tests: BMX_PG_PILOT=feature|lane (+ BMX_PG_AT, BMX_PG_PILOT_KMH=30, BMX_PG_PILOT_PUMP=0) starts with it on.

const LET_GO := 1.5            # m before a feature: hands off
const RUNUP := 30.0            # m before the feature it restarts at
const AFTER := 14.0            # m past a feature's end: that run is over

var course: PlaygroundCourse
var speed := 30.0 / 3.6        # m/s on the run-in
var mode := "feature"
var pump := true
var target = null              # the feature it repeats
var runs := 0
var _done_t := 0.0             # s since the run ended (a short pause, then back)
var _lane: PlaygroundCourse.Lane
var auto := true
var auto_v := {}               # feature id -> run-in speed (m/s) it learned for that jump
var cur = null                 # the feature it's riding at now (the bar shows its speed)
var _last := {}               # feature id -> [run-in m/s, landing error m] of the last run (bracketing)
var _seen := 0                 # the probe's jumps already learned from


func _init(c: PlaygroundCourse) -> void:
	course = c
	if Env.s("BMX_PG_PILOT_KMH") != "": speed = float(Env.s("BMX_PG_PILOT_KMH")) / 3.6
	if Env.s("BMX_PG_PILOT") == "lane": mode = "lane"
	if Env.s("BMX_PG_PILOT_PUMP") == "0": pump = false
	if Env.s("BMX_PG_PILOT_AUTO") == "0": auto = false


func reset() -> void:
	super.reset()
	_done_t = 0.0


func kmh() -> float:
	return speed_for(cur) * 3.6

## - / + on the bar: the learned speed of the jump it's on (auto), else the set speed
func set_kmh(k: float) -> void:
	if _auto_on(cur): auto_v[cur.id] = clampf(k, 6.0, 70.0) / 3.6
	else: speed = clampf(k, 6.0, 70.0) / 3.6

func _auto_on(f) -> bool:
	return auto and f != null and float(f.get("land0", -1.0)) >= 0.0

## the run-in speed for feature f
func speed_for(f) -> float:
	if not _auto_on(f): return speed
	if not auto_v.has(f.id): auto_v[f.id] = estimate(f)
	return auto_v[f.id]

## run-in speed from the shape: from the lip (height, angle) to 35 % down the landing, plus the climb up the kicker
func estimate(f) -> float:
	var l = course.lane_by_id(f.lane)
	var ul: float = f.lip
	var hl: float = l.profile(ul)
	var ut: float = f.land0 + 0.35 * (f.land1 - f.land0)
	var dx := ut - ul
	var dy: float = l.profile(ut) - hl
	var th := deg_to_rad(float(f.lip_deg))
	var den := 2.0 * cos(th) * cos(th) * (dx * tan(th) - dy)
	if den <= 0.01 or dx <= 0.0: return speed
	var vl := sqrt(9.81 * dx * dx / den)
	return sqrt(vl * vl + 2.0 * 9.81 * hl) * 1.03

## after a jump (the probe's record): move that jump's speed towards landing on the sweet spot
func _learn(j: Dictionary) -> void:
	var f = course.feature_by_id(str(j.get("feat", "")))
	if not _auto_on(f) or not j.has("u_land"): return
	var ut: float = f.land0 + 0.35 * (f.land1 - f.land0)
	var e: float = float(j.u_land) - ut                       # + = long, - = short (m)
	var v0 := speed_for(f)
	if str(j.get("result", "")).begins_with("CRASH") and e < 0.0: e = minf(e, -2.0)   # crashed short: well short
	var nv := v0
	if absf(e) >= 0.4:   # (on the spot: leave it)
		var p = _last.get(f.id)
		if p != null and signf(p[1]) != signf(e) and absf(p[0] - v0) > 0.05:
			# landed short once and long once: the speed is between them (secant), never outside
			nv = v0 - e * (v0 - p[0]) / (e - p[1])
			nv = clampf(nv, minf(v0, p[0]), maxf(v0, p[0]))
		else:   # distance ~ v²: d(dist) / dv = 2 dist / v, half of it (the lip is touchy), at most 0.8 m/s a run
			var dd := maxf(2.0, ut - float(f.lip))
			nv = v0 + clampf(-e * v0 / (2.0 * dd) * 0.5, -0.8, 0.8)
		_last[f.id] = [v0, e]
	auto_v[f.id] = clampf(nv, 3.0, 20.0)
	print("PG AUTO feat=%s landed %+.2f m from the spot (%s) -> run-in %.1f km/h (was %.1f)" % [f.id, e, str(j.get("result", "")), auto_v[f.id] * 3.6, v0 * 3.6])


## the next feature along the lane at u (rollins skipped), or null
func _next(l, uu: float):
	for f in l.feats:
		if str(f.id).begins_with("rollin"): continue
		if f.u1 > uu: return f
	return null


## back to the start of this run: RUNUP m before the target (feature mode) or the lane's start, already at speed
func restart(game) -> void:
	var sp: Vector3
	if mode == "feature" and target != null:
		sp = course.spawn_for(target, RUNUP)
	else:
		var l = _lane if _lane != null else course.lanes[0]
		sp = Vector3(PlaygroundCourse.X0 + 4.0, 0.0, l.z)
		target = null
	game.level_reset_to(sp)
	if mode == "feature" and target != null: game.phys.v = speed_for(target)
	runs += 1
	reset()


func tick(game, dt: float) -> Dictionary:
	var ph = game.phys
	var pr = game.level_probe
	while pr != null and _seen < pr.jumps.size():
		_learn(pr.jumps[_seen]); _seen += 1
	var out := {"pad": false, "body_fwd": 0.0, "body_lean": 0.0, "throttle": 0.0, "brake": 0.0, "steer": 0.0, "hop": false, "sprint": false}
	# crashed: lie there a moment, then the run again
	if ph.crash_on:
		_crash_t += dt
		if _crash_t > 2.0: restart(game)
		return out
	_crash_t = 0.0
	var l = course.lane_at(ph.x, ph.z)
	if l == null:   # off the lanes (a bowl, the grass): back to a lane
		_lane = _lane if _lane != null else course.lanes[0]
		restart(game)
		return out
	_lane = l
	var uu: float = ph.x - PlaygroundCourse.X0
	if mode == "feature" and (target == null or target.lane != l.id):
		target = _next(l, uu - 2.0)
	var f = _next(l, uu)
	cur = target if mode == "feature" else f
	var spd := speed_for(f)
	# this run is over: past the target (feature mode) or the lane's end
	var over := false
	if mode == "feature":
		over = target == null or uu > target.u1 + AFTER
	else:
		over = uu > l.length() - 6.0
	if over and not ph.air:
		_done_t += dt
		out.brake = 1.0
		if _done_t > 0.6: restart(game)
		return out
	_done_t = 0.0
	# steer: a point ahead on the lane's centre line (heading 0 = +x; atan2 as the demo rider does it)
	var look := clampf(5.0 + absf(ph.v) * 0.5, 6.0, 18.0)
	var err: float = BikePhysics.ang_diff(atan2(-(l.z - ph.z), look), ph.heading)
	var want := clampf(err * 2.4, -1.0, 1.0) if not ph.air else 0.0
	_steer += (want - _steer) * clampf(dt / (0.07 + dt), 0.0, 1.0)
	out.steer = _steer
	# speed: pedal / brake to `speed` on the run-in, hands off near and on a feature
	var near: bool = f != null and uu > f.u0 - LET_GO
	target_v = spd
	if ph.air or near:
		out.throttle = 0.0; out.brake = 0.0   # (letting go is fine; a fresh press near a lip would throw a flip)
	else:
		var d: float = ph.v - spd
		if d < -0.3: out.throttle = clampf(-d * 0.8, 0.3, 1.0)
		elif d > 0.4: out.brake = clampf(d * 0.35, 0.0, 1.0)
		out.sprint = ph.v < 5.0 and spd > 7.0
	out.hop = pump and not ph.air and ph.prep > 0.15
	# stuck (stopped against something, or crawling up a slope it can't climb): the run again
	if not ph.air and absf(ph.v) < 0.4 and not near:
		_stuck_t += dt
		if _stuck_t > 3.0: _stuck_t = 0.0; restart(game)
	else:
		_stuck_t = 0.0
	return out
