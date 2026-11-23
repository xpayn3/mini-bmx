extends Node
## Ride physics stress test on synthetic ground (no world, no rendering): grades up / down to 45 deg, side
## cambers, crests (take-off speed vs v^2 = g R), rollers, washboard, steps, kinks, plus a long random ride.
## Each case checks the result against plain physics where there is a closed form and prints PASS / FAIL.
##   ..._console.exe --headless --path godot res://tools/slope_stress.tscn [-- bike=dh only=<substr> verbose=1]
## (a scene, not -s: the physics needs the Tune autoload)
## Exit code = number of failed checks.

const DT := 1.0 / 120.0
const DH_EXTRAS := {"wheelbase": 1.2557, "wheelRadius": 0.374, "wheelRadiusRear": 0.355, "bbToRearAxle": 0.4423}

const ROUGH := [[4.1, 0.05, 0.3], [6.7, 0.1, 1.9], [11.3, 0.22, 4.0], [17.9, 0.35, 2.6], [23.3, 0.45, 0.9]]   # wavelength m, height m, phase

class Ground:
	var kind := "flat"
	var a := 0.0   # grade / camber angle (rad) or amplitude
	var b := 0.0   # wavelength / radius / step height
	var x0 := 20.0 # where the feature starts (m along +x)
	var noise: FastNoiseLite
	var surf := 0   # 0 grass (off the trail), 1 trail, 3 sand
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
			"rough":   # a trail-like descent: grade a (rad, < 0 = down) + crests and dips 4-23 m long, b x their trail size
				var s := x - x0
				if s <= 0.0: return 0.0
				var hh := tan(a) * s
				var fade := clampf(s / 15.0, 0.0, 1.0)
				for w in ROUGH: hh += b * w[1] * sin(TAU * s / w[0] + w[2]) * fade * fade * (3.0 - 2.0 * fade)
				return hh
			"dropcamber":   # a ledge of b (b < 0 = a drop) at x0, then ground falling to +z at a (a side-slope landing)
				return (0.0 if x < x0 else b) - (0.0 if x < x0 else tan(a) * z)
		return 0.0
	func deck_height(x: float, z: float) -> float: return height(x, z)
	func top_height(x: float, z: float) -> float: return height(x, z)
	func surface(_x: float, _z: float) -> int: return surf
	func jump_mask(_x: float, _z: float) -> float: return 0.0
	func colliders_near(_x: float, _z: float) -> Array: return []

class Host:
	var terrain := Ground.new()
	var susp = null
	var ragdoll = null
	var getup_anim = null
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
var compare := false   # compare=1: measure this bike's character (COMPARE line) instead of the checks
var feel := false   # feel=1: steering response by speed + right-stick lean slides (FEEL lines) instead of the checks
var extras: Dictionary = DH_EXTRAS
var tune: Node
var step_us := 0.0
var insane_n := 0        # rides that ended in a non-finite state
var step_worst := 0.0   # the slowest single physics step (us)
var trav_max := 0.0     # the most of its travel either end used (1 = all of it)
var squash_max := 0.0   # the most a tyre was squashed (m)
var step_n := 0
func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("only="): only = a.substr(5)
		elif a.begins_with("bike="): bike = a.substr(5)
		elif a == "verbose=1": verbose = true
		elif a == "trace=1": trace = true
		elif a == "compare=1": compare = true
		elif a == "feel=1": feel = true
	tune = get_node("/root/Tune")
	# the bike as the game rides it: its tuning x the garage build's parts x the frame's character
	# (GameState.bike_config_for), on its own geometry (the glb's extras)
	var gs = get_node("/root/GameState")
	var cfg: Dictionary = gs.bike_config_for(bike)
	tune.set_ride(cfg.ride)
	for a in OS.get_cmdline_user_args():   # tune=k=v,k=v overrides tuning values for this run
		if a.begins_with("tune="):
			for kv in a.substr(5).split(","):
				var pr := kv.split("=")
				if pr.size() == 2: tune.v[pr[0]] = float(pr[1])
	if bike != "bmx":
		var sc: Node = load(cfg.file).instantiate()
		var m: Node = sc.find_child(cfg.root, true, false)
		if m and m.has_meta("extras"): extras = (m.get_meta("extras") as Dictionary).duplicate(true)
		sc.free()
	if compare:
		_compare(cfg)
		get_tree().quit(0)
		return
	if feel:
		_feel()
		get_tree().quit(0)
		return
	if "sim=1" in OS.get_cmdline_user_args():
		_sim(cfg)
		get_tree().quit(0)
		return
	if "skip=1" in OS.get_cmdline_user_args():
		_skip(cfg)
		get_tree().quit(0)
		return
	if "slide=1" in OS.get_cmdline_user_args():
		_slide(cfg)
		get_tree().quit(0)
		return
	if "rollpump=1" in OS.get_cmdline_user_args():
		_rollpump(cfg)
		get_tree().quit(0)
		return
	if "sweep=1" in OS.get_cmdline_user_args():
		_sweep(cfg)
		get_tree().quit(0)
		return
	_run_all(cfg)
	print("SLOPE_STRESS %s: %d / %d checks passed, physics step %.1f us avg over %d steps" % [
		"PASS" if fails == 0 else "FAIL", checks - fails, checks, step_us / maxf(1.0, step_n), step_n])
	print("SUSP travel max=%.1f %% tyre squash max=%.1f cm  slowest step=%.0f us  blown-up rides=%d" % [trav_max * 100.0, squash_max * 100.0, step_worst, insane_n])
	get_tree().quit(fails)

