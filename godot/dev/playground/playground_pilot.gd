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
var RUNUP := float(Env.s("BMX_PG_PILOT_RUNUP")) if Env.s("BMX_PG_PILOT_RUNUP") != "" else 30.0   # m before the feature it restarts at (tests: BMX_PG_PILOT_RUNUP)
const AFTER := 14.0            # m past a feature's end: that run is over
const SLALOM_OFF := 1.3        # m beside a cone it passes

var course: PlaygroundCourse
var speed := 30.0 / 3.6        # m/s on the run-in
var mode := "feature"
var pump := true
var tech := ""          # tests: jump technique (pop / early / hold / squash / hop), see tick()
var tech_rel := 0.1
var land_yaw_deg := 0.0
var land_tuck := false
var _hop_clock := 0.0
var target = null              # the feature it repeats
var runs := 0
var _done_t := 0.0             # s since the run ended (a short pause, then back)
var _lane: PlaygroundCourse.Lane
var auto := true
var auto_v := {}               # feature id -> run-in speed (m/s) it learned for that jump
var cur = null                 # the feature it's riding at now (the bar shows its speed)
var _last := {}               # feature id -> [run-in m/s, landing error m] of the last run (bracketing)
var _brake_t := 0.0
var ended := ""                # how the last run ended: OVER (past the feature), STALLED, ROLLED_BACK, CRASH, STOPPED (brakes)
var _back_t := 0.0
var _brake_done := ""          # lane mode: the strip it has stopped on (rides on from there)
var _seen := 0                 # the probe's jumps already learned from


func _init(c: PlaygroundCourse) -> void:
	course = c
	if Env.s("BMX_PG_PILOT_KMH") != "": speed = float(Env.s("BMX_PG_PILOT_KMH")) / 3.6
	if Env.s("BMX_PG_PILOT") == "lane": mode = "lane"
	if Env.s("BMX_PG_PILOT_PUMP") == "0": pump = false
	tech = Env.s("BMX_PG_PILOT_TECH")
	if Env.s("BMX_PG_PILOT_YAW") != "": land_yaw_deg = float(Env.s("BMX_PG_PILOT_YAW"))
	land_tuck = Env.s("BMX_PG_PILOT_TUCK") != ""
	if Env.s("BMX_PG_PILOT_REL") != "": tech_rel = float(Env.s("BMX_PG_PILOT_REL"))
	if Env.s("BMX_PG_PILOT_AUTO") == "0": auto = false


