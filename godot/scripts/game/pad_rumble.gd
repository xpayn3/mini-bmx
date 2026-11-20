class_name PadRumble
extends RefCounted
## Layered controller vibration for the ride (Xbox: the left grip's heavy motor = "strong", low and
## thumpy; the right grip's light motor = "weak", a fast buzz). Every physics step `update` reads the
## bike's state and mixes layers you can feel:
##   ROAD    a fine buzz from the ground under the tyres, by surface and speed (trail hardpack hums, grass
##           and dirt are coarser, sand is soft and low, water a slow heavy drag)
##   BUMPS   each wheel's own up / down kick (rocks, roots, roller lips, a front wheel slapping down),
##           the suspension bottoming out = a hard thump
##   SLIP    the tyres scrubbing sideways: a chatter that grows with the slide and the speed, stepping
##           into a stutter as the rear lets go (fishtails, whips, drifts); wheelspin = a high whine
##   BRAKE   a light judder while braking hard, a coarse rattle once the rear locks and skids
##   EFFORT  a soft push on every pedal stroke while sprinting
##   HITS    take-off pop, landings by impact, smashing fences / cacti / bonks, a crash, then every
##           slam and slide of the ragdoll
## In the air everything ground-borne fades out: the silence is part of the feel.
## Layers are joined like probabilities (1 - (1-a)(1-b)...) so they stack without clipping.
## Settings › Controller: Vibration on / off, strength, and one strength per group (road / slip / hits).

const SEND_EVERY := 1.0 / 60.0   # real seconds between motor updates
const HOLD := 0.12               # each update keeps the motors on this long (they stop by themselves if the game freezes)
const FLOOR := 0.06              # the motors barely turn below this: anything felt at all starts here

var game   # Game
var weak := 0.0       # this step's mix, before the settings' strength (tests read these)
var strong := 0.0
var layers := {}      # per layer [weak, strong] (tests)

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

# tests (BMX_RUMBLE_PROBE): per layer peak and mean
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

## a one-off kick that fades out over secs (quadratic tail: punchy start, soft end)
func impulse(w: float, s: float, secs: float) -> void:
	if _hits.size() > 24: _hits.pop_front()
	_hits.append([clampf(w, 0, 1), clampf(s, 0, 1), maxf(secs, 0.02), 0.0])

## landing after air_time s with impact (m/s into the slope)
func landing(air_time: float, impact: float) -> void:
	if air_time < 0.12: return
	var k := clampf((impact - 0.5) / 9.0, 0.0, 1.0)
	impulse(0.25 + 0.6 * k, 0.15 + 0.85 * k, 0.1 + 0.3 * k)          # the touch-down itself
	if k > 0.35: impulse(0.0, (k - 0.35) * 0.8, 0.45)                 # the frame / body settling after a big one

func crash() -> void:
	impulse(1.0, 1.0, 0.35)
	impulse(0.3, 0.7, 0.9)

func stop() -> void:
	_hits.clear()
	if _sent != Vector2.ZERO: _send(0.0, 0.0, true)

static func _join(a: float, b: float) -> float:
	return 1.0 - (1.0 - clampf(a, 0, 1)) * (1.0 - clampf(b, 0, 1))

func _layer(name: String, w: float, s: float) -> void:
	weak = _join(weak, w)
	strong = _join(strong, s)
	if probe: layers[name] = [w, s]

func update(dt: float, inp: Dictionary) -> void:
	_t += dt
	weak = 0.0; strong = 0.0
	if probe: layers.clear()
	var st: BikePhysics = game.phys
	var road_k := float(Settings.get_v("rumble_road"))
	var slip_k := float(Settings.get_v("rumble_slip"))
	var hit_k := float(Settings.get_v("rumble_hits"))
	if st.crash_on:
		if not _crashed: crash()
		_crashed = true
		_crash_layers(dt, hit_k)
	else:
		_crashed = false
		_rag_on = false
		_ride_layers(dt, st, inp, road_k, slip_k, hit_k)
	# transients
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
	_layer("hits", hw * hit_k, hs * hit_k)
	if probe: _probe_step(dt)
	_output()

