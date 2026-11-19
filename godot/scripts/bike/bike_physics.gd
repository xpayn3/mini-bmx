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
var wheelie_up := 0.0   # sprint wheelie: how far up (rad) the rider is holding the front
var air := false; var air_time := 0.0; var air_k := 0.0; var cap_bank := 0.0; var lean_lim := 9.0
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
var pump_lift := 0.0   # a lip pump's leg drive still to come at take-off (m/s)
var body_pw := 0.0; var throw_v := 0.0; var lock_tw := false; var lock_ts := false
var air_w := 0.0; var air_inertia := 1.0; var air_tilt := 0.0; var air_tilt_v := 0.0
var air_yaw := 0.0; var air_tw := 0.0; var air_tw_v := 0.0; var land_jolt := 0.0
# pivot: how far a slow-speed pivot (pirouette) has turned the bike
var pivot := 0.0; var pivot_acc := 0.0
# rider body stick (gamepad right stick, any time): body_in = fore / aft (+ = forward over the bars),
# flick_in = side lean (+ = left, like steer). flick = the smoothed side lean (the bike is thrown under
# the body), manual_up = how far a pulled-back stick holds the front up (rad)
var aero_k := 1.0   # air drag scale from the body position (tuck < 1, sat up > 1)
var body_in := 0.0; var body_in_s := 0.0; var flick_in := 0.0; var flick := 0.0; var flick_prev := 0.0
var wheelie_time := 0.0; var wheelie_pedal := false   # how long the current stick wheelie / manual has been held
var manual_up := 0.0; var lock_sb := false; var lock_sf := false; var flick_kick := 0.0
var flick_v := 0.0; var _flick_arm := 0.0; var _flick_side := 0.0   # flick spring speed, deliberate-flick detector
const FLICK_VMAX := 6.0      # the bike can be thrown over at most this fast (stick units / s)
const FLICK_WINDOW := 0.18   # centre -> edge within this long = a deliberate flick
var air_stick := Vector2.ZERO   # right stick in the air, eased: x lean (+ left), y nose (+ up)
var edge_s := 0.0   # right stick held at its top / bottom edge in the air: the flip spin, built up gently
var spin_hold := 0.0; var spin_k := 1.0
# flat spins: the right stick held at its left / right edge in the air spins the bike round (180 / 360),
# built up gently and faster the longer it's held, eased out when let go (stick_yaw rad/s on top of air_yaw)
var yaw_edge_s := 0.0; var yaw_hold := 0.0; var stick_yaw := 0.0
var style_air := 0.0   # this jump's tweak: seconds x how far the stick swung the bike about (style points)   # how long it's been held one way, and the spin-rate multiplier that gives
var pad := false
var bank_probe := OS.get_environment("BMX_BANK_PROBE") != ""
var lean_room := NAN   # how steeply the ground rises beside the bike on its lean side (rad, eased)
var _lean_hist := []; var _bank_raw := 0.0   # the player is on a gamepad (Settings.pad_active): triggers don't tilt / throw in the air
var wheel_f := 0.0; var wheel_r := 0.0; var crank := 0.0; var pedal := 0.0; var throttle_in := 0.0   # the raw gas key / trigger this step (pedal is its smoothed version)
var yaw_rate := 0.0; var shake := 0.0
var course := NAN; var slip := 0.0; var since_land := 1.0
# riding backwards (fakie): landing turned ~180 deg from the travel doesn't crash, the bike just rolls on facing
# backwards (v < 0, course = heading). Both sticks pushed towards the pad's centre (left stick right + right
# stick left) swing it round to face forward (turn_off = the visual swing still to come, rad).
var turn_off := 0.0; var rev_cap := 3.0; var _rev_land := false; var _land_fix := false; var _fakie_hold := 0.0
const LAND_CONE := 1.05   # heading within ~60 deg of the travel at touch-down = a normal landing; past it the tyres grab the nearer axis
# tyre grip sim (_grip_step): slip_w = how fast the bike is yawing against its travel (the rear stepping out /
# coming back), grip_r = the rear tyre's sideways grip left (0 locked / spinning .. 1 full), loose = how loose
# the patch of ground under the rear is (0..1), bar_catch = the rider's drawn countersteer into a slide
var slip_w := 0.0; var grip_r := 1.0; var loose := 0.0; var bar_catch := 0.0
var _grip_noise: FastNoiseLite = null; var _grip_rng := RandomNumberGenerator.new(); var _grip_cv := 0.0
var _squirm := 0.0; var _grip_rough := 0.0
var front_air := false; var rear_air := false; var c_f := true; var c_r := true
var pitch_w := NAN; var stamina := 1.0; var tired := false; var sprint := 0.0
var spin := 0.0; var a_drive := 0.0
var n_f := NAN; var n_r := NAN; var n_ref := NAN
var flow := 0.0; var flow_t := 0.0
var spun_out := false
var bank := NAN; var carve := 0.0; var carve_acc := 0.0; var carve_berm := false
var lat_m := NAN; var lat_a := 0.0; var n_load := G   # (n_load: the ground's push on the tyres, m/s², for the ride log)
var g_pitch := NAN
var w_init := false; var hf_prev := NAN; var hr_prev := NAN
var nose_ref := NAN
var w_f := 0.0; var w_r := 0.0; var y_draw := 0.0; var pitch_draw := 0.0
var kick_t := 0.0; var hop_t := 0.0; var hop_load := 0.0; var hop_charge := 0.0; var charge := 0.0
var lift_t := 0.0; var hop_block := false; var hop_held := false
var prep := 0.0; var land_prep := 0.0; var pop_fired := false
var lip_scan := 0; var lip_state := 0; var lip_last := 0.0   # lip_state: 0 unknown, 1 none in sight, 2 lip_last valid
var y_prev := NAN; var pump_acc := 0.0; var brake_heat := 0.0
var foot_down := false    # set by Game: the rider's foot is on the ground (the bike stays put)
var brake_stop := false  # braked to a standstill: held in place while the brake stays on
var brake_back := false   # brake pressed fresh from a standstill: backs the bike up
var dust_acc := 0.0; var chunk_acc := 0.0
var joint_rock = null
var distance := 0.0
# tests (BMX_CLIP_PROBE): suspension bottom-outs (steps) and how rough the ride is on the ground
var probe_bottom := 0; var probe_acc2 := 0.0; var probe_n := 0; var probe_vy := NAN
var probe_g2 := 0.0; var probe_gy := [NAN, NAN]
# what the HUD reads
var skid_fx := false; var surf := 0; var hop_bar := 0.0; var hop_bar_show := false

# ---- crash ----
var crash_on := false; var crash_t := 0.0; var crash_pending := ""; var crash_side := 1.0
var getup_need := GETUP_HOLD   # hold time to get up (longer to revive at zero life, set by the HUD)
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
	gear = start_gear(cogs, ring_k) if geared else -1

## the cog a ride starts in: nearest the old 16T reference (the garage rollers use it too)
static func start_gear(p_cogs: Array, p_ring_k: float) -> int:
	var g := -1
	var best := 1e9
	for i in p_cogs.size():
		if absf(p_cogs[i] * 1.0 / p_ring_k - 16.0) < best: best = absf(p_cogs[i] * 1.0 / p_ring_k - 16.0); g = i
	return g

## crank turn rate (rad/s) for a wheel spinning at w rad/s in gear gk; shared with the garage rollers
static func crank_rate(w: float, gk: float, top_speed: float, p_sprint: float) -> float:
	# a sprint from slow spins the legs up hard (~70 rpm at once), not just at the wheel's rate
	return maxf(w / (2.78 * gk * top_speed), 3.5 + float(Tune.v.get("sprintSpin", 4.0)) * p_sprint * slowness(w * 0.37)) * (1 + 0.3 * p_sprint)

