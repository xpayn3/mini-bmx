extends Node
## Ride physics stress test on synthetic ground (no world, no rendering): grades up / down to 45 deg, side
## cambers, crests (take-off speed vs v^2 = g R), rollers, washboard, steps, kinks, plus a long random ride.
## Each case checks the result against plain physics where there is a closed form and prints PASS / FAIL.
##   ..._console.exe --headless --path godot res://tools/slope_stress.tscn [-- bike=dh only=<substr> verbose=1]
## (a scene, not -s: the physics needs the Tune autoload)
## Exit code = number of failed checks.

const DT := 1.0 / 120.0
const DH_EXTRAS := {"wheelbase": 1.2557, "wheelRadius": 0.374, "wheelRadiusRear": 0.355, "bbToRearAxle": 0.4423}

class Ground:
	var kind := "flat"
	var a := 0.0   # grade / camber angle (rad) or amplitude
	var b := 0.0   # wavelength / radius / step height
	var x0 := 20.0 # where the feature starts (m along +x)
	var noise: FastNoiseLite
	func height(x: float, z: float) -> float:
		match kind:
			"flat": return 0.0
			"grade":   # flat run-in, then a constant grade (a > 0 = uphill), joined by a 4 m round-off
				var s := x - x0
				if s <= 0.0: return 0.0
				var r := 4.0
				if s < r: return tan(a) * s * s / (2.0 * r)
				return tan(a) * (s - r * 0.5)
			"camber": return -tan(a) * z   # ground falls to +z (the rider's right when heading +x)
			"crest":   # circular-ish hump of radius b, height a
				var s := x - x0
				var w := sqrt(2.0 * b * a)
				if s < -w or s > w: return 0.0
				return a - s * s / (2.0 * b)
			"rollers":
				if x < x0: return 0.0
				return a * (1.0 - cos(TAU * (x - x0) / b)) * 0.5
			"washboard":
				if x < x0: return 0.0
				return a * sin(TAU * (x - x0) / b)
			"step":   # sharp ledge of height b (b < 0 = a drop), edge 2 cm wide
				return b * clampf((x - x0) / 0.02, 0.0, 1.0)
			"kink":   # constant grade a, then abruptly flat (a compression at the bottom of a chute)
				var s := x - x0
				return -tan(a) * minf(s, 0.0) if s < 0.0 else 0.0
			"noise":
				return noise.get_noise_2d(x, z) * a
		return 0.0
	func deck_height(x: float, z: float) -> float: return height(x, z)
	func top_height(x: float, z: float) -> float: return height(x, z)
	func surface(_x: float, _z: float) -> int: return 0
	func jump_mask(_x: float, _z: float) -> float: return 0.0
	func colliders_near(_x: float, _z: float) -> Array: return []

class Host:
	var terrain := Ground.new()
	var susp = null
	var ragdoll = null
	var pedal_a0 := [0.0, PI]
	var phys
	var crash := ""
	var takeoffs := 0
	var max_impact := 0.0
	func flash(_t): pass
	func msg_idle(): return false
	func burst(_p, _n, _s, _pw): pass
	func flow_up(): phys.flow_up()
	func smash(_c, _v, _p): return false
	func rock_chips(_c): pass
	func start_crash(r):
		if crash == "": crash = r
		phys.begin_crash()
	func get_up(): phys.get_up()
	func on_takeoff(): takeoffs += 1
	func on_landing(_at, imp): max_impact = maxf(max_impact, imp)
	func ride_fx(_dt, _f, _va, _w): pass