func _ride_layers(dt: float, st: BikePhysics, inp: Dictionary, road_k: float, slip_k: float, hit_k: float) -> void:
	var va := absf(st.v)
	var spd := clampf(va / 14.0, 0.0, 1.0)
	var ground := 0.0 if st.air else 1.0
	var in_water: bool = st.surf == 2
	# ROAD: [weak, strong] per surface at full speed (0 ground / grass, 1 trail, 2 water, 3 dry / sand)
	var sk: Vector2 = [Vector2(0.30, 0.14), Vector2(0.20, 0.07), Vector2(0.04, 0.22), Vector2(0.12, 0.14)][clampi(st.surf, 0, 3)]
	sk *= 0.6 + 0.4 * st.loose / 1.4 if st.surf != 2 else 1.0
	_surf_k = _surf_k.lerp(sk, minf(1.0, dt * 6.0))
	# texture: a fast wander (gravel / dirt grain) whose rate follows the speed, so slow = separate pebbles
	var n1 := _noise.get_noise_2d(st.distance * 3.1, 0.0)
	var n2 := _noise.get_noise_2d(st.distance * 0.7, 40.0)
	var grain := 0.55 + 0.45 * n1
	var swell := 0.7 + 0.3 * n2
	var road_s := sqrt(spd) * ground
	_layer("road", _surf_k.x * road_s * grain * road_k, _surf_k.y * road_s * swell * road_k)
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
	_layer("bumps", _join(0.75 * _bump_f, 0.35 * _bump_r) * road_k, _join(0.35 * _bump_f, 0.85 * _bump_r) * road_k)
	if st.probe_bottom > _bottom and not st.air:   # bottomed the suspension
		impulse(0.4, 0.9, 0.16)
	_bottom = st.probe_bottom
	# SLIP: sideways scrub (travel vs heading past the tyres' normal slip angle) + the rear letting go
	var slide := maxf(0.0, absf(st.slip) - 0.06)
	var loose_rear := (1.0 - minf(1.0, st.grip_r)) * minf(1.0, absf(st.slip_w) * 0.8)
	var sl := clampf(slide * 2.2 + loose_rear * 0.6 + st.whip * 0.5, 0.0, 1.0) * ground * clampf((va - 1.0) / 6.0, 0.0, 1.0)
	# chatter: on / off pulses whose rate rises with speed (the tyre skipping over the ground), deeper on loose ground
	_ph += dt * (9.0 + va * 0.9)
	var chat := 0.55 + 0.45 * signf(sin(_ph * TAU))
	var slip_w := sl * (0.35 + 0.45 * chat) * (0.8 + 0.3 * st.loose)
	var slip_s := sl * sl * (0.25 + 0.35 * chat)
	# wheelspin: a high whine
	slip_w = _join(slip_w, clampf(st.spin, 0.0, 1.0) * 0.4 * ground)
	_layer("slip", slip_w * slip_k, slip_s * slip_k)
	# BRAKE: judder while rolling, a coarse rattle once the rear skids
	var brake: float = float(inp.get("brake", 0.0))
	var bk := brake * clampf(va / 8.0, 0.0, 1.0) * ground
	var skid: float = (1.0 if st.skid_fx and brake > 0.5 else 0.0) * clampf(va / 5.0, 0.0, 1.0) * ground
	var rattle := 0.6 + 0.4 * _noise.get_noise_2d(_t * 40.0, 90.0)
	_layer("brake", (bk * 0.06 + skid * 0.35 * rattle) * slip_k, (bk * 0.03 + skid * 0.3 * rattle) * slip_k)
	# EFFORT: each pedal stroke while sprinting (two per crank turn)
	var half := int(floor(st.crank / PI))
	if half != _crank_half and not st.air and st.sprint > 0.3 and st.pedal > 0.3:
		impulse(0.0, 0.10 + 0.12 * st.sprint, 0.09)
	_crank_half = half
	# water: a heavy slow drag pulsing with the wading
	if in_water and not st.air:
		_layer("water", 0.0, (0.12 + 0.1 * sin(_t * 7.0)) * spd * road_k)
	# HITS: take-off pop, smashes (the physics raise its shake on bonks / smashes)
	if st.air and not _was_air:
		impulse(0.3 * clampf(st.vy / 4.0, 0.2, 1.0), 0.25 * clampf(st.vy / 4.0, 0.2, 1.0), 0.08)
	_was_air = st.air
	if st.shake > _shake + 0.05:
		impulse(0.6, minf(1.0, st.shake * 2.5), 0.25)
	_shake = st.shake

## ragdoll: every slam of the body on the ground + a rough slide
func _crash_layers(dt: float, hit_k: float) -> void:
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
		if jolt > 25.0: impulse(clampf(jolt / 160.0, 0.2, 0.9), clampf(jolt / 120.0, 0.25, 1.0), 0.18)
	_rag_v = c; _rag_on = true
	var pp: Vector3 = rd.p[0]
	var on_ground: float = 1.0 if lo - game.terrain.height(pp.x, pp.z) < 0.35 else 0.0
	var hs := Vector2(c.x, c.z).length()
	var g := 0.6 + 0.4 * _noise.get_noise_2d(_t * 30.0, 7.0)
	_layer("slide", clampf(hs / 8.0, 0.0, 0.5) * on_ground * g * hit_k, clampf(hs / 10.0, 0.0, 0.35) * on_ground * hit_k)

func _output() -> void:
	var k := float(Settings.get_v("rumble_strength"))
	if not Settings.get_v("rumble"): k = 0.0
	var w := _motor(weak * k)
	var s := _motor(strong * k)
	_send(w, s, false)

## 0..1 mix -> motor speed: nothing stays nothing, the faintest layer still just turns the motor
static func _motor(x: float) -> float:
	if x < 0.008: return 0.0
	return lerpf(FLOOR, 1.0, clampf(x, 0.0, 1.0))

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
			parts.append("%s=%.2f/%.2f" % [key, layers[key][0], layers[key][1]])
		print("RUMBLE t=%.2f v=%.1f surf=%d air=%s slip=%.2f mix=%.2f/%.2f motor=%.2f/%.2f  %s" % [_t, st.v, st.surf, st.air, st.slip, weak, strong, _motor(weak), _motor(strong), " ".join(parts)])

func probe_summary() -> String:
	var parts := []
	for key in _pr_peak:
		parts.append("%s peak=%.2f mean=%.3f" % [key, _pr_peak[key], _pr_sum[key] / maxf(1, _pr_n)])
	return "RUMBLESUM steps=%d  %s" % [_pr_n, "  |  ".join(parts)]
