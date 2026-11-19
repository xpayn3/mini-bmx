class_name BikePhysics
extends RefCounted
## The ride: a faithful port of physics() / crashPhysics() from src/main.js.
## Runs at a fixed 1/120 s step (called from Game._physics_process). Everything is in metres / seconds,
## Y up; the bike travels along fwd = (cos heading, 0, -sin heading).
##
## The host (Game) supplies the world and the side effects:
##   host.terrain  : height(), surface(), jump(), colliders_near()
##   host.flash(text), host.burst(pos, n, surf, power), host.flow_up(), host.msg_idle() -> bool,
##   host.smash(c, vel, pos) -> bool (fence / cactus / tape), host.rock_chips(c), host.start_crash(reason),
##   host.dust(...) via emit_fx(), host.susp (Suspension or null), host.pedal_a0 [left, right]

const G := 9.81
const CLIMB := 1.2
const HOP_PUSH := 0.09
const FLOW_MAX := 5.0
const GETUP_HOLD := 0.25   # seconds holding hop to get up after a crash

var host
var T: Dictionary          # Tune.v (effective values)
var L := 0.8985
var RWF := 0.261
var RWR := 0.261
var BB_REAR := 0.3331
var SH_R := 0.63
var LAND := 1.0
var geared := false
var gear := -1
var cogs: Array = [11, 12, 14, 16, 18, 21, 24]
var ring_k := 1.0   # chainring vs. the stock 34T
var bike_rock := 1.0

# ---- state (st in the JS) ----
var x := 0.0; var z := 0.0; var y := 0.0; var vy := 0.0
var heading := 0.0; var v := 0.0; var steer := 0.0; var steer_in := 0.0
var lean := 0.0; var lean_v := 0.0; var bike_lean := 0.0; var counter := 0.0; var rock := 0.0
var pitch := 0.0; var pitch_v := 0.0; var hop_nose := 0.0
var air := false; var air_time := 0.0; var air_k := 0.0
var compress := 0.0; var compress_v := 0.0; var load := 0.0
var body_y := NAN; var body_v := 0.0; var body_x := 0.0; var hip_shift := 0.0
# the rider's body as its own mass fore / aft: it lags the bike (braking and landings throw it forward,
# drive pushes it back), and in the air the rider leans (W / S) and pulls the bike up (Space)
var body_xv := 0.0; var hip_v := 0.0; var v_last := NAN
var air_lean := 0.0; var air_pull := 0.0; var air_lock_w := false; var air_lock_s := false; var air_lock_h := false
# air tricks: the rider's input this step, and how far the bike has turned since take-off (rad)
var air_lock_a := false; var flip_in := 0.0; var spin_in := 0.0; var flip_acc := 0.0; var spin_acc := 0.0
# rotation as real momentum. On the ground the rider's body turns with the bike, smoothed by the arms and
# legs (body_pw), and W / S pressed at a lip throw the body back / forward against the ground (throw_v).
# In the air nothing outside can turn rider + bike: their shared spin (air_w, rad/s at full stretch) is
# conserved; tucking (Space) lowers the inertia so it spins faster. The rider can only tilt the bike
# against their own body (air_tilt, limited) and twist it at the hips (air_tw).
var body_pw := 0.0; var throw_v := 0.0; var lock_tw := false; var lock_ts := false
var air_w := 0.0; var air_inertia := 1.0; var air_tilt := 0.0; var air_tilt_v := 0.0
var air_yaw := 0.0; var air_tw := 0.0; var air_tw_v := 0.0; var land_jolt := 0.0
# pivot: how far a slow-speed pivot (pirouette) has turned the bike
var pivot := 0.0; var pivot_acc := 0.0
var wheel_f := 0.0; var wheel_r := 0.0; var crank := 0.0; var pedal := 0.0
var yaw_rate := 0.0; var shake := 0.0
var course := NAN; var slip := 0.0; var since_land := 1.0
var front_air := false; var rear_air := false; var c_f := true; var c_r := true
var pitch_w := NAN; var stamina := 1.0; var tired := false; var sprint := 0.0
var spin := 0.0; var a_drive := 0.0
var n_f := NAN; var n_r := NAN; var n_ref := NAN
var flow := 0.0; var flow_t := 0.0
var spun_out := false
var bank := NAN; var carve := 0.0; var carve_acc := 0.0; var carve_berm := false
var lat_m := NAN; var lat_a := 0.0
var g_pitch := NAN
var w_init := false; var hf_prev := NAN; var hr_prev := NAN
var nose_ref := NAN
var w_f := 0.0; var w_r := 0.0; var y_draw := 0.0; var pitch_draw := 0.0
var kick_t := 0.0; var hop_t := 0.0; var hop_load := 0.0; var hop_charge := 0.0; var charge := 0.0
var lift_t := 0.0; var hop_block := false; var hop_held := false
var prep := 0.0; var land_prep := 0.0; var pop_fired := false
var lip_scan := 0; var lip_state := 0; var lip_last := 0.0   # lip_state: 0 unknown, 1 none in sight, 2 lip_last valid
var y_prev := NAN; var pump_acc := 0.0; var brake_heat := 0.0
var dust_acc := 0.0; var chunk_acc := 0.0
var joint_rock = null
var distance := 0.0
# what the HUD reads
var skid_fx := false; var surf := 0; var hop_bar := 0.0; var hop_bar_show := false

# ---- crash ----
var crash_on := false; var crash_t := 0.0; var crash_pending := ""; var crash_side := 1.0
var crash_rest := 0.0; var crash_bvy := 0.0; var crash_fall_v := 0.0; var crash_armed := false; var crash_hold := 0.0

func _init(h) -> void:
	host = h

func setup(extras: Dictionary, bike_cfg: Dictionary) -> void:
	L = float(extras.get("wheelbase", 0.8985))
	RWF = float(extras.get("wheelRadius", 0.261))
	RWR = float(extras.get("wheelRadiusRear", RWF))
	BB_REAR = float(extras.get("bbToRearAxle", 0.3331))
	SH_R = (L - BB_REAR) / L
	LAND = float(bike_cfg.get("land", 1.0))
	geared = bool(bike_cfg.get("geared", false))
	var mods: Dictionary = bike_cfg.get("mods", {})
	if mods.has("cogs"):
		cogs = mods.cogs; ring_k = mods.ring_k
		LAND *= float(mods.get("land", 1.0))
	else:
		# no garage build (the BMX): one neutral 16T cog, ratio 1 like the web version -- not the DH cassette
		cogs = [16]; ring_k = 1.0
	if cogs.size() <= 1: geared = false
	# start in the cog nearest the old 16T reference
	gear = -1
	if geared:
		var best := 1e9
		for i in cogs.size():
			if absf(cogs[i] * 1.0 / ring_k - 16.0) < best: best = absf(cogs[i] * 1.0 / ring_k - 16.0); gear = i

func gear_k() -> float:
	if gear < 0: return ring_k * 16.0 / float(cogs[0]) if cogs.size() > 0 else 1.0
	return ring_k * 16.0 / float(cogs[gear])

func shift(d: int) -> bool:
	if gear < 0:
		return false
	var g := clampi(gear + d, 0, cogs.size() - 1)
	if g == gear:
		return false
	gear = g
	return true

static func smooth01(t: float) -> float:
	t = clampf(t, 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)

static func ang_diff(a: float, b: float) -> float:
	return atan2(sin(a - b), cos(a - b))

static func _or(a: float, d: float) -> float:
	return d if is_nan(a) else a

func fwd() -> Vector3:
	return Vector3(cos(heading), 0.0, -sin(heading))