## 1 standing still .. 0 by ~40 km/h (smooth): how hard a sprinting rider fights to get up to speed
static func slowness(va: float) -> float:
	return 1.0 - smooth01(absf(va) / float(Tune.v.get("sprintSlowTo", 11.0)))

## side-to-side rock from pedalling out of the saddle: the bike swings ~6 deg each way under a steady
## body (~10 deg sprinting), most when pushing hard from slow, about a third of that spinning at speed
static func pedal_rock(p_crank: float, p_sprint: float, p_pedal: float, va: float, p_bike_rock: float) -> float:
	var rock_fade: float = 1.0 - 0.65 * smoothstep(5.0, 12.0, va)
	# sprinting from slow: the bike is thrown hard side to side under the rider (~15 deg each way)
	var effort: float = p_sprint * slowness(va)
	return sin(p_crank) * 0.105 * (1 + 0.65 * p_sprint + float(Tune.v.get("sprintRock", 0.75)) * effort) * p_pedal * minf(1.0, va / 2 + 0.3) * rock_fade * p_bike_rock

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
	turn_off = 0.0; rev_cap = 3.0; _fakie_hold = 0.0
	course = hd; slip = 0; slip_w = 0.0; bar_catch = 0.0; w_init = false; front_air = false; rear_air = false; pump_acc = 0; since_land = 1
	pitch_v = 0; c_f = true; c_r = true; wheelie_up = 0.0
	g_pitch = NAN
	y = host.terrain.height(x, z); body_y = y; body_v = 0
	n_f = NAN; n_r = NAN; n_ref = NAN; lip_state = 0; hf_prev = NAN; hr_prev = NAN
	bank = 0; body_x = 0; hip_shift = 0; spin = 0; a_drive = 0; charge = 0; hop_charge = 0; lift_t = 0
	body_xv = 0; hip_v = 0; v_last = NAN; air_lean = 0; air_pull = 0; flip_acc = 0; spin_acc = 0; flip_in = 0; spin_in = 0
	body_pw = 0; throw_v = 0; air_w = 0; air_inertia = 1; air_tilt = 0; air_tilt_v = 0; air_yaw = 0; air_tw = 0; air_tw_v = 0; land_jolt = 0
	pivot = 0; pivot_acc = 0; body_in_s = 0; flick = 0; flick_v = 0; _flick_arm = 0; _flick_side = 0; flick_prev = 0; manual_up = 0; flick_kick = 0
	sprint = 0; flow = 0; flow_t = 0; lat_m = 0; carve = 0; carve_acc = 0; carve_berm = false
	y_draw = y; pitch_draw = 0; nose_ref = NAN; pitch_w = NAN; y_prev = NAN; kick_t = 0
	w_f = y; w_r = y

