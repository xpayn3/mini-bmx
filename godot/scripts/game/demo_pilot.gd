class_name DemoPilot
extends RefCounted
## Demo mode (F2, or DEMO on the title screen): an AI rider that rides the whole trail like a pro while the
## player changes anything live (tuning card P / K / L, dust, light, camera...). It only produces the same input
## dictionary the keys and the pad do (`Game._read_input`), so the physics, the rider and every effect are
## exactly the real ones. No shortcuts: it reads the centreline, plans a speed profile from the bends, rocks and
## jumps ahead (brake early, never at a lip: a fresh brake press there throws a back flip), steers with a
## smooth pure pursuit that cuts the inside of a bend, pumps the lips and puts the rider back on the trail if
## it ever crashes or gets stuck.
## Sliders: Tune group "Demo rider" (tuning card > Ride > Demo): pace, top speed, racing line, pump, smoothness.

const DECEL := 5.5          # m/s^2 it plans to brake with (the bike can do more: brakeForce)
const A_LAT := 7.0          # m/s^2 of sideways grip it plans a bend with, at pace 1
## m/s over each kind of route feature at pace 1 (wood is steep and hard, so slowest)
const FEAT_V := {"table": 14.0, "tableLine": 14.0, "kicker": 12.0, "rhythm": 13.0, "flow": 14.0, "woodKicker": 8.5, "bridge": 11.0, "woodDrop": 7.0, "skinny": 5.5}
## the least speed a feature wants (m/s): tabletops have a gap to clear
const FEAT_MIN := {"table": 9.5, "tableLine": 9.5, "kicker": 7.5, "rhythm": 6.0, "woodKicker": 7.5}
const ROCK_V := 9.0         # m/s through a rock garden at pace 1
const SCAN := 100.0         # m looked ahead for the speed profile

var _i := -1                # nearest centreline index (2 m steps)
var _steer := 0.0           # smoothed steer command
var _thr := 0.0             # last throttle (held through lips and the air: a fresh press at a lip throws a flip)
var _brk := 0.0             # last brake
var _crash_t := 0.0
var _stuck_t := 0.0
var _flash_t := 0.0
var target_v := 0.0         # m/s, the speed the plan wants now (HUD / debug)
var s_here := 0.0           # m along the trail
var cross := 0.0            # m, signed distance from the centreline (debug)
var resets := 0             # how many times it had to be put back


func reset() -> void:
	_i = -1; _steer = 0.0; _thr = 0.0; _crash_t = 0.0; _stuck_t = 0.0


var _OLD_LINE := OS.get_environment("BMX_OLD_LINE") != ""   # (tests: the old line + flat-ground corner plan)
static func _tv(key: String, fallback: float) -> float:
	return float(Tune.v.get(key, fallback))