var fails := 0
var checks := 0
var only := ""
var verbose := false
var trace := false   # trace=1: prints the state 4x / s in every case run
var bike := "dh"
var tune: Node
var step_us := 0.0
var step_n := 0
func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("only="): only = a.substr(5)
		elif a.begins_with("bike="): bike = a.substr(5)
		elif a == "verbose=1": verbose = true
		elif a == "trace=1": trace = true
	tune = get_node("/root/Tune")
	var gs = load("res://scripts/core/game_state.gd")
	tune.set_ride(gs.BIKES[bike].ride)
	_run_all(gs.BIKES[bike])
	print("SLOPE_STRESS %s: %d / %d checks passed, physics step %.1f us avg over %d steps" % [
		"PASS" if fails == 0 else "FAIL", checks - fails, checks, step_us / maxf(1.0, step_n), step_n])
	get_tree().quit(fails)

func _make(cfg: Dictionary, kind: String, a := 0.0, b := 0.0) -> Array:
	var h := Host.new()
	h.terrain.kind = kind; h.terrain.a = a; h.terrain.b = b
	if kind == "noise":
		h.terrain.noise = FastNoiseLite.new()
	var p := BikePhysics.new(h); h.phys = p
	_last_p = p
	p.T = tune.v
	p.setup(DH_EXTRAS if bike != "bmx" else {}, cfg)
	p.reset_at(0.0, 0.0, 0.0)
	return [p, h]

func _inp(th := 0.0, br := 0.0, st := 0.0, sprint := false, hop := false) -> Dictionary:
	return {"throttle": th, "brake": br, "steer": st, "hop": hop, "sprint": sprint, "body_fwd": 0.0, "body_lean": 0.0, "pad": false}

## runs n steps, returns the stats; stops at a crash or a non-finite state
func _ride(p: BikePhysics, h: Host, secs: float, inp_f: Callable) -> Dictionary:
	p.ground_jolt = 0.0
	var st := {"vmax": 0.0, "insane": false, "air_t": 0.0, "lift_max": 0.0, "pitch_max": 0.0, "lean_max": 0.0, "steps": 0}
	var n := int(secs / DT)
	for i in n:
		var t := i * DT
		var t0 := Time.get_ticks_usec()
		p.step(DT, inp_f.call(t, p))
		step_us += Time.get_ticks_usec() - t0; step_n += 1
		st.steps += 1
		if not p.is_sane() or not is_finite(p.body_y + p.air_w + p.bike_lean + p.zw_f + p.zw_r):
			st.insane = true; break
		if h.crash != "": break
		st.vmax = maxf(st.vmax, absf(p.v))
		if trace and i % 30 == 0:
			print("  t=%.2f v=%.2f vy=%.2f pitch=%.2f g=%.2f slip=%.3f slip_w=%.3f grip_r=%.2f spin=%.2f drive=%.2f lean=%.2f nF=%.2f nR=%.2f air=%s cf=%s cr=%s comp_v=%.2f lat=%.2f" % [t, p.v, p.vy, p.pitch, p._g_pitch, p.slip, p.slip_w, p.grip_r, p.spin, p.a_drive, p.bike_lean, p.n_f, p.n_r, p.air, p.c_f, p.c_r, p.compress_v, p.lat_a])
		if p.air: st.air_t += DT
		else: st.lift_max = maxf(st.lift_max, p.y - h.terrain.height(p.x, p.z))
		st.pitch_max = maxf(st.pitch_max, absf(p.pitch - p._g_pitch) if not p.air else 0.0)
		st.lean_max = maxf(st.lean_max, absf(p.bike_lean))
	return st

var _last_p: BikePhysics
func _check(name: String, ok: bool, detail: String) -> void:
	checks += 1
	if _last_p: detail += " gjolt=%.1f" % _last_p.ground_jolt
	if not ok: fails += 1
	if not ok or verbose: print("%s  %-44s %s" % ["PASS" if ok else "FAIL", name, detail])

func _want(name: String) -> bool:
	return only == "" or name.contains(only)