func _make(cfg: Dictionary, kind: String, a := 0.0, b := 0.0) -> Array:
	var h := Host.new()
	h.terrain.kind = kind; h.terrain.a = a; h.terrain.b = b
	if kind == "noise":
		h.terrain.noise = FastNoiseLite.new()
	var p := BikePhysics.new(h); h.phys = p
	_last_p = p
	p.T = tune.v
	p.setup(extras if bike != "bmx" else {}, cfg)
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
		var us := Time.get_ticks_usec() - t0
		step_us += us; step_n += 1; step_worst = maxf(step_worst, us)
		# (the suspension never goes past the end of its travel, the tyre never past its rim)
		var trav_now: float = maxf(p.dg_xF, p.dg_xR) / maxf(p.dg_travel, 0.01)
		if trav_now > 1.02 and trav_now > trav_max and OS.get_environment("BMX_TRAV_DBG") != "":
			print("  TRAV %.0f %% xF=%.3f xR=%.3f tr=%.3f t=%.2f air=%s crash_on=%s cf=%s cr=%s y=%.2f g=%.2f vy=%.1f pitch=%.2f zwf=%.2f zwr=%.2f since_land=%.2f" % [trav_now * 100.0, p.dg_xF, p.dg_xR, p.dg_travel, t, p.air, p.crash_on, p.c_f, p.c_r, p.y, h.terrain.height(p.x, p.z), p.vy, p.pitch, p.zw_f, p.zw_r, p.since_land])
		trav_max = maxf(trav_max, trav_now)
		squash_max = maxf(squash_max, maxf(p.dg_sqF, p.dg_sqR))
		st.steps += 1
		if not p.is_sane() or not is_finite(p.body_y + p.air_w + p.bike_lean + p.zw_f + p.zw_r):
			st.insane = true; insane_n += 1; break
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

## compare=1: the same rides on the same ground for this bike, one COMPARE line (run once per bike and set them
## side by side): what each frame's character does in numbers
func _compare(cfg: Dictionary) -> void:
	var nothing := func(_t, _p): return _inp()
	var out := {}
	# terminal speed: coasting 30 s down a 12 deg grade
	var r := _make(cfg, "grade", deg_to_rad(-12)); r[1].terrain.x0 = 2.0
	r[0].v = 6.0
	_ride(r[0], r[1], 30.0, nothing)
	out["coast12"] = r[0].v * 3.6
	# pedalling from a standstill on the flat: time to 25 km/h
	r = _make(cfg, "flat")
	var t25 := -1.0
	for i in int(12.0 / DT):
		r[0].step(DT, _inp(1.0))
		if r[0].v * 3.6 >= 25.0: t25 = i * DT; break
	out["t0_25"] = t25
	# braking from 50 km/h on the flat: stopping distance
	r = _make(cfg, "flat"); r[0].v = 50.0 / 3.6
	_ride(r[0], r[1], 0.3, nothing)
	var xb: float = r[0].x
	_ride(r[0], r[1], 8.0, func(_t, _p): return _inp(0.0, 1.0))
	out["brake50_m"] = r[0].x - xb
	# turn radius on the flat at full lock, 20 and 40 km/h (speed held by pedalling a little)
	for kmh in [20, 40]:
		r = _make(cfg, "flat"); r[0].v = kmh / 3.6
		var p: BikePhysics = r[0]
		var target: float = kmh / 3.6
		_ride(p, r[1], 4.0, func(_t, pp): return _inp(clampf((target - pp.v) * 2.0, 0.0, 1.0), clampf((pp.v - target) * 0.5, 0.0, 1.0), 1.0))
		out["R%d_m" % kmh] = p.v / maxf(absf(p.yaw_rate), 0.001)
	# side-to-side flick at 30 km/h: full lock one way 2 s, then the other: time until the bike lean has crossed over
	r = _make(cfg, "flat"); r[0].v = 30.0 / 3.6
	_ride(r[0], r[1], 2.0, func(_t, pp): return _inp(clampf((30.0 / 3.6 - pp.v) * 2.0, 0.0, 1.0), 0.0, -1.0))
	var l0: float = r[0].bike_lean
	var flip := -1.0
	for i in int(3.0 / DT):
		r[0].step(DT, _inp(clampf((30.0 / 3.6 - r[0].v) * 2.0, 0.0, 1.0), 0.0, 1.0))
		if signf(r[0].bike_lean) != signf(l0) and absf(r[0].bike_lean) > absf(l0) * 0.8: flip = i * DT; break
	out["flick_s"] = flip
	# hop off a 0.5 m roller at 25 km/h with Space held into it: air time
	r = _make(cfg, "crest", 0.5, 4.0); r[1].terrain.x0 = 12.0; r[0].v = 25.0 / 3.6
	var st := _ride(r[0], r[1], 4.0, func(_t, pp): return _inp(0.0, 0.0, 0.0, false, pp.x > 8.0 and pp.x < 12.0))
	out["pop_air_s"] = st.air_t
	# washboard at 40 km/h: how far the rear gets knocked loose (max slip) and the speed lost in 4 s
	r = _make(cfg, "washboard", 0.05, 0.9); r[1].terrain.x0 = 2.0; r[0].v = 40.0 / 3.6
	var smax := 0.0
	for i in int(4.0 / DT):
		r[0].step(DT, _inp())
		smax = maxf(smax, absf(r[0].slip))
	out["wash_slip"] = smax
	out["wash_kmh"] = r[0].v * 3.6
	var line := "COMPARE %-5s kg=%.1f" % [bike, float(cfg.get("kg", 0.0))]
	for k in out: line += "  %s=%.2f" % [k, out[k]]
	print(line)

