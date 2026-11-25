extends SceneTree
## noise_d gradient vs central differences, and its value vs noise(); also C# vs GDScript noise_d. -s res://tools/noise_d_probe.gd
func _init() -> void:
	var f := TerrainField.new()
	f.setup(4242, {})
	var cs = load("res://scripts/world/TerrainFieldCs.cs").new()
	cs.setup_from(f)
	var worst := 0.0; var vbad := 0; var cbad := 0
	var e := 1e-5
	for i in 20000:
		var x := fmod(i * 7.31, 400.0) - 100.0 + 0.123
		var y := fmod(i * 3.77, 300.0) - 80.0 + 0.456
		var v := f.noise_d(x, y)
		var gx := f._ndx; var gy := f._ndy
		if v != f.noise(x, y): vbad += 1
		var fx := (f.noise(x + e, y) - f.noise(x - e, y)) / (2 * e)
		var fy := (f.noise(x, y + e) - f.noise(x, y - e)) / (2 * e)
		worst = maxf(worst, maxf(absf(fx - gx), absf(fy - gy)))
		var vc: float = cs.noise_d(x, y)
		if vc != v or cs._ndx != gx or cs._ndy != gy: cbad += 1
	print("NOISED worst_grad_err=%s value_mismatch=%d cs_mismatch=%d" % [str(worst), vbad, cbad])
	quit()
