extends SceneTree
## -s res://tools/feat_at_probe.gd --headless -- <seed> x,z [x,z ...]: which route feature (type, start, along) is at those
## points of the endless trail (grows the course far enough first) + the height profile across it

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var sd := int(args[0])
	var f := TerrainField.new()
	f.setup(sd)
	var want_x := 0.0
	for a in args.slice(1): want_x = maxf(want_x, float(a.split(",")[0]))
	var guard := 0
	while f.course.end_x() < want_x + 200.0 and guard < 10:
		var k = f.fork()
		k.grow_course(f.course.end_x() + Terrain.GROW_STEP)
		f.adopt_course(k)
		guard += 1
	for a in args.slice(1):
		var p := a.split(",")
		var x := float(p[0]); var z := float(p[1])
		var best = null; var bd := INF
		for rf in f.route_feats:
			var d := Vector2(rf.x - x, rf.z - z).length()
			if d < bd: bd = d; best = rf
		if best == null: print("FEATAT %s none" % a); continue
		var u: float = (x - best.x) * best.dx + (z - best.z) * best.dz
		print("FEATAT %s -> %s start=(%.1f,%.1f) dist=%.1f along=%.1f len=%.1f" % [a, best.type, best.x, best.z, bd, u, TrailFeatures.PROFILES[best.type].length if TrailFeatures.PROFILES.has(best.type) else -1.0])
	quit()
