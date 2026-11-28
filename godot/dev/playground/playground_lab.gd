class_name PlaygroundLab
extends Node
## The test playground's lab tools (made by RideDiag; the second toolbar row of the dev view):
## - ENERGY CHECK: the bike + rider's energy per kg (E = ½ speed² + g height; in the air the climb speed counts too).
##   With nothing putting energy in (no pedal, sprint, pump / hop, body stick) it can only go down: a rise of more than
##   GAIN_J J/kg within 0.25 s while "free" is flagged (`PG CHECK energy_gain`, an ENERGY+ event on the graphs).
## - PHYSICS CHECKS: things a real bike can't do: a tyre squashed past RIM_M (rim strike), an acceleration over
##   MAX_G g, the bike under the ground, a jump of more than 0.3 m in one step, a non-finite value. Each is counted,
##   marked on the graphs and printed as `PG CHECK <kind> ...` with where it happened.
## - TIME: G pause / resume the physics, N one physics step (1/120 s) while paused, T slow motion 1 / ½ / ¼ / ⅒.
## - RECORD / REPLAY: V records the next run (from a reset 25 m before the feature you're at, or the test rider's next
##   run) until the next reset / V again / 60 s: inputs per physics step + the path + every graph channel + the Tune
##   values. Saved to user://playground/last_run.dat (it survives a restart, so: record, change the code, restart,
##   replay). J replays it from the same start with the same inputs; a ghost bike (Debug Draw, white wireframe) rides
##   the recorded path and the graphs draw the recorded run as faint lines under the live ones. At the end
##   `PG REPLAY` says how far the end point moved and which Tune values differ from the recording.
## Tests: BMX_PG_REC=1 records the test rider's first run (with BMX_PG_PILOT), BMX_PG_REPLAY=1 replays the saved run
## at start (+ prints PG REPLAY), BMX_PG_SLOW=0.25, BMX_LAB_PROBE=1 prints a CHECKS summary at the end.

const GAIN_J := 0.5            # J/kg of energy gained "for free" within GAIN_WIN steps = a check
const GAIN_WIN := 30
const RIM_M := 0.05            # tyre squash (m) past which a real tyre would hit its rim
const MAX_G := 50.0            # g in one step: past what a bike's suspension + a rider's legs can spread a hit to
const REC_MAX := 7200          # steps (60 s)
const SLOWS := [1.0, 0.5, 0.25, 0.1]
const SAVE := "user://playground/last_run.dat"
const IN_KEYS := ["throttle", "brake", "brake_front", "brake_rear", "steer", "body_fwd", "body_lean", "hop", "sprint", "pad"]

var game
var diag                       # RideDiag
# energy + checks
var e0 := NAN                  # energy at the last reset (the graphs show E - e0)
var energy := 0.0
var _e_prev := NAN
var _gain := PackedFloat32Array()
var _gain_i := 0
var _gain_cool := 0.0
var _v_prev := Vector2(NAN, NAN)
var _y_prev := NAN
var _skip := 2                 # steps to skip the checks after a reset (the teleport)
var checks: Array = []         # the last 40: {kind, text, t}
var counts := {}               # kind -> count this session
var _t := 0.0
var free := false              # this step nothing put energy in
var _busy_t := 0.0
# time
var paused := false
var _steps := 0
var slow := 1.0
var _ts_set := 1.0
# record / replay
var rec := {}                  # the recording (also what was loaded from disk)
var _in := PackedFloat32Array()   # while recording: inputs / path / graph channels (appended in place; into rec on stop)
var _tr := PackedFloat32Array()
var _ch := PackedFloat32Array()
var recording := false
var _rec_armed := false        # waiting for the reset that starts the recording
var replaying := false
var _rp_i := 0
var _rp_serial := -1           # diag serial of the replay's first step (the graphs' ghost lines line up on it)
var ghost := true
var _ghost_i := -1
var _probe := Env.s("BMX_LAB_PROBE") != ""
var status := ""