## feel=1: on the flat, speed held. STEER: full lock from straight: time to 63 % of the steady yaw rate and
## bike lean, steady yaw rate / radius / lean. SWAP: full left 1.5 s then full right: time until the bike lean
## crosses over. LEAN: right stick only / right stick + steer the same way / right stick against the steer:
## steady yaw, peak slip (the rear sliding) and speed lost over 3 s
func _feel() -> void:
	var gs = get_node("/root/GameState")
	var cfg: Dictionary = gs.bike_config_for(bike)
	for kmh in [8, 12, 18, 25, 35, 50]:
		var tv: float = kmh / 3.6
		var hold := func(pp, st: float, bl := 0.0) -> Dictionary:
			var d := _inp(clampf((tv - pp.v) * 2.0, 0.0, 1.0), clampf((pp.v - tv) * 0.5, 0.0, 1.0), st)
			d.body_lean = bl
			return d
		# step to full lock
		var r := _make(cfg, "flat"); var p: BikePhysics = r[0]; p.v = tv
		for i in int(1.0 / DT): p.step(DT, hold.call(p, 0.0))
		var yaws: Array = []; var leans: Array = []
		for i in int(2.5 / DT):
			p.step(DT, hold.call(p, 1.0))
			yaws.append(absf(p.yaw_rate)); leans.append(absf(p.bike_lean))
		var steer_crash: String = r[1].crash
		var y_ss: float = yaws[-1]; var l_ss: float = leans[-1]
		var ty := -1.0; var tl := -1.0
		for i in yaws.size():
			if ty < 0 and yaws[i] >= 0.63 * y_ss: ty = i * DT
			if tl < 0 and leans[i] >= 0.63 * l_ss: tl = i * DT
		# swap
		var tsw := -1.0
		var l0: float = p.bike_lean
		for i in int(2.5 / DT):
			p.step(DT, hold.call(p, -1.0))
			if signf(p.bike_lean) != signf(l0) and absf(p.bike_lean) > absf(l0) * 0.63: tsw = i * DT; break
		print("FEEL STEER %2d km/h  yaw63=%.2fs lean63=%.2fs  yaw=%.2f rad/s R=%.1fm lean=%.0fdeg  swap=%.2fs %s %s" % [kmh, ty, tl, y_ss, p.v / maxf(y_ss, 0.001), rad_to_deg(l_ss), tsw, steer_crash, r[1].crash])
		for gk in ["flat", "noise"]:
			for mode in [["steer", 1.0, 0.0], ["stick", 0.0, 1.0], ["both", 1.0, 1.0], ["half+stick", 0.5, 0.7], ["against", 1.0, -1.0], ["throw", 1.0, 2.0]]:
				r = _make(cfg, gk, 0.15); p = r[0]; p.v = tv
				if gk == "noise": r[1].terrain.noise.frequency = 0.35
				for i in int(1.0 / DT): p.step(DT, hold.call(p, 0.0))
				var smax := 0.0; var wmax := 0.0; var crash := ""; var yaw_sum := 0.0; var n := 0
				for i in int(3.0 / DT):
					# throw = the stick thrown from the centre to the edge with the steer held: a deliberate whip
					# the other cases lean the stick in over 0.35 s (a body lean, not a throw)
					var bl: float = mode[2] * clampf(i * DT / 0.35, 0.0, 1.0) if mode[2] <= 1.0 else clampf(i * DT / 0.08, 0.0, 1.0)
					var d: Dictionary = _inp(0.0, 0.0, mode[1]); d.body_lean = bl
					p.step(DT, d)
					smax = maxf(smax, absf(p.slip)); wmax = maxf(wmax, p.whip)
					if i * DT > 1.0: yaw_sum += absf(p.yaw_rate); n += 1
					if r[1].crash != "": crash = r[1].crash; break
				print("FEEL LEAN  %2d km/h %-5s %-10s yaw=%.2f slip_max=%.0fdeg whip=%.2f v_end=%.1f %s" % [kmh, gk, mode[0], yaw_sum / maxf(1, n), rad_to_deg(smax), wmax, p.v * 3.6, crash])

