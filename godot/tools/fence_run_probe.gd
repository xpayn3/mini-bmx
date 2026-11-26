extends SceneTree
## which course run a fence piece starting at (x, z) belongs to, before and after one growth step. -- seed x z
func _init() -> void:
	var a := OS.get_cmdline_user_args()
	var t := Terrain.new(int(a[0]))
	var f: TerrainField = t.field
	var px := float(a[1]); var pz := float(a[2])
	for step in 2:
		var C: TrailCourse = f.course
		var bi := 0; var bd := INF
		for i in C.n:
			var d: float = Vector2(C.X[i] - px, C.Z[i] - pz).length()
			if d < bd: bd = d; bi = i
		var run_s := ""
		for run in C.runs():
			if bi >= run[0] - 20 and bi <= run[1] + 20: run_s += "[%d..%d k%d] " % run
		for fc in C.fences:
			var p0: Array = fc["posts"][0]
			if Vector2(p0[0] - px, p0[1] - pz).length() < 0.5: print("FRUN step=%d n=%d idx=%d d=%.1f posts=%d runs %s" % [step, C.n, bi, bd, fc["posts"].size(), run_s])
		if step == 0:
			var k := f.fork()
			k.grow_course(C.end_s() + Terrain.GROW_STEP)
			f.adopt_course(k)
			f.course.plan_marking(f)
	t.free(); quit()
