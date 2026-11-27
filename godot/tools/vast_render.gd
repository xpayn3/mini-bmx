extends SceneTree
## Renders VastAirSynth's open-landscape ambience loop, played twice in a row (to hear the seam):
## godot --headless -s res://tools/vast_render.gd -- out.wav [seed] [secs]
func _init() -> void:
	var a := OS.get_cmdline_user_args()
	var path := a[0] if a.size() > 0 else "user://vast.wav"
	var seed := int(a[1]) if a.size() > 1 else 3
	var secs := float(a[2]) if a.size() > 2 else 29.0
	var syn = load("res://scripts/game/VastAirSynth.cs").new()
	var t0 := Time.get_ticks_usec()
	var d: PackedByteArray = syn.RenderLoop(seed, secs)
	print("VAST %.0f ms" % ((Time.get_ticks_usec() - t0) / 1000.0))
	d = d + d
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_buffer("RIFF".to_ascii_buffer()); f.store_32(36 + d.size())
	f.store_buffer("WAVEfmt ".to_ascii_buffer()); f.store_32(16); f.store_16(1); f.store_16(2)
	f.store_32(48000); f.store_32(192000); f.store_16(4); f.store_16(16)
	f.store_buffer("data".to_ascii_buffer()); f.store_32(d.size()); f.store_buffer(d)
	f.close()
	quit()