func reset() -> void:
	super.reset()
	_brake_done = ""
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
	if f.has("design"): return float(f.design.p.v)   # a JumpDesign jump: the speed it was laid out for
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
	if game.lab != null: game.lab.fresh(game.phys)   # (a clean state: the same run comes out the same)
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
		if _crash_t > 2.0: ended = "CRASH"; restart(game)
		return out
	_crash_t = 0.0
	if mode == "feature" and target != null and target.has("ramp"):
		return _tick_ramp(game, dt, ph, out)
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
		if _done_t > 0.6: ended = "OVER"; restart(game)
		return out
	_done_t = 0.0
	# a brake strip: from its line full on the lever(s) it tests, until stopped; then the run again
	var on = course.feature_at(ph.x, ph.z)
	if on != null and str(on.get("kind", "")) == "brake" and uu >= float(on.lip) - 0.05 and uu <= float(on.u1) and not ph.air 			and on.id != _brake_done and (mode != "feature" or on == target):   # (feature mode: only its own strip)
		var which: String = on.get("which", "both")
		if which == "front": out.brake_front = 1.0
		elif which == "rear": out.brake_rear = 1.0
		else: out.brake = 1.0
		out.steer = 0.0
		if absf(ph.v) < 0.3:
			_brake_t += dt
			if _brake_t > 0.6:   # stopped: feature mode = the run again, lane mode = ride on to the next one
				_brake_t = 0.0
				if mode == "feature": ended = "STOPPED"; restart(game)
				else: _brake_done = on.id
		return out
	_brake_t = 0.0
	# steer: a point ahead on the lane's centre line (heading 0 = +x; atan2 as the demo rider does it); in a slalom
	# the point beside the next cone, alternate sides
	var look := clampf(5.0 + absf(ph.v) * 0.5, 6.0, 18.0)
	var aim := Vector2(look, l.z - ph.z)
	if on != null and str(on.get("kind", "")) == "slalom":
		for i in l.cones.size():
			var c: Array = l.cones[i]
			if c[0] > uu + 0.3:
				var side := 1.0 if i % 2 == 0 else -1.0
				aim = Vector2(c[0] - uu, l.z + c[1] + side * SLALOM_OFF - ph.z)
				break
	var err: float = BikePhysics.ang_diff(atan2(-aim.y, maxf(1.0, aim.x)), ph.heading)
	var want := clampf(err * 2.4, -1.0, 1.0) if not ph.air else 0.0
	_steer += (want - _steer) * clampf(dt / (0.07 + dt), 0.0, 1.0)
	out.steer = _steer
	# speed: pedal / brake to `speed` on the run-in, hands off near and on a feature
	# hands off only into jumps (a fresh press at a lip throws a flip); bumps, slopes, camber, brakes: keep riding
	var near: bool = f != null and uu > f.u0 - LET_GO and bool(f.get("jump", true)) and str(f.get("kind", "")) not in ["brake", "slalom"]
	target_v = spd
	if ph.air or near:
		out.throttle = 0.0; out.brake = 0.0   # (letting go is fine; a fresh press near a lip would throw a flip)
	else:
		var d: float = ph.v - spd
		if d < -0.3: out.throttle = clampf(-d * 0.8, 0.3, 1.0)
		elif d > 0.4: out.brake = clampf(d * 0.35, 0.0, 1.0)
		out.sprint = ph.v < 5.0 and spd > 7.0
	out.hop = pump and not ph.air and ph.prep > 0.15
	# jump technique (tests, BMX_PG_PILOT_TECH): how he works the lip with the body stick / hop.
	#   pop = stick back as the lip comes up (preload), snapped forward `tech_rel` s before its edge; early = the same
	#   let go 0.4 s out (a hop off the face); hold = hop held right through the lip, never let go (the assist alone);
	#   squash = stick held forward into it; hop = a full hop on the flat run-in every 2.5 s
	# tests: land every jump with the bike turned this many degrees to the way it flies (BMX_PG_PILOT_YAW), or with the
	# tuck held into the ground (BMX_PG_PILOT_TUCK=1)
	if land_yaw_deg != 0.0 and ph.air and ph.air_time > 0.3: ph.slip = deg_to_rad(land_yaw_deg)
	if land_tuck and ph.air and ph.air_time > 0.15: out.hop = true
	# (tests, BMX_PG_PILOT_AIRTUCK=1: hop held from just after take-off, let go as he reaches for the landing: the air tuck)
	if Env.s("BMX_PG_PILOT_AIRTUCK") != "" and ph.air and ph.air_time > 0.05 and ph.land_prep < 0.15: out.hop = true
	# tests: come down nose up / down this many degrees from level (BMX_PG_PILOT_PITCH: a back-wheel landing)
	if Env.s("BMX_PG_PILOT_PITCH") != "" and ph.air and ph.air_time > 0.25:
		ph.pitch = deg_to_rad(float(Env.s("BMX_PG_PILOT_PITCH"))); ph.pitch_v = 0.0; ph.air_w = 0.0
	if Env.s("BMX_PG_PILOT_VY") != "" and ph.air and ph.air_time > 0.25 and ph.vy < 0.0:   # tests: comes down at least this fast (m/s)
		ph.vy = minf(ph.vy, -float(Env.s("BMX_PG_PILOT_VY")))
	if tech != "":
		out.hop = false
		var lip_in: float = ph.lip_last if ph.lip_state == 2 else INF
		var rel: float = 0.4 if tech == "early" else tech_rel
		if tech == "pop" or tech == "early":
			if ph.air: out.body_fwd = 0.0   # (the thumb is back at the centre: pushed again in the air it read as nose down)
			elif lip_in < rel: out.body_fwd = 1.0
			elif lip_in < INF: out.body_fwd = -1.0
		elif tech == "hold":
			out.hop = (not ph.air and lip_in < INF) or (ph.air and ph.air_time < 0.4)
		elif tech == "squash":
			out.body_fwd = 0.9 if (near and not ph.air) else 0.0
		elif tech == "hop":
			_hop_clock += dt
			var hp := fmod(_hop_clock, 2.5)
			if hp < 0.3: out.body_fwd = -1.0
			elif hp < 0.45: out.body_fwd = 1.0
	# gears like a rider: easier when slow and working (a climb), harder when spinning out (shift() +1 = easier)
	_gear_t -= dt
	if ph.geared and not ph.air and _gear_t <= 0.0:
		if ph.v < 4.5 and out.throttle > 0.5: ph.shift(1); _gear_t = 0.35
		elif ph.v > 8.0 and out.throttle > 0.5: ph.shift(-1); _gear_t = 0.6
	# stalled on a climb and rolling back down: brake and stand (then the stuck rule starts the run again)
	if not ph.air and ph.v < -0.2:
		out.throttle = 0.0; out.sprint = false; out.brake = 1.0
		_back_t += dt
		if _back_t > 1.0:
			_back_t = 0.0; ended = "ROLLED_BACK"; restart(game)
		return out
	_back_t = 0.0
	# stuck (stopped against something, or crawling up a slope it can't climb): the run again
	if not ph.air and absf(ph.v) < 0.4 and not near:
		_stuck_t += dt
		if _stuck_t > 3.0: _stuck_t = 0.0; ended = "STALLED"; restart(game)
	else:
		_stuck_t = 0.0
	return out


