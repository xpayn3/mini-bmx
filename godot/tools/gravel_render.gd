extends SceneTree
## Renders GravelSynth (C#) to a mono 16-bit WAV for comparing with the reference recording.
## godot --headless -s res://tools/gravel_render.gd -- out.wav [speed=8] [amp=1] [tone=700] [crack=0.4] [rumble=1] [secs=20]

func _init() -> void:
	var a := OS.get_cmdline_user_args()
	var out := a[0] if a.size() > 0 else "user://gravel.wav"
	var p := {"speed": 8.0, "amp": 1.0, "tone": 700.0, "crack": 0.4, "rumble": 1.0, "secs": 20.0}
	for s in a.slice(1):
		var kv: PackedStringArray = s.split("=")
		p[kv[0]] = float(kv[1])
	var syn = load("res://scripts/game/GravelSynth.cs").new()
	var n := int(p.secs * 22050.0)
	var data := PackedByteArray()
	data.resize(n * 2)
	var i := 0
	var sq := 0.0
	while i < n:
		var m := mini(512, n - i)
		var buf: PackedVector2Array = syn.Render(m, p.speed, p.amp, p.tone, p.crack, p.rumble)
		for v in buf:
			var x := clampf((v.x + v.y) * 0.5, -1.0, 1.0)
			sq += x * x
			data.encode_s16(i * 2, int(x * 32767.0))
			i += 1
	var f := FileAccess.open(out, FileAccess.WRITE)
	f.store_buffer("RIFF".to_ascii_buffer()); f.store_32(36 + n * 2)
	f.store_buffer("WAVEfmt ".to_ascii_buffer()); f.store_32(16); f.store_16(1); f.store_16(1)
	f.store_32(22050); f.store_32(44100); f.store_16(2); f.store_16(16)
	f.store_buffer("data".to_ascii_buffer()); f.store_32(n * 2); f.store_buffer(data)
	f.close()
	print("GRAVEL rms=%.4f -> %s" % [sqrt(sq / n), out])
	quit()