func _init() -> void:
	_gain.resize(GAIN_WIN)
	if Env.s("BMX_PG_SLOW") != "": slow = float(Env.s("BMX_PG_SLOW"))


func setup(g, d) -> void:
	game = g; diag = d
	_load()
	if Env.s("BMX_PG_REC") != "":   # (after the test rider has started, so it records his run)
		get_tree().create_timer(0.5).timeout.connect(arm_record)
	if Env.s("BMX_PG_REPLAY") != "": start_replay.call_deferred()


# ---- called by Game ---------------------------------------------------------------------------------------------

## before the physics step: true = hold it (paused, no step asked for)
func hold_physics() -> bool:
	if not paused: return false
	if _steps > 0:
		_steps -= 1
		return false
	return true


## a replayed input for this step, or null
func replay_input():
	if not replaying: return null
	var a: PackedFloat32Array = rec.inputs
	var n := a.size() / IN_KEYS.size()
	if _rp_i >= n:
		_end_replay()
		return null
	var inp := {}
	var b := _rp_i * IN_KEYS.size()
	for i in IN_KEYS.size():
		var k: String = IN_KEYS[i]
		inp[k] = a[b + i] > 0.5 if k in ["hop", "sprint", "pad"] else a[b + i]
	_rp_i += 1
	return inp


## after level_probe.pre_step, before phys.step: what the physics is about to get
func pre_step(inp: Dictionary) -> void:
	if not recording: return
	var ph = game.phys
	if int(rec.n) == 0:
		rec.spawn = Vector3(ph.x, ph.heading, ph.z); rec.v0 = ph.v
	if int(rec.n) >= REC_MAX:
		stop_record(); return
	for k in IN_KEYS:
		var x = inp.get(k, 0.0)
		_in.append((1.0 if x else 0.0) if typeof(x) == TYPE_BOOL else float(x))


## AIR (LAB row, BMX_PG_AIRHOLD=1): the bike held HOLD_H up in the air, gravity cancelled after every physics step,
## drifting at HOLD_V: everything about rotation in the air runs as in a real jump (right stick tilt / lean, flips and
## flat spins at the stick's edge, whips, the tuck, the landing aim, the rider's pose) for as long as you like. Off: set
## down from a low height
const HOLD_H := 4.0
const HOLD_V := 1.5
var air_hold := Env.s("BMX_PG_AIRHOLD") != ""
var _held := false
var _hold_print := 0.0

func toggle_air_hold() -> void:
	air_hold = not air_hold
	if not air_hold and _held:
		var ph = game.phys
		_lift_to(ph, game.terrain.height(ph.x, ph.z) + 0.7)
		_held = false
	status = "AIR: held %.0f m up, sticks rotate him (off: set down)" % HOLD_H if air_hold else "AIR off"

## moves the whole bike (frame, wheels, the rider's body mass) to height `want`, at rest up / down
func _lift_to(ph, want: float) -> void:
	var dy: float = want - ph.y
	ph.y += dy; ph.vy = 0.0
	if not is_nan(ph.body_y): ph.body_y += dy
	ph.body_v = 0.0
	if not is_nan(ph.zw_f): ph.zw_f += dy; ph.vw_f = 0.0
	if not is_nan(ph.zw_r): ph.zw_r += dy; ph.vw_r = 0.0

func _air_hold_step(dt: float, ph) -> void:
	if not air_hold or ph.crash_on:
		_held = false
		return
	_held = true
	_lift_to(ph, game.terrain.height(ph.x, ph.z) + HOLD_H)
	ph.v = move_toward(ph.v, HOLD_V, 25.0 * dt)
	_hold_print += dt
	if Env.s("BMX_PG_AIRHOLD") != "" and _hold_print >= 0.25:   # tests
		_hold_print = 0.0
		print("AIRHOLD t=%.2f air=%s pitch=%.0f lean=%.0f yaw=%.0f tilt=%.2f air_w=%.2f stick=(%.2f,%.2f) pull=%.2f" % [ph.air_time, ph.air,
			rad_to_deg(ph.pitch), rad_to_deg(ph.bike_lean), rad_to_deg(ph.slip), ph.air_tilt, ph.air_w, ph.air_stick.x, ph.air_stick.y, ph.air_pull])