func get_up() -> void:
	crash_on = false; crash_hold = 0; crash_armed = false
	v = 0; vy = 0; lean = 0; lean_v = 0; bike_lean = 0; counter = 0; steer = 0; steer_in = 0; yaw_rate = 0; air = false
	pitch = 0; compress = 0; compress_v = 0; hop_nose = 0; hop_t = 0; load = 0
	slip = 0; slip_w = 0.0; bar_catch = 0.0; w_init = false; front_air = false; rear_air = false; pump_acc = 0; pitch_v = 0; c_f = true; c_r = true; wheelie_up = 0.0
	course = heading; turn_off = 0.0; rev_cap = 3.0; _fakie_hold = 0.0
	hop_block = true
	y = host.terrain.height(x, z); body_y = y; body_v = 0
	n_f = NAN; n_r = NAN; n_ref = NAN; lip_state = 0; hf_prev = NAN; hr_prev = NAN
	bank = 0; body_x = 0; hip_shift = 0; spin = 0; a_drive = 0; charge = 0; hop_charge = 0; lift_t = 0
	body_xv = 0; hip_v = 0; v_last = NAN; air_lean = 0; air_pull = 0; flip_acc = 0; spin_acc = 0; flip_in = 0; spin_in = 0
	body_pw = 0; throw_v = 0; air_w = 0; air_inertia = 1; air_tilt = 0; air_tilt_v = 0; air_yaw = 0; air_tw = 0; air_tw_v = 0; land_jolt = 0
	pivot = 0; pivot_acc = 0; body_in_s = 0; flick = 0; flick_v = 0; _flick_arm = 0; _flick_side = 0; flick_prev = 0; manual_up = 0; flick_kick = 0
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
	if crash_hold >= getup_need:
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
	# rider body stick (gamepad right stick): fore / aft weight, side lean. Works the whole ride
	pad = bool(inp.get("pad", false))
	body_in = clampf(float(inp.get("body_fwd", 0.0)), -1.0, 1.0)
	flick_in = clampf(float(inp.get("body_lean", 0.0)), -1.0, 1.0)
	body_in_s += (body_in - body_in_s) * minf(1.0, dt * 10)
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
		# + the body stick (forward = nose down), with a dead band so a light lean held from the ground doesn't
		# spin the bike. On a gamepad the triggers (held pedalling / braking into a jump) don't tilt it at all
		# the right stick doesn't spin the bike, it points it (see air_stick); only pushed right to the top
		# / bottom edge it keeps the bike turning over (flips in the air)
		# The spin builds up gently while the stick is held at the edge (stickSpinBuild /s) and eases out
		# quicker when it comes off the edge: no sudden kick into a flip
		var edge := signf(body_in) * clampf((absf(body_in) - 0.8) / 0.15, 0.0, 1.0)
		var e_rate: float = float(T.get("stickSpinBuild", 2.5)) if absf(edge) > absf(edge_s) else 4.0
		edge_s = move_toward(edge_s, edge, e_rate * dt)
		# the longer it's held one way, the faster it spins (like winding it up): spin_hold seconds held,
		# x (1 + stickSpinGrow per second, up to 1.5 s); turning the other way starts over
		if absf(edge) > 0.5 and signf(edge) == signf(edge_s): spin_hold += dt
		else: spin_hold = maxf(0.0, spin_hold - dt * 3.0)
		spin_k = 1.0 + float(T.get("stickSpinGrow", 0.8)) * minf(spin_hold, 1.5) if absf(edge_s) > 0.01 else 1.0
		lean_in = clampf((0.0 if pad else throttle - brake_k) + edge_s * float(T.get("stickSpinMax", 0.7)), -1.0, 1.0)
		var ex := signf(flick_in) * clampf((absf(flick_in) - 0.8) / 0.15, 0.0, 1.0)
		var ey_rate: float = float(T.get("stickSpinBuild", 2.5)) if absf(ex) > absf(yaw_edge_s) else 4.0
		yaw_edge_s = move_toward(yaw_edge_s, ex, ey_rate * dt)
		if absf(ex) > 0.5 and signf(ex) == signf(yaw_edge_s): yaw_hold += dt
		else: yaw_hold = maxf(0.0, yaw_hold - dt * 3.0)
		var yk: float = 1.0 + float(T.get("stickSpinGrow", 0.8)) * minf(yaw_hold, 1.5)
		var y_t: float = yaw_edge_s * float(T.get("stickYawRate", 5.0)) * yk
		if absf(ex) < 0.1 and land_prep > 0.2:
			# coming in to land off a spin: the rider twists it the rest of the way straight if it's close
			var off := wrapf(slip, -PI, PI)
			if absf(off) < 1.0: y_t = clampf(-off * 6.0, -4.0, 4.0)
		var y_resp: float = 4.0 if absf(y_t) > absf(stick_yaw) else 3.0
		stick_yaw += (y_t - stick_yaw) * minf(1.0, y_resp * dt)
	else:
		edge_s = 0.0; spin_hold = 0.0; spin_k = 1.0
		yaw_edge_s = 0.0; yaw_hold = 0.0; stick_yaw = 0.0
	flip_in = -lean_in                                          # + = nose up
	spin_in = 0.0 if (not air or air_lock_a) else steer_input   # + = the steering direction
	var roll_keys := spin_in
	if air: spin_in = clampf(spin_in + flick_in, -1.0, 1.0)     # the body stick leans the bike too
	# 360° air control with the right stick: x = lay the bike over left / right, y = nose up / down. It sets
	# the bike's attitude (held where the stick points, back to the landing aim when let go), so circling
	# the stick swings the bike round through every mix of tilt and lean
	var stick_raw := Vector2(flick_in, -body_in) if air else Vector2.ZERO
	if stick_raw.length() < 0.08: stick_raw = Vector2.ZERO
	# eased: the bike follows a smoothed stick (stickAirEase /s), so a quick flick of the thumb swings it
	# over smoothly instead of snapping it
	air_stick += (stick_raw - air_stick) * (1.0 - exp(-dt * float(T.get("stickAirEase", 3.5))))
	if not air: air_stick = Vector2.ZERO
	else: style_air += minf(air_stick.length(), 1.0) * dt
	air_lean += (lean_in - air_lean) * minf(1.0, dt * 6)
	# the rider tucks into a flip as well as when Space is held
	var pull_t := maxf(1.0 if air and inp.hop and not air_lock_h else 0.0, 0.7 * absf(flip_in) if air else 0.0)
	# right after take-off the rider lifts the bike up into the body (it moves about the shared centre of
	# mass, the arc stays the same), then lets it down to reach for the landing (land_prep)
	if air:
		var lift_k: float = smooth01((air_time - 0.03) / 0.1) * (1.0 - smooth01((air_time - 0.3) / 0.3)) * (1.0 - land_prep)
		pull_t = maxf(pull_t, T.airLift * lift_k)
	air_pull += (pull_t - air_pull) * minf(1.0, dt * 8)
	# the lip throw: W / S pressed fresh as the bike leaves a lip (a jump spotted just ahead, or one wheel
	# already off) throw the rider back / forward, pushing against the bike and through it the ground. That
	# is the only way to start a flip (keys held from before don't count; S there pulls back, it doesn't brake)
	var lip_win := not air and (prep > 0.25 or front_air or rear_air)
	if pad:   # gamepad: the triggers never throw a flip (the right stick does), so brake stays a brake
		lock_tw = true; lock_ts = true
	elif not lip_win:
		lock_tw = throttle > 0.1; lock_ts = brake
	else:
		if throttle <= 0.1: lock_tw = false
		if not brake: lock_ts = false
	var throw_in := 0.0
	if lip_win:
		throw_in = (0.0 if lock_ts else brake_k) - (0.0 if lock_tw else throttle)   # + = back (nose up)
		if not lock_ts:
			brake_k = 0.0; brake = false
	# the body stick throws too, but only a real yank: pushed past half way, starting from the centre inside
	# the lip window. Any lean held into the lip (riding in the attack position, a manual) never throws -
	# a light forward lean used to throw a front flip at every lip and nose-dive the landing
	if not lip_win:
		lock_sb = body_in < -0.05; lock_sf = body_in > 0.05
	else:
		if body_in >= -0.15: lock_sb = false
		if body_in <= 0.15: lock_sf = false
		var yb := 0.0 if lock_sb else clampf((-body_in - 0.5) / 0.4, 0.0, 1.0)
		var yf := 0.0 if lock_sf else clampf((body_in - 0.5) / 0.4, 0.0, 1.0)
		throw_in = clampf(throw_in + yb - yf, -1.0, 1.0)
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
	var slope: float = _or(pitch_w, _g_pitch) if (not air and (front_air or rear_air) and wheelie_up <= 0.0) else _g_pitch   # a wheelie rolls on the ground's slope
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
	# rider weight fore / aft moves load between the tyres (total unchanged): leaning back puts it on the rear
	# (drive + rear sideways grip up, front light and washy), leaning forward does the opposite (rear lets go)
	var lean_fb := 0.0
	if not air:
		lean_fb = clampf(body_in_s + (body_x + hip_shift) * 0.5 / maxf(0.05, T.weightShift), -1.0, 1.0)
		var dN: float = -lean_fb * float(T.get("leanTraction", 0.45)) * G
		dN = clampf(dN, -nR + 0.08 * G, nF - 0.08 * G)
		nR += dN; nF -= dN
	n_load = n_tot
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
		# sprinting, the slower the rider is the harder they stamp on it (out of the saddle, full body):
		# all of the extra push from a standstill, less and less as the speed comes back, none by ~40 km/h
		var kick: float = float(T.get("sprintKick", 0.9)) * slowness(v)
		var p_mul: float = (1 + (T.sprintPower - 1 + kick) * sp_k) * ts
		var cad: float = v / (gk * T.pedalTop * ts * 0.7)
		var grind := 1.0 if gear < 0 else 0.35 + 0.65 * smooth01((cad - 0.15) / 0.7)
		var drive: float = (throttle if (rear_down and not (v < -0.3 and rev_cap > 3.0)) else 0.0) * minf(T.pedalLaunch * p_mul / ts / gk, T.pedalPower * p_mul / vp) * grind * clampf((p_top - v) / 2.5, 0, 1)
		var drive_cap := mu * nR
		if drive > drive_cap:
			spin = minf(1.0, (drive - drive_cap) / 3); drive = drive_cap + (drive - drive_cap) * 0.15
		a_long = absf(drive)
		var a := drive - G * sin(slope)
		if brake and rear_down and v > 0.3:
			var b: float = minf(T.brakeForce * brake_k, 0.85 * mu * n_tot)
			a -= b; a_long += b; drive -= b
			brake_heat += b * v * dt / 45.0
		elif brake and rear_down and v < -0.3 and rev_cap > 3.0:
			# braking while rolling backwards after a fakie landing
			var b: float = minf(T.brakeForce * brake_k, 0.85 * mu * n_tot)
			a += b; a_long += b; drive += b
			brake_heat += b * -v * dt / 45.0
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
		# aerodynamics: the drag is the rider's frontal area. Folded down over the bars (right stick forward)
		# it drops (~40 %: an upright downhill rider vs a race tuck), so the bike runs on and tops out faster;
		# sat up tall (stick back) it catches the wind like an air brake. Pedalling hard spoils the tuck a bit
		var tuck: float = clampf(body_in_s, 0.0, 1.0) * (1.0 - 0.5 * clampf(throttle, 0.0, 1.0))
		var sit_up: float = clampf(-body_in_s, 0.0, 1.0)
		aero_k = 1.0 - float(T.get("tuckDrag", 0.42)) * tuck + float(T.get("upDrag", 0.3)) * sit_up
		a -= (roll + T.airDrag / (ts * ts) * v * absf(v) * aero_k) * carry
		if in_water: a -= 0.7 * v
		v = clampf(v + a * dt, -maxf(3.0, rev_cap), 24 * maxf(1.0, ts))
		rev_cap = maxf(3.0, minf(rev_cap, -v))   # the extra reverse room (fakie landing) only shrinks
		# braked to a stop the brake holds the bike where it is (no creeping, even on a slope) until it's let
		# go; pressing brake again from a standstill backs the bike up
		if not brake:
			brake_stop = false; brake_back = absf(v) < 0.3
		elif v <= 0.3 and not brake_back:
			brake_stop = true
		if brake_stop or (foot_down and throttle < 0.1 and not (brake and brake_back)):
			v = 0.0   # a foot on the ground holds the bike still (no creeping on a slope)
		elif brake and brake_back and v <= 0.3:
			v += (-1.3 - v) * minf(1.0, dt * 3)
		if throttle < 0.1 and not brake and absf(v) < 0.05 and absf(_g_pitch) < 0.03: v = 0
	if flow > 0:
		flow_t += dt
		if brake and v > 1: flow = maxf(0.0, flow - dt * 3)
		elif flow_t > T.flowTime: flow = maxf(0.0, flow - dt * 1.5)
	var top_now: float = (T.pedalTop + T.sprintTop * sprint) * gear_k() * T.topSpeed
	if v > top_now + 0.3: spun_out = true
	elif v < top_now - 0.8: spun_out = false
	pedal += ((throttle if (not air and not spun_out) else 0.0) - pedal) * minf(1.0, dt * 6)
	throttle_in = throttle

	# --- steering, countersteer and lean ---
	var va := absf(v)
	var spd_k := smooth01(va / 14.0)
	# body stick side lean: the rider throws the bike under them. Leaning alone turns the bike (the bars
	# follow the lean); leaning with the steer turns harder (more lean, more bite). A quick flick of the
	# stick outwards whips the bike round (flick_kick: a yaw kick, the rear stepping out a little)
	# the bike follows the stick on a critically damped spring (flickSpeed = its natural rate) with a top
	# speed, so a thumb throw left -> right swings the bike over smoothly instead of snapping it
	var fw: float = float(T.get("flickSpeed", 14.0))
	flick_v += ((flick_in - flick) * fw * fw - 2.0 * fw * flick_v) * dt
	flick_v = clampf(flick_v, -FLICK_VMAX, FLICK_VMAX)
	flick = clampf(flick + flick_v * dt, -1.0, 1.0)
	# a deliberate flick (stick thrown from near the centre to the edge within FLICK_WINDOW) whips the bike
	# round once; thumb wobble / holding a lean never does (it used to fire on every outward twitch)
	if absf(flick_in) < 0.35:
		_flick_arm = 0.0; _flick_side = 0.0
	elif _flick_side == 0.0:
		_flick_side = signf(flick_in)
	if _flick_side != 0.0 and _flick_arm >= 0.0:
		_flick_arm += dt
		if absf(flick_in) > 0.85 and signf(flick_in) == _flick_side:
			if _flick_arm < FLICK_WINDOW and not air and va > 2.0:
				flick_kick += _flick_side * float(T.get("flickKick", 0.16)) * smooth01((va - 2.0) / 5.0)
			_flick_arm = -1.0   # spent until the stick comes back towards the centre
	flick_prev = flick_in
	var steer_eff := clampf(steer_input + flick * float(T.get("flickSteer", 0.5)), -1.0, 1.0)
	# leaning with the steer: how much the two agree, smooth through zero (no on / off as the steer crosses)
	var agree := clampf(flick * steer_eff * 2.0, 0.0, 1.0) * absf(flick)
	var in_rate: float = T.steerRate * 1.5 if (steer_eff != 0 and signf(steer_eff) != signf(steer_in)) else T.steerRate
	var rate: float = in_rate if absf(steer_eff) > 0.01 else T.steerRelease
	steer_in += clampf(steer_eff - steer_in, -rate * dt, rate * dt)
	var s_in: float = steer_in * (1 - T.steerCurve + T.steerCurve * absf(steer_in))
	if true:
		var w := 0.5
		var lx := f.z * w
		var lz := -f.x * w
		# the lay of the land (berms, cambers, wooden decks) WITHOUT the rock / log domes: a rock under one
		# side read as a 30 deg berm and threw the lean about (the wheels still ride over the rock). Read
		# across both axles, +-0.5 m, so a sharp trail edge isn't a sudden berm either
		var b := 0.0
		if not air:
			var dh := 0.0
			for wo in [L - BB_REAR, -BB_REAR]:
				var mx: float = x + f.x * wo
				var mz: float = z + f.z * wo
				dh += terrain.deck_height(mx - lx, mz - lz) - terrain.deck_height(mx + lx, mz + lz)
			b = atan(dh * 0.5 / (2 * w))
		_bank_raw = b
		# a sharp edge (berm lip, trail edge) gives a one-frame spike across the 0.7 m: the bank the bike
		# feels changes at most 3 rad/s
		var b0: float = _or(bank, b)
		bank = b0 + clampf((clampf(b, -0.9, 0.9) - b0) * minf(1.0, dt * 20), -3.0 * dt, 3.0 * dt)
	var bk := bank
	var carving := not air and absf(steer_eff) > 0.01 and va > 4 and not skid and absf(slip) < 0.3
	carve = minf(1.0, carve + dt * 2) if carving else maxf(0.0, carve - dt * 5)
	var carve_f := carve * smooth01((va - 4) / 4)
	var a_lat_lim: float = maxf(1.2, T.turnSlow + spd_k * (T.turnFast - T.turnSlow) + G * tan(bk) * signf(s_in) * spd_k + carve_f * T.carveBite + agree * float(T.get("flickTurn", 4.0)) * spd_k)
	var lock: float = T.steerMax + maxf(0.0, T.slowSteer - T.steerMax) * (1 - smooth01(va / maxf(0.5, T.slowSteerFade)))
	var d_max: float = minf(lock, maxf(atan(a_lat_lim * L / maxf(va * va, 0.01)), atan(T.turnFloor * L / maxf(va, 0.1))))
	var cmd: float = s_in * d_max
	var lean_need: float = clampf(atan(v * (v * tan(cmd) / L) / G), -T.leanMax + minf(0.0, bk), T.leanMax + maxf(0.0, bk))
	var tipping_in := absf(steer_eff) > 0.01 and absf(lean_need) > absf(lean) and signf(lean_need) == signf(steer_eff)
	var c_max: float = absf(cmd) * T.counter
	var ctr: float = clampf((lean_need - lean) * T.counter, -c_max, c_max) * minf(1.0, va / 4) * (1 - spd_k) if tipping_in else 0.0
	var steer_target := cmd - ctr
	steer += (steer_target - steer) * (1 - exp(-dt * T.barSpeed))
	var load_k := clampf(pow(maxf(0.0, n_tot / G), 0.7), 0.25, 1.5)
	var mu_g := mu * G * load_k
	var a_grip: float = mu_g * sqrt(maxf(0.05, 1 - pow(a_long / mu_g, 2))) * (0.75 if skid else 1.0) * (1 + T.carveGrip * carve_f + float(T.get("flickGrip", 0.2)) * agree) * (0.65 + 0.35 * clampf(nF / maxf(0.1, G * (1.0 - SH_R)), 0.0, 1.2) if not air else 1.0)
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
		if bank_probe:   # tests: the lean collapsing fast at speed, and what the bank / grip limits were then
			_lean_hist.append(lean)
			if _lean_hist.size() > 12: _lean_hist.pop_front()
			if va > 7.0 and _lean_hist.size() == 12 and absf(lean - _lean_hist[0]) > 0.22 and absf(lean) < absf(_lean_hist[0]):
				print("BANKDROP v=%.1f lean %.2f->%.2f bank=%.2f raw=%.2f lat_m=%.1f a_min=%.1f a_max=%.1f steer_in=%.2f slip=%.2f" % [va, _lean_hist[0], lean, bk, _bank_raw, lat_m, a_min, a_max, steer_in, slip])
				_lean_hist.clear()
		var course_rate := a_lat / v if absf(v) > 0.3 else yaw_use
		var excess := yaw_use - course_rate
		var share: float = 1.0 if skid else T.oversteer
		var margin := 1 - minf(1.0, absf(a_lat) / maxf(0.1, a_max if a_lat >= 0 else -a_min))
		var gr := _grip_step(dt, va, skid, brake_k, mu, nR, a_lat, a_max, a_min)
		# the plain catch (tyre pulling back in line) only works with grip to pull with: a locked / spinning /
		# loose rear barely pulls, so the slide lives on in slip_w (the grip sim) instead of being snapped out
		var catch_k: float = (T.slipRecover * (0.25 + margin) + maxf(0.0, -signf(slip) * steer) * 8) * gr * gr
		var slip_rate := excess * share - (slip - _squirm) * catch_k + slip_w
		var slip_was := slip
		slip = clampf(slip + slip_rate * dt, -1.5, 1.5)
		course += course_rate * dt
		# the rear swings round the front: the front tyre holds its line, so the bike's BB moves sideways as
		# the heading turns against the travel (pivot gripPivot of the way from the BB to the front axle)
		var ds := slip - slip_was
		var pv: float = float(T.get("gripPivot", 0.7)) * (L - BB_REAR) * ds
		var hh := course + slip
		x += pv * sin(hh); z += pv * cos(hh)
		if flick_kick != 0.0:   # a body flick whips the bike round: most of it turns the travel, a little steps the rear out
			var fk := flick_kick * minf(1.0, dt * 10)
			flick_kick -= fk
			course += fk * 0.9; slip = clampf(slip + fk * 0.1, -T.slipMax * 0.8, T.slipMax * 0.8)
		if absf(v) < 1.2:
			var k := minf(1.0, dt * 6); course += slip * k; slip -= slip * k; slip_w -= slip_w * k
		# fakie: both sticks towards the pad's centre (left stick right, right stick left) swing the bike round to
		# face the way it travels: the travel flips at once, the drawn heading swings round (turn_off) in ~0.4 s
		if v < -0.5 and steer_input < -0.6 and flick_in > 0.6: _fakie_hold += dt
		else: _fakie_hold = 0.0
		if _fakie_hold > 0.1:
			_fakie_hold = 0.0
			course += PI; v = -v; turn_off = -PI; rev_cap = 3.0
			host.flash("SWITCH!")
		turn_off -= turn_off * minf(1.0, dt * 7.0)
		if absf(turn_off) < 0.01: turn_off = 0.0
		heading = course + slip + turn_off
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
		var sys_slip := wrapf(slip - air_tw, -PI, PI) + (air_yaw + stick_yaw) * dt
		var tw_t := clampf(-sys_slip, -T.airTwist, T.airTwist)
		air_tw_v += (60.0 * (tw_t - air_tw) - 12.0 * air_tw_v) * dt
		air_tw += air_tw_v * dt
		if absf(air_tw) > T.airTwist:
			air_tw = signf(air_tw) * T.airTwist; air_tw_v = 0.0
		var slip_new := wrapf(sys_slip + air_tw, -PI, PI)
		yaw_rate = wrapf(slip_new - slip, -PI, PI) / dt
		spin_acc += yaw_rate * dt
		slip = slip_new
		turn_off -= turn_off * minf(1.0, dt * 7.0)
		heading = course + slip + turn_off
		lat_a = 0; lat_m = 0; flick_kick = 0.0
		slip_w = 0.0; grip_r = 1.0; bar_catch += -bar_catch * minf(1.0, dt * 6)
	if not air:
		_pivot_step(dt, steer_input, brake_k)
	var roll_t: float = roll_keys * T.airRoll + air_stick.x * float(T.get("stickAirRoll", 0.75))
	var lean_t: float = (roll_t if absf(roll_t) > 0.03 else lean * 0.98) if air else clampf(atan(lat_a / G), -T.leanMax + minf(0.0, bk), T.leanMax + maxf(0.0, bk))
	var kL: float = T.leanIn if absf(steer_eff) > 0.01 else T.leanOut
	if air and air_stick.length() > 0.02: kL = 45.0   # the stick lays the bike over in the air (soft, no snap)
	if not air:
		# only the ground pushing on the tyres can change the lean: over a crest or an edge (tyres light) the
		# bike carries its lean on instead of snapping upright with the momentary lack of grip
		kL *= clampf(n_tot / G, 0.12, 1.0)
	lean_v += ((lean_t - lean) * kL - lean_v * 2 * sqrt(kL) * T.leanDamp) * dt
	lean += lean_v * dt
	# the body stick throws the bike over under the rider (the body stays upright: counter grows)
	var bl: float = lean * T.bikeLeanMul + (0.0 if air else flick * float(T.get("flickLean", 0.35)) * smooth01(va / 3.0))
	if not air:
		cap_bank = 0.0 if signf(bk) != signf(bl) else absf(bk)
	else:   # the bank's extra room is carried off the lip, fading over 2 s (the lean must not snap at take-off)
		cap_bank = maxf(0.0, cap_bank - dt * 0.5)
	var cap_b: float = T.bikeLeanCap + cap_bank
	bike_lean = cap_b * tanh(bl / cap_b)
	var lim_t := 9.0
	if not air and absf(bike_lean) > 0.05:
		# what matters for the tyre is its lean against the ground WHERE IT SWINGS TO, not gravity: leaned deep
		# toward ground that rises beside the bike (a trail's edge, the hillside, a berm's lip) the tyre went
		# into it and the drawn bike was shoved 25-38 cm up ("shoots up for a sec"). Look 0.3 / 0.5 m to the
		# lean side at both wheels: the bike leans at most groundLeanMax against the steepest rise there
		var sg := signf(bike_lean)
		var lx := -f.z * sg
		var lz := f.x * sg   # unit vector to the lean side
		var phi := -0.5
		for wo in [L - BB_REAR, -BB_REAR]:
			var wx: float = x + f.x * wo
			var wz: float = z + f.z * wo
			# the land itself (deck_height: no rock / log domes): passing a rock beside the wheel used to clamp
			# the lean down for a moment ("going over something resets the angle")
			var h0: float = terrain.deck_height(wx, wz)
			for d in [0.3, 0.5]:
				phi = maxf(phi, atan((terrain.deck_height(wx + lx * d, wz + lz * d) - h0) / d))
		lean_room = _or(lean_room, phi)
		lean_room += clampf(phi - lean_room, -3.0 * dt, 3.0 * dt)
		lim_t = maxf(0.25, float(T.get("groundLeanMax", 1.05)) - maxf(lean_room, -0.3))
	# the ground's limit on the lean opens / closes over a moment when the bike leaves / meets the ground: it used
	# to switch on and off in a single step (a 0.5-0.8 rad jump of the bike and the rider at take-off and landing)
	if air:
		lean_lim = minf(9.0, lean_lim + 2.5 * dt)
	elif since_land < 0.4:
		lean_lim = maxf(lim_t, lean_lim - 4.0 * dt)
	else:
		lean_lim = lim_t
	if lean_lim < 8.0:
		bike_lean = signf(bike_lean) * minf(absf(bike_lean), lean_lim)
	# the bike leans under the rider: the body always stays a little more upright than the bike (never
	# hangs inside it, or the inside leg cuts through the frame). The body leans ~70 % of the way the
	# rider + bike lean, so in a fast turn the bike tips well under a fairly upright rider
	counter = maxf(absf(bike_lean - lean * T.bodyLean), absf(bike_lean) * 0.2) * signf(bike_lean)
	# in the air the stick's lean is the rider's doing: they push the bike over with the legs and arms and
	# their body goes the other way a little (counter-lean), staying over the centre of mass
	if air:
		var wl := clampf(absf(air_stick.x) * 2.5, 0.0, 1.0)
		counter = lerpf(counter, bike_lean * (1.0 + float(T.get("stickBodyCounter", 0.25))), wl)
	rock = pedal_rock(crank, sprint, pedal, va, bike_rock)

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
			# the body stick moves the rider fore / aft on the ground too, further than the auto shift reaches
			var reach: float = R * float(T.get("stickShift", 1.7))
			var R2 := maxf(R, absf(body_in_s) * reach)   # stick idle: exactly the old limits
			if not air:
				xT = clampf(xT, -R, R) + body_in_s * reach; hT = clampf(hT, -R, R) + body_in_s * reach
			else:   # in the air the body shifts with the stick too (the bike tilts against it)
				xT += body_in_s * reach * 0.7; hT += body_in_s * reach * 0.7
			# a damped spring to where the rider wants to be, pushed by the bike's own speed changes:
			# the body carries on when the bike slows (braking, a landing, a root) and lags when it surges
			var a_body := 0.0
			if not is_nan(v_last) and not air:
				a_body = clampf((v - v_last) / maxf(dt, 1e-4), -40.0, 40.0)
			v_last = v
			var kx: float = T.bodyStiff
			var cx := 2 * sqrt(kx) * 0.75
			var push: float = -a_body * T.bodyInertia
			body_xv += (kx * (clampf(xT, -R2, R2) - body_x) - cx * body_xv + push) * dt
			body_x = clampf(body_x + body_xv * dt, -R2 * 1.4, R2 * 1.4)
			hip_v += (kx * (clampf(hT, -R2, R2) - hip_shift) - cx * hip_v + push) * dt
			hip_shift = clampf(hip_shift + hip_v * dt, -R2 * 1.6, R2 * 1.6)
		var tq: float = a_drive * T.loadHeight
		# sprint wheelie (like a motorbike): stamping on the pedals from slow, the rider hauls on the bars
		# with every stroke and the front comes up. Once it's up they keep pulling as long as sprint is
		# held (and stop balancing it), so it climbs on until it loops out; let go and it drops back down
		var pulling: bool = sprint > 0.5 and not air and throttle > 0.1 and not brake
		if pulling and not front_air:
			var lift_k: float = sprint * minf(throttle, 1.0) * slowness(v)
			tq += float(T.get("sprintLift", 11.0)) * lift_k * (0.55 + 0.45 * absf(sin(crank)))
		# once the stamp has the front up: the rider pops it to ~23 deg and balances it there; holding
		# sprint keeps pulling it higher (wheelieClimb rad/s) until it goes past the balance point and
		# loops out. Let go and it is set back down
		if pulling and (front_air or wheelie_up > 0.0):
			wheelie_up = maxf(wheelie_up, float(T.get("wheelieAngle", 0.4))) + float(T.get("wheelieClimb", 0.45)) * dt
		else:
			wheelie_up = maxf(0.0, wheelie_up - float(T.get("wheelieDrop", 1.6)) * dt)
		# manual: the body stick pulled well back on the ground lifts the front and balances it there (how
		# far back = how high); let go and it's set down. Only rolling, not at a lip throw
		# Pedalling it's a WHEELIE: from walking pace, higher (stickWheelie at full stick), the legs keep it up.
		var m_from: float = float(T.get("manualFrom", 0.4))
		var m_t := 0.0
		var pedalling := throttle > 0.1 and not brake
		if not air and v > (0.6 if pedalling else 1.5) and body_in < -m_from and throw_v <= 0.5:
			var top: float = float(T.get("stickWheelie", 0.6)) if pedalling else float(T.get("manualAngle", 0.32))
			m_t = top * smooth01((-body_in - m_from) / maxf(0.05, 1.0 - m_from))
		# up quick-ish (a pull on the bars + a pedal stroke), down at the set-down speed
		manual_up = move_toward(manual_up, m_t, (2.5 if m_t > manual_up else float(T.get("wheelieDrop", 1.6))) * dt)
		# style: a wheelie / manual held a while scores when it comes down
		if manual_up > 0.12 and front_air and not rear_air:
			wheelie_time += dt; wheelie_pedal = wheelie_pedal or pedalling
		elif manual_up < 0.05 and wheelie_time > 0.0:
			if wheelie_time > 1.0 and host.has_method("on_style"):
				host.on_style(roundi(wheelie_time * 220.0), "%s %.1f s" % ["WHEELIE" if wheelie_pedal else "MANUAL", wheelie_time])
			wheelie_time = 0.0; wheelie_pedal = false
		wheelie_up = maxf(wheelie_up, manual_up)
		if wheelie_up > 0.0:
			bal_max = maxf(bal_max, 30.0)   # the whole body holds a wheelie, not just the hands
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
			if cF != cR or (wheelie_up > 0.0 and cR):
				var ref := _or(nose_ref, _g_pitch) + (wheelie_up if cR else 0.0)
				var wk := 4.0 if (wheelie_up > 0.0 and cR) else 1.0   # holding a wheelie: the whole body works it
				alpha += clampf(30 * wk * (ref - pitch) - 9 * sqrt(wk) * pitch_v, -bal_max, bal_max)
			vy += (FF + FR - (press if (cF or cR) else 0.0) - mB * G - leg_f) / mB * h
			pitch_v += alpha * h
			if not cF and not cR and was_air:
				# in the air: no outside torque. The shared spin air_w only changes with the inertia (tuck),
				# the bike turns with it plus whatever tilt the rider gives it against their own body:
				# W / S tilt it on purpose, hands off the rider aims it at the landing slope
				var I_new: float = 1.0 - T.riderShare * T.tuckSpin * air_pull
				air_w *= air_inertia / I_new; air_inertia = I_new
				# arcade air control (old side-on bike games): holding W / S spins the bike at a steady rate,
				# letting go eases the spin out. The flight arc itself stays real; airArcade 0 = pure physics
				var arc: float = T.airArcade
				if arc > 0.0:
					if absf(flip_in) > 0.05:
						air_w += (flip_in * T.airSpinRate * spin_k - air_w) * minf(1.0, T.airSpinResp * h) * arc
					else:
						air_w *= 1.0 - minf(1.0, T.airSpinStop * h) * arc
				var tgt: float
				var kt_base := 70.0
				if absf(flip_in) > 0.05:
					tgt = flip_in * T.airTilt
				else:
					var hh := maxf(0.0, y - _g_y)
					var tg := (vy + sqrt(vy * vy + 2 * G * hh)) / G
					tgt = wrapf(_g_pitch - (pitch - air_tilt + air_w * minf(tg, 1.0)), -PI, PI)
					# hands off the rider doesn't snap the bike to the landing slope the moment he leaves the ground: he holds
					# the attitude he took off with for airAimDelay s, then eases the bike round softly, and reaches for the
					# landing (stiffer) only in the last moments
					# (a bike that has turned well away from the landing slope is brought back at once)
					var off_k := clampf((absf(tgt) - 0.3) / 0.3, 0.0, 1.0)
					var aim_k: float = maxf(maxf(smooth01((air_time - float(T.get("airAimDelay", 1.0))) / 0.5), land_prep), off_k)
					tgt *= aim_k
					kt_base = lerpf(lerpf(float(T.get("airAimSpeed", 14.0)), 45.0, off_k), 70.0, land_prep)
				tgt = clampf(tgt, -T.airTilt, T.airTilt)
				# right stick: the nose goes where it points, on top of the landing aim
				var st_t: float = float(T.get("stickAirTilt", 0.55))
				tgt += air_stick.y * st_t
				var t_lim: float = T.airTilt + absf(air_stick.y) * st_t
				# the rider's arms and legs move the bike: quick when they aim it at the landing on their own,
				# softer (it takes the whole body) when the stick swings it round
				var soft: float = clampf(air_stick.length() * 3.0 + absf(edge_s) * 2.0, 0.0, 1.0)
				var kt: float = lerpf(kt_base, 22.0, soft)
				air_tilt_v += (kt * (tgt - air_tilt) - 2.0 * sqrt(kt) * 0.85 * air_tilt_v) * h
				air_tilt += air_tilt_v * h
				if absf(air_tilt) > t_lim:
					air_tilt = signf(air_tilt) * t_lim
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
				probe_bottom += 1
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
				compress_v -= minf(1.5, slap * 0.25)   # (no camera shake: at speed it rattled all the time)
				if slap > 3.5: host.burst(Vector3(x + f.x * XF, _g_hf + 0.03, z + f.z * XF), 10, surf, 0.8)
		c_f = cF; c_r = cR
		if not now_air:
			# the rider's body turns with the bike, smoothed by the arms and legs
			body_pw += (pitch_v - body_pw) * minf(1.0, dt * 4)
		if now_air and not was_air:
			if since_land < 0.5 and OS.get_environment("BMX_TRICK") != "": print("BOUNCE %.2fs after landing vy=%.2f pitch=%.2f" % [since_land, vy, pitch])   # tests
			air = true; air_time = 0; flip_acc = 0.0; spin_acc = 0.0; style_air = 0.0
			# rider + bike fly off at the speed of their shared centre of mass: a bike kicked up by a roller
			# while the body (on soft legs) lags behind doesn't launch the rider with it. In the air the
			# two then move together (the legs only shift them about that centre)
			if coupled and not is_nan(body_v): vy = PHI * body_v + mB * vy
			if pump_lift > 0.0: vy += pump_lift; pump_lift = 0.0
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
			_rev_land = false; _land_fix = false
			_land_trick(at)
			if _land_fix:
				# the tyres grab the nearer axis: the bike keeps its heading, the travel is dragged round to within
				# slipMax of it (what's left decays as a normal slide), speed lost by the angle dragged through.
				# Past 90 deg that axis is backwards: speed runs negative (fakie)
				var base: float = wrapf(slip - PI, -PI, PI) if _rev_land else wrapf(slip, -PI, PI)
				var keep: float = minf(absf(base), 0.9 * T.slipMax)
				var sl: float = signf(base) * keep
				var drag_a: float = absf(base) - keep
				v = (-v if _rev_land else v) * cos(minf(drag_a, 1.4))
				course = heading - sl; slip = sl; slip_w = 0.0; turn_off = 0.0
				if _rev_land: rev_cap = maxf(3.0, -v)
				_rev_land = false; _land_fix = false
			air = false; since_land = 0; land_jolt = 0.0
			body_v = vy_in
			body_pw = air_w
			nose_ref = _g_pitch
			# the velocity into the slope is stopped by the tyres, suspension and legs; along the slope it carries on
			v = v * cos(_g_pitch) + vy_in * sin(_g_pitch)
			compress_v -= minf(2.2, impact * 0.35) + (minf(1.2, impact * 0.2 + 0.4) if back_land else 0.0)
			if host.susp != null: host.susp.land(maxf(0.0, -vy_in) * cos(_g_pitch) * 0.5 + impact * (0.57 if back_land else 0.4), front_air, rear_air)
			if OS.get_environment("BMX_TRICK") != "": print("LAND impact=%.1f back=%s v_after=%.1f" % [impact, back_land, v])   # tests
			# only a real landing shakes the camera (rollers at speed give lots of tiny hops)
			if at > 0.4 and impact > 3.0: shake = maxf(shake, minf(0.2, (impact - 3.0) * 0.04))
			if at > 0.15: host.burst(Vector3(x, y + 0.03, z), roundi(10 + minf(30, impact * 6)), surf, 0.8 + minf(1.5, impact * 0.25))
			if at > 0.45 and impact < 5: flow_up()
			host.on_landing(at, impact)
		# ride roughness: the body's vertical acceleration vs the ground's under it (riding, not landing)
		var gy_now := hrC + (hfC - hrC) * (BB_REAR / L)
		if not air and not was_air and since_land > 0.6 and not is_nan(probe_vy) and not is_nan(probe_gy[1]):
			var ay := (vy - probe_vy) / dt
			var ag: float = (gy_now - 2.0 * probe_gy[0] + probe_gy[1]) / (dt * dt)
			probe_acc2 += ay * ay; probe_g2 += ag * ag; probe_n += 1
		probe_vy = vy; probe_gy = [gy_now, probe_gy[0]]
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
		# the pump: the legs drive up off the lip (through the rider + bike centre of mass at take-off). Hold
		# Space through the transition (pumping into it) for the full push; on his own the rider only gives
		# autoPump of it
		var pump: float = T.autoPump + (1.0 - T.autoPump) * clampf(load * 1.4, 0.0, 1.0)
		pop_fired = true; body_v = _or(body_v, 0) + T.popKick * prep * pump * (1.0 + 0.4 * charge); compress_v += 2.5 * prep * pump
		# the legs keep driving to the end of their stroke: the ground pushes back, lifting rider + bike
		pump_lift = T.popKick * 0.9 * prep * pump * (1.0 + 0.4 * charge)
		if OS.get_environment("BMX_TRICK") != "": print("POP prep=%.2f pump=%.2f load=%.2f lift=%.2f" % [prep, pump, load, pump_lift])   # tests
	if not air and lip_t == INF: pop_fired = false
	if not air: pump_lift *= exp(-dt * 1.2)   # the drive fades if the lip is still a while off
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
	if v < -0.05 and not air and not skid:
		# rolling backwards the freewheel's pawls catch: the chain turns the cranks back with the wheel
		crank += v / RWR / (2.78 * gear_k() * T.topSpeed) * dt
	elif pedal > 0.05:
		crank += crank_rate(w, gear_k(), T.topSpeed, sprint) * pedal * dt
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

	skid_fx = skid or spin > 0.3 or (not air and va > 1.5 and (absf(slip - _squirm) > 0.1 or (grip_r < 0.45 and absf(slip_w) > 0.3)))
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
	# Graded landing zone instead of a hard cut: within ~60 deg of the travel it is a normal landing; past that
	# the bike lands sideways-ish and the tyres grab the nearer axis (forward, or backwards = fakie past 90 deg),
	# dragging the travel round and scrubbing speed by how far (applied at touch-down, see _ride_step)
	var a_s := absf(slip)
	if a_s > LAND_CONE:
		_rev_land = a_s > PI * 0.5
		_land_fix = true
		host.flash("FAKIE!" if _rev_land else "SKETCHY!")
	var flips := roundi(absf(flip_acc) / TAU)
	var turns := int((absf(spin_acc) + 0.6) / TAU)   # flat spins landed facing forward again (within ~35 deg): 360, 720...
	if flips >= 1 or turns >= 1:
		var trick := ""
		if turns >= 1: trick = "%d" % (turns * 360)
		if flips >= 1:
			var kind := "BACKFLIP" if flip_acc > 0 else "FRONTFLIP"
			trick = (trick + " " if trick != "" else "") + (["", "", "DOUBLE ", "TRIPLE "][mini(flips, 3)] if flips > 1 else "") + kind
		host.flash(trick + "!")
		if host.has_method("on_trick"): host.on_trick(trick)
		flow_up()
	_style_points(at, flips, turns)

