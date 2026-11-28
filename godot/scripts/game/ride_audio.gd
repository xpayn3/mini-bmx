extends Node
## Procedural ride sound (the web version was silent): wind that rises with speed, tyre roll on gravel
## (GravelSynth.cs, fitted to a real tyres-on-gravel recording; its tone follows the surface; skids play it louder),
## splashes, and one-shot
## crunches, synthesised into one AudioStreamGenerator; plus the freewheel, synthesised
## in C# (FreewheelSynth.cs, modelled on a real hub) on its own 44.1 kHz generator for a crisp top end;
## gear shifts are game/shift_sound.gd (the user's shifter recording).

const RATE := 22050.0

var game
var player := AudioStreamPlayer.new()
var pb: AudioStreamGeneratorPlayback
# smoothed control values
var wind := 0.0
var roll := 0.0
var roll_tone := 0.3
var skid := 0.0
var water := 0.0
# filter / oscillator state
var lp_w := 0.0
var lp_w2 := 0.0
var lp_r := 0.0
var lp_r2 := 0.0
var hp_s := 0.0
var wind_tone := 0.03   # wind low-pass coefficient: opens up (brighter) with speed
var gust_ph := 0.0
var gust_ph2 := 0.0   # (GDScript fallback) time left until the next gust / pan target
var _g_t := 0.78; var _g_v := 0.78; var _g_v2 := 0.78
var _p_t := 0.0; var _p_v := 0.0; var _p_v2 := 0.0
var lp_wR := 0.0
var lp_wR2 := 0.0
var bp_lo := 0.0
var bp_hi := 0.0
var whistle := 0.0
# freewheel: pawl clicks synthesised in C#; speed sets the click rate only, the tone stays crisp
const FW_RATE := 44100.0
var fw_ver := -1       # FreewheelSound.version last applied to the synth
var fw := AudioStreamPlayer.new()
var fw_pb: AudioStreamGeneratorPlayback
var fw_synth = null    # FreewheelSynth (C#); null on the non-.NET Godot -> no freewheel
var fw_clicks := 0.0
var fw_amp := 0.0
var fw_fast := 0.0     # 0 slow .. 1 full speed character
var fw_peak := 0.0
# tyre on gravel: pebble knocks synthesised in C# (GravelSynth.cs); null -> the old noise rumble
var gravel = null
var bed = null   # RideBedSynth (C#): wind / splash / gravel mix per sample; null -> the GDScript loop in _fill
var g_speed := 0.0
var g_amp := 0.0
var g_tone := 650.0
var g_crack := 0.3
var g_rumble := 1.0
# per surface (0 ground/grass, 1 trail, 2 water, 3 dry/sand): [gain, tone Hz, crack, rumble]
const GRAVEL_SURF := [[0.09, 420.0, 0.04, 1.2], [0.15, 600.0, 0.12, 0.9], [0.0, 500.0, 0.05, 0.5], [0.13, 520.0, 0.08, 0.7]]   # subtle: ~half the level, little crack (clicks)
# one-shots: [kind, t, amp]
var shots: Array = []
var layers: RideLayers   # recorded layers driven by the ride (game/ride_layers.gd): silent until recordings exist
var shift_snd: ShiftSound
## the instant replay drives the sound: `src` = a recorded state (ReplayMode.AudioState: the same fields this reads
## from BikePhysics), and every one-shot played while riding is handed to the replay (`_rec`) to play again there
var src = null

func _rec(kind: String, args: Array) -> void:
	if game and game.replay and not game.replay_on: game.replay.audio_event(kind, args)

## drop the C# synths while the engine is still up: if their .NET finalizers run during shutdown
## instead, Godot can crash on exit ("Leaked unsafe reference" -> SEHException). On PREDELETE, not _exit_tree:
## the ride world built during the boot intro is moved into the scene (main.gd), which fires _exit_tree
func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		gravel = null
		bed = null
		fw_synth = null