## reference coast over the same ground (1D along +x): dv/dt = -g sin(slope) - roll - k v|v|, the slope read
## from the ground under the bike, so the run-in and round-off count the same as in the game
func _coast_model(v0: float, g: Ground, secs: float) -> float:
	var T: Dictionary = tune.v
	var ts: float = T.topSpeed
	var k: float = T.airDrag / (ts * ts)
	var v := v0
	var x := 0.0
	for i in int(secs / DT):
		var th := atan((g.height(x + 0.4, 0.0) - g.height(x - 0.4, 0.0)) / 0.8)
		var roll: float = 0.32 * T.rollRes * signf(v) * minf(1.0, absf(v) * 4)
		v += (-9.81 * sin(th) - roll - k * v * absf(v)) * DT
		v = clampf(v, -3.0, 24.0 * maxf(1.0, ts))
		x += v * cos(th) * DT
	return v

func _run_all(cfg: Dictionary) -> void:
	var nothing := func(_t, _p): return _inp()

	# 1. coasting on grades: speed after 5 s on the grade vs the closed form (within 6 %, +-0.4 m/s)
	for deg in [-45, -35, -25, -15, -8, -3, 0, 3, 8, 15]:
		var name := "coast grade %+d deg" % deg
		if not _want(name): continue
		var r := _make(cfg, "grade", deg_to_rad(deg))
		var p: BikePhysics = r[0]; var h: Host = r[1]
		h.terrain.x0 = 2.0
		p.v = 6.0
		var st := _ride(p, h, 6.0, nothing)
		var vm := _coast_model(6.0, h.terrain, 6.0)
		var ok: bool = not st.insane and r[1].crash == "" and absf(p.v - vm) < maxf(0.25, absf(vm) * 0.03)
		_check(name, ok, "v=%.2f model=%.2f m/s lift=%.3f crash=%s" % [p.v, vm, st.lift_max, h.crash])

	# 2. braking on grades: hard brake from 8 m/s; stopping distance vs mu g cos - g sin, holds still if it can
	for deg in [-35, -25, -15, -5, 0, 10]:
		var name := "brake grade %+d deg" % deg
		if not _want(name): continue
		var th := deg_to_rad(deg)
		var r := _make(cfg, "grade", th)
		var p: BikePhysics = r[0]; var h: Host = r[1]
		h.terrain.x0 = -10.0   # on the grade from the start
		p.reset_at(10.0, 0.0, 0.0); p.v = 8.0; p.vy = 8.0 * sin(th)   # rolling down it, not launched off it
		_ride(p, h, 0.5, nothing)   # settle onto the slope
		var x_b := p.x
		var st := _ride(p, h, 6.0, func(_t, _p): return _inp(0.0, 1.0))
		var mu: float = 0.72 * float(tune.v.grip)
		var can_hold := 9.81 * sin(absf(th)) < minf(float(tune.v.brakeForce), 0.85 * mu * 9.81 * cos(th))
		var stopped := absf(p.v) < 0.05
		var x_s := p.x
		_ride(p, h, 2.0, func(_t, _p): return _inp(0.0, 1.0))
		var creep := absf(p.x - x_s)
		var ok: bool = not st.insane and (stopped == can_hold) and (not can_hold or creep < 0.01)
		_check(name, ok, "stopped=%s (friction can hold: %s) dist=%.1f m creep=%.3f v=%.2f crash=%s" % [stopped, can_hold, (x_s - x_b) / cos(th), creep, p.v, h.crash])

	# 3. pedalling up grades from a standstill: climbs what a rider can, nothing silly on the steep ones
	for deg in [5, 10, 15, 20, 30]:
		var name := "pedal up grade %d deg" % deg
		if not _want(name): continue
		var r := _make(cfg, "grade", deg_to_rad(deg))
		var p: BikePhysics = r[0]; var h: Host = r[1]
		h.terrain.x0 = -10.0
		p.reset_at(5.0, 0.0, 0.0)
		var st := _ride(p, h, 8.0, func(_t, _p): return _inp(1.0))
		var ok: bool = not st.insane and h.crash == "" and st.lift_max < 0.15 and st.air_t < 0.05
		_check(name, ok, "v=%.2f m/s climbed %.1f m lift=%.3f air=%.2fs crash=%s" % [p.v, p.y, st.lift_max, st.air_t, h.crash])

	# 4. side cambers riding straight across: no crash, no take-off; past the friction angle it slides down
	for deg in [5, 15, 25, 35, 45]:
		var name := "camber %d deg" % deg
		if not _want(name): continue
		var r := _make(cfg, "camber", deg_to_rad(deg))
		var p: BikePhysics = r[0]; var h: Host = r[1]
		p.reset_at(0.0, 0.0, 0.0); p.v = 8.0
		var st := _ride(p, h, 5.0, func(_t, _p): return _inp(0.4))
		var drift := p.z
		var ok: bool = not st.insane and st.air_t < 0.05 and st.lift_max < 0.2
		_check(name, ok, "v=%.2f drift=%.2f m heading=%.2f lean=%.2f lift=%.3f crash=%s" % [p.v, drift, p.heading, p.bike_lean, st.lift_max, h.crash])

	# 5. crests: a hump of radius R leaves the ground only once v^2 > g R (rider soaking it a little lets it go higher)
	for R in [6.0, 15.0]:
		for frac in [0.6, 1.5]:
			var vt: float = sqrt(9.81 * R) * frac
			var name := "crest R=%d v=%.1f (%.0f%% of sqrt(gR))" % [R, vt, frac * 100]
			if not _want(name): continue
			var r := _make(cfg, "crest", 1.2, R)
			var p: BikePhysics = r[0]; var h: Host = r[1]
			h.terrain.x0 = 30.0
			p.v = vt
			# hold the speed on the run-in by pedalling to it, then coast over
			var st := _ride(p, h, 40.0 / vt + 2.0, func(t, pp): return _inp(1.0 if (pp.x < 30.0 - sqrt(2 * R * 1.2) - 3 and pp.v < vt) else 0.0))
			var flew: bool = st.air_t > 0.06
			var ok: bool = not st.insane and h.crash == "" and flew == (frac > 1.0)
			_check(name, ok, "air=%.2fs takeoffs=%d crash=%s" % [st.air_t, h.takeoffs, h.crash])

	# 6. rollers / washboard at speed: stays sane, tyres stay near the ground, no crash
	for spec in [["rollers", 0.4, 6.0, 8.0], ["rollers", 0.8, 10.0, 12.0], ["rollers", 0.3, 3.0, 15.0], ["washboard", 0.04, 0.9, 12.0], ["washboard", 0.1, 1.5, 18.0]]:
		var name := "%s amp=%.2f wl=%.1f v=%.0f" % spec
		if not _want(name): continue
		var r := _make(cfg, spec[0], spec[1], spec[2])
		var p: BikePhysics = r[0]; var h: Host = r[1]
		p.v = spec[3]
		var st := _ride(p, h, 6.0, func(_t, _p): return _inp(0.5))
		var ok: bool = not st.insane and h.crash == ""
		_check(name, ok, "v=%.2f air=%.2fs takeoffs=%d maximpact=%.1f crash=%s" % [p.v, st.air_t, h.takeoffs, h.max_impact, h.crash])

	# 7. ledges: drops land, small curbs roll over, a tall step stops the bike without blowing up
	for spec in [[-0.5, 6.0], [-1.5, 8.0], [-3.0, 10.0], [0.12, 5.0], [0.3, 6.0], [1.0, 8.0]]:
		var name := "step %+.2f m at %.0f m/s" % spec
		if not _want(name): continue
		var r := _make(cfg, "step", 0.0, spec[0])
		var p: BikePhysics = r[0]; var h: Host = r[1]
		p.v = spec[1]
		var st := _ride(p, h, 6.0, func(_t, pp): return _inp(0.0 if pp.air else 0.3))   # hands off in the air (W tilts the nose down)
		var ok: bool = not st.insane
		_check(name, ok, "v=%.2f x=%.1f air=%.2fs impact=%.1f crash=%s" % [p.v, p.x, st.air_t, h.max_impact, h.crash])

	# 8. compression at the bottom of a steep chute: sane, the body takes it (a crash is allowed only when brutal)
	for spec in [[20, 8.0], [35, 12.0], [45, 15.0]]:
		var name := "kink %d deg into flat at %.0f m/s" % spec
		if not _want(name): continue
		var r := _make(cfg, "kink", deg_to_rad(spec[0]))
		var p: BikePhysics = r[0]; var h: Host = r[1]
		h.terrain.x0 = 20.0
		p.reset_at(0.0, 0.0, 0.0)
		p.y = h.terrain.height(0, 0); p.body_y = p.y; p.v = spec[1]; p.vy = -spec[1] * sin(deg_to_rad(spec[0]))
		var st := _ride(p, h, 4.0, nothing)
		# a 10 m/s hit into the ground (~ a 5 m drop to flat) must put the rider down, a mild one must not
		var ok: bool = not st.insane and (h.crash != "" if spec[0] >= 45 else (h.crash == "" if spec[0] <= 20 else true))
		_check(name, ok, "v=%.2f air=%.2fs impact=%.1f crash=%s" % [p.v, st.air_t, h.max_impact, h.crash])

	# 9. carving on grades: full lock at speed on 0 / 15 / 30 deg downhill keeps finite, lean stays inside the cap
	for deg in [0, -15, -30]:
		var name := "full-lock turn on %+d deg" % deg
		if not _want(name): continue
		var r := _make(cfg, "grade", deg_to_rad(deg))
		var p: BikePhysics = r[0]; var h: Host = r[1]
		h.terrain.x0 = -10.0
		p.reset_at(5.0, 0.0, 0.0); p.v = 10.0; p.vy = 10.0 * sin(deg_to_rad(deg))
		var st := _ride(p, h, 4.0, func(t, _p): return _inp(0.0, 0.0, 1.0 if t > 0.5 else 0.0))
		var ok: bool = not st.insane and st.lean_max < float(tune.v.bikeLeanCap) + 0.6
		_check(name, ok, "v=%.2f lean_max=%.2f heading=%.2f air=%.2fs crash=%s" % [p.v, st.lean_max, p.heading, st.air_t, h.crash])

	# 10. a long random ride on rough noise ground with random inputs: never non-finite
	if _want("random"):
		var rng := RandomNumberGenerator.new(); rng.seed = 77
		for run in 4:
			var r := _make(cfg, "noise", [0.5, 1.5, 3.0, 6.0][run])
			var p: BikePhysics = r[0]; var h: Host = r[1]
			h.terrain.noise.frequency = [0.08, 0.05, 0.03, 0.02][run]; h.terrain.noise.seed = run
			p.reset_at(0, 0, 0); p.y = h.terrain.height(0, 0); p.body_y = p.y
			var held := [_inp()]
			var crashes := 0
			var insane := false
			for seg in 120:
				var ii := _inp(rng.randf(), 1.0 if rng.randf() < 0.2 else 0.0, rng.randf_range(-1, 1), rng.randf() < 0.3, rng.randf() < 0.3)
				ii.body_fwd = rng.randf_range(-1, 1) if rng.randf() < 0.4 else 0.0
				ii.body_lean = rng.randf_range(-1, 1) if rng.randf() < 0.4 else 0.0
				ii.pad = run % 2 == 1
				held[0] = ii
				var st := _ride(p, h, 0.5, func(_t, _p): return held[0])
				if st.insane: insane = true; break
				if h.crash != "":
					crashes += 1; h.crash = ""
					for k in 300:
						p.step(DT, _inp(0, 0, 0, false, k > 60))
						if not p.crash_on: break
					if p.crash_on: p.get_up()
			_check("random ride amp=%.1f" % h.terrain.a, not insane, "60 s, crashes=%d x=%.0f z=%.0f" % [crashes, p.x, p.z])