# =====================================================================
func reset_at(px: float, pz: float, hd: float) -> void:
	crash_on = false; crash_pending = ""; crash_hold = 0.0; crash_armed = false
	x = px; z = pz; heading = hd
	v = 0; vy = 0; steer = 0; steer_in = 0; lean = 0; lean_v = 0; pitch = 0; air = false
	bike_lean = 0; counter = 0; rock = 0; yaw_rate = 0; hop_nose = 0; hop_t = 0; air_time = 0; air_k = 0
	load = 0; compress = 0; compress_v = 0; prep = 0; land_prep = 0; pop_fired = false; spun_out = false; shake = 0
	course = hd; slip = 0; w_init = false; front_air = false; rear_air = false; pump_acc = 0; since_land = 1
	pitch_v = 0; c_f = true; c_r = true
	g_pitch = NAN
	y = host.terrain.height(x, z); body_y = y; body_v = 0
	n_f = NAN; n_r = NAN; n_ref = NAN; lip_state = 0; hf_prev = NAN; hr_prev = NAN
	bank = 0; body_x = 0; hip_shift = 0; spin = 0; a_drive = 0; charge = 0; hop_charge = 0; lift_t = 0
	body_xv = 0; hip_v = 0; v_last = NAN; air_lean = 0; air_pull = 0; flip_acc = 0; spin_acc = 0; flip_in = 0; spin_in = 0
	body_pw = 0; throw_v = 0; air_w = 0; air_inertia = 1; air_tilt = 0; air_tilt_v = 0; air_yaw = 0; air_tw = 0; air_tw_v = 0; land_jolt = 0
	pivot = 0; pivot_acc = 0
	sprint = 0; flow = 0; flow_t = 0; lat_m = 0; carve = 0; carve_acc = 0; carve_berm = false
	y_draw = y; pitch_draw = 0; nose_ref = NAN; pitch_w = NAN; y_prev = NAN; kick_t = 0
	w_f = y; w_r = y

func get_up() -> void:
	crash_on = false; crash_hold = 0; crash_armed = false
	v = 0; vy = 0; lean = 0; lean_v = 0; bike_lean = 0; counter = 0; steer = 0; steer_in = 0; yaw_rate = 0; air = false
	pitch = 0; compress = 0; compress_v = 0; hop_nose = 0; hop_t = 0; load = 0
	slip = 0; w_init = false; front_air = false; rear_air = false; pump_acc = 0; pitch_v = 0; c_f = true; c_r = true
	course = heading
	hop_block = true
	y = host.terrain.height(x, z); body_y = y; body_v = 0
	n_f = NAN; n_r = NAN; n_ref = NAN; lip_state = 0; hf_prev = NAN; hr_prev = NAN
	bank = 0; body_x = 0; hip_shift = 0; spin = 0; a_drive = 0; charge = 0; hop_charge = 0; lift_t = 0
	body_xv = 0; hip_v = 0; v_last = NAN; air_lean = 0; air_pull = 0; flip_acc = 0; spin_acc = 0; flip_in = 0; spin_in = 0
	body_pw = 0; throw_v = 0; air_w = 0; air_inertia = 1; air_tilt = 0; air_tilt_v = 0; air_yaw = 0; air_tw = 0; air_tw_v = 0; land_jolt = 0
	pivot = 0; pivot_acc = 0
	sprint = 0; flow = 0; flow_t = 0; lat_m = 0; carve = 0; carve_acc = 0; carve_berm = false; y_draw = y; pitch_draw = 0

func begin_crash() -> void:
	crash_pending = ""
	flow = 0
	crash_on = true; crash_t = 0; crash_rest = 0; crash_armed = false; crash_hold = 0
	crash_side = signf(bike_lean) if absf(bike_lean) > 0.05 else (-1.0 if randf() < 0.5 else 1.0)
	crash_fall_v = crash_side * 1.5
	crash_bvy = vy if air else minf(vy, 0.5)
	air = false; pedal = 0; load = 0; shake = 0.45

# =====================================================================
## inp: {throttle 0..1, brake 0..1, steer -1..1 (+ = left), hop bool, sprint bool, hop_pressed bool}
func step(dt: float, inp: Dictionary) -> void:
	if crash_pending != "":
		host.start_crash(crash_pending)
	if crash_on:
		_crash_step(dt, inp)
		return
	_ride_step(dt, inp)

# ---------------------------------------------------------------------
func _crash_step(dt: float, inp: Dictionary) -> void:
	var terrain = host.terrain
	var rag = host.ragdoll
	crash_t += dt
	var f := fwd()
	v *= exp(-dt * 2.2)
	if absf(v) < 0.05: v = 0
	yaw_rate *= exp(-dt * 3); heading += yaw_rate * dt
	x += f.x * v * dt; z += f.z * v * dt
	for c in terrain.colliders_near(x, z):
		if c.has("top") and c.top < y + 0.45: continue
		if c.get("tape", false): continue
		if c.get("fence", false) and absf(v) > 2 and Vector2(x - c.x, z - c.z).length() < c.r + 0.35:
			host.smash(c, Vector3(f.x * v, 0, f.z * v), Vector3(x, y, z)); continue
		var dx: float = x - c.x
		var dz: float = z - c.z
		var d := sqrt(dx * dx + dz * dz)
		var mn: float = (c.r if c.has("top") else c.r - 0.1) + 0.25
		if d < mn and d > 1e-4:
			x = c.x + dx / d * mn; z = c.z + dz / d * mn; v *= -0.2
	var lim := 1.48
	crash_fall_v += sin(bike_lean if bike_lean != 0.0 else crash_side * 0.05) * 14.0 * dt
	bike_lean += crash_fall_v * dt
	if absf(bike_lean) > lim:
		bike_lean = signf(bike_lean) * lim; crash_fall_v *= -0.25
	counter = 0; rock = 0; pedal = 0
	steer += (crash_side * 0.5 - steer) * minf(1.0, dt * 4)
	var ground: float = terrain.height(x, z) + 0.24 * absf(sin(bike_lean))
	crash_bvy -= G * dt; y += crash_bvy * dt
	if y < ground:
		y = ground; crash_bvy = -crash_bvy * 0.25 if crash_bvy < -2 else 0.0
	var hr: float = terrain.height(x - f.x * BB_REAR, z - f.z * BB_REAR)
	var hf: float = terrain.height(x + f.x * (L - BB_REAR), z + f.z * (L - BB_REAR))
	pitch += (atan2(hf - hr, L) - pitch) * minf(1.0, dt * 6)
	hop_nose *= exp(-dt * 4)
	wheel_f += v / RWF * dt; wheel_r += v / RWR * dt
	body_y = y; body_v = 0; y_draw = y; pitch_draw = pitch
	if rag:
		var P: Vector3 = rag.p[Ragdoll.PELVIS]
		for c in terrain.colliders_near(P.x, P.z):
			if c.get("tape", false): continue
			if not c.get("fence", false) or rag.speed < 2.5 or Vector2(P.x - c.x, P.z - c.z).length() > c.r + 0.3 or P.y > terrain.height(P.x, P.z) + 1.4: continue
			var Q: Vector3 = rag.q[Ragdoll.PELVIS]
			host.smash(c, (P - Q) / dt * 3.0 * Vector3(1, 0, 1), P - Vector3(0, 0.4, 0))
		rag.step(dt, terrain.colliders_near(P.x, P.z))
		crash_rest = crash_rest + dt if rag.speed < 0.6 else 0.0
	var holding: bool = crash_armed and inp.hop
	if holding: crash_hold += dt
	else:
		crash_armed = false; crash_hold = maxf(0.0, crash_hold - dt * 3)
	if crash_hold >= GETUP_HOLD:
		host.get_up()