func _ready() -> void:
	_slam_pool.call_deferred()   # (players + the slam bank now, not on the first landing)
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = RATE
	gen.buffer_length = 0.12
	player.stream = gen
	player.bus = Settings.bus_for("Wind")
	add_child(player)
	player.play()
	pb = player.get_stream_playback()
	_setup_chain()
	layers = RideLayers.new()
	layers.game = game
	add_child(layers)
	shift_snd = ShiftSound.new()
	add_child(shift_snd)
	var gs = load("res://scripts/game/GravelSynth.cs")
	if gs != null and gs.can_instantiate():
		gravel = gs.new()
	var bs = load("res://scripts/game/RideBedSynth.cs")
	if bs != null and bs.can_instantiate():
		bed = bs.new()
	var cs = load("res://scripts/game/FreewheelSynth.cs")
	if cs != null and cs.can_instantiate():
		fw_synth = cs.new()
		var g2 := AudioStreamGenerator.new()
		g2.mix_rate = FW_RATE
		g2.buffer_length = 0.1
		fw.stream = g2
		fw.bus = Settings.bus_for("Bike")
		add_child(fw)
		fw.play()
		fw_pb = fw.get_stream_playback()

# chain rub: the "bicycle forward movement" recording (its first steady part, 5-11 s, crossfaded into a seamless
# 6 s loop, assets/audio/chain_rub.ogg) kept quietly under everything while the cranks turn (the
# freewheel synth has the coasting). Its
# playback rate follows the wheel speed (CHAIN_REF m/s = as recorded), so the ticking speeds up / slows
# down with the bike; louder with speed, fades out when coasting, stopped or in the air.
const CHAIN_DB := -6.0   # the recording itself is very quiet (mean -40 dB, peaks -16 dB): -24 was inaudible, +10 far too loud
const CHAIN_REF := 7.0
var chain := AudioStreamPlayer.new()
var chain_amp := 0.0

func _setup_chain() -> void:
	var s = load("res://assets/audio/chain_rub.ogg")
	if s == null: return
	if s is AudioStreamOggVorbis: s.loop = true
	chain.stream = s
	chain.bus = Settings.bus_for("Bike")
	chain.volume_db = -80.0
	add_child(chain)
	chain.play(randf() * 6.0)

var _crank_last := 0.0
var _crank_w := 0.0   # how fast the cranks really turn (rad/s, smoothed)

# freewheel: the hub shell's spin over the driver's (rad/s of the rear wheel, smoothed)
var OLD_FW := Env.s("BMX_OLD_FW") != ""   # = the old rule: bike speed whenever the gas key is up
var FW_OLDSYN := Env.s("BMX_OLD_FWSYNTH") != ""   # = the freewheel synth before 2026-11-28 (FreewheelSynth.OLD)
var OLD_SLAMDOUBLE := Env.s("BMX_OLD_SLAMDOUBLE") != ""   # = the double hits of before (rear tyre's second hit, late clatter)
var _hw_crank := 0.0; var _hw_init := false
var _hw_cw := 0.0     # the cranks' turn rate (rad/s, signed, smoothed)
var _hub_w := 0.0

func _hub_overrun(dt: float, st) -> float:
	if dt <= 0.0: return maxf(_hub_w, 0.0)
	var phys = game.phys
	# the rear wheel: the physics turns it at exactly v / RWR, and not at all while the rear is locked
	# the live physics has the rear wheel's own spin (free in the air, braked, spun by the legs: wr_w);
	# a replay state only the speed and the skid
	var wheel_w: float
	if "wr_w" in st:
		wheel_w = float(st.wr_w)
	else:
		wheel_w = 0.0 if bool(st.skid_fx) else float(st.v) / float(st.RWR)
	# the cranks: measured off their angle (pedalling, slowing legs, settling to the coasting angle, kickback);
	# smoothed over ~0.1 s: a drawn frame holds 0..3 physics ticks
	var crank: float = float(st.crank)
	var dc := crank - _hw_crank
	_hw_crank = crank
	if not _hw_init or absf(dc) > 100.0 * dt + 1.0:   # first frame / a respawn or replay jump
		_hw_init = true
		dc = _hw_cw * dt
	_hw_cw += (dc / dt - _hw_cw) * minf(1.0, dt * 10.0)
	# rear turns per crank turn (the physics spins the cranks off the FRONT wheel's rate, w = v / RWF, so
	# that ratio x RWF / RWR)
	var ratio := 2.78
	if phys != null:
		if BikePhysics._OLD_CADENCE: ratio = 2.78 * phys.gear_k() * float(phys.T.topSpeed) * float(phys.RWF) / maxf(float(phys.RWR), 0.05)
		else: ratio = phys.drive_ratio()   # (the real chainring / cog: the cranks turn off the rear wheel now)
	var raw := wheel_w - _hw_cw * ratio
	# pawls engaged: the driver keeps up within a few % (chain slack, smoothing lag) = no clicks
	raw = signf(raw) * maxf(0.0, absf(raw) - (0.06 * absf(wheel_w) + 0.3))
	_hub_w += (raw - _hub_w) * minf(1.0, dt * 20.0)
	return maxf(_hub_w, 0.0)

