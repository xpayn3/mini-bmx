class_name PadRumble
extends RefCounted
## Layered controller vibration for the ride (Xbox: the left grip's heavy motor = "strong", low and
## thumpy; the right grip's light motor = "weak", a fast buzz). Every physics step `update` reads the
## bike's state and mixes the effects in EFFECTS, each with its own strength in Settings › Controller:
##   GROUND  road (a fine buzz by surface + speed: trail hums, grass / dirt coarser, sand soft), bumps (each
##           wheel's own up / down kick: rocks, roots, lips, a front wheel slapping down), bottom (the
##           suspension bottoming out = a thump), water (a slow heavy drag)
##   TYRES   slip (sideways scrub: a chatter that grows with the slide + speed, the rear letting go in
##           fishtails / whips / drifts), spin (wheelspin whine), brake (judder), skid (locked-rear rattle)
##   RIDER   pedal (a push per stroke sprinting), takeoff (a pop off the lip), land (by impact)
##   HITS    smash (fences, cacti, bonks), crash (the moment you go down), tumble (each slam of the ragdoll + its slide)
## In the air everything ground-borne fades out: the silence is part of the feel.
## Effects are joined like probabilities (1 - (1-a)(1-b)...) so they stack without clipping.
## Motors (Settings): master strength, heavy / light motor strength, the lowest speed a motor turns at
## (`rumble_floor`), how fast the slip chatter pulses (`rumble_chatter`).
## Moving a slider plays that effect (`PadRumble.preview`), so you feel what you're setting.

const SEND_EVERY := 1.0 / 60.0   # real seconds between motor updates
const HOLD := 0.12               # each update keeps the motors on this long (they stop by themselves if the game freezes)

## [settings key, label, tip, group]; every key defaults to 1.0 (Settings.DEFAULTS)
const EFFECTS := [
	["rumble_road", "Ground buzz", "The surface under the tyres: trail hum, coarse grass and dirt, soft sand. Grows with speed", "GROUND"],
	["rumble_bumps", "Bumps", "Each wheel's own kick over rocks, roots and lips; the front in the right grip, the rear in the left", "GROUND"],
	["rumble_bottom", "Bottoming out", "The suspension using all its travel", "GROUND"],
	["rumble_water", "Water", "A slow heavy drag wading through water", "GROUND"],
	["rumble_slip", "Tyre slip", "Tyres scrubbing sideways, the rear stepping out, whips and drifts", "TYRES"],
	["rumble_spin", "Wheelspin", "The rear spinning up under power", "TYRES"],
	["rumble_brake", "Braking", "A light judder under hard braking", "TYRES"],
	["rumble_skid", "Skids", "A coarse rattle with the rear locked and sliding", "TYRES"],
	["rumble_pedal", "Pedal strokes", "A push on every stroke while sprinting", "RIDER"],
	["rumble_takeoff", "Take-off", "The pop as the wheels leave a lip", "RIDER"],
	["rumble_land", "Landings", "Touch-down after a jump, harder the bigger the hit", "RIDER"],
	["rumble_smash", "Smashes", "Riding through fences, cacti, billboards; bonks", "HITS"],
	["rumble_crash", "Crash", "The moment you go down", "HITS"],
	["rumble_tumble", "Tumbling", "Every slam of the body while it tumbles, and its slide", "HITS"],
]
const GROUPS := {"GROUND": "GROUND", "TYRES": "TYRES + BRAKES", "RIDER": "RIDER + JUMPS", "HITS": "HITS + CRASHES"}

var game   # Game
var weak := 0.0       # this step's mix, before the settings' strength (tests read these)
var strong := 0.0
var layers := {}      # per effect [weak, strong] (tests)

var _k := {}                    # per effect strength this step
var _hits: Array = []           # transients: [weak, strong, secs, age]
var _vw_f := NAN; var _vw_r := NAN
var _bump_f := 0.0; var _bump_r := 0.0
var _bottom := 0
var _was_air := false
var _shake := 0.0
var _crank_half := 0
var _surf_k := Vector2.ZERO     # road texture per surface, eased between surfaces
var _t := 0.0
var _ph := 0.0                  # slip chatter phase
var _noise := FastNoiseLite.new()
var _rag_v := Vector3.ZERO; var _rag_on := false
var _send_t := 0.0; var _sent := Vector2(-1, -1)
var _crashed := false

# tests (BMX_RUMBLE_PROBE): per effect peak and mean
var probe := Env.s("BMX_RUMBLE_PROBE") != ""
var _pr_t := 0.0
var _pr_peak := {}
var _pr_sum := {}
var _pr_n := 0