# ---------------------------------------------------------------------
var _g_y := 0.0; var _g_pitch := 0.0; var _g_hr := 0.0; var _g_hf := 0.0
func _sample(f: Vector3) -> void:
	var terrain = host.terrain
	var hr: float = terrain.height(x - f.x * BB_REAR, z - f.z * BB_REAR)
	var hf: float = terrain.height(x + f.x * (L - BB_REAR), z + f.z * (L - BB_REAR))
	_g_hr = hr; _g_hf = hf
	_g_y = hr + (hf - hr) * (BB_REAR / L); _g_pitch = atan2(hf - hr, L)

func _wheel_ground(f: Vector3, x0: float, R: float, cp0: float) -> float:
	var terrain = host.terrain
	var best := -INF
	for k in range(-3, 4):
		var s := k / 3.0 * R
		var d := x0 * cp0 + s
		var hh: float = terrain.height(x + f.x * d, z + f.z * d) + sqrt(R * R - s * s) - R
		if hh > best: best = hh
	return best

func _ride_step(dt: float, inp: Dictionary) -> void:
	var terrain = host.terrain
	var throttle: float = inp.throttle
	var brake_k: float = inp.brake
	var brake := brake_k > 0.1
	var steer_input: float = inp.steer
	# air control: W / S tilt the bike nose down / up against the rider's body (limited, see air_tilt; a
	# flip has to be thrown at the lip), A / D lean it left / right, Space tucks (pulls the bike up into the
	# body, spinning faster). W / S work at once; A / D and Space held at take-off count only once pressed
	# again in the air (carving into a jump mustn't lean you).
	if not air:
		air_lock_w = throttle > 0.1; air_lock_s = brake; air_lock_h = inp.hop; air_lock_a = absf(steer_input) > 0.1
	else:
		if throttle <= 0.1: air_lock_w = false
		if not brake: air_lock_s = false
		if not inp.hop: air_lock_h = false
		if absf(steer_input) <= 0.1: air_lock_a = false
	var lean_in := 0.0
	if air:   # W / S act straight away, even if held from the ground (the user wants no re-press)
		lean_in = throttle - brake_k
	flip_in = -lean_in                                          # + = nose up
	spin_in = 0.0 if (not air or air_lock_a) else steer_input   # + = the steering direction
	air_lean += (lean_in - air_lean) * minf(1.0, dt * 6)
	# the rider tucks into a flip as well as when Space is held
	var pull_t := maxf(1.0 if air and inp.hop and not air_lock_h else 0.0, 0.7 * absf(flip_in) if air else 0.0)
	air_pull += (pull_t - air_pull) * minf(1.0, dt * 8)
	# the lip throw: W / S pressed fresh as the bike leaves a lip (a jump spotted just ahead, or one wheel
	# already off) throw the rider back / forward, pushing against the bike and through it the ground. That
	# is the only way to start a flip (keys held from before don't count; S there pulls back, it doesn't brake)
	var lip_win := not air and (prep > 0.25 or front_air or rear_air)
	if not lip_win:
		lock_tw = throttle > 0.1; lock_ts = brake
	else:
		if throttle <= 0.1: lock_tw = false
		if not brake: lock_ts = false
	var throw_in := 0.0
	if lip_win:
		throw_in = (0.0 if lock_ts else brake_k) - (0.0 if lock_tw else throttle)   # + = back (nose up)
		if not lock_ts:
			brake_k = 0.0; brake = false
	if not air:
		if absf(throw_in) > 0.05:
			var room := 1.0 - clampf(throw_v * signf(throw_in) / T.flipRate, 0.0, 1.0)
			throw_v += throw_in * T.flipAccel * room * dt
		else:
			throw_v *= exp(-dt * 6)   # a throw can't be held on the ground: the body settles back
	var f := fwd()
	_sample(f)
	surf = terrain.surface(x, z)
	var in_water := surf == 2
	if is_nan(course):
		course = heading; slip = 0
	since_land += dt
	var slope: float = _or(pitch_w, _g_pitch) if (not air and (front_air or rear_air)) else _g_pitch
	var rear_down := not air and not rear_air
	var skid := brake and v > 0.5 and rear_down
	# --- sprint / stamina ---
	var want_sprint: bool = inp.sprint and throttle > 0.1 and not brake and not air
	if stamina <= 0: tired = true
	elif stamina > 0.25: tired = false
	var sprinting := want_sprint and not tired and not in_water
	if sprinting and not air: stamina = maxf(0.0, stamina - dt / T.sprintTime)
	elif not sprinting: stamina = minf(1.0, stamina + dt / T.sprintRecharge)
	sprint += ((1.0 if sprinting else 0.0) - sprint) * minf(1.0, dt * 5)
	var sp_k := sprint
	var a_long := 0.0
	var n_sc := G / _or(n_ref, G)
	var nR := 0.0 if air else _or(n_r, G * SH_R) * n_sc
	var nF := 0.0 if air else _or(n_f, G * (1 - SH_R)) * n_sc
	var n_tot := nR + nF
	var mu: float = (0.95 if surf == 1 else 0.5 if surf == 3 else 0.45 if surf == 2 else 0.72) * T.grip
	spin = 0; a_drive = 0

	# --- longitudinal ---
	if not air:
		var vp := maxf(v, 0.5)
		var gk := gear_k()
		# Top speed (Settings > Controls / tuning card): scales the pedalling top speed, with the power
		# to reach it and less drag holding it back (drag-limited top speed scales with it too)
		var ts: float = T.topSpeed
		var p_top: float = (T.pedalTop + T.sprintTop * sp_k) * gk * ts
		var p_mul: float = (1 + (T.sprintPower - 1) * sp_k) * ts
		var cad: float = v / (gk * T.pedalTop * ts * 0.7)
		var grind := 1.0 if gear < 0 else 0.35 + 0.65 * smooth01((cad - 0.15) / 0.7)
		var drive: float = (throttle if rear_down else 0.0) * minf(T.pedalLaunch * p_mul / ts / gk, T.pedalPower * p_mul / vp) * grind * clampf((p_top - v) / 2.5, 0, 1)
		var drive_cap := mu * nR
		if drive > drive_cap:
			spin = minf(1.0, (drive - drive_cap) / 3); drive = drive_cap + (drive - drive_cap) * 0.15
		a_long = absf(drive)
		var a := drive - G * sin(slope)
		if brake and rear_down and v > 0.3:
			var b: float = minf(T.brakeForce * brake_k, 0.85 * mu * n_tot)
			a -= b; a_long += b; drive -= b
			brake_heat += b * v * dt / 45.0
		a_drive = drive
		var pump_ok := not front_air and not rear_air and not (hop_t > 0) and since_land > 0.25 and prep < 0.1 and v > 1
		var a_pump: float = T.pumpGain * clampf(compress_v, -2, 2) * -sin(slope) if pump_ok else 0.0
		a += a_pump
		if compress_v > 0.15 and pump_ok: pump_acc += a_pump * dt
		elif compress_v <= 0.05:
			if pump_acc > 0.35:
				flow_up()
				if host.msg_idle(): host.flash("PUMP +%d km/h" % roundi(pump_acc * 3.6))
			pump_acc = 0
		var carry: float = 1 - T.flowCarry * flow / FLOW_MAX
		var roll: float = (0.32 if surf == 0 else 0.42 if surf == 3 else 0.1) * T.rollRes * signf(v) * minf(1.0, absf(v) * 4)
		a -= (roll + T.airDrag / (ts * ts) * v * absf(v)) * carry
		if in_water: a -= 0.7 * v
		v = clampf(v + a * dt, -3, 24 * maxf(1.0, ts))
		if brake and v <= 0.3: v += (-1.3 - v) * minf(1.0, dt * 3)
		if throttle < 0.1 and not brake and absf(v) < 0.05 and absf(_g_pitch) < 0.03: v = 0
	if flow > 0:
		flow_t += dt
		if brake and v > 1: flow = maxf(0.0, flow - dt * 3)
		elif flow_t > T.flowTime: flow = maxf(0.0, flow - dt * 1.5)
	var top_now: float = (T.pedalTop + T.sprintTop * sprint) * gear_k() * T.topSpeed
	if v > top_now + 0.3: spun_out = true
	elif v < top_now - 0.8: spun_out = false
	pedal += ((throttle if (not air and not spun_out) else 0.0) - pedal) * minf(1.0, dt * 6)

	# --- steering, countersteer and lean ---
	var va := absf(v)
	var spd_k := smooth01(va / 14.0)
	var in_rate: float = T.steerRate * 1.5 if (steer_input != 0 and signf(steer_input) != signf(steer_in)) else T.steerRate
	var rate: float = in_rate if absf(steer_input) > 0.01 else T.steerRelease
	steer_in += clampf(steer_input - steer_in, -rate * dt, rate * dt)
	var s_in: float = steer_in * (1 - T.steerCurve + T.steerCurve * absf(steer_in))
	if true:
		var w := 0.35
		var lx := f.z * w
		var lz := -f.x * w
		var mx := x + f.x * (L / 2 - BB_REAR)
		var mz := z + f.z * (L / 2 - BB_REAR)
		var b := 0.0 if air else atan((terrain.height(mx - lx, mz - lz) - terrain.height(mx + lx, mz + lz)) / (2 * w))
		bank = _or(bank, b) + (clampf(b, -0.9, 0.9) - _or(bank, b)) * minf(1.0, dt * 20)
	var bk := bank
	var carving := not air and absf(steer_input) > 0.01 and va > 4 and not skid and absf(slip) < 0.3
	carve = minf(1.0, carve + dt * 2) if carving else maxf(0.0, carve - dt * 5)
	var carve_f := carve * smooth01((va - 4) / 4)
	var a_lat_lim: float = maxf(1.2, T.turnSlow + spd_k * (T.turnFast - T.turnSlow) + G * tan(bk) * signf(s_in) * spd_k + carve_f * T.carveBite)
	var lock: float = T.steerMax + maxf(0.0, T.slowSteer - T.steerMax) * (1 - smooth01(va / maxf(0.5, T.slowSteerFade)))
	var d_max: float = minf(lock, maxf(atan(a_lat_lim * L / maxf(va * va, 0.01)), atan(T.turnFloor * L / maxf(va, 0.1))))
	var cmd: float = s_in * d_max
	var lean_need: float = clampf(atan(v * (v * tan(cmd) / L) / G), -T.leanMax + minf(0.0, bk), T.leanMax + maxf(0.0, bk))
	var tipping_in := absf(steer_input) > 0.01 and absf(lean_need) > absf(lean) and signf(lean_need) == signf(steer_input)
	var c_max: float = absf(cmd) * T.counter
	var ctr: float = clampf((lean_need - lean) * T.counter, -c_max, c_max) * minf(1.0, va / 4) * (1 - spd_k) if tipping_in else 0.0
	var steer_target := cmd - ctr
	steer += (steer_target - steer) * (1 - exp(-dt * T.barSpeed))
	var load_k := clampf(pow(maxf(0.0, n_tot / G), 0.7), 0.25, 1.5)
	var mu_g := mu * G * load_k
	var a_grip: float = mu_g * sqrt(maxf(0.05, 1 - pow(a_long / mu_g, 2))) * (0.75 if skid else 1.0) * (1 + T.carveGrip * carve_f)
	if not air:
		var yaw_cmd := 0.0 if front_air else v * tan(steer) / L
		var gE := G * load_k
		var mE := a_grip / gE
		var cb := cos(bk)
		var sb := sin(bk)
		var a_max := minf(2.5 * G, gE * (sb + mE * cb) / maxf(0.2, cb - mE * sb))
		var a_min := maxf(-2.5 * G, gE * (sb - mE * cb) / maxf(0.2, cb + mE * sb))
		var yaw_use := yaw_cmd
		if carve_f > 0 and not skid and absf(v) > 0.3:
			var want := v * yaw_cmd
			var cap := (a_max if want >= 0 else a_min) * 0.97
			if absf(want) > absf(cap): yaw_use = yaw_cmd + (cap / v - yaw_cmd) * carve_f
		var a_lat_t := clampf(v * yaw_use, a_min, a_max)
		var tau_y: float = T.turnWeight * (0.4 + 0.6 * spd_k)
		lat_m = _or(lat_m, a_lat_t) + (a_lat_t - _or(lat_m, a_lat_t)) * (1 - exp(-dt / tau_y)) if tau_y > 0.005 else a_lat_t
		var a_lat := clampf(lat_m, a_min, a_max)
		var course_rate := a_lat / v if absf(v) > 0.3 else yaw_use
		var excess := yaw_use - course_rate
		var share: float = 1.0 if skid else T.oversteer
		var margin := 1 - minf(1.0, absf(a_lat) / maxf(0.1, a_max if a_lat >= 0 else -a_min))
		var catch_k: float = T.slipRecover * (0.25 + margin) + maxf(0.0, -signf(slip) * steer) * 8
		var slip_rate := excess * share - slip * catch_k
		slip = clampf(slip + slip_rate * dt, -1.5, 1.5)
		course += course_rate * dt
		if absf(v) < 1.2:
			var k := minf(1.0, dt * 6); course += slip * k; slip -= slip * k
		heading = course + slip
		yaw_rate = course_rate + slip_rate
		lat_a = a_lat
		var scrub := mu * G * minf(load_k, 1.5) * absf(sin(slip)) * 0.9 + absf(excess) * (1 - share) * absf(v) * 0.15
		v -= signf(v) * minf(absf(v), scrub * dt)
		if absf(slip) > T.slipMax and va > 3: crash_pending = "WASHED OUT!"
		var into_bank := maxf(0.0, bk * signf(a_lat))
		if absf(slip) > 0.3: carve_acc = 0
		elif carve > 0.6: carve_acc += absf(a_lat) * dt * (1 + 3 * into_bank)
		elif carve < 0.2 and carve_acc > 0:
			var gain: float = minf(T.carveBoost * (1.0 if (into_bank > 0.1 or carve_berm) else 0.5), carve_acc * 0.08) if carve_acc > 2 else 0.0
			carve_acc = 0
			if gain > 0.05 and v > 3:
				v += gain; flow_up()
				if host.msg_idle(): host.flash("%s +%d km/h" % ["BERM" if carve_berm else "CARVE", roundi(gain * 3.6)])
		carve_berm = (carve_berm or into_bank > 0.15) if carve > 0.6 else (carve_acc > 0 and carve_berm)
	else:
		# yaw in the air: a turn carried off the lip keeps turning rider + bike (nothing outside can stop
		# it). The rider can only twist the bike at the hips, within airTwist, to keep it pointing where
		# they fly; slip is the bike's heading against the travel direction
		var sys_slip := wrapf(slip - air_tw, -PI, PI) + air_yaw * dt
		var tw_t := clampf(-sys_slip, -T.airTwist, T.airTwist)
		air_tw_v += (60.0 * (tw_t - air_tw) - 12.0 * air_tw_v) * dt
		air_tw += air_tw_v * dt
		if absf(air_tw) > T.airTwist:
			air_tw = signf(air_tw) * T.airTwist; air_tw_v = 0.0
		var slip_new := wrapf(sys_slip + air_tw, -PI, PI)
		yaw_rate = wrapf(slip_new - slip, -PI, PI) / dt
		spin_acc += yaw_rate * dt
		slip = slip_new
		heading = course + slip
		lat_a = 0; lat_m = 0
	if not air:
		_pivot_step(dt, steer_input, brake_k)
	var lean_t: float = (spin_in * T.airRoll if absf(spin_in) > 0.05 else lean * 0.98) if air else clampf(atan(lat_a / G), -T.leanMax + minf(0.0, bk), T.leanMax + maxf(0.0, bk))
	var kL: float = T.leanIn if absf(steer_input) > 0.01 else T.leanOut
	lean_v += ((lean_t - lean) * kL - lean_v * 2 * sqrt(kL) * T.leanDamp) * dt
	lean += lean_v * dt
	var bl: float = lean * T.bikeLeanMul
	var cap_b: float = T.bikeLeanCap + (0.0 if (air or signf(bk) != signf(bl)) else absf(bk))
	bike_lean = cap_b * tanh(bl / cap_b)
	# the bike leans under the rider: the body always stays a little more upright than the bike (never
	# hangs inside it, or the inside leg cuts through the frame)
	counter = maxf(absf(bike_lean - lean * 0.85), absf(bike_lean) * 0.2) * signf(bike_lean)
	# side-to-side rock from pedalling: full when grinding up to speed, fades out once the rider is spinning fast
	var rock_fade: float = 1.0 - 0.85 * smoothstep(5.0, 12.0, va)
	rock = sin(crank) * 0.065 * (1 + 1.3 * sprint) * pedal * minf(1.0, va / 2 + 0.3) * rock_fade * bike_rock

	# --- move ---
	f = fwd()
	var px := x
	var pz := z
	var g_prev: float = terrain.deck_height(px, pz)   # (the JS meant this: its duplicate surface() shadowed it)
	# on the ground v is the speed along the slope (the tyres carry the bike up / down it, so only its
	# horizontal part moves it across the map); in the air v is the horizontal speed
	var v_h := v if air else v * cos(_g_pitch)
	x += cos(course) * v_h * dt; z -= sin(course) * v_h * dt
	distance += absf(v) * dt
	if true:
		var stp := maxf(absf(v) * dt, 1e-3)
		var g_new: float = terrain.deck_height(x, z)
		var wall := g_new > y + 0.35 if air else ((g_new - g_prev) / stp > 1.6 and g_new - g_prev > 0.05)
		if wall:
			x = px; z = pz
			if absf(v) > 6: crash_pending = "SMACK! Hit the cliff"
			else:
				if absf(v) > 1.5:
					shake = 0.3; host.flash("BONK!")
				v *= -0.25

	# --- obstacles ---
	var FRONT := L - BB_REAR
	for c in terrain.colliders_near(x, z):
		var fx0 := x + f.x * FRONT
		var fz0 := z + f.z * FRONT
		var fdx: float = fx0 - c.x
		var fdz: float = fz0 - c.z
		var fd := sqrt(fdx * fdx + fdz * fdz)
		var cdx: float = x - c.x
		var cdz: float = z - c.z
		var cd := sqrt(cdx * cdx + cdz * cdz)
		var f_min: float = c.r + 0.05
		var c_min: float = c.r + 0.16
		var hit_f := fd < f_min
		var hit_c := cd < c_min
		if not hit_f and not hit_c: continue
		var dx := fdx if hit_f else cdx
		var dz := fdz if hit_f else cdz
		var d := maxf(1e-4, fd if hit_f else cd)
		var mn := f_min if hit_f else c_min
		var vel := Vector3(f.x * v, vy, f.z * v)
		if c.get("cactus", false) and absf(v) > 2.5 and not (air and y > c.get("ceil", INF)):
			if host.smash(c, vel, Vector3(x, y, z)):
				v *= 0.8; shake = maxf(shake, 0.35); host.flash("OUCH! CACTUS!")
			continue
		if c.get("tape", false):
			if y > c.get("ceil", 0.0) - 0.25: continue
			if host.smash(c, vel, Vector3(x, c.get("ceil", y) - 0.1, z)):
				v *= 0.97
				if absf(v) > 3: host.flash("SNAP!")
			continue
		if c.get("fence", false) and (absf(v) > 2.2 or (air and vy < -2)) and not (air and y > terrain.height(c.x, c.z) + 1.2):
			if host.smash(c, vel, Vector3(x, y, z)):
				v *= 0.86; shake = maxf(shake, 0.3); host.flash("CRUNCH!" if c.get("fence_style", "") == "picket" else "SMASH!")
			continue
		if c.has("top"):
			var clear: float = c.top - y
			if clear < CLIMB * RWF: continue
			if not hit_f or fd > c.r * 0.85: continue
			if (f.x * fdx + f.z * fdz) / fd >= 0: continue
			if absf(v) > 2 and joint_rock != c:
				joint_rock = c
				host.rock_chips(c)
			var back: float = (c.r * 0.85 - fd) / fd
			x += fdx * back; z += fdz * back
			var head := (f.x * fdx + f.z * fdz) / fd
			if head < -0.77 and -v * head > 6: crash_pending = "BONK! Over the bars"
			elif head < -0.3 and v > 1.5:
				host.burst(Vector3(fx0, y + 0.3, fz0), 16, 0, 1.2); v *= -0.25; shake = 0.35; host.flash("BONK!")
			else: v *= 0.97
			continue
		if air:
			var ceil_h: float = c.ceil if c.has("ceil") else terrain.height(c.x, c.z) + (1.2 if c.get("fence", false) else 3.2)
			if y > ceil_h: continue
		var push := (mn - d) / d
		x += dx * push; z += dz * push
		var hd := (f.x * dx + f.z * dz) / d
		if hd < -0.77 and -v * hd > 6: crash_pending = "BONK! Over the bars"
		elif hd < -0.3 and v > 1.5:
			host.burst(Vector3(fx0, y + 0.3, fz0), 16, 0, 1.2); v *= -0.25; shake = 0.35; host.flash("BONK!")
		else: v *= 0.97

	# --- vertical + pitch: spring physics ---
	_sample(f)
	var natural: bool
	var dP := _g_pitch - _or(g_pitch, _g_pitch)
	if true:
		if not air and dP > 0.02 and v > 0: v *= cos(minf(dP, 1.2))
		g_pitch = _g_pitch
		natural = float(terrain.jump(x, z)[1]) < 0.05
		var climb_max := absf(v) * 0.9 + 0.3
		var XF := L - BB_REAR
		var XR := -BB_REAR
		var cp0 := cos(clampf(pitch, -1.3, 1.3))
		var hfC := _wheel_ground(f, XF, RWF, cp0)
		var hrC := _wheel_ground(f, XR, RWR, cp0)
		if not w_init or is_nan(hf_prev):
			hf_prev = hfC; hr_prev = hrC; pitch_v = 0; w_init = true
		var hfP := hf_prev
		var hrP := hr_prev
		var vgF := minf((hfC - hfP) / dt, climb_max)
		var vgR := minf((hrC - hrP) / dt, climb_max)
		hf_prev = hfC; hr_prev = hrC
		var shF := 1 - SH_R
		var shR := SH_R
		var IK := 0.32
		var coupled := not air and not (hop_t > 0) and not (lift_t > 0)
		var PHI: float = clampf(T.riderMass, 0, 0.7) if coupled else 0.0
		var mB := 1 - PHI
		var Kb: float = pow(2 * PI * T.tyreHz, 2)
		var K := Kb * mB
		var C: float = 2 * T.tyreDamp * sqrt(Kb) * mB
		# legs stiffen as the rider crouches into a lip, and brace (work hard against the fall) for the
		# first moments after a landing
		var brace := 1.0 - smooth01(since_land / 0.35)
		var kB: float = T.legStiff * (1 + 5 * prep + 4 * brace)
		var cB: float = 2 * sqrt(kB) * T.legDamp
		var press: float = T.legPress * G if (natural and not (hop_t > 0) and not (lift_t > 0)) else 0.0
		var s0 := (G + press) / K
		n_ref = _or(n_ref, G + press) + (G + press - _or(n_ref, G + press)) * minf(1.0, dt * 2 * PI * T.tyreHz * 0.6)
		var TRAVEL: float = T.travel
		var bal_max: float = T.riderBalance * G * BB_REAR / IK
		if true:
			var R: float = T.weightShift
			var x_brake: float = -0.8 * R * (1.0 if (brake and not air) else 0.0) + 0.5 * R * clampf(a_drive / 4, 0, 1)
			var xT: float = 0.0 if air else x_brake + R * clampf(_g_pitch * 2.2, -1, 1)
			# in the air the rider leans where they choose (W forward, S back)
			if air:
				xT = air_lean * R
			var hT: float = air_lean * R if air else x_brake
			# a damped spring to where the rider wants to be, pushed by the bike's own speed changes:
			# the body carries on when the bike slows (braking, a landing, a root) and lags when it surges
			var a_body := 0.0
			if not is_nan(v_last) and not air:
				a_body = clampf((v - v_last) / maxf(dt, 1e-4), -40.0, 40.0)
			v_last = v
			var kx: float = T.bodyStiff
			var cx := 2 * sqrt(kx) * 0.75
			var push: float = -a_body * T.bodyInertia
			body_xv += (kx * (clampf(xT, -R, R) - body_x) - cx * body_xv + push) * dt
			body_x = clampf(body_x + body_xv * dt, -R * 1.4, R * 1.4)
			hip_v += (kx * (clampf(hT, -R, R) - hip_shift) - cx * hip_v + push) * dt
			hip_shift = clampf(hip_shift + hip_v * dt, -R * 1.6, R * 1.6)
		var tq: float = a_drive * T.loadHeight
		var was_air := air
		var vy_in := vy
		var was_f := c_f
		var was_r := c_r
		var cF := false
		var cR := false
		var sumF := 0.0
		var sumR := 0.0
		if not is_finite(body_y):
			body_y = y; body_v = vy
		var N := 4
		var h := dt / N
		for i in range(1, N + 1):
			var u := float(i) / N
			var gF := hfP + (hfC - hfP) * u
			var gR := hrP + (hrC - hrP) * u
			var cs := cos(pitch)
			var sn := sin(pitch)
			var dF := gF - (y + XF * sn) + s0
			var dR := gR - (y + XR * sn) + s0
			var pvF := vy + XF * cs * pitch_v
			var pvR := vy + XR * cs * pitch_v
			cF = dF > 0; cR = dR > 0
			var FF := maxf(0.0, shF * (K * dF + C * (vgF - pvF))) if cF else 0.0
			var FR := maxf(0.0, shR * (K * dR + C * (vgR - pvR))) if cR else 0.0
			sumF += FF; sumR += FR
			var leg_f := 0.0
			if not was_air:
				var f_leg := kB * (y - body_y) - cB * (body_v - vy)
				body_v += f_leg * h; body_y += body_v * h
				leg_f = PHI * (G + f_leg)
			var alpha := (FF * XF + FR * XR - leg_f * body_x) * cs / IK + (tq / IK if (cF or cR) else 0.0)
			if cF != cR:
				var ref := _or(nose_ref, _g_pitch)
				alpha += clampf(30 * (ref - pitch) - 9 * pitch_v, -bal_max, bal_max)
			vy += (FF + FR - (press if (cF or cR) else 0.0) - mB * G - leg_f) / mB * h
			pitch_v += alpha * h
			if not cF and not cR and was_air:
				# in the air: no outside torque. The shared spin air_w only changes with the inertia (tuck),
				# the bike turns with it plus whatever tilt the rider gives it against their own body:
				# W / S tilt it on purpose, hands off the rider aims it at the landing slope
				var I_new: float = 1.0 - T.riderShare * T.tuckSpin * air_pull
				air_w *= air_inertia / I_new; air_inertia = I_new
				var tgt: float
				if absf(flip_in) > 0.05:
					tgt = flip_in * T.airTilt
				else:
					var hh := maxf(0.0, y - _g_y)
					var tg := (vy + sqrt(vy * vy + 2 * G * hh)) / G
					tgt = wrapf(_g_pitch - (pitch - air_tilt + air_w * minf(tg, 1.0)), -PI, PI)
				tgt = clampf(tgt, -T.airTilt, T.airTilt)
				air_tilt_v += (70.0 * (tgt - air_tilt) - 13.0 * air_tilt_v) * h
				air_tilt += air_tilt_v * h
				if absf(air_tilt) > T.airTilt:
					air_tilt = signf(air_tilt) * T.airTilt
					if air_tilt_v * air_tilt > 0: air_tilt_v = 0.0
				pitch_v = air_w + air_tilt_v
			y += vy * h; pitch += pitch_v * h
			if not cF and not cR:   # in the air the bike can go all the way round (flips)
				flip_acc += pitch_v * h
				pitch = wrapf(pitch, -PI, PI)
			# bottom-out
			for wi in 2:
				var xx := XF if wi == 0 else XR
				var gg := gF if wi == 0 else gR
				var vg := vgF if wi == 0 else vgR
				var c2 := cos(pitch)
				var dd := gg - (y + xx * sin(pitch)) - TRAVEL
				if dd <= 0: continue
				var lx := xx * c2
				var m_inv := 1 / mB + lx * lx / IK
				var dq := dd / m_inv
				y += dq / mB; pitch += dq * lx / IK
				var vpp := vy + lx * pitch_v
				if vpp < vg:
					var j := (vg - vpp) / m_inv
					vy += j / mB; pitch_v += j * lx / IK
				if wi == 0: cF = true
				else: cR = true
			if not was_air:
				var rel := body_y - y
				if rel < -T.legComp:
					body_y = y - T.legComp
					# legs bottomed out: the speed the body still had into the bike is the hit the rider takes
					if body_v < vy and since_land < 0.6 and land_jolt >= 0: land_jolt = maxf(land_jolt, vy - body_v)
					if body_v < vy:
						var vc := PHI * body_v + mB * vy if coupled else vy
						body_v = vc; vy = vc
				elif rel > T.legExt:
					body_y = y + T.legExt
					if body_v > vy:
						var vc := PHI * body_v + mB * vy if coupled else vy
						body_v = vc; vy = vc
		var kN := minf(1.0, dt * 30)
		n_f = _or(n_f, shF * G) + (sumF / N - _or(n_f, shF * G)) * kN
		n_r = _or(n_r, shR * G) + (sumR / N - _or(n_r, shR * G)) * kN
		var now_air := not cF and not cR
		front_air = not now_air and not cF; rear_air = not now_air and not cR
		var gpC := asin(clampf((hfC - hrC) / L, -1, 1))
		# looped out: on the back wheel past what the rider can hold, or still rotating back well past
		# the balance point (a back-wheel landing itself is caught, see _land_trick)
		var back_up := pitch - _local_slope(f, XR, RWR, cp0) if cR and not cF and pitch - gpC > 0.6 else 0.0
		if back_up > T.landBack + 0.1 or (back_up > 1.15 and pitch_v > 0.5 and not was_air): crash_pending = "LOOPED OUT!"
		elif cF and not cR and gpC - pitch > 0.6 and _local_slope(f, XF, RWF, cp0) - pitch > 1.15: crash_pending = "NOSE DIVE!"
		if absf(pitch) > 1.45 and (cF or cR):   # on the ground only: in the air flips go all the way round
			pitch = signf(pitch) * 1.45; pitch_v = 0
		if not now_air and (front_air or rear_air) and was_f and was_r: nose_ref = gpC - dP
		if front_air and pitch - _or(nose_ref, _g_pitch) < -T.noseDive: crash_pending = "NOSE DIVE!"
		var snN := sin(pitch)
		w_f = hfC if cF else y + XF * snN
		w_r = hrC if cR else y + XR * snN
		pitch_w = pitch
		if host.susp != null:
			y_draw = y; pitch_draw = pitch
		else:
			y_draw = w_r + (w_f - w_r) * (BB_REAR / L); pitch_draw = asin(clampf((w_f - w_r) / L, -1, 1))
		if not was_air and not now_air and not was_f and cF:
			var slap := maxf(0.0, vgF - (vy_in + XF * cos(pitch) * pitch_v))
			if slap > 2:
				shake = maxf(shake, minf(0.25, slap * 0.05)); compress_v -= minf(1.5, slap * 0.25)
				if slap > 3.5: host.burst(Vector3(x + f.x * XF, _g_hf + 0.03, z + f.z * XF), 10, surf, 0.8)
		c_f = cF; c_r = cR
		if not now_air:
			# the rider's body turns with the bike, smoothed by the arms and legs
			body_pw += (pitch_v - body_pw) * minf(1.0, dt * 4)
		if now_air and not was_air:
			if since_land < 0.5 and OS.get_environment("BMX_TRICK") != "": print("BOUNCE %.2fs after landing vy=%.2f pitch=%.2f" % [since_land, vy, pitch])   # tests
			air = true; air_time = 0; flip_acc = 0.0; spin_acc = 0.0
			# rider + bike fly off at the speed of their shared centre of mass: a bike kicked up by a roller
			# while the body (on soft legs) lags behind doesn't launch the rider with it. In the air the
			# two then move together (the legs only shift them about that centre)
			if coupled and not is_nan(body_v): vy = PHI * body_v + mB * vy
			# the speed along the lip splits into the horizontal part (v from now on) and the climb (vy)
			v *= cos(_g_pitch)
			# the spin rider + bike leave with: mostly the rider's (they're most of the inertia), plus the
			# throw. Whatever the bike turns on its own beyond that is relative motion the arms and legs soak up
			var sh: float = T.riderShare
			air_w = (1 - sh) * pitch_v + sh * body_pw + throw_v
			air_tilt = 0.0; air_tilt_v = sh * (pitch_v - body_pw)
			air_inertia = 1.0
			pitch_v = air_w + air_tilt_v
			throw_v = 0.0
			air_yaw = yaw_rate; air_tw = 0.0; air_tw_v = 0.0
			if OS.get_environment("BMX_TRICK") != "": print("TAKEOFF v=%.1f vy=%.2f pitch_v=%.2f spin=%.2f natural=%s at=(%.0f,%.0f) slope=%.2f" % [v, vy, pitch_v, air_w, natural, x, z, _g_pitch])   # tests
			host.on_takeoff()
		elif not now_air and was_air:
			# how fast the bike comes down into the slope (the speed along it is kept: the tyres just roll on)
			var impact: float = maxf(0.0, v * sin(_g_pitch) - vy_in * cos(_g_pitch))
			var at := air_time
			var back_land: bool = cR and not cF and wrapf(pitch - _g_pitch, -PI, PI) > 0.4
			_land_trick(at)
			air = false; since_land = 0; land_jolt = 0.0
			body_v = vy_in
			body_pw = air_w
			nose_ref = _g_pitch
			# the velocity into the slope is stopped by the tyres, suspension and legs; along the slope it carries on
			v = v * cos(_g_pitch) + vy_in * sin(_g_pitch)
			compress_v -= minf(2.2, impact * 0.35) + (minf(1.2, impact * 0.2 + 0.4) if back_land else 0.0)
			if host.susp != null: host.susp.land(maxf(0.0, -vy_in) * cos(_g_pitch) * 0.5 + impact * (0.57 if back_land else 0.4), front_air, rear_air)
			if OS.get_environment("BMX_TRICK") != "": print("LAND impact=%.1f back=%s v_after=%.1f" % [impact, back_land, v])   # tests
			if at > 0.15: shake = maxf(shake, minf(0.2, impact * 0.025))
			if at > 0.15: host.burst(Vector3(x, y + 0.03, z), roundi(10 + minf(30, impact * 6)), surf, 0.8 + minf(1.5, impact * 0.25))
			if at > 0.45 and impact < 5: flow_up()
			host.on_landing(at, impact)
		if air: air_time += dt
		elif land_jolt > 0 and since_land < 0.6:
			# the legs bottomed out: a hit bigger than they can take throws the rider down
			if land_jolt > T.slamJolt * LAND: crash_pending = "SLAM!"
			elif land_jolt > T.slamJolt * LAND * 0.6: host.flash("OOF!")
			if OS.get_environment("BMX_TRICK") != "" and land_jolt > 0.5: print("JOLT %.2f m/s" % land_jolt)   # tests
			land_jolt = -1.0   # one verdict per landing
		kick_t = maxf(0.0, kick_t - dt)

	# --- hop / pump ---
	if hop_block and not inp.hop: hop_block = false
	var space: bool = inp.hop and not hop_block
	if not air and space: load = minf(1.0, load + dt * 3.5)
	if not air and space and not (hop_t > 0): charge = minf(1.0, charge + dt / T.chargeTime)
	var backside: bool = not air and _g_pitch < -0.06 and float(terrain.jump(x, z)[1]) > 0.05
	if not space and hop_held and not air and load > 0.15 and not (hop_t > 0) and not backside:
		hop_t = HOP_PUSH; hop_load = maxf(load, 0.5)
		hop_charge = smooth01(maxf(0.0, (charge * T.chargeTime - 0.2) / (T.chargeTime - 0.2)))
		compress_v = maxf(compress_v, (0.05 - compress) / HOP_PUSH)
		body_v = vy + (T.legExt - minf(0.0, _or(body_y, y) - y)) / HOP_PUSH
	if hop_t > 0:
		hop_t -= dt
		var k := 1 - maxf(0.0, hop_t) / HOP_PUSH
		hop_nose = maxf(hop_nose, (0.22 + 0.15 * hop_load) * 0.6 * k)
		if hop_t <= 0 or air:
			hop_t = 0
			vy = maxf(vy, 0) + 1.4 + T.popPower * (0.4 + 0.6 * hop_charge) + T.chargePop * hop_charge
			kick_t = 0.3
			hop_nose = 0.22 + 0.15 * hop_load + 0.08 * hop_charge
			hop_charge = 0
			body_v = vy; lift_t = 0.12
	if not space or air: load = maxf(0.0, load - dt * 6)
	if not space or (air and air_time > 0.15): charge = 0
	if lift_t > 0: lift_t = 0.0 if air else maxf(0.0, lift_t - dt)
	hop_bar_show = space and charge * T.chargeTime > 0.2
	hop_bar = charge
	hop_held = space
	hop_nose *= exp(-dt * 3.5)

	# --- reading the trail: spot a lip ahead ---
	var lip_t := INF
	lip_scan = (lip_scan + 1) % 3
	if lip_scan != 0 and not air and v > 3 and lip_state != 0:
		lip_t = INF if lip_state == 1 else maxf(0.0, lip_last - dt)
	elif not air and v > 3:
		var stp := 0.3
		var n := mini(36, ceili(v * (T.prepTime + 0.1) / stp))
		var h_prev: float = terrain.height(x, z)
		var s_prev := NAN
		for i in range(1, n + 1):
			var d := i * stp
			var sx := x + f.x * d
			var sz := z + f.z * d
			var hh: float = terrain.height(sx, sz)
			var sl := (hh - h_prev) / stp
			if not is_nan(s_prev) and s_prev > 0.15 and (s_prev - sl) * v * v / stp > 2.5 * G and float(terrain.jump(sx, sz)[1]) > 0.05:
				lip_t = (d - stp) / v; break
			s_prev = sl; h_prev = hh
	if air or v <= 3: lip_state = 0
	elif lip_t == INF: lip_state = 1
	else:
		lip_state = 2; lip_last = lip_t
	var prep_t: float = smooth01(1 - lip_t / T.prepTime) if lip_t < T.prepTime else 0.0
	prep = maxf(0.0, prep - dt * 4) if air else prep + (prep_t - prep) * minf(1.0, dt * 8)
	var popping := lip_t < 0.14
	if popping and not pop_fired:
		pop_fired = true; body_v = _or(body_v, 0) + T.popKick * prep; compress_v += 2.5 * prep
	if not air and lip_t == INF: pop_fired = false
	var lp := 0.0
	var tuck := 0.0
	if air:
		var hh := maxf(0.0, y - _g_y)
		var tg := (vy + sqrt(vy * vy + 2 * G * hh)) / G
		lp = smooth01(1 - tg / T.landPrepTime) if vy < 0 else 0.0
		tuck = smooth01((air_time - 0.08) / 0.2) * (1 - lp)
	land_prep = lp
	var cT: float
	if air: cT = -0.12 * tuck
	elif popping or hop_t > 0: cT = 0.05
	else: cT = -0.17 * load - 0.1 * charge - 0.06 * carve - T.prepDepth * prep
	compress_v += ((cT - compress) * 120 - compress_v * 14) * dt
	compress = clampf(compress + compress_v * dt, -0.28, 0.05)
	air_k += ((1.0 if (air and air_time > 0.12) else 0.0) - air_k) * minf(1.0, dt * 6)
	if host.susp != null:
		var sp := sin(pitch)
		host.susp.update(dt, {"air": air, "load": maxf(load, -compress * 2.5), "brake": 1.0 if (brake and not air) else 0.0,
			"bumpF": 0.0 if air else w_f - (y + (L - BB_REAR) * sp), "bumpR": 0.0 if air else w_r - (y - BB_REAR * sp)})

	# --- wheels / cranks ---
	var w := v / RWF
	wheel_f += w * dt
	if not skid: wheel_r += v / RWR * dt
	if pedal > 0.05:
		crank += maxf(w / (2.78 * gear_k() * T.topSpeed), 3.5) * (1 + 0.3 * sprint) * pedal * dt
	elif not air:
		var aL: float = host.pedal_a0[0]
		var aR: float = host.pedal_a0[1]
		var tgt: float
		var period := TAU
		if lean > 0.12: tgt = aR + PI / 2
		elif lean < -0.12: tgt = aL + PI / 2
		else:
			tgt = aL; period = PI
		tgt += period * round((crank - tgt) / period)
		crank += (tgt - crank) * minf(1.0, dt * 3.5)
	if air:
		# legs reach for the landing; holding Space tucks the bike up into the body instead
		var rel_t: float = T.legExt * land_prep - T.legComp * 0.85 * air_pull * (1 - land_prep)
		# on the take-off step the leg spring already moved body_y alongside y; after that body_y is
		# last step's bike height + rel
		var rel := _or(body_y, y) - (y if air_time <= dt * 1.5 else _or(y_prev, y))
		var nrel := rel + (rel_t - rel) * (1 - exp(-dt * 12))
		# body and bike push apart about their shared centre of mass, which flies on undisturbed:
		# tucking lifts the bike, reaching down for the landing drops it
		y -= clampf(T.riderMass, 0, 0.7) * (nrel - rel)
		body_y = y + nrel; body_v = vy
	y_prev = y

	skid_fx = skid or spin > 0.3 or (not air and absf(slip) > 0.1 and va > 1.5)
	host.ride_fx(dt, f, va, in_water)