func _update_chain(dt: float, va: float, on_ground: bool, st) -> void:
	if chain.stream == null: return
	# only while the legs spin the cranks: the raw gas key (the smoothed pedal lingers ~0.5 s after letting
	# go) AND the cranks measurably turning (not stalled, not just settling to their coasting angle)
	if dt > 0.0:
		var w: float = absf(st.crank - _crank_last) / dt
		_crank_w += (minf(w, 40.0) - _crank_w) * minf(1.0, dt * 10.0)
	_crank_last = st.crank
	var spinning: bool = st.throttle_in >= 0.1 and st.pedal > 0.05 and on_ground
	var t := smoothstep(0.6, 2.0, _crank_w) * smoothstep(0.3, 3.0, va) * (0.6 + 0.4 * clampf(va / 14.0, 0.0, 1.0)) if spinning else 0.0
	chain_amp += (t - chain_amp) * minf(1.0, dt * (5.0 if t > chain_amp else 14.0))
	chain.volume_db = CHAIN_DB + linear_to_db(maxf(chain_amp, 0.0001)) if chain_amp > 0.003 else -80.0
	chain.pitch_scale = clampf(va / CHAIN_REF, 0.6, 1.4)

## the landing slam: the user's recording of a bike hitting the ground (assets/audio/bike_slam_1..10.ogg: two hits, each with five tonal variants, cut from a
## mountain-bike sound video). The harder the landing (`impact` = the speed lost into the ground, m/s: ~1 a soft
## roll-out, ~6-8 a big drop) the louder it plays (and a touch deeper); a tiny one stays silent.
## 1-5 are the first recording (plain, deeper, lighter, dull, crisp), 6-10 the same five of the second
const SLAM_CLIPS := 10
const SLAM_VARY := 0.12   # how far each landing strays from the recording's own fit
const SLAM_PEAK := 0.63   # -4 dBFS, like the recorded clips
const SLAM_MIN := 0.8      # below this impact nothing plays
const SLAM_FULL := 7.0     # impact that plays at full volume
const SLAM_DB_SOFT := -30.0
const SLAM_DB_HARD := -7.0
var _slam_clips: Array = []
var _slam_pl: Array = []
var _slam_i := 0
var _slam_last := -1

var _slam_syn = null   # SlamSynth (C#): a fresh slam every landing, 4-8 ms; null -> the recorded clips

func _slam_pool() -> void:
	if not _slam_pl.is_empty(): return
	var ss = load("res://scripts/game/SlamSynth.cs")
	if ss != null and ss.can_instantiate():
		_slam_syn = ss.new()
		_slam_syn.StartBank(SLAM_VARY, SLAM_PEAK)   # every kind of slam rendered ahead on .NET threads (SlamSynth.Take)
	if _slam_syn == null:
		for n in range(1, SLAM_CLIPS + 1):   # no C#: the recorded clips
			var c = load("res://assets/audio/bike_slam_%d.ogg" % n)
			if c != null: _slam_clips.append(c)
	for i in 4:
		var pl := AudioStreamPlayer.new()
		pl.bus = Settings.bus_for("Impacts")
		add_child(pl)
		_slam_pl.append(pl)

