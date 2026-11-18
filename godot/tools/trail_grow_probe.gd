extends SceneTree
## Endless trail check: grows the course several times like Terrain does and verifies that
##  - every point already laid out stays exactly where it was (layout + fences / stakes / route features
##    well behind the old end),
##  - the C# field (rebind_course) matches the GDScript field bit for bit on the new stretch,
##  - and prints how long a grow takes.
## Run: godot --headless --path godot -s res://tools/trail_grow_probe.gd

const GROWS := 6
const SAFE := 400.0   # behind the old end by this much, nothing may change


func _init() -> void:
	var seed := int(OS.get_environment("BMX_SEED")) if OS.get_environment("BMX_SEED") != "" else 4242
	var t0 := Time.get_ticks_msec()
	var f := TerrainField.new()
	f.setup(seed)
	print("setup %d ms, course to x=%.0f, n=%d" % [Time.get_ticks_msec() - t0, f.course.end_x(), f.course.n])
	var cs = load("res://scripts/world/TerrainFieldCs.cs").new()
	cs.setup_from(f)
	var bad := 0
	for g in GROWS:
		var old: TrailCourse = f.course
		var old_feats: Array = f.route_feats
		var old_end := old.end_x()
		t0 = Time.get_ticks_msec()
		var k := f.fork()
		k.grow_course(old_end + Terrain.GROW_STEP)
		var t_grow := Time.get_ticks_msec() - t0
		t0 = Time.get_ticks_msec()
		f.adopt_course(k)
		cs.rebind_course(f)
		var t_adopt := Time.get_ticks_msec() - t0
		var c: TrailCourse = f.course
		# layout: an exact prefix
		var lay := 0
		for i in old.n:
			if c.X[i] != old.X[i] or c.Z[i] != old.Z[i] or c.KD[i] != old.KD[i]:
				lay += 1
		# derived values and marking well behind the old end
		var der := 0
		for i in old.n:
			if old.X[i] > old_end - SAFE:
				continue
			if c.E[i] != old.E[i] or c.W[i] != old.W[i] or c.BT[i] != old.BT[i] or c.KAP[i] != old.KAP[i]:
				der += 1
		var mk := _marks(old, old_end - SAFE) != _marks(c, old_end - SAFE)
		var rf := _feats(old_feats, old_end - SAFE) != _feats(f.route_feats, old_end - SAFE)
		# C# vs GDScript on the new stretch (and a bit before it)
		var r := WorldRng.new(seed + g)
		var cmp := 0
		var miss := 0
		for j in 4000:
			var s := (old.n - 300) * TrailCourse.STEP + r.next() * (c.length - (old.n - 300) * TrailCourse.STEP)
			var p := c.at(s)
			var x: float = p[0] + (r.next() * 2 - 1) * 30
			var z: float = p[1] + (r.next() * 2 - 1) * 30
			cmp += 3
			if f.ground(x, z) != cs.ground(x, z): miss += 1
			if f.trail(x, z) != cs.trail(x, z): miss += 1
			if f.route_dist(x, z) != cs.route_dist(x, z): miss += 1
		var ok := lay == 0 and der == 0 and not mk and not rf and miss == 0
		if not ok:
			bad += 1
		print("GROW %d: to x=%.0f n=%d  grow %d ms  adopt %d ms | layout changed %d, derived changed %d, marks changed %s, route feats changed %s | C# vs GD %d/%d mismatches  %s" % [
			g + 1, c.end_x(), c.n, t_grow, t_adopt, lay, der, mk, rf, miss, cmp, "OK" if ok else "FAIL"])
	print("TRAIL GROW PROBE: %s" % ("PASS" if bad == 0 else "FAIL (%d)" % bad))
	quit()


func _marks(c: TrailCourse, xmax: float) -> String:
	var parts := PackedStringArray()
	for fc in c.fences:
		var p0: Array = fc["posts"][0]
		var p1: Array = fc["posts"][fc["posts"].size() - 1]
		if p1[0] < xmax:
			parts.append("%s,%s,%s,%d" % [p0, p1, fc["style"], fc["posts"].size()])
	for st in c.stakes:
		if st["x"] < xmax:
			parts.append("%.6f,%.6f,%d,%s" % [st["x"], st["z"], st["prev"], st["caution"]])
	return ";".join(parts)


func _feats(list: Array, xmax: float) -> String:
	var parts := PackedStringArray()
	for j in list:
		if j.x < xmax - 60:
			parts.append("%.6f,%.6f,%s,%.6f" % [j.x, j.z, j.type, j.s])
	return ";".join(parts)