## touch-down after a jump: the bike must meet the slope roughly lined up and facing down the trail,
## or the rider goes down
func _land_trick(at: float) -> void:
	slip = wrapf(slip, -PI, PI)
	if OS.get_environment("BMX_TRICK") != "":   # tests
		print("TRICK air=%.2fs v=%.1f flip=%.0fdeg spin=%.0fdeg pitch_err=%.0fdeg twist=%.0fdeg" % [at, v, rad_to_deg(flip_acc),
			rad_to_deg(spin_acc), rad_to_deg(absf(wrapf(pitch - _g_pitch, -PI, PI))), rad_to_deg(absf(slip))])
	if at < 0.2:
		return
	# Everything else (nose-dive, loop-out, a slide that washes out, a hit the legs can't take) is decided
	# by the ground physics after touch-down. Only geometry is checked here: turned so far that the
	# wheels can't be what meets the ground, the rider or the bars hit first
	var perr_s := wrapf(pitch - _g_pitch, -PI, PI)   # + = nose up (back wheel first)
	if absf(perr_s) > 1.45:
		# (a flip short of all the way round lands turned against the spin, one too far lands turned with it)
		crash_pending = ("UNDER-ROTATED!" if absf(flip_acc) > 3.0 and signf(perr_s) != signf(flip_acc) else
			"OVER-ROTATED!" if absf(flip_acc) > 3.0 else "LOOPED OUT!" if perr_s > 0 else "BAD LANDING!")
		return
	if absf(slip) > 2.2:
		crash_pending = "BACKWARDS!"
		return
	var flips := roundi(absf(flip_acc) / TAU)
	if flips >= 1:
		var kind := "BACKFLIP" if flip_acc > 0 else "FRONTFLIP"
		var trick: String = (["", "", "DOUBLE ", "TRIPLE "][mini(flips, 3)] if flips > 1 else "") + kind
		host.flash(trick + "!")
		if host.has_method("on_trick"): host.on_trick(trick)
		flow_up()

