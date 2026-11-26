extends SceneTree
## C# vs GDScript ground over every drop's spur in the first 4 km (the general cmp may not sample one). -- [seed]
func _init() -> void:
	var sd := int(OS.get_cmdline_user_args()[0]) if OS.get_cmdline_user_args().size() > 0 else 5
	var tg := Terrain.new(); tg.use_cs = false; tg.set_seed(sd)
	var tc := Terrain.new(); tc.use_cs = true; tc.set_seed(sd)
	var fg: TerrainField = tg.field
	var fc = tc.fcs
	var C = fg.course
	var n := 0; var bad := 0; var worst := 0.0; var lifted := 0
	for dr in C.drops:
		for i in range(dr[0], mini(dr[1], C.n - 1), 4):
			for ox in range(-48, 49, 6):
				for oz in range(-48, 49, 6):
					var x: float = C.X[i] + ox; var z: float = C.Z[i] + oz
					var a := fg.ground(x, z); var b: float = fc.ground(x, z)
					n += 1
					if a != b: bad += 1; worst = maxf(worst, absf(a - b))
					if fg._spur(x, z) > 0.5: lifted += 1
	print("SPURCMP seed=%d drops=%d points=%d lifted=%d mismatches=%d worst_mm=%.4f" % [sd, C.drops.size(), n, lifted, bad, worst * 1000.0])
	tg.free(); tc.free()
	quit()
