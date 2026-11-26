extends SceneTree
## the start peak and the trail down it: summit height, where the trail starts, its height every 200 m, the grade per 100 m,
## the steepest 50 m, how much is steeper than 15 / 25 / 35 %, and the flanks (land 150 / 300 / 600 m out from the trail).
## -- [seed]
func _init() -> void:
	var a := OS.get_cmdline_user_args()
	var sd := int(a[0]) if a.size() > 0 else 4242
	var t := Terrain.new(sd)
	var f: TerrainField = t.field
	var C = f.course
	var line := ""
	var s := 0.0
	var steep := [0.0, 0.0, 0.0]; var worst := 0.0
	while s < 3400.0:
		var p: Array = C.at(s)
		var h := f.ground(p[0], p[1])
		if fmod(s, 200.0) < 1.0: line += "%.0f:%.0f " % [s, h]
		var p2: Array = C.at(s + 50.0)
		var g := (h - f.ground(p2[0], p2[1])) / 50.0
		worst = maxf(worst, g)
		for k in 3:
			if g > [0.15, 0.25, 0.35][k]: steep[k] += 10.0
		s += 10.0
	print("PEAK seed=%d hill_top(0)=%.0f start ground=%.0f" % [sd, f.hill_top(0.0), f.ground(C.X[0], C.Z[0])])
	print("PEAK trail ", line)
	print("PEAK steepest 50 m %.0f %%, m steeper than 15/25/35 %%: %.0f / %.0f / %.0f" % [worst * 100.0, steep[0], steep[1], steep[2]])
	for s2 in [300.0, 1000.0, 1800.0, 2500.0]:
		var p: Array = C.at(s2)
		var nx: float = -p[3]; var nz: float = p[2]
		var row := ""
		for o in [0.0, 75.0, 150.0, 300.0, 600.0]:
			row += "%.0f:%.0f/%.0f " % [o, f.ground(p[0] + nx * o, p[1] + nz * o), f.ground(p[0] - nx * o, p[1] - nz * o)]
		print("PEAK flank s=%.0f  %s" % [s2, row])
	t.free(); quit()