## sim=1: the ground sim in numbers (SIM lines). Side slopes ridden straight hands off, a berm turn (how far the
## rider sinks, the turn's load), brakes from 40 km/h (front / rear / both: distance, locks), braking hard in a
## turn (front push, wash-out), straight over rough ground (how much the front gets knocked about)
func _sim(cfg: Dictionary) -> void:
	for deg in [5, 10, 20, 30]:
		var r := _make(cfg, "camber", deg_to_rad(deg)); var p: BikePhysics = r[0]
		p.reset_at(0.0, 0.0, 0.0); p.v = 6.0
		_ride(p, r[1], 5.0, func(_t, pp): return _inp(clampf((6.0 - pp.v) * 2.0, 0.0, 1.0)))
		print("SIM CAMBER %2d deg  drift=%.2f m  heading=%+.0fdeg  slip=%+.0fdeg  v=%.1f crash=%s" % [deg, p.z, rad_to_deg(p.heading), rad_to_deg(p.slip), p.v * 3.6, r[1].crash])
	for gk in [["flat", 0.0], ["berm", 0.35]]:
		var r := _make(cfg, "camber", -gk[1]); var p: BikePhysics = r[0]   # ground rising to the right... turn right into it
		p.reset_at(0.0, 0.0, 0.0); p.v = 9.0
		var sink := 0.0; var cg := 0.0; var fu := 0.0
		for i in int(2.5 / DT):
			p.step(DT, _inp(clampf((9.0 - p.v) * 2.0, 0.0, 1.0), 0.0, -0.8))
			if i * DT > 1.0:
				sink = maxf(sink, p.y - p.body_y); cg = maxf(cg, p.corner_g); fu = maxf(fu, p.front_use)
		print("SIM TURN %-5s 32 km/h  yaw=%.2f rad/s  body_sink=%.3f m  extra_g=%.1f  front_use=%.2f  lean=%.0fdeg crash=%s" % [gk[0], absf(p.yaw_rate), sink, cg, fu, rad_to_deg(p.bike_lean), r[1].crash])
	# a berm (20 deg, rising to the right) with a light steer into it (left, 30 %): with / without bermAssist
	for ba in [0.0, 0.8]:
		for kmh in [15, 25]:
			tune.v["bermAssist"] = ba
			var r := _make(cfg, "camber", deg_to_rad(-20)); var p: BikePhysics = r[0]
			p.reset_at(0.0, 0.0, 0.0); p.v = kmh / 3.6
			var tv: float = kmh / 3.6
			for i in int(1.0 / DT): p.step(DT, _inp(clampf((tv - p.v) * 2.0, 0.0, 1.0), clampf((p.v - tv) * 0.5, 0.0, 1.0), 0.3))
			print("SIM BERM assist=%.1f %2d km/h  lean=%+.0fdeg (bank %+.0f)  yaw=%.2f rad/s  tyre_side_grip_used=%.2f  berm_k=%.2f crash=%s" % [
				ba, kmh, rad_to_deg(p.lean), rad_to_deg(p.bank), p.yaw_rate, absf(p._f_prev), p.berm_k, r[1].crash])
	tune.v["bermAssist"] = 0.8
	# landings: off a 1.5 m ledge at 25 km/h onto flat / a 15 deg side slope, and leaned 40 deg (right stick held over)
	for lc in [["flat", 0.0, 0.0], ["slope15", 15.0, 0.0], ["leaned40", 0.0, 0.7]]:
		var r := _make(cfg, "dropcamber", deg_to_rad(lc[1]), -1.5); var p: BikePhysics = r[0]
		r[1].terrain.x0 = 8.0
		p.reset_at(0.0, 0.0, 0.0); p.v = 25.0 / 3.6
		var landed := false; var t_l := 0.0; var smax := 0.0; var c0 := 0.0; var imp := 0.0
		for i in int(4.0 / DT):
			var d := _inp(0.4)
			if p.air: d.body_lean = lc[2]
			if p.x < 8.0: r[1].max_impact = 0.0
			var was_air := p.air
			p.step(DT, d)
			if was_air and not p.air and not landed and p.x > 8.5: landed = true; c0 = p.course; imp = r[1].max_impact
			if landed:
				t_l += DT; smax = maxf(smax, absf(p.slip))
				if t_l > 1.5: break
			if r[1].crash != "": break
		print("SIM LAND %-8s  impact=%.1f  travel_turned=%+.0fdeg  slip_max=%.0fdeg  lean=%+.0fdeg  v=%.1f crash=%s" % [lc[0], imp,
			rad_to_deg(p.course - c0) if landed else 0.0, rad_to_deg(smax), rad_to_deg(p.bike_lean), p.v * 3.6, r[1].crash])
	for b in [["front", 0.0, 1.0, 0.0, 1], ["rear", 0.0, 0.0, 1.0, 1], ["both(S)", 1.0, 0.0, 0.0, 1], ["S grass", 1.0, 0.0, 0.0, 0], ["S wet", 1.0, 0.0, 0.0, 2], ["S sand", 1.0, 0.0, 0.0, 3], ["F grass", 0.0, 1.0, 0.0, 0], ["R grass", 0.0, 0.0, 1.0, 0]]:
		var r := _make(cfg, "flat"); var p: BikePhysics = r[0]; p.v = 40.0 / 3.6
		r[1].terrain.surf = b[4]
		_ride(p, r[1], 0.3, func(_t, _p): return _inp())
		var x0: float = p.x; var lr := 0.0; var lf := 0.0; var pmin := 0.0
		for i in int(6.0 / DT):
			var d := _inp(0.0, b[1]); d.brake_front = b[2]; d.brake_rear = b[3]
			p.step(DT, d)
			lr = maxf(lr, p.rear_lock); lf = maxf(lf, p.front_lock); pmin = minf(pmin, p.pitch)
			if trace and i % 12 == 0: print("    t=%.2f v=%.1f nF=%.2f nR=%.2f fbF=%.2f fbR=%.2f lockF=%.2f lockR=%.2f risk=%.2f fair=%s rair=%s bmuf=%.2f bmur=%.2f inbf=%.2f" % [i * DT, p.v, p.n_f, p.n_r, p._fb_f, p._fb_r, p.front_lock, p.rear_lock, p.risk, p.front_air, p.rear_air, p._bmu_f, p._bmu_r, p.brake_f if "brake_f" in p else -1.0])
			if p.v < 0.2 or r[1].crash != "": break
		print("SIM BRAKE %-7s 40 km/h  stop=%.1f m  (%.2f g)  rear_lock=%.2f front_lock=%.2f nose_down=%.0fdeg crash=%s" % [b[0], p.x - x0, (40.0 / 3.6) * (40.0 / 3.6) / (2.0 * maxf(0.1, p.x - x0) * 9.81), lr, lf, rad_to_deg(-pmin), r[1].crash])
	for b in [["none", 0.0, 0.0], ["S", 1.0, 0.0], ["front", 0.0, 1.0]]:
		var r := _make(cfg, "flat"); var p: BikePhysics = r[0]; p.v = 30.0 / 3.6
		_ride(p, r[1], 1.5, func(_t, pp): return _inp(clampf((30.0 / 3.6 - pp.v) * 2.0, 0.0, 1.0), 0.0, 1.0))
		var fu := 0.0; var push := 0.0
		for i in int(1.5 / DT):
			var d := _inp(0.0, b[1], 1.0); d.brake_front = b[2]
			p.step(DT, d)
			fu = maxf(fu, p.front_use); push = maxf(push, p.front_push)
			if r[1].crash != "": break
		print("SIM TURNBRAKE %-5s 30 km/h full lock  front_use=%.2f push=%.2f v=%.1f crash=%s" % [b[0], fu, push, p.v * 3.6, r[1].crash])
	for kn in [0.0, 0.6]:
		tune.v["groundKnock"] = kn
		var r := _make(cfg, "noise", 0.12); var p: BikePhysics = r[0]
		r[1].terrain.noise.frequency = 1.2
		p.v = 20.0 / 3.6
		var hs := 0.0; var n := 0
		for i in int(4.0 / DT):
			p.step(DT, _inp(clampf((20.0 / 3.6 - p.v) * 2.0, 0.0, 1.0)))
			hs += p.yaw_rate * p.yaw_rate; n += 1
			if r[1].crash != "": break
		print("SIM KNOCK groundKnock=%.1f  yaw_rms=%.3f rad/s  heading_end=%+.0fdeg crash=%s" % [kn, sqrt(hs / maxf(1, n)), rad_to_deg(p.heading), r[1].crash])
	tune.v["groundKnock"] = 0.6

