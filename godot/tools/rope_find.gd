extends SceneTree
## lists the rope-bridge / gorge route features of a few seeds (to pick test worlds), and for every rope
## canyon compares the C# ground with the GDScript one on a 1.5 m grid over the whole canyon (must be EXACT)
## and checks the trail itself never runs through it outside the bridge
func _init() -> void:
	var bad := 0
	var cmp := 0
	for sd in [4242, 5, 7, 12, 99]:
		var tg := Terrain.new()
		tg.use_cs = false
		tg.set_seed(sd)
		var tc := Terrain.new()
		tc.use_cs = true
		tc.set_seed(sd)
		var f: TerrainField = tg.field
		var out := []
		for j in f.route_feats:
			if j.type != "rope" and j.type != "gorge":
				continue
			out.append("%s@%d" % [j.type, int(j.s)])
			if j.type != "rope":
				continue
			var miss := 0
			for a in range(-8, 60):
				for b in range(-36, 37):
					var u := a * 0.83 - 2.0
					var w := b * 1.37
					var x: float = j.x + j.dx * u - j.dz * w
					var z: float = j.z + j.dz * u + j.dx * w
					cmp += 1
					if f.ground(x, z) != tc.fcs.ground(x, z):
						miss += 1
			# the trail outside the bridge: never down in the canyon
			var low := 0
			var C := f.course
			for i in C.n:
				var si := i * TrailCourse.STEP
				if absf(si - j.s - j.len * 0.5) > 400.0 or (si > j.s - 1.0 and si < j.s + j.len + 1.0):
					continue
				var rx: float = C.X[i] - j.x
				var rz: float = C.Z[i] - j.z
				if f.canyon_dig(j.s, j.len, rx * j.dx + rz * j.dz, -rx * j.dz + rz * j.dx) < -0.2:
					low += 1
			print("CANYON seed %d s=%d: C# vs GD mismatches %d, trail points in the canyon %d" % [sd, int(j.s), miss, low])
			bad += miss + low
		print("SEED ", sd, " ", out)
		tg.free()
		tc.free()
	print("ROPE CANYONS: %s (%d comparisons)" % ["PASS" if bad == 0 else "FAIL", cmp])
	quit()