## after the physics step (and diag.record)
func post_step(dt: float, inp: Dictionary) -> void:
	var ph = game.phys
	_air_hold_step(dt, ph)
	_t += dt
	var vt: float = ph.v * ph.v + (ph.vy * ph.vy if ph.air else 0.0)
	energy = 0.5 * vt + 9.81 * ph.y
	if is_nan(e0): e0 = energy
	_checks(dt, ph, inp)
	_e_prev = energy
	if recording:
		_tr.append(ph.x); _tr.append(ph.y); _tr.append(ph.z); _tr.append(ph.heading); _tr.append(ph.pitch); _tr.append(ph.bike_lean)
		var base: int = ((diag.head - 1 + RideDiag.RING) % RideDiag.RING) * diag.C
		for c in diag.C: _ch.append(diag.buf[base + c])
		rec.n = int(rec.n) + 1
	if replaying or _ghost_i >= 0:
		_ghost_i += 1


## Game.level_reset_to: a reset ends a recording / replay and (armed) starts one
func on_reset() -> void:
	_skip = 3; e0 = NAN; _e_prev = NAN
	_v_prev = Vector2(NAN, NAN)
	if recording and int(rec.n) > 10: stop_record()
	if replaying: replaying = false
	_ghost_i = -1
	if _rec_armed:
		_rec_armed = false
		_begin_record()


# ---- energy + checks --------------------------------------------------------------------------------------------

func _checks(dt: float, ph, inp: Dictionary) -> void:
	if _held: return   # (held in the air: not real physics, nothing to check)
	# (a pump / hop counts for a moment after it's let go: its push comes at the release / the lip)
	if inp.get("hop", false) or inp.get("sprint", false) or float(inp.get("throttle", 0.0)) >= 0.02 or absf(float(inp.get("body_fwd", 0.0))) >= 0.05:
		_busy_t = 0.35
	_busy_t -= dt
	free = not ph.crash_on and _busy_t <= 0.0
	if _skip > 0:
		_skip -= 1
		_v_prev = Vector2(ph.v, ph.vy); _y_prev = ph.y
		return
	var u: float = ph.x - PlaygroundCourse.X0
	# energy for free
	var dE: float = energy - _e_prev if is_finite(_e_prev) else 0.0
	_gain[_gain_i] = dE if free else minf(dE, 0.0)
	_gain_i = (_gain_i + 1) % GAIN_WIN
	_gain_cool -= dt
	var sum := 0.0
	for x in _gain: sum += x
	if sum > GAIN_J and _gain_cool <= 0.0:
		var ctx := ("take-off" if ph.air_time < 0.25 else "air") if ph.air else ("take-off" if ph.air_time < 0.2 and ph.since_land > 0.3 and game.terrain.jump_mask(ph.x, ph.z) > 0.0 else "ground")
		_check("energy_gain", "+%.2f J/kg (%.1f km/h worth) in 0.25 s, %s, coasting" % [sum, (sqrt(maxf(0.0, ph.v * ph.v + 2.0 * sum)) - absf(ph.v)) * 3.6, ctx], ph)
		_gain_cool = 0.5
		_gain.fill(0.0)
	# rim strike
	var sq := maxf(ph.dg_sqF, ph.dg_sqR)
	if sq > RIM_M and not _recent("rim_strike", 0.3):
		_check("rim_strike", "tyre squashed %.1f cm (%s)" % [sq * 100.0, "front" if ph.dg_sqF >= ph.dg_sqR else "rear"], ph)
	# acceleration
	var vn := Vector2(ph.v, ph.vy)
	if is_finite(_v_prev.x) and not ph.crash_on:
		var a: float = (vn - _v_prev).length() / maxf(dt, 1e-4) / 9.81
		if a > MAX_G and not _recent("accel", 0.3):
			_check("accel", "%.0f g in one step" % a, ph)
	_v_prev = vn
	# under the ground / teleport / non-finite
	var gy: float = game.terrain.height(ph.x, ph.z)
	if ph.y < gy - ph.dg_travel - 0.15 and not ph.crash_on and not _recent("sunk", 0.5):   # (full travel is allowed)
		_check("sunk", "bike %.2f m under the ground (travel %.2f)" % [gy - ph.y, ph.dg_travel], ph)
	if is_finite(_y_prev) and absf(ph.y - _y_prev) > 0.3 and not _recent("jump_step", 0.3):
		_check("jump_step", "height jumped %.2f m in one step" % (ph.y - _y_prev), ph)
	_y_prev = ph.y
	if not is_finite(ph.v + ph.vy + ph.y + ph.pitch + ph.lean):
		_check("non_finite", "a physics value went NaN / inf", ph)