## a ramp placed with the ramp editor: the same riding, along its own axis
func _tick_ramp(game, dt: float, ph, out: Dictionary) -> Dictionary:
	var r = target.ramp
	if not (r in course.ramps): target = null; return out
	cur = target
	var lc: Vector2 = r.local(ph.x, ph.z)
	var uu := lc.x
	if uu > float(target.u1) + AFTER or absf(lc.y) > r.reach + 25.0 or uu < -RUNUP - 20.0:
		if not ph.air:
			_done_t += dt
			out.brake = 1.0
			if _done_t > 0.6: ended = "OVER"; restart(game)
		return out
	_done_t = 0.0
	var look := clampf(5.0 + absf(ph.v) * 0.5, 6.0, 18.0)
	var p: Vector2 = r.origin() + r.dir() * (uu + look)
	var aim := Vector2(p.x - ph.x, p.y - ph.z)
	var err: float = BikePhysics.ang_diff(atan2(-aim.y, aim.x), ph.heading)
	var want := clampf(err * 2.4, -1.0, 1.0) if not ph.air else 0.0
	_steer += (want - _steer) * clampf(dt / (0.07 + dt), 0.0, 1.0)
	out.steer = _steer
	var spd := speed_for(target)
	target_v = spd
	var near := uu > float(target.u0) - LET_GO
	if ph.air or near:
		out.throttle = 0.0; out.brake = 0.0
	else:
		var d: float = ph.v - spd
		if d < -0.3: out.throttle = clampf(-d * 0.8, 0.3, 1.0)
		elif d > 0.4: out.brake = clampf(d * 0.35, 0.0, 1.0)
		out.sprint = ph.v < 5.0 and spd > 7.0
	out.hop = pump and not ph.air and ph.prep > 0.15
	if not ph.air and absf(ph.v) < 0.4 and not near:
		_stuck_t += dt
		if _stuck_t > 3.0: _stuck_t = 0.0; ended = "STALLED"; restart(game)
	else:
		_stuck_t = 0.0
	return out