func _init(g) -> void:
	game = g
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_noise.frequency = 1.0
	_noise.seed = 77

static func strength(key: String) -> float:
	return float(Settings.get_v(key)) if Settings.DEFAULTS.has(key) else 1.0

## a one-off kick that fades out over secs (quadratic tail: punchy start, soft end), scaled by its effect's strength
func impulse(w: float, s: float, secs: float, key := "") -> void:
	var k := strength(key) if key != "" else 1.0
	if k <= 0.0: return
	if _hits.size() > 24: _hits.pop_front()
	_hits.append([clampf(w * k, 0, 1), clampf(s * k, 0, 1), maxf(secs, 0.02), 0.0])
	if probe: layers[key] = [w * k, s * k]

## landing after air_time s with impact (m/s into the slope)
func landing(air_time: float, impact: float) -> void:
	if air_time < 0.12: return
	var k := clampf((impact - 0.5) / 9.0, 0.0, 1.0)
	impulse(0.25 + 0.6 * k, 0.15 + 0.85 * k, 0.1 + 0.3 * k, "rumble_land")          # the touch-down itself
	if k > 0.35: impulse(0.0, (k - 0.35) * 0.8, 0.45, "rumble_land")                 # the frame / body settling after a big one

func crash() -> void:
	impulse(1.0, 1.0, 0.35, "rumble_crash")
	impulse(0.3, 0.7, 0.9, "rumble_crash")

func stop() -> void:
	_hits.clear()
	if _sent != Vector2.ZERO: _send(0.0, 0.0, true)

static func _join(a: float, b: float) -> float:
	return 1.0 - (1.0 - clampf(a, 0, 1)) * (1.0 - clampf(b, 0, 1))

func _layer(key: String, w: float, s: float) -> void:
	var k: float = _k.get(key, 1.0)
	weak = _join(weak, w * k)
	strong = _join(strong, s * k)
	if probe: layers[key] = [w * k, s * k]

func update(dt: float, inp: Dictionary) -> void:
	_t += dt
	weak = 0.0; strong = 0.0
	if probe: layers.clear()
	for e in EFFECTS: _k[e[0]] = strength(e[0])
	var st: BikePhysics = game.phys
	if st.crash_on:
		if not _crashed: crash()
		_crashed = true
		_crash_layers(dt)
	else:
		_crashed = false
		_rag_on = false
		_ride_layers(dt, st, inp)
	# transients (already scaled by their effect)
	var hw := 0.0; var hs := 0.0
	var i := 0
	while i < _hits.size():
		var h: Array = _hits[i]
		h[3] += dt
		var f: float = 1.0 - h[3] / h[2]
		if f <= 0.0:
			_hits.remove_at(i)
			continue
		f *= f
		hw = _join(hw, h[0] * f); hs = _join(hs, h[1] * f)
		i += 1
	weak = _join(weak, hw); strong = _join(strong, hs)
	if probe: _probe_step(dt)
	_output()