## sweep=1: every ride slider set to its min and its max (one at a time, the rest default) through a battery of short
## standard rides; SWEEP lines = how much each metric moved. A slider that moves nothing here is either dead or only
## matters somewhere the battery doesn't go (the drawing, sound, the demo rider...). Ends with SWEEPQUIET (< 2 %)
func _battery(cfg: Dictionary) -> Dictionary:
	var m := {}
	var hold := func(pp, tv: float, st := 0.0) -> Dictionary: return _inp(clampf((tv - pp.v) * 2.0, 0.0, 1.0), clampf((pp.v - tv) * 0.5, 0.0, 1.0), st)
	var r := _make(cfg, "grade", deg_to_rad(-12)); r[1].terrain.x0 = 2.0; r[0].v = 6.0
	_ride(r[0], r[1], 8.0, func(_t, _p): return _inp()); m.coast = r[0].v
	r = _make(cfg, "flat"); var t25 := 8.0
	for i in int(8.0 / DT):
		r[0].step(DT, _inp(1.0, 0.0, 0.0, i * DT < 3.0))
		if r[0].v * 3.6 >= 25.0: t25 = i * DT; break
	m.accel = t25
	r = _make(cfg, "flat"); r[0].v = 40.0 / 3.6
	var xb: float = r[0].x
	_ride(r[0], r[1], 6.0, func(_t, _p): return _inp(0.0, 1.0)); m.brake = r[0].x - xb
	for kmh in [20, 40]:
		r = _make(cfg, "flat"); r[0].v = kmh / 3.6; var p: BikePhysics = r[0]
		var lmax := 0.0; var cg := 0.0; var ctr := 0.0
		for i in int(3.0 / DT):
			p.step(DT, hold.call(p, kmh / 3.6, 1.0))
			if i * DT > 2.0: lmax = maxf(lmax, absf(p.bike_lean)); cg = maxf(cg, p.corner_g); ctr = maxf(ctr, absf(p.counter))
		m["R%d" % kmh] = p.v / maxf(absf(p.yaw_rate), 0.001); m["lean%d" % kmh] = lmax; m["cg%d" % kmh] = cg; m["counter%d" % kmh] = ctr
	# yaw response + a left / right swap at 25 km/h
	r = _make(cfg, "flat"); r[0].v = 25.0 / 3.6; var p2: BikePhysics = r[0]
	var y63 := 2.0; var ys: Array = []
	for i in int(1.5 / DT):
		p2.step(DT, hold.call(p2, 25.0 / 3.6, 1.0)); ys.append(absf(p2.yaw_rate))
	for i in ys.size():
		if ys[i] >= 0.63 * ys[-1]: y63 = i * DT; break
	m.yaw63 = y63
	var sw := 3.0; var l0: float = p2.bike_lean
	for i in int(3.0 / DT):
		p2.step(DT, hold.call(p2, 25.0 / 3.6, -1.0))
		if signf(p2.bike_lean) != signf(l0) and absf(p2.bike_lean) > absf(l0) * 0.6: sw = i * DT; break
	m.swap = sw
	r = _make(cfg, "crest", 0.5, 4.0); r[1].terrain.x0 = 12.0; r[0].v = 25.0 / 3.6
	var st := _ride(r[0], r[1], 4.0, func(_t, pp): return _inp(0.0, 0.0, 0.0, false, pp.x > 8.0 and pp.x < 12.0)); m.air = st.air_t
	r = _make(cfg, "washboard", 0.05, 0.9); r[1].terrain.x0 = 2.0; r[0].v = 40.0 / 3.6
	var smax := 0.0
	for i in int(4.0 / DT): r[0].step(DT, _inp()); smax = maxf(smax, absf(r[0].slip))
	m.wash_slip = smax; m.wash_v = r[0].v
	r = _make(cfg, "camber", deg_to_rad(10)); r[0].reset_at(0.0, 0.0, 0.0); r[0].v = 6.0
	_ride(r[0], r[1], 4.0, func(_t, pp): return _inp(clampf((6.0 - pp.v) * 2.0, 0.0, 1.0))); m.camber = r[0].z
	r = _make(cfg, "camber", deg_to_rad(-20)); r[0].reset_at(0.0, 0.0, 0.0); r[0].v = 25.0 / 3.6
	for i in int(1.0 / DT): r[0].step(DT, hold.call(r[0], 25.0 / 3.6, 0.3))
	m.berm_lean = r[0].bike_lean; m.berm_yaw = r[0].yaw_rate
	r = _make(cfg, "dropcamber", deg_to_rad(15), -1.5); r[1].terrain.x0 = 8.0; r[0].reset_at(0.0, 0.0, 0.0); r[0].v = 25.0 / 3.6
	var ls := 0.0; var tw := 0.0
	for i in int(3.0 / DT):
		var d := _inp(0.4); if r[0].air: d.body_lean = 0.7
		r[0].step(DT, d); ls = maxf(ls, absf(r[0].slip) if not r[0].air else 0.0); tw = maxf(tw, absf(r[0].air_tw))
	m.land_slip = ls; m.whip = tw
	r = _make(cfg, "flat"); r[0].v = 15.0 / 3.6; var pm := 0.0
	for i in int(3.0 / DT):
		var d2 := hold.call(r[0], 15.0 / 3.6) as Dictionary; d2.body_fwd = -0.9
		r[0].step(DT, d2); if i * DT > 1.0: pm += r[0].pitch * DT
	m.manual = pm
	r = _make(cfg, "noise", 0.15); r[1].terrain.noise.frequency = 0.35; r[0].v = 30.0 / 3.6
	var s2 := 0.0; var n := 0
	for i in int(4.0 / DT):
		r[0].step(DT, hold.call(r[0], 30.0 / 3.6, sin(i * DT * 2.5)))
		s2 += r[0].slip * r[0].slip; n += 1
	m.loose_slip = sqrt(s2 / maxf(1, n)); m.loose_v = r[0].v
	# half-lock turns (the bars' turn limits matter here, not at full lock where the grip decides)
	for kmh in [20, 40]:
		r = _make(cfg, "flat"); r[0].v = kmh / 3.6
		for i in int(2.5 / DT): r[0].step(DT, hold.call(r[0], kmh / 3.6, 0.5))
		m["Rhalf%d" % kmh] = r[0].v / maxf(absf(r[0].yaw_rate), 0.001)
	# crawling-speed full-lock turn (slow bar lock, pivots) and a brake-held pivot
	r = _make(cfg, "flat"); r[0].v = 2.2
	for i in int(2.0 / DT): r[0].step(DT, hold.call(r[0], 2.2, 1.0))
	m.R8 = r[0].v / maxf(absf(r[0].yaw_rate), 0.001)
	r = _make(cfg, "flat"); r[0].v = 1.2; var h0: float = r[0].heading
	for i in int(1.5 / DT): r[0].step(DT, _inp(0.0, 1.0, 1.0))
	m.pivot = absf(wrapf(r[0].heading - h0, -PI, PI))
	# body stick into the turn / against it at 25 km/h, 60 % steer
	for bl in [1.0, -1.0]:
		r = _make(cfg, "noise", 0.08); r[1].terrain.noise.frequency = 0.5; r[0].v = 25.0 / 3.6
		var sl := 0.0
		for i in int(2.5 / DT):
			var d3 := hold.call(r[0], 25.0 / 3.6, 0.6) as Dictionary; d3.body_lean = bl * clampf(i * DT / 0.4, 0.0, 1.0)
			r[0].step(DT, d3); sl = maxf(sl, absf(r[0].slip))
		m["stick%+d_yaw" % int(bl)] = absf(r[0].yaw_rate); m["stick%+d_slip" % int(bl)] = sl
	# hop held down an 8 deg slope for 4 s (pumping) and the body stick pumping forward
	for mode in ["hop", "stick"]:
		r = _make(cfg, "grade", deg_to_rad(-8)); r[1].terrain.x0 = 1.0; r[0].v = 6.0
		for i in int(4.0 / DT):
			var d4 := _inp(0.0, 0.0, 0.0, false, mode == "hop")
			if mode == "stick": d4.body_fwd = 0.9 * (0.5 + 0.5 * sin(i * DT * 6.0))
			r[0].step(DT, d4)
		m["pump_" + mode] = r[0].v
	# a hop off a roller at 25 km/h (charged pop) and a perfectly matched landing off a 1.2 m drop onto a down-slope
	r = _make(cfg, "rollers", 0.6, 7.0); r[1].terrain.x0 = 4.0; r[0].v = 25.0 / 3.6
	var st2 := _ride(r[0], r[1], 4.0, func(t, pp): return _inp(0.3, 0.0, 0.0, false, t < 0.6 or (pp.prep > 0.2)))
	m.hop_air = st2.air_t; m.hop_v = r[0].v
	r = _make(cfg, "kink", deg_to_rad(20)); r[1].terrain.x0 = 10.0; r[0].v = 9.0
	_ride(r[0], r[1], 3.0, func(_t, _p): return _inp()); m.land_v = r[0].v
	# a rock garden (sharp noise) at 30 km/h: knocks, bumps, the crash meters
	r = _make(cfg, "noise", 0.25); r[1].terrain.noise.frequency = 2.5; r[0].v = 30.0 / 3.6
	var ks := 0.0; var rk := 0.0
	for i in int(4.0 / DT):
		r[0].step(DT, hold.call(r[0], 30.0 / 3.6, 0.3 * sin(i * DT * 2.0))); ks += absf(r[0].knock) * DT; rk = maxf(rk, r[0].risk)
		if r[1].crash != "": break
	m.rocks_knock = ks; m.rocks_risk = rk; m.rocks_v = r[0].v
	# a long 6 deg descent coasting 10 s (drag, rolling, flow)
	r = _make(cfg, "grade", deg_to_rad(-6)); r[1].terrain.x0 = 2.0; r[0].v = 8.0
	_ride(r[0], r[1], 10.0, func(_t, _p): return _inp()); m.descent = r[0].v
	return m

