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
var gust_ph2 := 0.0
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
var shift_snd: ShiftSound

## drop the C# synths while the engine is still up: if their .NET finalizers run during shutdown
## instead, Godot can crash on exit ("Leaked unsafe reference" -> SEHException). On PREDELETE, not _exit_tree:
## the ride world built during the boot intro is moved into the scene (main.gd), which fires _exit_tree
func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		gravel = null
		bed = null
		fw_synth = null


func _ready() -> void:
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = RATE
	gen.buffer_length = 0.12
	player.stream = gen
	player.bus = "SFX" if AudioServer.get_bus_index("SFX") >= 0 else "Master"
	add_child(player)
	player.play()
	pb = player.get_stream_playback()
	_setup_chain()
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
		fw.bus = player.bus
		add_child(fw)
		fw.play()
		fw_pb = fw.get_stream_playback()

# chain rub: the gravel recording looped very quietly under everything; louder with wheel speed and
# when the chain is loaded (pedalling), silent when stopped or in the air
const CHAIN_DB := -27.0
var chain := AudioStreamPlayer.new()
var chain_amp := 0.0

func _setup_chain() -> void:
	var s = load("res://assets/audio/chain_rub.mp3")
	if s == null: return
	if s is AudioStreamMP3: s.loop = true
	chain.stream = s
	chain.bus = player.bus
	chain.volume_db = -80.0
	add_child(chain)
	chain.play()

func _update_chain(dt: float, va: float, on_ground: bool, pedal: float) -> void:
	if chain.stream == null: return
	var t := clampf(va / 8.0, 0.0, 1.0) * (0.55 + 0.45 * clampf(pedal, 0.0, 1.0)) if on_ground else 0.0
	chain_amp += (t - chain_amp) * minf(1.0, dt * 6.0)
	chain.volume_db = CHAIN_DB + linear_to_db(maxf(chain_amp, 0.0001)) if chain_amp > 0.003 else -80.0
	chain.pitch_scale = 0.8 + clampf(va / 20.0, 0.0, 1.0) * 0.5

func thud(power: float) -> void: shots.append(["thud", 0.0, clampf(power * 0.5, 0.2, 1.0)])
func crunch() -> void: shots.append(["crunch", 0.0, 0.8])

## wooden planks breaking: a sharp splintering crack, then the pieces knocking and bouncing on the ground.
## Each hit is a plank ringing (free-free beam modes, ratio 1 : 2.76 : 5.40) with a tick of noise; the hits
## come faster and quieter as the pieces settle, each with its own pitch. Built per call so no two sound alike.
func wood_crash(power: float = 1.0) -> void:
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
func crash() -> void: shots.append(["thud", 0.0, 1.0]); shots.append(["crunch", 0.0, 0.5])
## a gear change: the user's shifter recording (game/shift_sound.gd)
func shift(d: int = 1) -> void: if shift_snd: shift_snd.shift(d)

func update_audio(dt: float) -> void:
	if pb == null: return
	var st: BikePhysics = game.phys
	var va := absf(st.v)
	var on_ground := not st.air and not st.crash_on
	# the map / photo mode freeze the ride (time_scale 0) but leave the last speed in the physics: without
	# this the tyres, wind and chain kept playing under the paper
	if (game.paper_map != null and game.paper_map.busy()) or game.photo:
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
	var fs: float = va
	# (the raw key, not the smoothed pedal: that took ~0.4 s to fall under the threshold after letting go)
	var coasting := st.throttle_in < 0.1 and va > 0.12 and not st.crash_on
	if FreewheelSound.preview_speed > 0.0 and va < 0.5:
		fs = FreewheelSound.preview_speed; coasting = true
	var poe := FreewheelSound.get_value("poe")
	fw_clicks = fs / st.RWR / TAU * poe if coasting else 0.0
	fw_amp = 0.23 * FreewheelSound.get_value("vol") * smoothstep(0.1, 1.0, fs) 		* (1.0 - FreewheelSound.get_value("fade") * clampf((fs - 8.0) / 10.0, 0.0, 1.0))
	_update_chain(dt, va, on_ground, st.pedal)
	_fill()
	_fill_fw()
	if Env.s("BMX_AUDIO_PROBE") != "" and Engine.get_process_frames() % 30 == 0:
		print("FW v=%.1f pedal=%.2f clicks/s=%.0f amp=%.2f peak=%.3f | GRAVEL surf=%d amp=%.2f wind=%.2f" % [va, st.pedal, fw_clicks, fw_amp, fw_peak, st.surf, g_amp, wind])
		fw_peak = 0.0


func _fill_fw() -> void:
	if fw_synth == null: return
	var n := fw_pb.get_frames_available()
	if n <= 0: return
	var buf: PackedVector2Array = fw_synth.Render(n, fw_clicks, fw_amp)
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
	# slow gusts: two incommensurate LFOs so the wind breathes instead of hissing flat
	var g_inc := 0.23 / RATE
	var g_inc2 := 0.61 / RATE
	var wl := 0.0
	var wr := 0.0
	for i in n:
		gust_ph = fmod(gust_ph + g_inc, 1.0)
		gust_ph2 = fmod(gust_ph2 + g_inc2, 1.0)
		var gust := 0.78 + 0.16 * sin(TAU * gust_ph) + 0.08 * sin(TAU * gust_ph2)
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
		var wh := (bp_hi - bp_lo) * whistle * (0.6 + 0.4 * sin(TAU * gust_ph2 * 3.0))
		var wamp := wind * 2.6 / sqrt(maxf(aw, 0.02) / 0.03)  # keep loudness even as it brightens
		wl = lp_w2 * wamp * gust + wh
		wr = lp_wR2 * wamp * (1.56 - gust) + wh
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
		buf[i] = buf[i].clamp(Vector2(-1, -1), Vector2(1, 1))
	return buf