func _ride_layers(dt: float, st: BikePhysics, inp: Dictionary) -> void:
	var va := absf(st.v)
	var spd := clampf(va / 14.0, 0.0, 1.0)
	var ground := 0.0 if st.air else 1.0
	var in_water: bool = st.surf == 2
	# GROUND buzz: [weak, strong] per surface at full speed (0 ground / grass, 1 trail, 2 water, 3 dry / sand)
	var sk: Vector2 = [Vector2(0.30, 0.14), Vector2(0.20, 0.07), Vector2(0.04, 0.22), Vector2(0.12, 0.14)][clampi(st.surf, 0, 3)]
	sk *= 0.6 + 0.4 * st.loose / 1.4 if st.surf != 2 else 1.0
	_surf_k = _surf_k.lerp(sk, minf(1.0, dt * 6.0))
	# texture: a fast wander (gravel / dirt grain) whose rate follows the speed, so slow = separate pebbles
	var n1 := _noise.get_noise_2d(st.distance * 3.1, 0.0)
	var n2 := _noise.get_noise_2d(st.distance * 0.7, 40.0)
	var road_s := sqrt(spd) * ground
	_layer("rumble_road", _surf_k.x * road_s * (0.55 + 0.45 * n1), _surf_k.y * road_s * (0.7 + 0.3 * n2))
	# BUMPS: each wheel's vertical acceleration past what smooth rolling gives
	if is_nan(_vw_f) or st.air or not st.w_init:
		_vw_f = st.vw_f; _vw_r = st.vw_r
	var af := absf(st.vw_f - _vw_f) / maxf(dt, 1e-4)
	var ar := absf(st.vw_r - _vw_r) / maxf(dt, 1e-4)
	_vw_f = st.vw_f; _vw_r = st.vw_r
	var kf := clampf((af - 25.0) / 220.0, 0.0, 1.0) * ground
	var kr := clampf((ar - 25.0) / 220.0, 0.0, 1.0) * ground
	_bump_f = maxf(_bump_f * exp(-dt * 16.0), kf)
	_bump_r = maxf(_bump_r * exp(-dt * 14.0), kr)
	# the front is felt more in the hands (light buzz), the rear through the frame (heavy motor)
	_layer("rumble_bumps", _join(0.75 * _bump_f, 0.35 * _bump_r), _join(0.35 * _bump_f, 0.85 * _bump_r))
	if st.probe_bottom > _bottom and not st.air:   # bottomed the suspension
		impulse(0.4, 0.9, 0.16, "rumble_bottom")
	_bottom = st.probe_bottom
	# TYRE SLIP: sideways scrub (travel vs heading past the tyres' normal slip angle) + the rear letting go
	var slide := maxf(0.0, absf(st.slip) - 0.06)
	var loose_rear := (1.0 - minf(1.0, st.grip_r)) * minf(1.0, absf(st.slip_w) * 0.8)
	var sl := clampf(slide * 2.2 + loose_rear * 0.6 + st.whip * 0.5, 0.0, 1.0) * ground * clampf((va - 1.0) / 6.0, 0.0, 1.0)
	# chatter: on / off pulses whose rate rises with speed (the tyre skipping over the ground), deeper on loose ground
	_ph += dt * (9.0 + va * 0.9) * float(Settings.get_v("rumble_chatter"))
	var chat := 0.55 + 0.45 * signf(sin(_ph * TAU))
	_layer("rumble_slip", sl * (0.35 + 0.45 * chat) * (0.8 + 0.3 * st.loose), sl * sl * (0.25 + 0.35 * chat))
	# wheelspin: a high whine
	_layer("rumble_spin", clampf(st.spin, 0.0, 1.0) * 0.4 * ground, clampf(st.spin, 0.0, 1.0) * 0.05 * ground)
	# BRAKE: judder while rolling; SKID: a coarse rattle once the rear locks
	var brake: float = float(inp.get("brake", 0.0))
	var bk := brake * clampf(va / 8.0, 0.0, 1.0) * ground
	_layer("rumble_brake", bk * 0.06 * (0.8 + 0.2 * sin(_t * 70.0)), bk * 0.03)
	var skid: float = (1.0 if st.skid_fx and brake > 0.5 else 0.0) * clampf(va / 5.0, 0.0, 1.0) * ground
	var rattle := 0.6 + 0.4 * _noise.get_noise_2d(_t * 40.0, 90.0)
	_layer("rumble_skid", skid * 0.35 * rattle, skid * 0.3 * rattle)
	# PEDAL: each stroke while sprinting (two per crank turn)
	var half := int(floor(st.crank / PI))
	if half != _crank_half and not st.air and st.sprint > 0.3 and st.pedal > 0.3:
		impulse(0.0, 0.10 + 0.12 * st.sprint, 0.09, "rumble_pedal")
	_crank_half = half
	# WATER: a heavy slow drag pulsing with the wading
	if in_water and not st.air:
		_layer("rumble_water", 0.0, (0.12 + 0.1 * sin(_t * 7.0)) * spd)
	# TAKE-OFF pop, SMASHES (the physics raise its shake on bonks / smashes)
	if st.air and not _was_air:
		var vk := clampf(st.vy / 4.0, 0.2, 1.0)
		impulse(0.3 * vk, 0.25 * vk, 0.08, "rumble_takeoff")
	_was_air = st.air
	if st.shake > _shake + 0.05:
		impulse(0.6, minf(1.0, st.shake * 2.5), 0.25, "rumble_smash")
	_shake = st.shake

