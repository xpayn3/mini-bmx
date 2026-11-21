extends SceneTree
## Renders FreewheelSynth (C#) to a mono 16-bit WAV and prints its level + brightness.
## godot --headless -s res://tools/freewheel_render.gd -- out.wav [kmh=30] [secs=4] [sweep=1] [<FreewheelSound key>=v ...]
## sweep=1: speed runs 5 -> kmh over the file. Uses the Stock values unless overridden.

func _init() -> void:
	var a := OS.get_cmdline_user_args()
	var out := a[0] if a.size() > 0 else "user://freewheel.wav"
	var c := {"kmh": 30.0, "secs": 4.0, "sweep": 0.0}
	for r in FreewheelSound.PARAMS: c[r[0]] = float(r[2])
	for s in a.slice(1):
		var kv: PackedStringArray = s.split("=")
		c[kv[0]] = float(kv[1])
	var syn = load("res://scripts/game/FreewheelSynth.cs").new()
	syn.SetParams(c.pitch, c.ring, c.crack, c.crack_len, c.detune, c.tilt, c.uneven, c.jitter, c.vary)
	syn.SetSpeedParams(c.poe, c.warble, c.sp_pitch, c.sp_bright, c.sp_ring, c.repeat, c.sp_soft)
	var sr := 44100.0
	var n := int(c.secs * sr)
	var data := PackedByteArray()
	data.resize(n * 2)
	var i := 0
	var sq := 0.0; var dsq := 0.0; var prev := 0.0; var peak := 0.0
	while i < n:
		var m := mini(512, n - i)
		var kmh: float = lerpf(5.0, c.kmh, float(i) / n) if c.sweep > 0.0 else c.kmh
		var fs := kmh / 3.6
		var clicks: float = fs / 0.35 / TAU * c.poe
		var amp: float = 0.23 * c.vol * (1.0 - c.fade * clampf((fs - 8.0) / 10.0, 0.0, 1.0))
		var sp0: float = c.sp_from / 3.6
		var fast := smoothstep(sp0, maxf(sp0 + 0.5, c.sp_full / 3.6), fs)
		var buf: PackedVector2Array = syn.Render(m, clicks, amp, fast)
		for v in buf:
			var x := clampf(v.x, -1.0, 1.0)
			sq += x * x; dsq += (x - prev) * (x - prev); prev = x; peak = maxf(peak, absf(x))
			data.encode_s16(i * 2, int(x * 32767.0))
			i += 1
	var f := FileAccess.open(out, FileAccess.WRITE)
	f.store_buffer("RIFF".to_ascii_buffer()); f.store_32(36 + n * 2)
	f.store_buffer("WAVEfmt ".to_ascii_buffer()); f.store_32(16); f.store_16(1); f.store_16(1)
	f.store_32(44100); f.store_32(88200); f.store_16(2); f.store_16(16)
	f.store_buffer("data".to_ascii_buffer()); f.store_32(n * 2); f.store_buffer(data)
	f.close()
	# bright = rms of the sample-to-sample difference / rms: rises with the spectrum's centre
	print("FREEWHEEL kmh=%.0f rms=%.4f peak=%.3f bright=%.3f -> %s" % [c.kmh, sqrt(sq / n), peak, sqrt(dsq / maxf(sq, 1e-12)), out])
	quit()