## style points for a landed jump: air time, spins, flips, tweaking the bike about with the stick, and a
## clean (straight) landing bonus. The HUD chains them into combos and drops them if the rider goes down
func _style_points(at: float, flips: int, turns: int) -> void:
	if at < 0.35 or not host.has_method("on_style"): return
	var pts := roundi(at * 250.0) + turns * 600 + flips * 1000 + roundi(minf(style_air, 3.0) * 400.0)
	var parts := []
	if turns >= 1: parts.append("%d" % (turns * 360))
	if flips >= 1: parts.append(("%dx " % flips if flips > 1 else "") + ("BACKFLIP" if flip_acc > 0 else "FRONTFLIP"))
	if style_air > 0.35: parts.append("TWEAK")
	if parts.is_empty(): parts.append("BIG AIR" if at > 1.0 else "AIR")
	var clean := absf(wrapf(slip, -PI, PI)) < 0.2 and absf(wrapf(pitch - _g_pitch, -PI, PI)) < 0.15
	if clean:
		pts = roundi(pts * 1.5)
		parts.append("CLEAN")
	host.on_style(pts, " + ".join(parts))

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

## Tyre grip sim (ground only). The bike's yaw against its travel (slip) is a real second-order motion:
## the rear tyre's sideways grip pulls it back in line, the front tyre (ahead of the centre of mass) pushes
## it further round, the rider catches it (countersteer + weight). The rear's sideways grip is what's left
## of its friction circle after braking / driving, times the load on it and the patch of ground under it:
## lock the rear and the front wins -> the rear swings out and fishtails until let go / caught; wheelspin
## steps it out in a turn; loose patches, bumps and pedal strokes keep nudging it so the bike never runs
## dead straight. Sets slip_w, grip_r, loose, _squirm, bar_catch; returns grip_r (0..~1.2).
func _grip_step(dt: float, va: float, skid: bool, brake_k: float, mu: float, nR: float, a_lat: float, a_max: float, a_min: float) -> float:
	if _grip_noise == null:
		_grip_noise = FastNoiseLite.new()
		_grip_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		_grip_noise.frequency = 0.22; _grip_noise.fractal_octaves = 2; _grip_noise.seed = 913
		_grip_rng.seed = 4711
	var spd := smooth01((va - 1.0) / 5.0)
	# the ground under the rear tyre: loose patches a few metres across (gravel, dust over hardpack)
	var rx := x - cos(heading) * BB_REAR
	var rz := z + sin(heading) * BB_REAR
	var s_loose: float = 1.0 if surf == 0 else 0.2 if surf == 1 else 0.7 if surf == 2 else 1.4
	var n := 0.5 + 0.5 * _grip_noise.get_noise_2d(rx, rz)
	loose = smooth01((n - 0.4) / 0.45) * s_loose
	var patch: float = 1.0 - float(T.get("gripLoose", 0.5)) * 0.4 * loose
	# the rear tyre's friction circle: what braking / driving uses along the bike isn't there sideways
	var lock: float = clampf(brake_k * 1.4 - 0.4, 0.0, 1.0) if skid else 0.0
	var r_cap := maxf(0.3, mu * nR)
	var use := clampf(absf(a_drive) / r_cap, 0.0, 1.0)
	use = maxf(use, lock)
	if spin > 0.0: use = maxf(use, 0.85 + 0.15 * spin)
	var lat_k := sqrt(maxf(0.0, 1.0 - use * use))
	lat_k = lerpf(lat_k, 0.12, lock)   # a sliding tyre still drags a little sideways
	var load_r := clampf(nR / (G * SH_R), 0.0, 1.4)   # a light rear (bumps, nose-heavy braking) grips less
	var g := clampf(lat_k * patch * sqrt(load_r), 0.0, 1.2)
	grip_r = g
	# tyre squirm: in a turn the tyres run a few degrees of slip angle, more as they near the limit
	var lim := a_max if a_lat >= 0.0 else -a_min
	var u_lat := clampf(a_lat / maxf(0.1, lim), -1.0, 1.0)
	_squirm = float(T.get("gripSquirm", 1.0)) * (0.025 * u_lat + 0.07 * u_lat * u_lat * u_lat) * spd * (1.0 + 0.5 * loose)
	# yaw against the travel: rear tyre stiffness vs the front pushing it round, the rider catching it
	var catch_r: float = float(T.get("gripCatch", 0.6))
	var k_r := 15.0 * g
	var k_f: float = 18.0 * float(T.get("gripRearLock", 1.0)) * spd
	var k := k_r - k_f + 4.0 * catch_r
	var c := 2.2 + 3.0 * g + 1.5 * catch_r
	var acc := -k * (sin(slip) - _squirm) - c * slip_w
	# wheelspin in a turn: the spinning rear is thrown out of the turn
	var pw: float = float(T.get("gripPower", 1.0))
	acc += pw * spin * signf(a_lat) * 6.0 * spd
	# pedal strokes on loose ground: each stamp nudges the rear (alternating sides)
	acc += pw * sin(crank * 2.0) * clampf(a_drive / r_cap, 0.0, 1.0) * (1.25 - minf(1.0, g)) * 3.0 * spd
	slip_w += acc * dt
	# bumps: rough ground (suspension working hard, smoothed over ~0.2 s) makes a rear that's cornering near
	# its limit drift out of the turn - a gentle push, never a kick (instant kicks per rock made the bike
	# twitch about on rocky ground). The bump's real effect is already in load_r: an unloaded rear grips less
	var bmp: float = float(T.get("gripBumps", 1.0))
	var jolt := minf(absf(compress_v - _grip_cv) / maxf(dt, 1e-4), 60.0)
	_grip_cv = compress_v
	_grip_rough += (jolt - _grip_rough) * minf(1.0, dt * 5.0)
	var lim_k := smooth01((absf(u_lat) - 0.5) / 0.5)   # only near the grip limit
	slip_w += bmp * signf(a_lat) * lim_k * minf(_grip_rough / 30.0, 1.0) * 1.2 * spd * dt
	# chatter: pebbles, ruts - a small smooth random wander, bigger on loose ground / sliding
	slip_w += bmp * _grip_rng.randfn(0.0, 1.0) * sqrt(dt) * spd * (0.1 + 0.45 * loose + 0.8 * (1.0 - minf(1.0, g)))
	slip_w = clampf(slip_w, -4.0, 4.0)
	# drawn: the rider steers into the slide (front pointing along the travel) - catch strength sets how much
	var bc := clampf(-(slip - _squirm) * (0.5 + 0.4 * catch_r) - slip_w * 0.06, -0.55, 0.55) * spd
	bar_catch += (bc - bar_catch) * minf(1.0, dt * 14.0)
	return g

func _local_slope(f: Vector3, xx: float, R: float, cp0: float) -> float:
	return atan((_wheel_ground(f, xx + 0.05 / cp0, R, cp0) - _wheel_ground(f, xx - 0.05 / cp0, R, cp0)) / 0.1)

func flow_up() -> void:
	flow = minf(FLOW_MAX, floorf(flow) + 1); flow_t = 0

## Every float field finite? (the frame loop's safety net)
func is_sane() -> bool:
	for k in ["x", "z", "y", "vy", "v", "heading", "pitch", "pitch_v", "lean", "lean_v", "steer", "slip", "slip_w", "course", "compress", "compress_v",
			"body_x", "body_xv", "hip_shift", "hip_v", "air_lean", "air_pull", "a_drive"]:
		if not is_finite(get(k)):
			return false
	return true

## after a bad step: zero the body / rider state so a NaN there can't keep poisoning the ride
func reset_body() -> void:
	body_v = 0; body_y = y; body_x = 0; body_xv = 0; hip_shift = 0; hip_v = 0; v_last = NAN
	air_lean = 0; air_pull = 0; a_drive = 0; pitch_v = 0; compress_v = 0; lean_v = 0