func _recent(kind: String, secs: float) -> bool:
	for c in checks:
		if c.kind == kind and _t - float(c.t) < secs: return true
	return false


func _check(kind: String, text: String, ph) -> void:
	var u: float = ph.x - PlaygroundCourse.X0
	var f = game.terrain.course.feature_at(ph.x, ph.z)
	var where := "%s u=%.1f" % [f.id if f != null else "-", u]
	checks.append({"kind": kind, "text": text, "t": _t, "where": where})
	if checks.size() > 40: checks.pop_front()
	counts[kind] = int(counts.get(kind, 0)) + 1
	diag._event(kind.to_upper().replace("_", " "), Color(1.0, 0.35, 0.9))
	print("PG CHECK %s %s | %s v=%.1f km/h air=%s" % [kind, text, where, ph.v * 3.6, str(ph.air)])


# ---- time -------------------------------------------------------------------------------------------------------

func toggle_pause() -> void:
	paused = not paused; _steps = 0
	status = "PAUSED (N = one step)" if paused else ""
	if _probe: print("PG LAB paused=%s x=%.4f" % [str(paused), game.phys.x])

func step_once() -> void:
	if not paused: paused = true
	_steps += 1
	if _probe: print("PG LAB step x=%.4f" % game.phys.x)

func cycle_slow() -> void:
	slow = SLOWS[(SLOWS.find(slow) + 1) % SLOWS.size()] if slow in SLOWS else 1.0


func _process(_dt: float) -> void:
	# slow motion: only while nobody else owns time_scale (crash slow motion, photo mode, the map)
	var ts := Engine.time_scale
	if absf(ts - _ts_set) < 1e-4 or absf(ts - 1.0) < 1e-4:
		if absf(ts - slow) > 1e-4:
			Engine.time_scale = slow
		_ts_set = slow


func _exit_tree() -> void:
	if absf(Engine.time_scale - _ts_set) < 1e-4: Engine.time_scale = 1.0
	if _probe:
		var s := ""
		for k in counts: s += " %s=%d" % [k, counts[k]]
		print("PG CHECKS%s" % (s if s != "" else " none"))


# ---- record / replay --------------------------------------------------------------------------------------------

## V: record the next run (the test rider's next run, or from 25 m before the feature you're at); V again stops
func toggle_record() -> void:
	if recording: stop_record(); return
	arm_record()

func arm_record() -> void:
	if replaying: replaying = false
	_rec_armed = true
	var pl = game.demo
	if pl is PlaygroundPilot:
		pl.restart(game)   # (its reset starts the recording; it starts from a clean state)
	else:
		var sp: Vector3 = game.terrain.level_reset(game.phys.x, game.phys.z)
		fresh(game.phys)
		game.level_reset_to(sp)
	status = "REC"