func _sweep(cfg: Dictionary) -> void:
	# from the defaults (the Tune autoload starts from the player's saved sliders: resetting each tested slider to
	# its default afterwards drifted every later test away from that baseline - the "10.7 %" on every slider)
	tune.base = tune.defaults.duplicate()
	tune._rebuild()
	var base_v: Dictionary = tune.v.duplicate()
	_battery(cfg)   # warm-up: the very first run after start differs (first-use setup), it was every slider's "10.7 %"
	var base := _battery(cfg)
	var again := _battery(cfg)
	var noise := {}   # how much a metric wobbles between two identical runs: changes inside 3x that don't count
	for mk in base: noise[mk] = absf(float(again[mk]) - float(base[mk])) / maxf(absf(float(base[mk])), 0.05)
	print("SWEEPNOISE ", noise)
	var quiet: Array = []
	for g in tune.DEFS:
		if str(g[0]).begins_with("Dust") or g[0] == "Demo rider": continue
		for row in g[1]:
			var k: String = row[0]
			var worst := 0.0; var worst_m := ""
			for val in [float(row[3]), float(row[4])]:
				tune.v = base_v.duplicate(); tune.base[k] = val; tune._rebuild()
				var mm := _battery(cfg)
				for mk in base:
					var d: float = absf(float(mm[mk]) - float(base[mk])) / maxf(absf(float(base[mk])), 0.05)
					d = maxf(0.0, d - 3.0 * float(noise[mk]))
					if d > worst: worst = d; worst_m = mk
				tune.base[k] = tune.defaults[k]
			tune.v = base_v.duplicate()
			print("SWEEP %-18s %-8s max change %5.1f %% (%s)" % [k, g[0].substr(0, 8), worst * 100.0, worst_m])
			if worst < 0.02: quiet.append(k)
	tune._rebuild()
	print("SWEEPQUIET ", ", ".join(quiet))

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
		var mu: float = BikePhysics.BRAKE_MU[0] * float(tune.v.get("brakeGrip", 1.0))   # (the braking grip on grass, the test ground)
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

	# 12. suspension torture: the hardest things a spring / damper / tyre can be asked to take. Whatever the setup or
	# the sliders, the state stays finite, no end goes past its travel and no tyre past its rim
	for spec in [["step", 0.0, -5.0, 12.0, "drop 5 m at 12 m/s"], ["step", 0.0, -9.0, 16.0, "drop 9 m at 16 m/s"], ["step", 0.0, 0.25, 16.0, "25 cm square edge at 16 m/s"],
			["washboard", 0.15, 0.6, 20.0, "washboard 15 cm / 0.6 m at 20 m/s"], ["rollers", 1.2, 5.0, 16.0, "rollers 1.2 m / 5 m at 16 m/s"]]:
		var name := "susp: %s" % spec[4]
		if not _want(name): continue
		var t0m := trav_max
		var r := _make(cfg, spec[0], spec[1], spec[2])
		var p: BikePhysics = r[0]; var h: Host = r[1]
		p.v = spec[3]
		var crashes := 0
		var insane := false
		for seg in 8:   # 8 s; after a crash it gets up and rides on (the hit is what is being tested)
			var st := _ride(p, h, 1.0, func(_t, pp): return _inp(0.0 if pp.air else 0.6, 0.0 if pp.air or int(_t * 2.0) % 2 == 0 else 1.0))
			if st.insane: insane = true; break
			if h.crash != "":
				crashes += 1; h.crash = ""
				p.begin_crash()
				for k in 300:
					p.step(DT, _inp(0, 0, 0, false, k > 60))
					if not p.crash_on: break
				if p.crash_on: p.get_up()
		_check(name, not insane and trav_max <= 1.005, "travel max=%.1f %% (this test %.1f %%) tyre squash max=%.1f cm crashes=%d" % [trav_max * 100.0, maxf(trav_max, t0m) * 100.0, squash_max * 100.0, crashes])