func _slam_play(stream, db: float, pitch: float) -> void:
	_slam_i = (_slam_i + 1) % _slam_pl.size()
	var pl: AudioStreamPlayer = _slam_pl[_slam_i]
	pl.stream = stream
	pl.volume_db = db
	pl.pitch_scale = pitch
	pl.play()

## a slam from the pre-rendered bank (~0.05 ms: bytes wrapped into a WAV); rendered here only if the bank isn't ready yet (the
## first ~0.3 s of a ride, 5-10 ms)
func _slam_take(size: float, side: float, kind: int) -> AudioStreamWAV:
	var b: PackedByteArray = _slam_syn.Take(size, side, kind)
	if b.is_empty(): return _slam_wav(_slam_syn.Render(randi(), SLAM_VARY, SLAM_PEAK, size, side, kind))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = 48000
	w.data = b
	return w

func _slam_wav(x: PackedFloat32Array) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(x.size() * 2)
	for i in x.size(): data.encode_s16(i * 2, int(clampf(x[i], -1.0, 1.0) * 32767.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = 48000
	w.data = data
	return w

## touch-down of a jump. `impact` sets the size (a small drop = higher, quicker, lighter; a big one = deeper, longer, with a sub thump and more
## rattle) and the volume; `yaw` = the sideways speed the tyres had to catch (m/s): from ~1 the rear tyre lands a moment after the front and
## rubber scrubs over the dirt. Every landing is rendered fresh (random seed), so no two are the same.
func landing(impact: float, yaw: float = 0.0) -> void:
	_rec("landing", [impact, yaw])
	if impact < SLAM_MIN: return
	_slam_pool()
	var k := clampf((impact - SLAM_MIN) / (SLAM_FULL - SLAM_MIN), 0.0, 1.0)
	var db := lerpf(SLAM_DB_SOFT, SLAM_DB_HARD, pow(k, 0.75))
	if _slam_syn != null:
		var side := clampf((yaw - 0.8) / 3.5, 0.0, 1.0)
		_slam_play(_slam_take(k, side, 0), db, 1.0)
		# a hard landing shakes the whole bike: the parts' clatter WITH the hit (it used to come with the heavy-landing
		# verdict 0.4 s later and read as a second impact; user: "double impact, weird")
		if k > 0.45 and not OLD_SLAMDOUBLE:
			var kc := clampf((k - 0.45) / 0.55, 0.0, 1.0)
			_slam_play(_slam_take(0.5 + 0.5 * kc, 0.0, 1), db + lerpf(-12.0, -4.0, kc), 1.0)
		if Env.s("BMX_LAYER_PROBE") != "": print("LANDSND impact=%.1f k=%.2f db=%.1f side=%.2f clatter=%s" % [impact, k, db, side, k > 0.45 and not OLD_SLAMDOUBLE])
		return
	if _slam_clips.is_empty(): return
	var i := randi() % _slam_clips.size()
	if i == _slam_last and _slam_clips.size() > 1: i = (i + 1) % _slam_clips.size()
	_slam_last = i
	_slam_play(_slam_clips[i], db, randf_range(0.985, 1.015) * lerpf(1.03, 0.97, k))

## a landing that went badly (heavy landing / SLAM, `sev` 0..1): the bike bounces again and parts clatter, a moment after the first hit
func landing_bad(sev: float) -> void:
	_rec("landing_bad", [sev])
	if not OLD_SLAMDOUBLE: return   # (silent: the clatter plays with the touch-down hit, `landing`)
	_slam_pool()
	if _slam_syn == null: return
	_slam_play(_slam_take(clampf(0.4 + 0.6 * sev, 0.0, 1.0), 0.0, 1), lerpf(-16.0, -6.0, clampf(sev, 0.0, 1.0)), 1.0)

func thud(power: float) -> void: _rec("thud", [power]); shots.append(["thud", 0.0, clampf(power * 0.5, 0.2, 1.0)])
func crunch() -> void: _rec("crunch", []); shots.append(["crunch", 0.0, 0.8])

## wooden planks breaking: a sharp splintering crack, then the pieces knocking and bouncing on the ground.
## Each hit is a plank ringing (free-free beam modes, ratio 1 : 2.76 : 5.40) with a tick of noise; the hits
## come faster and quieter as the pieces settle, each with its own pitch. Built per call so no two sound alike.
func wood_crash(power: float = 1.0) -> void:
	_rec("wood_crash", [power])
	var hits: Array = []
	var t := 0.012
	var g := 1.0
	for k in 7 + int(power * 6.0):
		hits.append([t, randf_range(170.0, 620.0) * (1.0 + 0.5 * randf() * randf()), g * randf_range(0.55, 1.0)])
		t += randf_range(0.018, 0.05) * (1.0 + k * 0.28)
		g *= 0.86
	shots.append(["wood", 0.0, clampf(0.55 + 0.35 * power, 0.5, 1.0), hits])

func _wood_sample(t: float, hits: Array) -> float:
	# crack: noise with a fast-falling brightness, plus a short splintering burst
	var v := (randf() * 2 - 1) * exp(-t * 260.0) * 0.8
	if t < 0.09:
		v += (randf() * 2 - 1) * exp(-t * 60.0) * (0.5 + 0.5 * sin(t * 1300.0)) * 0.22
	for h in hits:
		var dt: float = t - h[0]
		if dt < 0.0 or dt > 0.45: continue
		var f: float = h[1]
		var m := sin(TAU * f * dt) * exp(-dt * 38.0) + 0.5 * sin(TAU * f * 2.76 * dt) * exp(-dt * 70.0) + 0.25 * sin(TAU * f * 5.4 * dt) * exp(-dt * 140.0)
		v += (m + (randf() * 2 - 1) * exp(-dt * 600.0) * 0.5) * h[2] * 0.55
	return v
func crash() -> void: _rec("crash", []); shots.append(["thud", 0.0, 0.7]); shots.append(["crunch", 0.0, 0.32])
## a gear change: the user's shifter recording (game/shift_sound.gd)
func shift(d: int = 1) -> void:
	_rec("shift", [d])
	if shift_snd: shift_snd.shift(d)

func update_audio(dt: float) -> void:
	if pb == null: return
	var st = src if (game.replay_on and src != null) else game.phys
	var va := absf(float(st.v))
	var on_ground: bool = not st.air and not st.crash_on
	# the map / photo mode freeze the ride (time_scale 0) but leave the last speed in the physics: without
	# this the tyres, wind and chain kept playing under the paper (a replay that is paused / rewinding: no src)
	if (game.paper_map != null and game.paper_map.busy()) or game.photo or (game.replay_on and src == null):
		va = 0.0; on_ground = false
	var k := minf(1.0, dt * 8)
	# wind: louder AND brighter the faster you go, a touch more in the air (nothing else masks it)
	# (keeps building past ~60 km/h: the roar is a big part of feeling fast)
	var wt := clampf(va * va / 340.0, 0, 1.3) * (0.62 if st.air else 0.55)
	wind += (wt - wind) * minf(1.0, dt * 4)
	wind_tone += ((0.018 + clampf(va / 24.0, 0, 1.15) * 0.09) - wind_tone) * k
	whistle += ((clampf((va - 9.0) / 14.0, 0, 1) * 0.15) - whistle) * k
	var surf_amp: float = [0.32, 0.22, 0.0, 0.42][st.surf]
	roll += ((clampf(va / 12.0, 0, 1) * surf_amp if on_ground else 0.0) - roll) * k
	roll_tone += (([0.12, 0.2, 0.1, 0.06][st.surf]) - roll_tone) * k
	# gravel: knocks are laid per metre rolled, so speed sets the density; a little louder with speed too
	# skidding = the same gravel, just louder, denser and grittier (the tyre scrapes instead of rolls)
	skid += ((0.5 if (st.skid_fx and on_ground and va > 1) else 0.0) - skid) * minf(1.0, dt * 12)
	var sk := skid * 2.0
	var gp: Array = GRAVEL_SURF[st.surf]
	g_speed = va * (1.0 + 0.6 * sk) if on_ground else 0.0
	g_amp += ((gp[0] * (0.7 + 0.3 * clampf(va / 12.0, 0, 1)) * (1.0 + 0.9 * sk) if on_ground else 0.0) - g_amp) * k
	g_tone += (gp[1] - g_tone) * k
	g_crack += (gp[2] * (1.0 + sk) - g_crack) * k
	g_rumble += (gp[3] - g_rumble) * k
	water += ((clampf(va / 6, 0, 1) * 0.6 if (st.surf == 2 and on_ground) else 0.0) - water) * k
	# freewheel: the pawls click while the wheel turns but the cranks don't. The click rate follows the
	# rear wheel exactly ("poe" per turn: slow ticks -> a fast buzz); pedalling stops new clicks at once
	# and the last ones ring out. A little quieter at speed, where the wind takes over.
	# The sound itself is the player's (Sound tab: FreewheelSound); Preview spins it while standing still.
	FreewheelSound.ensure_loaded()
	if fw_synth != null and fw_ver != FreewheelSound.version:
		fw_ver = FreewheelSound.version
		var c := FreewheelSound.current
		fw_synth.SetParams(c.pitch, c.ring, c.crack, c.crack_len, c.detune, c.tilt, c.uneven, c.jitter, c.vary)
		fw_synth.SetSpeedParams(c.poe, c.warble, c.sp_pitch, c.sp_bright, c.sp_ring, c.repeat, c.sp_soft, c.drop_ms, c.sp_hit)
	# (2026-11-27) the pawls click as fast as the hub shell overruns the driver: rear wheel spin (its real
	# angle, so a locked / skidding rear is silent) minus the cranks' spin x the drive ratio (the cassette
	# turns with the cranks). Pedalling = driver engaged = silent; legs slowing / stopped = the clicks build
	# with the gap; the cranks settling to the coasting angle or kicked back move them a touch.
	# fs = that overrun as a rim speed (m/s), so loudness / the fast-click tone follow it too.
	var fs: float = _hub_overrun(dt, st) * float(st.RWR)
	if OLD_FW:
		fs = va if (st.throttle_in < 0.1 and va > 0.12) else 0.0
	var coasting: bool = fs > 0.12 and not st.crash_on
	if FreewheelSound.preview_speed > 0.0 and va < 0.5:
		fs = FreewheelSound.preview_speed; coasting = true
	var poe := FreewheelSound.get_value("poe")
	fw_clicks = fs / st.RWR / TAU * poe if coasting else 0.0
	# each click is as loud at walking pace as at speed (the pawl's spring sets the hit): only a short ramp
	# so the first click doesn't pop (2026-11-28; was smoothstep(0.1, 1.0 m/s): slow ticks at ~25 %)
	var amp_ramp := smoothstep(0.1, 1.0, fs) if FW_OLDSYN else smoothstep(0.12, 0.25, fs)
	fw_amp = 0.23 * FreewheelSound.get_value("vol") * amp_ramp 		* (1.0 - FreewheelSound.get_value("fade") * clampf((fs - 8.0) / 10.0, 0.0, 1.0))
	_fw_hits(dt, st)
	# at speed the pawls have less time to drop: higher, brighter, shorter clicks (0 slow .. 1 full)
	# (the new synth works out the pawls' float itself from the click rate; the old one took km/h 12 .. 60)
	fw_fast = smoothstep(12.0 / 3.6, 60.0 / 3.6, fs) if FW_OLDSYN else (fw_synth.Fast if fw_synth != null else 0.0)
	_update_chain(dt, va, on_ground, st)
	# the recorded layers only follow the live ride (in a replay / the map / photo mode they fade out)
	var live: bool = not (game.replay_on or game.photo or (game.paper_map != null and game.paper_map.busy()))
	layers.update(dt, game.phys, va if live else 0.0, on_ground and live, live)
	if Env.s("BMX_LAYER_PROBE") != "": layers.probe(dt)
	_fill()
	_fill_fw()
	if Env.s("BMX_AUDIO_PROBE") != "" and Engine.get_process_frames() % 30 == 0:
		print("FW v=%.1f vib=%.3f hit=%.2f shake=%.2f wr=%.1f air=%s knocks=%d hub_w=%.1f pedal=%.2f clicks/s=%.0f amp=%.2f fast=%.2f peak=%.3f | GRAVEL surf=%d amp=%.2f wind=%.2f | CHAIN db=%.1f rate=%.2f crank_w=%.1f" % [va, _fw_vibp, _fw_hitp, _fw_shake, float(st.wr_w) if "wr_w" in st else 0.0, st.air, _fw_knocks, _hub_w, st.pedal, fw_clicks, fw_amp, fw_fast, fw_peak, st.surf, g_amp, wind, chain.volume_db, chain.pitch_scale, _crank_w])
		fw_peak = 0.0; _fw_vibp = 0.0; _fw_hitp = 0.0


# hits on the rear wheel: a sharp change of its vertical speed (a rock, a root, a landing) knocks the hub,
# and the pawls riding the ratchet bounce = a short loose rattle (FreewheelSynth.Knock); rough ground's
# steady shaking makes the clicks uneven in loudness (the hub never sits still)
var _fw_knocks := 0
var _fw_vibp := 0.0; var _fw_hitp := 0.0
var _fw_vr := 0.0; var _fw_rair := true; var _fw_shake := 0.0; var _fw_kcool := 0.0
func _fw_hits(dt: float, st) -> void:
	if dt <= 0.0 or not ("wr_knock" in st) or OLD_FW: return
	var rair: bool = bool(st.air) or bool(st.rear_air)
	var hit := 0.0
	if "wr_knock" in st:
		hit = float(st.wr_knock); st.wr_knock = 0.0
	var vib := 0.0   # rms one-tick change of the rear wheel's vertical speed this frame (m/s)
	if "wr_vibn" in st and int(st.wr_vibn) > 0:
		vib = sqrt(float(st.wr_vib2) / int(st.wr_vibn)); st.wr_vib2 = 0.0; st.wr_vibn = 0
	_fw_vibp = maxf(_fw_vibp, vib); _fw_hitp = maxf(_fw_hitp, hit)
	if rair:
		hit = 0.0
	elif _fw_rair:
		hit = maxf(hit, 2.5)   # the rear wheel touching down (the tyre grabs it back to the ground speed)
	_fw_rair = rair
	_fw_kcool = maxf(0.0, _fw_kcool - dt)
	# one physics tick: 0.4 m/s = a small knock .. 3 m/s+ = a hard hit
	if hit > 0.4 and _fw_kcool <= 0.0 and fw_synth != null and fw_clicks > 0.0:
		fw_synth.Knock(clampf((hit - 0.4) / 2.6, 0.0, 1.0))
		_fw_knocks += 1
		_fw_kcool = 0.05
	# road vibration: the rear wheel's vertical speed changing tick to tick (measured on seed 4242's trail:
	# ~0.03 m/s smooth packed dirt .. 0.2-0.35 rough, 0.5 rocks) -> 0..1 into the synth, per click
	var sh_to := 0.0 if rair else clampf((vib - 0.03) / 0.3, 0.0, 1.0)
	_fw_shake += (sh_to - _fw_shake) * minf(1.0, dt * (20.0 if sh_to > _fw_shake else 6.0))
	if fw_synth != null: fw_synth.SetShake(_fw_shake)

func _fill_fw() -> void:
	if fw_synth == null: return
	var n := fw_pb.get_frames_available()
	if n <= 0: return
	var buf: PackedVector2Array = fw_synth.Render(n, fw_clicks, fw_amp, fw_fast)
	if Env.s("BMX_AUDIO_PROBE") != "":
		for v in buf: fw_peak = maxf(fw_peak, absf(v.x))
	fw_pb.push_buffer(buf)

func _fill() -> void:
	var n := pb.get_frames_available()
	if n <= 0: return
	if bed != null:   # C#: the per-sample bed (wind, splash, gravel mixed in, clamped)
		var gb: PackedVector2Array = gravel.Render(n, g_speed, g_amp, g_tone, g_crack, g_rumble) if gravel != null else PackedVector2Array()
		var bb: PackedVector2Array = bed.Render(n, wind_tone, roll_tone, wind, roll, skid, water, whistle, gb)
		if not shots.is_empty(): bb = _mix_shots(bb, n)
		pb.push_buffer(bb)
		return
	var buf := PackedVector2Array()
	buf.resize(n)
	var aw := wind_tone  # wind low-pass, brighter with speed
	var ar := roll_tone  # roll low-pass
	# gusts: random swells (as RideBedSynth.cs), no fixed LFOs: a steady sine read as "whoosh whoosh" in rhythm
	var g_dt := 1.0 / RATE
	var g_a := 1.0 / (RATE * 0.35)
	var wl := 0.0
	var wr := 0.0
	for i in n:
		gust_ph -= g_dt
		if gust_ph <= 0.0: _g_t = randf_range(0.62, 0.94); gust_ph = randf_range(0.7, 2.6)
		gust_ph2 -= g_dt
		if gust_ph2 <= 0.0: _p_t = randf_range(-0.16, 0.16); gust_ph2 = randf_range(1.2, 3.6)
		_g_v += (_g_t - _g_v) * g_a; _g_v2 += (_g_v - _g_v2) * g_a
		_p_v += (_p_t - _p_v) * g_a; _p_v2 += (_p_v - _p_v2) * g_a
		var gust := _g_v2
		# wind: two-pole low-passed noise, separate noise per ear for a wide stereo rush
		var w := randf() * 2.0 - 1.0
		lp_w += (w - lp_w) * aw
		lp_w2 += (lp_w - lp_w2) * aw
		var wn := randf() * 2.0 - 1.0
		lp_wR += (wn - lp_wR) * aw
		lp_wR2 += (lp_wR - lp_wR2) * aw
		# soft whistle past the helmet at speed: band-passed noise
		bp_hi += (w - bp_hi) * 0.18
		bp_lo += (bp_hi - bp_lo) * 0.06
		var wh := (bp_hi - bp_lo) * whistle * (0.45 + 0.6 * (gust - 0.62) / 0.32)
		var wamp := wind * 2.6 / sqrt(maxf(aw, 0.02) / 0.03)  # keep loudness even as it brightens
		wl = lp_w2 * wamp * gust * (1.0 + _p_v2) + wh
		wr = lp_wR2 * wamp * gust * (1.0 - _p_v2) + wh
		var s := 0.0
		# tyre roll: low rumble (only without the C# gravel synth)
		var w2 := randf() * 2.0 - 1.0
		if gravel == null:
			lp_r += (w2 - lp_r) * ar
			lp_r2 += (lp_r - lp_r2) * ar
			s += lp_r2 * roll * 2.2
		# splash: high-passed hiss (skids too, but only without the gravel synth)
		hp_s += (w2 - hp_s) * 0.25
		s += (w2 - hp_s) * ((skid * 0.35 if gravel == null else 0.0) + water * 0.25)
		buf[i] = Vector2(s + wl, s + wr)
	if gravel != null:
		var gb: PackedVector2Array = gravel.Render(n, g_speed, g_amp, g_tone, g_crack, g_rumble)
		for i in n: buf[i] += gb[i]
	pb.push_buffer(_mix_shots(buf, n))

## one-shots (crunches, wood, gear clicks) mixed on top of buf, clamped; returns it (packed arrays are values)
func _mix_shots(buf: PackedVector2Array, n: int) -> PackedVector2Array:
	for sh in shots:
		var kind: String = sh[0]
		var t0: float = sh[1]
		var amp: float = sh[2]
		for i in n:
			var t := t0 + i / RATE
			var v := 0.0
			match kind:
				"thud":
					v = sin(TAU * (70.0 - t * 60.0) * t) * exp(-t * 14.0) * amp + (randf() * 2 - 1) * exp(-t * 40.0) * amp * 0.4
				"crunch":
					v = (randf() * 2 - 1) * exp(-t * 9.0) * amp * (0.6 + 0.4 * sin(t * 900.0))
				"wood":
					v = _wood_sample(t, sh[3]) * amp
			buf[i] += Vector2(v, v)
		sh[1] = t0 + n / RATE
	shots = shots.filter(func(sh): return sh[1] < (1.6 if sh[0] == "wood" else 0.8))
	for i in n:
		buf[i] = Vector2(tanh(buf[i].x), tanh(buf[i].y))   # soft clip: stacked hits squash instead of cracking
	return buf