func _begin_record() -> void:
	var ph = game.phys
	_reseed(ph)
	var f = game.demo.target if game.demo is PlaygroundPilot and game.demo.target != null else game.terrain.course.feature_at(ph.x, ph.z)
	if f == null: f = game.level_probe._next_feature(ph.x, ph.z) if game.level_probe else null
	_in = PackedFloat32Array(); _tr = PackedFloat32Array(); _ch = PackedFloat32Array()
	rec = {"n": 0, "inputs": PackedFloat32Array(), "track": PackedFloat32Array(), "chans": PackedFloat32Array(),
		"channels": RideDiag.CH, "spawn": Vector3(ph.x, ph.heading, ph.z), "v0": ph.v, "feat": f.id if f != null else "-",
		"tune": Tune.v.duplicate(), "pilot": game.demo is PlaygroundPilot, "date": Time.get_datetime_string_from_system()}
	recording = true
	status = "REC %s" % rec.feat


func stop_record() -> void:
	if not recording: return
	recording = false
	rec.inputs = _in; rec.track = _tr; rec.chans = _ch
	status = "recorded %s %.1f s" % [rec.feat, int(rec.n) / 120.0]
	print("PG REC feat=%s steps=%d (%.1f s) saved %s" % [rec.feat, int(rec.n), int(rec.n) / 120.0, SAVE])
	_save()


## J: the saved run again, same start, same inputs, with its ghost
func start_replay() -> void:
	if rec.is_empty() or int(rec.get("n", 0)) < 2:
		status = "nothing recorded yet (V)"; return
	if recording: stop_record()
	if game.demo != null: game.set_demo(false)
	fresh(game.phys)
	game.level_reset_to(rec.spawn)   # (on_reset clears the ghost: set it up after)
	var ph = game.phys
	ph.v = float(rec.v0)
	_reseed(ph)
	replaying = true
	_rp_i = 0
	_ghost_i = 0
	_rp_serial = diag.serial
	status = "REPLAY %s" % rec.feat


func _end_replay() -> void:
	replaying = false
	var ph = game.phys
	var tr: PackedFloat32Array = rec.track
	var n := tr.size() / 6
	var d := 0.0
	if n > 0:
		var b := (n - 1) * 6
		d = Vector3(ph.x - tr[b], ph.y - tr[b + 1], ph.z - tr[b + 2]).length()
	var changed := ""
	var t0: Dictionary = rec.get("tune", {})
	for k in t0:
		if Tune.v.has(k) and typeof(t0[k]) in [TYPE_FLOAT, TYPE_INT] and absf(float(Tune.v[k]) - float(t0[k])) > 1e-6:
			changed += " %s %s->%s" % [k, str(t0[k]), str(Tune.v[k])]
	status = "replayed: end %.2f m from the recording" % d
	print("PG REPLAY feat=%s steps=%d end_moved=%.3f m tune_changed:%s" % [rec.feat, _rp_i, d, changed if changed != "" else " none"])


## a clean physics state for a repeatable run: every plain value copied from a brand-new BikePhysics (reset_at only
## clears motion: smoothed grip per surface, tyre loads, crash meters, stamina, flow, the grip randomness... carried on
## from the last run and made the same run come out different: gap_5 left at 41 deg one time, 84 the next). The bike's
## build (geometry, gearing), the Tune values and objects stay; the gear goes back to the start gear.
## Call before Game.level_reset_to (its reset_at then puts the bike down).
const KEEP := ["host", "T", "L", "RWF", "RWR", "BB_REAR", "SH_R", "LAND", "geared", "cogs", "ring_k", "bike_rock", "distance", "bank_probe", "sus", "_sus_synced", "_su", "_sag_seen", "test_rider", "prof"]   # (test_rider: its landing help was lost after the first restart; prof: the profiler's dict)
func fresh(ph) -> void:
	var clean := BikePhysics.new(game)
	for p in clean.get_property_list():
		if not (int(p.usage) & PROPERTY_USAGE_SCRIPT_VARIABLE): continue
		var k: String = p.name
		if k in KEEP: continue
		var v = clean.get(k)
		if typeof(v) == TYPE_OBJECT: continue
		ph.set(k, v)
	ph.gear = BikePhysics.start_gear(ph.cogs, ph.ring_k) if ph.geared else -1
	_reseed(ph)