## Pivot (pirouette): slow, brake held and steering -> the rear swings round the front wheel, as far as you like
func _pivot_step(dt: float, steer_input: float, brake_k: float) -> void:
	var on := absf(v) < 2.5 and brake_k > 0.3 and absf(steer_input) > 0.1 and not front_air and not rear_air
	if not on:
		pivot = maxf(0.0, pivot - dt * 5)
		if pivot == 0.0: pivot_acc = 0.0
		return
	pivot = minf(1.0, pivot + dt * 5)
	var FRONT := L - BB_REAR
	var fx := x + cos(heading) * FRONT
	var fz := z - sin(heading) * FRONT
	var dh: float = signf(steer_input) * T.pivotRate * pivot * dt
	var n0 := floori(absf(pivot_acc) / PI)
	pivot_acc += dh
	course += dh; heading += dh
	x = fx - cos(heading) * FRONT; z = fz + sin(heading) * FRONT
	v = move_toward(v, 0.0, 10.0 * dt)
	yaw_rate = dh / dt
	var n1 := floori(absf(pivot_acc) / PI)
	if n1 > n0:
		host.flash("%d PIVOT!" % (n1 * 180))
		if n1 % 2 == 0: flow_up()

func _local_slope(f: Vector3, xx: float, R: float, cp0: float) -> float:
	return atan((_wheel_ground(f, xx + 0.05 / cp0, R, cp0) - _wheel_ground(f, xx - 0.05 / cp0, R, cp0)) / 0.1)

func flow_up() -> void:
	flow = minf(FLOW_MAX, floorf(flow) + 1); flow_t = 0

## Every float field finite? (the frame loop's safety net)
func is_sane() -> bool:
	for k in ["x", "z", "y", "vy", "v", "heading", "pitch", "pitch_v", "lean", "lean_v", "steer", "slip", "course", "compress", "compress_v",
			"body_x", "body_xv", "hip_shift", "hip_v", "air_lean", "air_pull", "a_drive"]:
		if not is_finite(get(k)):
			return false
	return true

## after a bad step: zero the body / rider state so a NaN there can't keep poisoning the ride
func reset_body() -> void:
	body_v = 0; body_y = y; body_x = 0; body_xv = 0; hip_shift = 0; hip_v = 0; v_last = NAN
	air_lean = 0; air_pull = 0; a_drive = 0; pitch_v = 0; compress_v = 0; lean_v = 0