## the input dictionary for this physics step
func tick(game, dt: float) -> Dictionary:
	var ph = game.phys
	var out := {"pad": false, "body_fwd": 0.0, "body_lean": 0.0, "throttle": 0.0, "brake": 0.0, "steer": 0.0, "hop": false, "sprint": false}
	var tc: TrailCourse = game.terrain.field.course if game.terrain and game.terrain.field else null
	if tc == null or tc.n < 8:
		return out
	# --- crashed: lie there a moment, then back on the trail (the same as a tap on bail)
	if ph.crash_on:
		if _crash_t == 0.0 and OS.get_environment("BMX_DEMO") != "":
			for f in game.terrain.field.route_feats:
				if absf(f.s - s_here) < 80.0: print("  FEAT type=%s s=%.0f len=%.0f" % [str(f.type), f.s, f.len])
			print("DEMOCRASH s=%.0f v=%.1f km/h reason='%s' pitch=%.2f lean=%.2f slip=%.2f since_land=%.2f feat_tgt=%.1f" % [s_here, ph.v * 3.6, ph.crash_pending, ph.pitch, ph.lean, ph.slip, ph.since_land, target_v * 3.6])
		_crash_t += dt
		if _crash_t > 2.6:
			_crash_t = 0.0; resets += 1
			game.reset_to_trail()
			reset()
		return out
	_crash_t = 0.0
	# --- where on the trail (window search around the last index; whole trail when lost)
	var px: float = ph.x
	var pz: float = ph.z
	var best := -1
	var bd := INF
	if _i >= 0:
		for k in range(maxi(0, _i - 20), mini(tc.n, _i + 40)):
			var d: float = (tc.X[k] - px) * (tc.X[k] - px) + (tc.Z[k] - pz) * (tc.Z[k] - pz)
			if d < bd: bd = d; best = k
	if best < 0 or bd > 25.0 * 25.0:
		best = 0; bd = INF
		for k in tc.n:
			var d2: float = (tc.X[k] - px) * (tc.X[k] - px) + (tc.Z[k] - pz) * (tc.Z[k] - pz)
			if d2 < bd: bd = d2; best = k
	_i = best
	s_here = _i * TrailCourse.STEP
	cross = sqrt(bd)
	if cross > 18.0 and not ph.air:   # far off the trail: back on it
		resets += 1
		game.reset_to_trail(); reset()
		return out

	var pace := clampf(_tv("demoPace", 1.0), 0.3, 2.0)
	var vmax := _tv("demoMaxKmh", 60.0) / 3.6
	var v: float = ph.v
	var in_air: bool = ph.air or ph.front_air or ph.rear_air
	var lip: bool = ph.prep > 0.2 or in_air

	# --- the speed plan: the lowest speed any point ahead allows, as it could be reached braking from here
	var tgt := vmax
	var a_lat := A_LAT * pace * pace
	var steps := int(SCAN / TrailCourse.STEP)
	var kmax_near := 0.0
	for j in range(0, steps, 2):
		var idx := mini(tc.n - 2, _i + j)
		var k := 0.0
		for q in range(maxi(1, idx - 1), mini(tc.n - 1, idx + 2)):
			k = maxf(k, absf(tc.KAP[q]))
		var d := j * TrailCourse.STEP
		if j < 8: kmax_near = maxf(kmax_near, k)
		# (a berm holds the bike up: its bank's own share of the turn, G x tan, comes on top of the tyres' grip)
		var bank_t := 0.0
		for q in range(maxi(0, idx - 1), mini(tc.n, idx + 2)): bank_t = maxf(bank_t, absf(tc.BT[q]))
		if _OLD_LINE: bank_t = 0.0
		var va := minf(vmax, sqrt((a_lat + BikePhysics.G * bank_t * _tv("demoBerm", 1.0)) / maxf(k, 0.004)))
		if tc.KD[idx] == TrailCourse.ROCKS: va = minf(va, ROCK_V * pace)
		tgt = minf(tgt, sqrt(va * va + 2.0 * DECEL * d))
	var near_feat := false
	var floor_v := 0.0
	var rf: Array = game.terrain.field.route_feats
	if rf.size() > 0:
		var lo := 0
		var hi := rf.size()
		while lo < hi:   # first feature that hasn't ended behind us
			var mid := (lo + hi) >> 1
			if rf[mid].s + rf[mid].len > s_here: hi = mid
			else: lo = mid + 1
		for q in range(lo, mini(lo + 3, rf.size())):
			var fd: float = rf[q].s - s_here
			if fd > SCAN: break
			var own = rf[q].get("v")   # (a built level's jump: its own design speed)
			var vf := minf(vmax, (float(own) if own != null else float(FEAT_V.get(str(rf[q].type), 12.0))) * pace)
			var brake_d := maxf(0.0, fd - 14.0)   # be at the feature speed 14 m before it
			tgt = minf(tgt, sqrt(vf * vf + 2.0 * DECEL * brake_d))
			if fd < 16.0 and rf[q].s + rf[q].len > s_here - 4.0: near_feat = true
			var own_min = rf[q].get("vmin")
			var fmin: float = float(own_min) if own_min != null else float(FEAT_MIN.get(str(rf[q].type), 0.0))   # a gap needs a run-up, or it drops in
			if fmin > 0.0 and fd < 40.0: floor_v = maxf(floor_v, minf(fmin, vmax))
	tgt = maxf(tgt, floor_v)
	target_v = tgt

	# --- steering: pure pursuit to a point ahead, nudged to the inside of the bend (racing line)
	var look := clampf(4.5 + absf(v) * 0.45, 6.0, 20.0)
	var li := mini(tc.n - 3, _i + int(look / TrailCourse.STEP))
	var lx: float = tc.X[li]
	var lz: float = tc.Z[li]
	var line := _tv("demoLine", 0.5)
	if line > 0.0 and not near_feat:
		var nx: float = tc.TX[li + 1] - tc.TX[li - 1]
		var nz: float = tc.TZ[li + 1] - tc.TZ[li - 1]
		var nl := sqrt(nx * nx + nz * nz)
		if nl > 1e-5:
			var bend := smoothstep(0.012, 0.05, absf(tc.KAP[li]))
			var off := minf(tc.W[li] * 0.4, 1.3) * line * bend
			# a banked bend: up on the berm (outside of the centreline, where its bank is), not cut to the flat inside
			var bw := 0.0 if _OLD_LINE else smoothstep(TrailCourse.BERM_LINE_FROM, TrailCourse.BERM_LINE_FULL, absf(tc.BT[li]))
			off = lerpf(off, -minf(TrailCourse.BERM_LINE, maxf(0.0, tc.W[li] - 0.9)) * bend, bw)
			lx += nx / nl * off; lz += nz / nl * off
	var ra = game.terrain.rope_aim(px, pz, look)   # a rope bridge: its own straight line, not the trail's
	if ra != null:
		lx = ra.x; lz = ra.y
	var err: float = BikePhysics.ang_diff(atan2(-(lz - pz), lx - px), ph.heading)
	var want := clampf(err * 2.4, -1.0, 1.0)
	if in_air: want = 0.0
	var smooth := _tv("demoSmooth", 1.0)
	var rate := clampf(dt / (0.07 * smooth + dt), 0.0, 1.0)
	_steer += (want - _steer) * rate
	out.steer = clampf(_steer, -1.0, 1.0)

	# --- pedal / brake
	var over: float = v - tgt
	if in_air:
		out.brake = 0.0; out.throttle = 0.0    # hands off in the air (W / S there tilt the bike)
	elif lip or near_feat:
		# the physics reads a FRESH brake / pedal press near a lip as a back / front flip throw: here a key may be
		# let go but never newly pressed (speed is planned so that it is already right 16 m before a feature)
		out.brake = _brk if over > -0.5 else 0.0
		out.throttle = _thr if over < 0.5 else 0.0
	elif over > 0.6:
		out.brake = clampf(over * 0.35, 0.0, 1.0)
		out.throttle = 0.0
	elif over < -0.5:
		out.throttle = 1.0
	else:
		out.throttle = 0.0                 # on the plan: coast
	if absf(ph.slip) > 0.55 * float(Tune.v.get("slipMax", 1.1)) and not lip:   # sliding: lift and straighten
		out.throttle = 0.0
		out.brake = maxf(out.brake, 0.0)
	_thr = out.throttle
	_brk = out.brake
	# the pump: push into the lips and rollers
	out.hop = _tv("demoPump", 1.0) > 0.5 and not ph.air and ph.prep > 0.15
	# ...and through a banked turn: pushed into the berm with the body stick forward (bermPump), not the hop button
	# (held hop crouches and pops off the berm's top), not near a lip
	# (only when it wants the speed: pumped while already too fast it arrives at the next bend braking hard)
	if _tv("demoPump", 1.0) > 0.5 and not ph.air and not near_feat and ph.berm_k > 0.15 and absf(ph.lat_a) > 3.0 and over < -0.3:
		out.body_fwd = 0.7
	# from a standstill: sprint away
	out.sprint = v < 5.0 and tgt > 7.0 and not in_air
	if v < 5.0 and tgt > 4.0: out.throttle = 1.0; out.brake = 0.0

	# --- stuck (against something): put back on the trail
	if not in_air and absf(v) < 0.4 and tgt > 3.0:
		_stuck_t += dt
		if _stuck_t > 4.0:
			_stuck_t = 0.0; resets += 1
			game.reset_to_trail(); reset()
	else:
		_stuck_t = 0.0
	return out
