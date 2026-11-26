extends SceneTree
## each jump run: where, its trail grade (course E) start -> end, the land's grade under it, what was built in it. -- seed
func _init() -> void:
	var t := Terrain.new(int(OS.get_cmdline_user_args()[0]))
	var f: TerrainField = t.field
	var C = f.course
	for run in C.runs():
		if run[2] != TrailCourse.JUMP: continue
		var s0: float = run[0] * 2.0; var s1: float = run[1] * 2.0
		var lf0 := f.landform(C.X[run[0]], C.Z[run[0]]); var lf1 := f.landform(C.X[run[1]], C.Z[run[1]])
		var built := []
		for ft in f.route_feats:
			if ft.s >= s0 - 5 and ft.s <= s1: built.append(ft.type)
		print("JRUN s=%.0f..%.0f len=%.0f trail_grade=%.1f%% land_grade=%.1f%% built=%s" % [s0, s1, s1 - s0, 100.0 * (C.E[run[1]] - C.E[run[0]]) / (s1 - s0), 100.0 * (lf1 - lf0) / (s1 - s0), str(built)])
	t.free(); quit()
