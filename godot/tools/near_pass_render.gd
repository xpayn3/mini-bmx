extends SceneTree
## Renders close pass-bys (PassBySynth.RenderNear) to 48 kHz stereo WAVs, one per case, for listening / checking.
## godot --headless -s res://tools/near_pass_render.gd -- outdir
func _init() -> void:
	var a := OS.get_cmdline_user_args()
	var dir := a[0] if a.size() > 0 else "user://"
	var syn = load("res://scripts/game/PassBySynth.cs").new()
	# name, speed, r0, side, up, kind (0 rock 1 bush 2 trunk), size
	var cases := [["rock_right_30cm_12ms", 12.0, 0.3, 1.0, -0.15, 0, 1.0], ["trunk_left_20cm_14ms", 14.0, 0.2, -1.0, 0.0, 2, 8.0],
		["bush_left_10cm_10ms", 10.0, 0.1, -1.0, 0.0, 1, 1.4], ["bush_right_80cm_16ms", 16.0, 0.8, 1.0, -0.2, 1, 1.2],
		["trunk_right_1m_18ms", 18.0, 1.0, 1.0, 0.0, 2, 10.0], ["boulder_left_1m5_16ms", 16.0, 1.5, -1.0, 0.0, 0, 2.2]]
	for c in cases:
		var pcm: PackedByteArray = syn.RenderNear(7, c[1], c[2], c[3], c[4], c[5], c[6], 0.85)
		var f := FileAccess.open(dir.path_join(c[0] + ".wav"), FileAccess.WRITE)
		f.store_buffer("RIFF".to_ascii_buffer()); f.store_32(36 + pcm.size())
		f.store_buffer("WAVEfmt ".to_ascii_buffer()); f.store_32(16); f.store_16(1); f.store_16(2)
		f.store_32(48000); f.store_32(192000); f.store_16(4); f.store_16(16)
		f.store_buffer("data".to_ascii_buffer()); f.store_32(pcm.size()); f.store_buffer(pcm)
		f.close()
		print("NEARRENDER ", c[0])
	quit()