## the same random draws for the same run: the grip noise and stamina carry over otherwise
func _reseed(ph) -> void:
	ph.reseed_grip(4711)
	ph.stamina = 1.0


func _save() -> void:
	DirAccess.make_dir_recursive_absolute(SAVE.get_base_dir())
	var f := FileAccess.open(SAVE, FileAccess.WRITE)
	if f: f.store_var(rec); f.close()


func _load() -> void:
	if not FileAccess.file_exists(SAVE): return
	var f := FileAccess.open(SAVE, FileAccess.READ)
	if f == null: return
	var d = f.get_var()
	f.close()
	if d is Dictionary and d.has("inputs"):
		rec = d
		status = "saved run: %s %.1f s (J replays)" % [rec.get("feat", "?"), int(rec.get("n", 0)) / 120.0]


## the ghost's recorded graph value for diag channel ch at the sample with this serial (NAN = none)
func ghost_val(ch_name: String, serial_: int) -> float:
	if rec.is_empty() or _rp_serial < 0 or _ghost_i < 0: return NAN
	var gi := serial_ - _rp_serial
	var n := int(rec.n)
	if gi < 0 or gi >= n: return NAN
	var chs: Array = rec.channels
	var c := chs.find(ch_name)
	if c < 0: return NAN
	var a: PackedFloat32Array = rec.chans
	return a[gi * chs.size() + c]


## Debug Draw: the ghost bike at the recorded step (a wireframe: wheels, frame, a line up to the rider)
func draw_ghost(d3) -> void:
	if not ghost or rec.is_empty() or _ghost_i < 0: return
	var tr: PackedFloat32Array = rec.track
	var n := tr.size() / 6
	if n == 0: return
	var i := clampi(_ghost_i, 0, n - 1)
	var b := i * 6
	var p := Vector3(tr[b], tr[b + 1], tr[b + 2])
	var hd := tr[b + 3]
	var pit := tr[b + 4]
	var lean := tr[b + 5]
	var ph = game.phys
	var fwd := Vector3(cos(hd), 0.0, -sin(hd))
	var up := Vector3.UP.rotated(fwd, -lean)
	var fp := fwd * cos(pit) + Vector3.UP * sin(pit)
	var r: float = ph.RWF
	var rear: Vector3 = p - fp * ph.BB_REAR + up * r
	var front: Vector3 = p + fp * (ph.L - ph.BB_REAR) + up * r
	var col := Color(1, 1, 1, 0.9)
	for c in [rear, front]:
		var pts := PackedVector3Array()
		for k in 17:
			var a := TAU * k / 16.0
			pts.append(c + fp * cos(a) * r + up * sin(a) * r)
		d3.draw_line_path(pts, col)
	d3.draw_line(rear, front, col)
	d3.draw_line(p + up * 0.45, p + up * 1.5, col)
	d3.draw_sphere(p + up * 1.55, 0.12, col)
	# the recorded path, the bit ahead of the ghost
	var path := PackedVector3Array()
	for k in range(i, mini(n, i + 360), 6):
		path.append(Vector3(tr[k * 6], tr[k * 6 + 1] + 0.05, tr[k * 6 + 2]))
	if path.size() >= 2: d3.draw_line_path(path, Color(1, 1, 1, 0.5))
