extends SceneTree
## Renders SlamSynth (C#) to mono 16-bit 48 kHz WAVs, one per landing type, three seeds each:
## godot --headless -s res://tools/slam_render.gd -- outdir [vary=0.12]
## (small / medium / big drop, sideways landing, and the bad-landing clatter that follows a heavy one)
func _init() -> void:
	var a := OS.get_cmdline_user_args()
	var dir := a[0] if a.size() > 0 else "user://"
	var vary := 0.12
	for s in a.slice(1):
		var kv: PackedStringArray = s.split("=")
		if kv[0] == "vary": vary = float(kv[1])
	var syn = load("res://scripts/game/SlamSynth.cs").new()
	# name, size, side, kind
	var types := [["small", 0.1, 0.0, 0], ["medium", 0.5, 0.0, 0], ["big", 1.0, 0.0, 0], ["sideways", 0.55, 0.8, 0], ["bad", 0.7, 0.0, 1]]
	for t in types:
		for seed in 3:
			var t0 := Time.get_ticks_usec()
			var x: PackedFloat32Array = syn.Render(seed + 1, vary, 0.63, t[1], t[2], t[3])
			var ms := (Time.get_ticks_usec() - t0) / 1000.0
			var n := x.size()
			var data := PackedByteArray()
			data.resize(n * 2)
			for i in n: data.encode_s16(i * 2, int(clampf(x[i], -1.0, 1.0) * 32767.0))
			var path := "%s/slam_%s_%d.wav" % [dir, t[0], seed + 1]
			var f := FileAccess.open(path, FileAccess.WRITE)
			f.store_buffer("RIFF".to_ascii_buffer()); f.store_32(36 + n * 2)
			f.store_buffer("WAVEfmt ".to_ascii_buffer()); f.store_32(16); f.store_16(1); f.store_16(1)
			f.store_32(48000); f.store_32(96000); f.store_16(2); f.store_16(16)
			f.store_buffer("data".to_ascii_buffer()); f.store_32(n * 2); f.store_buffer(data)
			f.close()
			print("SLAM %s %.1f ms" % [path.get_file(), ms])
	quit()