## TUMBLING: every slam of the ragdoll on the ground + a rough slide
func _crash_layers(dt: float) -> void:
	var rd = game.ragdoll
	if rd == null or not rd.active or rd.p.is_empty() or rd.q.size() != rd.p.size(): return
	var h: float = maxf(rd.last_h, 1e-4)
	var c := Vector3.ZERO
	var lo := 1e9
	for k in rd.p.size():
		c += (rd.p[k] - rd.q[k]) / h
		lo = minf(lo, rd.p[k].y)
	c /= rd.p.size()
	if _rag_on:
		var jolt := (c - _rag_v).length() / maxf(dt, 1e-3)
		if jolt > 25.0: impulse(clampf(jolt / 160.0, 0.2, 0.9), clampf(jolt / 120.0, 0.25, 1.0), 0.18, "rumble_tumble")
	_rag_v = c; _rag_on = true
	var pp: Vector3 = rd.p[0]
	var on_ground: float = 1.0 if lo - game.terrain.height(pp.x, pp.z) < 0.35 else 0.0
	var hs := Vector2(c.x, c.z).length()
	var g := 0.6 + 0.4 * _noise.get_noise_2d(_t * 30.0, 7.0)
	_layer("rumble_tumble", clampf(hs / 8.0, 0.0, 0.5) * on_ground * g, clampf(hs / 10.0, 0.0, 0.35) * on_ground)

func _output() -> void:
	var m := motors(weak, strong)
	_send(m.x, m.y, false)

## 0..1 mix -> motor speeds (x light / weak, y heavy / strong) after the master + per-motor strength;
## nothing stays nothing, the faintest effect still just turns the motor (rumble_floor)
static func motors(w: float, s: float) -> Vector2:
	if not Settings.get_v("rumble"): return Vector2.ZERO
	var k := float(Settings.get_v("rumble_strength"))
	return Vector2(_motor(w * k * float(Settings.get_v("rumble_light"))), _motor(s * k * float(Settings.get_v("rumble_heavy"))))

static func _motor(x: float) -> float:
	if x < 0.008: return 0.0
	return lerpf(float(Settings.get_v("rumble_floor")), 1.0, clampf(x, 0.0, 1.0))

func _send(w: float, s: float, force: bool) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	var same := absf(w - _sent.x) < 0.01 and absf(s - _sent.y) < 0.01
	if not force and same and (w == 0.0 and s == 0.0): return   # already off
	if not force and same and now - _send_t < HOLD * 0.5: return
	if not force and not same and now - _send_t < SEND_EVERY: return
	_send_t = now
	_sent = Vector2(w, s)
	for j in Input.get_connected_joypads():
		if w == 0.0 and s == 0.0: Input.stop_joy_vibration(j)
		else: Input.start_joy_vibration(j, w, s, HOLD)

# ---------------------------------------------------------------------------------------------------
## Settings: play a short sample of one effect (or the motors' settings) on the pad, at its current
## strength. A new preview replaces the one playing. Runs on real time, also while paused.
static var _pv: Preview = null
static func preview(tree: SceneTree, key: String) -> void:
	if tree == null: return
	if _pv == null or not is_instance_valid(_pv):
		_pv = Preview.new()
		_pv.process_mode = Node.PROCESS_MODE_ALWAYS
		tree.root.add_child(_pv)
	_pv.play(key)

