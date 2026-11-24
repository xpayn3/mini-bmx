extends SceneTree
## RouteStyle.grade: the C# land (TerrainFieldCs.landform) must equal the GDScript one at every grade (EXACT), and the
## trail's fall / steepest 100 m per grade. -s res://tools/route_grade_probe.gd [-- seed]

func _init() -> void:
	var bad_all := 0
	for sd in [4242, 5, 12]:
		for g in [1.0, 0.6, 1.3, 1.7, 100.0, 101.0, 102.0, 103.0, 104.0]:   # 100+ = a biome pick (1..4 = green, rocky, dunes, canyons)
			var f := TerrainField.new()
			f.setup(sd, {"grade": g} if g < 50.0 else {"biome": g - 100.0})
			var cs = load("res://scripts/world/TerrainFieldCs.cs").new()
			cs.setup_from(f)
			var bad := 0
			var cnt := 0
			var x := -320.0
			while x < 6200.0:
				for dz in [-300.0, -90.0, 0.0, 60.0, 200.0]:
					var z: float = f.zc(x) + dz
					cnt += 1
					if f.landform(x, z) != cs.landform(x, z): bad += 1
				x += 37.0
			var C: TrailCourse = f.course
			var steep := 0.0
			for i in range(0, C.n - 50, 5): steep = maxf(steep, absf(C.E[i] - C.E[i + 50]))
			print("GRADE seed=%d g=%.1f compared=%d mismatches=%d fall=%.0f m steepest100=%.1f m n=%d" % [sd, g, cnt, bad, C.E[0] - C.E[C.n - 1], steep, C.n])
			bad_all += bad
	print("GRADE ", "EXACT" if bad_all == 0 else "MISMATCH %d" % bad_all)
	quit()
