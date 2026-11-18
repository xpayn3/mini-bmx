extends Node
## Procedural ride sound (the web version was silent): wind that rises with speed, tyre roll whose
## tone follows the surface, skid hiss, splashes, and one-shot
## crunches / gear clicks, synthesised into one AudioStreamGenerator; plus the freewheel, synthesised
## in C# (FreewheelSynth.cs, modelled on a real hub) on its own 44.1 kHz generator for a crisp top end.

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
var bp_s := 0.0
var lp_wt := 0.0
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
const FW_POE := 24.0   # pawl clicks per wheel turn
var fw := AudioStreamPlayer.new()
var fw_pb: AudioStreamGeneratorPlayback
var fw_synth = null    # FreewheelSynth (C#); null on the non-.NET Godot -> no freewheel
var fw_clicks := 0.0
var fw_amp := 0.0
var fw_peak := 0.0
var pan := 0.0
# one-shots: [kind, t, amp]
var shots: Array = []

func _ready() -> void:
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = RATE
	gen.buffer_length = 0.12
	player.stream = gen
	player.bus = "SFX" if AudioServer.get_bus_index("SFX") >= 0 else "Master"
	add_child(player)
	player.play()
	pb = player.get_stream_playback()
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

func thud(power: float) -> void: shots.append(["thud", 0.0, clampf(power * 0.5, 0.2, 1.0)])
func crunch() -> void: shots.append(["crunch", 0.0, 0.8])
func crash() -> void: shots.append(["thud", 0.0, 1.0]); shots.append(["crunch", 0.0, 0.5])
func shift() -> void: shots.append(["click", 0.0, 0.6])

func update_audio(dt: float) -> void:
	if pb == null: return
	var st: BikePhysics = game.phys
	var va := absf(st.v)
	var on_ground := not st.air and not st.crash_on
	var k := minf(1.0, dt * 8)
	# wind: louder AND brighter the faster you go, a touch more in the air (nothing else masks it)
	var wt := clampf(va * va / 260.0, 0, 1) * (0.62 if st.air else 0.55)
	wind += (wt - wind) * minf(1.0, dt * 4)
	wind_tone += ((0.018 + clampf(va / 22.0, 0, 1) * 0.09) - wind_tone) * k
	whistle += ((clampf((va - 9.0) / 10.0, 0, 1) * 0.12) - whistle) * k
	var surf_amp: float = [0.32, 0.22, 0.0, 0.42][st.surf]
	roll += ((clampf(va / 12.0, 0, 1) * surf_amp if on_ground else 0.0) - roll) * k
	roll_tone += (([0.12, 0.2, 0.1, 0.06][st.surf]) - roll_tone) * k
	skid += ((0.5 if (st.skid_fx and on_ground and va > 1) else 0.0) - skid) * minf(1.0, dt * 12)
	water += ((clampf(va / 6, 0, 1) * 0.6 if (st.surf == 2 and on_ground) else 0.0) - water) * k
	# freewheel: the pawls click while the wheel turns but the cranks don't. The click rate follows the
	# rear wheel exactly (FW_POE per turn: slow ticks -> a fast buzz); pedalling stops new clicks at once
	# and the last ones ring out. A little quieter at speed, where the wind takes over.
	var coasting := st.pedal < 0.1 and va > 0.12 and not st.crash_on
	fw_clicks = va / st.RWR / TAU * FW_POE if coasting else 0.0
	fw_amp = 0.23 * smoothstep(0.1, 1.0, va) * (1.0 - 0.3 * clampf((va - 8.0) / 10.0, 0.0, 1.0))
	_fill()
	_fill_fw()
	if OS.get_environment("BMX_AUDIO_PROBE") != "" and Engine.get_process_frames() % 30 == 0:
		print("FW v=%.1f pedal=%.2f clicks/s=%.0f amp=%.2f peak=%.3f" % [va, st.pedal, fw_clicks, fw_amp, fw_peak])
		fw_peak = 0.0


func _fill_fw() -> void:
	if fw_synth == null: return
	var n := fw_pb.get_frames_available()
	if n <= 0: return
	var buf: PackedVector2Array = fw_synth.Render(n, fw_clicks, fw_amp)
	if OS.get_environment("BMX_AUDIO_PROBE") != "":
		for v in buf: fw_peak = maxf(fw_peak, absf(v.x))
	fw_pb.push_buffer(buf)

func _fill() -> void:
	var n := pb.get_frames_available()
	if n <= 0: return
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
		# tyre roll: low rumble
		var w2 := randf() * 2.0 - 1.0
		lp_r += (w2 - lp_r) * ar
		lp_r2 += (lp_r - lp_r2) * ar
		s += lp_r2 * roll * 2.2
		# skid / splash: high-passed hiss
		hp_s += (w2 - hp_s) * 0.25
		s += (w2 - hp_s) * (skid * 0.35 + water * 0.25)
		buf[i] = Vector2(s + wl, s + wr)
	# one-shots, mixed on top
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
				"click":
					v = (randf() * 2 - 1) * exp(-t * 120.0) * amp + sin(TAU * 2400 * t) * exp(-t * 90.0) * amp * 0.3
			buf[i] += Vector2(v, v)
		sh[1] = t0 + n / RATE
	shots = shots.filter(func(sh): return sh[1] < 0.8)
	for i in n:
		buf[i] = buf[i].clamp(Vector2(-1, -1), Vector2(1, 1))
	pb.push_buffer(buf)