class Preview extends Node:
	const LEN := 1.2
	var key := ""
	var t := -1.0
	var _last := 0
	var _noise := FastNoiseLite.new()
	var _sent := false

	func _init() -> void:
		_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
		_noise.frequency = 1.0

	func play(k: String) -> void:
		key = k; t = 0.0; _sent = false; _last = Time.get_ticks_usec()

	func _process(_dt: float) -> void:
		if t < 0.0: return
		var now := Time.get_ticks_usec()
		var dt := minf((now - _last) / 1e6, 0.1)
		_last = now
		t += dt
		if t > LEN:
			t = -1.0
			for j in Input.get_connected_joypads(): Input.stop_joy_vibration(j)
			if Env.s("BMX_RUMBLE_PROBE") != "": print("RUMBLE preview %s done" % key)
			return
		var ws := _sample(key, t)
		var k := PadRumble.strength(key) if key.begins_with("rumble_") and PadRumble._is_effect(key) else 1.0
		var m := PadRumble.motors(ws.x * k, ws.y * k)
		for j in Input.get_connected_joypads():
			if m == Vector2.ZERO: Input.stop_joy_vibration(j)
			else: Input.start_joy_vibration(j, m.x, m.y, 0.1)
		if Env.s("BMX_RUMBLE_PROBE") != "" and not _sent and m != Vector2.ZERO:
			_sent = true
			print("RUMBLE preview %s at %.2fs motors=%.2f/%.2f" % [key, t, m.x, m.y])

	## the effect's pattern at time s: Vector2(weak, strong) before its strength
	func _sample(k: String, s: float) -> Vector2:
		var fade := 1.0 - smoothstep(LEN - 0.25, LEN, s)
		var n := 0.55 + 0.45 * _noise.get_noise_1d(s * 45.0)
		match k:
			"rumble_road": return Vector2(0.22 * n, 0.08 * (0.7 + 0.3 * _noise.get_noise_1d(s * 9.0))) * fade
			"rumble_bumps": return _kicks(s, [0.1, 0.38, 0.55, 0.9], 0.12, Vector2(0.6, 0.8))
			"rumble_bottom": return _kicks(s, [0.1], 0.16, Vector2(0.4, 0.9))
			"rumble_water": return Vector2(0.0, 0.12 + 0.1 * sin(s * 7.0 * TAU / 6.28)) * fade
			"rumble_slip":
				var chat := 0.55 + 0.45 * signf(sin(s * 16.0 * float(Settings.get_v("rumble_chatter")) * TAU))
				var sl := 0.7 * sin(PI * clampf(s / LEN, 0, 1))
				return Vector2(sl * (0.35 + 0.45 * chat), sl * sl * (0.25 + 0.35 * chat))
			"rumble_spin": return Vector2(0.4, 0.05) * fade
			"rumble_brake": return Vector2(0.06 * (0.8 + 0.2 * sin(s * 70.0)), 0.03) * 3.0 * fade
			"rumble_skid": return Vector2(0.35, 0.3) * n * fade
			"rumble_pedal": return _kicks(s, [0.1, 0.35, 0.6, 0.85], 0.09, Vector2(0.0, 0.2))
			"rumble_takeoff": return _kicks(s, [0.1], 0.08, Vector2(0.3, 0.25))
			"rumble_land": return _kicks(s, [0.1], 0.3, Vector2(0.65, 0.8))
			"rumble_smash": return _kicks(s, [0.1], 0.25, Vector2(0.6, 0.75))
			"rumble_crash": return _join2(_kicks(s, [0.05], 0.35, Vector2(1, 1)), _kicks(s, [0.05], 0.9, Vector2(0.3, 0.7)))
			"rumble_tumble": return _join2(_kicks(s, [0.1, 0.45, 0.7], 0.18, Vector2(0.6, 0.8)), Vector2(0.3, 0.2) * n * fade)
			"rumble_light": return Vector2(0.5, 0.0) * fade
			"rumble_heavy": return Vector2(0.0, 0.5) * fade
			"rumble_floor": return Vector2(0.02, 0.02) * fade   # the faintest effect: what the floor alone feels like
			"rumble_chatter": return _sample("rumble_slip", s)
		return _kicks(s, [0.1], 0.3, Vector2(0.6, 0.6))   # master switch / strength

	func _kicks(s: float, at: Array, secs: float, amp: Vector2) -> Vector2:
		var out := Vector2.ZERO
		for a in at:
			var f: float = 1.0 - (s - a) / secs
			if s >= a and f > 0.0: out = _join2(out, amp * f * f)
		return out

	func _join2(a: Vector2, b: Vector2) -> Vector2:
		return Vector2(PadRumble._join(a.x, b.x), PadRumble._join(a.y, b.y))

static func _is_effect(key: String) -> bool:
	for e in EFFECTS:
		if e[0] == key: return true
	return false

func _probe_step(dt: float) -> void:
	_pr_n += 1
	for key in layers:
		var v: float = maxf(layers[key][0], layers[key][1])
		_pr_peak[key] = maxf(_pr_peak.get(key, 0.0), v)
		_pr_sum[key] = _pr_sum.get(key, 0.0) + v
	_pr_t += dt
	if _pr_t >= 0.25:
		_pr_t = 0.0
		var st: BikePhysics = game.phys
		var parts := []
		for key in layers:
			parts.append("%s=%.2f/%.2f" % [key.trim_prefix("rumble_"), layers[key][0], layers[key][1]])
		var m := motors(weak, strong)
		print("RUMBLE t=%.2f v=%.1f surf=%d air=%s slip=%.2f mix=%.2f/%.2f motor=%.2f/%.2f  %s" % [_t, st.v, st.surf, st.air, st.slip, weak, strong, m.x, m.y, " ".join(parts)])

func probe_summary() -> String:
	var parts := []
	for key in _pr_peak:
		parts.append("%s peak=%.2f mean=%.3f" % [key.trim_prefix("rumble_"), _pr_peak[key], _pr_sum[key] / maxf(1, _pr_n)])
	return "RUMBLESUM steps=%d  %s" % [_pr_n, "  |  ".join(parts)]
