extends SceneTree
## Renders PassBySynth (C#) to stereo 16-bit 48 kHz WAVs: riding under a gate at several speeds / offsets.
## godot --headless -s res://tools/passby_render.gd -- outdir
func _init() -> void:
	var a := OS.get_cmdline_user_args()
	var dir := a[0] if a.size() > 0 else "user://"
	var syn = load("res://scripts/game/PassBySynth.cs").new()
	syn.Render(1, 10.0, 2.3, 5.5, 0.0, 0.6, 0.25, 0.8)   # (first call pays the C# JIT: not timed)
	# name, speed m/s, half, clear, lat, depth, flap  (gantry: half ~2.3, clear ~5.5; race gate: half 3.5, clear 3.25)
	var cases := [["gantry_25kmh", 7.0, 2.3, 5.5, 0.0, 0.6, 0.25], ["gantry_45kmh", 12.5, 2.3, 5.5, 0.0, 0.6, 0.25],
		["gantry_65kmh", 18.0, 2.3, 5.5, 0.0, 0.6, 0.25], ["gantry_offset_left", 14.0, 2.3, 5.5, -1.5, 0.6, 0.25],
		["racegate_45kmh", 12.5, 3.5, 3.25, 0.0, 0.3, 1.0], ["racegate_65kmh", 18.0, 3.5, 3.25, 0.4, 0.3, 1.0]]
	for c in cases:
		var t0 := Time.get_ticks_usec()
		var data: PackedByteArray = syn.Render(7, c[1], c[2], c[3], c[4], c[5], c[6], 0.8)
		var ms := (Time.get_ticks_usec() - t0) / 1000.0
		var path := "%s/passby_%s.wav" % [dir, c[0]]
		var f := FileAccess.open(path, FileAccess.WRITE)
		f.store_buffer("RIFF".to_ascii_buffer()); f.store_32(36 + data.size())
		f.store_buffer("WAVEfmt ".to_ascii_buffer()); f.store_32(16); f.store_16(1); f.store_16(2)
		f.store_32(48000); f.store_32(192000); f.store_16(4); f.store_16(16)
		f.store_buffer("data".to_ascii_buffer()); f.store_32(data.size()); f.store_buffer(data)
		f.close()
		print("PASSBY %s %.1f ms" % [path.get_file(), ms])
	quit()