## rollpump=1: 8 sine rollers of each height / wavelength at each speed, ridden hands off, the pump held the whole
## way, the pump only down the backsides (hop / the body stick forward): `ROLLPUMP h= L= kmh= mode= dE=` = the energy
## won per roller (J/kg, + the rolling / air drag the hands-off run lost on the same ground), air time, crash
## skip=1: hands off down a trail-like rough descent (crests and dips 4-23 m long) at fixed speeds: how often the bike
## leaves the ground by itself, sorted by the ground's curve under it at take-off (crest = it must fly, v^2 x curve < -g;
## dip = thrown off while the ground pressed up), the time on one wheel, the longest ride on the front alone.
## Repeatable (the trail runs aren't): the way to judge a change to how the bike follows the ground. SKIP lines + a total
func _skip(cfg: Dictionary) -> void:
	var tot := {"n": 0, "dip": 0, "crest": 0, "air": 0.0, "front": 0.0, "m": 0.0}
	for sz in ([0.4] if trace else [0.25, 0.4]):
		for kmh in ([45.0] if trace else [35.0, 45.0, 55.0, 65.0]):
			var r := _make(cfg, "rough", deg_to_rad(-8.0), sz); var p: BikePhysics = r[0]; var g: Ground = r[1].terrain
			g.x0 = 5.0; p.v = kmh / 3.6
			var n := 0; var dip := 0; var crest := 0; var other := 0; var air := 0.0; var front := 0.0; var front_run := 0.0; var front_max := 0.0
			var was := false; var kap0 := 0.0; var crash := ""; var ring: Array[String] = []; var pre: Array[String] = []; var dumped := 0
			for i in int(30.0 / DT):
				# (held at the speed: pedalled below it, a light brake well above it, on the ground only)
				var d := _inp(1.0 if p.v < kmh / 3.6 else 0.0, 0.25 if (p.v > kmh / 3.6 + 1.0 and not p.air) else 0.0, 0.0, false, false)
				p.step(DT, d)
				if trace:
					ring.append("  ST x=%.2f y=%.3f vy=%+.2f gy=%.3f pitch=%+.3f pv=%+.2f cf=%s cr=%s xF=%.3f xR=%.3f tyF=%.1f tyR=%.1f leg=%+.3f legf=%+.1f bv=%+.2f relt=%+.3f" % [p.x - g.x0, p.y, p.vy, g.height(p.x, 0.0), p.pitch, p.pitch_v, p.c_f, p.c_r, p.dg_xF, p.dg_xR, p.dg_tyF, p.dg_tyR, p.dg_leg, p.dg_leg_f, p.body_v, p.dg_abs])
					if ring.size() > 40: ring.pop_front()
				if p.x < g.x0 + 10.0: continue
				if p.air and not was:
					kap0 = (g.height(p.x + 0.6, 0.0) + g.height(p.x - 0.6, 0.0) - 2.0 * g.height(p.x, 0.0)) / 0.36
					pre = ring.duplicate()
				if was and not p.air and p.air_time >= 0.05:
					n += 1; air += p.air_time
					var ng := p.v * p.v * kap0 / BikePhysics.G
					if ng > 0.0: dip += 1
					elif ng < -1.0: crest += 1
					else: other += 1
					if trace and dumped < 2 and ng > -1.0 and ng < 0.0:
						dumped += 1; print("  SKIPEV x=%.1f air=%.2f g=%.2f" % [p.x - g.x0, p.air_time, ng])
						for ln in pre: print(ln)
				was = p.air
				if not p.air and p.rear_air and not p.front_air: front += DT; front_run += DT; front_max = maxf(front_max, front_run)
				else: front_run = 0.0
				if r[1].crash != "": crash = r[1].crash; break
				if p.x > g.x0 + 400.0: break
			var m := p.x - g.x0 - 10.0
			print("SKIP size=%.1f kmh=%.0f flights=%d (dip %d, crest %d, other %d) per100m=%.1f air=%.1fs front-only=%.1fs longest=%.2fs %s" % [sz, kmh, n, dip, crest, other, 100.0 * n / maxf(1.0, m), air, front, front_max, crash])
			tot.n += n; tot.dip += dip; tot.crest += crest; tot.air += air; tot.front += front; tot.m += m
	print("SKIP TOTAL flights=%d (dip %d, crest %d) per100m=%.2f air=%.1fs front-only=%.1fs over %.0f m" % [tot.n, tot.dip, tot.crest, 100.0 * tot.n / maxf(1.0, tot.m), tot.air, tot.front, tot.m])

