extends SceneTree
## built route jumps vs the trail's grade under them (15 m before the lip .. end of the landing): how many sit on a climb,
## and the riders' speed there. -- [seeds...]
func _init() -> void:
	var a := OS.get_cmdline_user_args()
	var seeds: Array = [4242, 5, 12, 2, 31]
	if not a.is_empty():
		seeds = []
		for x in a: seeds.append(int(x))
	var tot := 0; var up := 0; var slow := 0
	for sd in seeds:
		var t := Terrain.new(int(sd))
		var f: TerrainField = t.field
		var C = f.course
		var jr := 0; var jm := 0.0
		for run in C.runs():
			if run[2] == TrailCourse.JUMP: jr += 1; jm += (run[1] - run[0]) * 2.0
		var on_j := 0; var on_r := 0
		for ft in f.route_feats:
			if not TerrainField.AIR_TYPES.has(ft.type): continue
			if C.KD[clampi(int(ft.s / 2.0), 0, C.n - 1)] == TrailCourse.JUMP: on_j += 1
			else: on_r += 1
		print("SECTIONS seed=%d len=%.0f jump_runs=%d jump_m=%.0f jumps_in_runs=%d jumps_on_road=%d" % [sd, C.length, jr, jm, on_j, on_r])
		for ft in f.route_feats:
			if not TerrainField.AIR_TYPES.has(ft.type): continue
			var g: float = (f._course_e(ft.s + ft.len) - f._course_e(ft.s - 15.0)) / (ft.len + 15.0)
			var v: float = C.VA[clampi(int((ft.s + 12.0) / 2.0), 0, C.n - 1)] * TerrainField.RIDER_K
			tot += 1
			if g > 0.01: up += 1; print("UPHILL seed=%d s=%.0f %s grade=%.1f%% v=%.1f" % [sd, ft.s, ft.type, g * 100.0, v])
			if v < 8.5 * 0.85: slow += 1
		t.free()
	print("REJECTS ", TerrainField.REJECTS)
	print("UPHILLSUM jumps=%d uphill=%d slow=%d" % [tot, up, slow])
	quit()
