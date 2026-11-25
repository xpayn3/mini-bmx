extends SceneTree
## Far backdrop grid (C# far_ground) against the field's own ground() along a line east of x0: where do they differ?
## godot --headless --path godot -s res://tools/far_vs_ground.gd -- seed x0 z0

func _init() -> void:
	var seed := 4242
	var x0 := 2150.0
	var z0 := 36.0
	var a := OS.get_cmdline_user_args()
	if a.size() > 2:
		seed = int(a[0]); x0 = float(a[1]); z0 = float(a[2])
	var t := Terrain.new()
	t.use_cs = true
	t.set_seed(seed)
	var f = t.fcs
	var n := 41
	var gx := snappedf(x0, 20.0) - 400.0
	var gz := snappedf(z0, 20.0) - 400.0
	var hg: PackedFloat32Array = f.far_ground(gx, gz, 20.0, n)   # n x n grid, row = z
	var worst := 0.0
	for off in [0, 60, 100, 140, 170, 220, 300]:
		var x := snappedf(x0 + off, 20.0)
		var zi := int(round((snappedf(z0, 20.0) - gz) / 20.0))
		var xi := int(round((x - gx) / 20.0))
		var far_h: float = hg[zi * n + xi]
		var real_h: float = f.ground(x, gz + zi * 20.0)
		print("OFF %4d  x=%.0f  far=%.2f  ground=%.2f  diff=%.2f" % [off, x, far_h, real_h, far_h - real_h])
		worst = maxf(worst, absf(far_h - real_h))
	print("worst diff ", worst)
	root.add_child(t)
	t.queue_free()
	await process_frame
	quit(0)