func _rollpump(cfg: Dictionary) -> void:
	for hl in [[0.3, 4.0], [0.3, 6.0], [0.5, 6.0], [0.5, 8.0], [0.48, 10.0], [0.8, 5.0]]:
		for kmh in [15.0, 25.0, 35.0, 45.0]:
			var base := 0.0
			for mode in ["off", "hold", "hop_back", "stick_back", "stick_pump"]:
				if only != "" and not ("h%.2fL%.0fk%.0f%s" % [hl[0], hl[1], kmh, mode]).contains(only): continue
				var r := _make(cfg, "rollers", hl[0], hl[1]); var p: BikePhysics = r[0]; var g: Ground = r[1].terrain
				g.x0 = 6.0; p.v = kmh / 3.6
				var x_end: float = g.x0 + 8.0 * hl[1]
				var e0 := -1.0; var e1 := -1.0; var air := 0.0; var crash := ""; var pops := 0; var was_air := false
				for i in int(12.0 / DT):
					var sl: float = (g.height(p.x + 0.05, 0.0) - g.height(p.x - 0.05, 0.0)) / 0.1
					var back := sl < -0.02 and p.x > g.x0
					# hop_back = the button pump done right: pressed going over the top (the legs bend as the ground goes light),
					# let go at the bottom of the dip (they push as it presses hardest). stick_pump = the same with the stick
					# (back down the backside, forward up the face); stick_back = the stick the wrong way round
					var d := _inp(0.0, 0.0, 0.0, false, mode == "hold" or (mode == "hop_back" and back))
					if mode == "stick_back" and back: d.body_fwd = 0.9
					if mode == "stick_pump" and p.x > g.x0: d.body_fwd = -0.45 if back else 0.9
					p.step(DT, d)
					if trace and p.x > g.x0 and p.x < g.x0 + 2.0 * hl[1] and i % 3 == 0:
						print("  RPT x=%.2f sl=%+.2f hop=%s push=%+.2f pleg=%+.2f hop_t=%.2f crouch=%.2f prep=%.2f air=%s fa=%s ra=%s v=%.2f man=%.2f pressT=%.2f" % [p.x - g.x0, sl, d.hop, p.pump_push, p.pleg, p.hop_t, p.crouch, p.prep, p.air, p.front_air, p.rear_air, p.v, p.man_a, p.pump_press_t])
					if e0 < 0.0 and p.x >= g.x0: e0 = 0.5 * p.v * p.v + BikePhysics.G * p.y
					if p.x > g.x0 and p.x < x_end:
						if p.air: air += DT
						if p.air and not was_air: pops += 1
					was_air = p.air
					if r[1].crash != "": crash = r[1].crash; break
					if p.x >= x_end: e1 = 0.5 * p.v * p.v + BikePhysics.G * p.y; break
				if only != "":
					p._eb_t = 5.0; p._e_tick(0.0, false)
				var de := (e1 - e0) / 8.0 if e1 > -1.0 and e0 > -1.0 else NAN
				if mode == "off": base = de
				print("ROLLPUMP h=%.2f L=%.0f kmh=%.0f %-10s dE/roller=%+6.2f vs off=%+6.2f air=%.2fs flights=%d %s" % [hl[0], hl[1], kmh, mode, de, de - base, air, pops, crash])

## slide=1: free riding like a player off the trail (grass, bumpy) and on it: weaving at full / half lock, holding
## full lock, pedalling hard through a turn. How much of the time the rear is out (slip past the tyres' own slip
## angle) with nothing asking for it (no rear brake, no whip): SLIDE lines
func _slide(cfg: Dictionary) -> void:
	var tot := {}
	var sfs := [[0, "grass"], [1, "trail"], [3, "sand"]]
	if trace: sfs = [[0, "grass"]]
	for sf in sfs:
		for gk in (["noise"] if trace else ["flat", "noise"]):
			var t8 := 0.0; var t15 := 0.0; var tt := 0.0; var smax := 0.0; var crashes := 0
			for kmh in ([40.0] if trace else [12.0, 20.0, 30.0, 40.0]):
				for mode in (["hold"] if trace else ["weave", "weave_half", "hold", "sprint_turn", "keys"]):
					var r := _make(cfg, gk, 0.15); var p: BikePhysics = r[0]; var g: Ground = r[1].terrain
					g.surf = sf[0]
					if gk == "noise": g.noise.frequency = 0.25
					var tv: float = kmh / 3.6
					p.v = tv
					var ms := 0.0
					for i in int(8.0 / DT):
						var t := i * DT
						var st := 0.0
						match mode:
							"weave": st = sin(t * TAU / 2.4)
							"weave_half": st = 0.5 * sin(t * TAU / 2.0)
							"hold": st = 1.0 if t > 1.0 else 0.0
							"sprint_turn": st = 0.6 if t > 1.0 else 0.0
							"keys": st = 1.0 if fmod(t, 2.0) < 1.0 else -1.0   # keyboard: full left / full right
						var th := clampf((tv - p.v) * 2.0, 0.0, 1.0)
						var d := _inp(th, clampf((p.v - tv - 1.5) * 0.4, 0.0, 1.0), st, mode == "sprint_turn")
						if mode == "sprint_turn": d.throttle = 1.0
						p.step(DT, d)
						if trace and mode == "hold" and i % 12 == 0 and t < 8.0: print("    t=%.2f v=%.1f slip=%+.1f sw=%+.2f squirm=%.1f gr=%.2f steer=%+.2f lat=%+.1f yaw=%+.2f fuse=%.2f fpush=%.2f lean=%+.2f loose=%.2f nR=%.1f" % [t, p.v, rad_to_deg(p.slip), p.slip_w, rad_to_deg(p._squirm), p.grip_r, p.steer, p.lat_a, p.yaw_rate, p.front_use, p.front_push, p.bike_lean, p.loose, p.n_r])
						if r[1].crash != "": crashes += 1; break
						if t < 1.0 or p.air: continue
						var sl := absf(p.slip - p._squirm)
						tt += DT
						if sl > deg_to_rad(8.0): t8 += DT
						if sl > deg_to_rad(15.0): t15 += DT
						ms = maxf(ms, sl)
					smax = maxf(smax, ms)
					if verbose: print("  SLIDE %s %s %2.0f km/h %-11s max=%.0fdeg %s v_end=%.0f" % [sf[1], gk, kmh, mode, rad_to_deg(ms), r[1].crash, p.v * 3.6])
			print("SLIDE %-5s %-5s  out>8deg %4.1f %%  out>15deg %4.1f %%  max %2.0f deg  crashes %d" % [sf[1], gk, 100.0 * t8 / maxf(tt, 0.01), 100.0 * t15 / maxf(tt, 0.01), rad_to_deg(smax), crashes])
