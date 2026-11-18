extends SceneTree
## Headless check of the terrain port: queries for seed 12345, height() timing, chunk streaming.
var terrain: Terrain
var frames := 0


func _init() -> void:
	terrain = Terrain.new()
	root.add_child(terrain)
	var t0 := Time.get_ticks_usec()
	terrain.set_seed(12345)
	print("set_seed(12345): %.1f ms  course points=%d fences=%d stakes=%d route features=%d" % [(Time.get_ticks_usec() - t0) / 1000.0,
		terrain.field.course.n, terrain.field.course.fences.size(), terrain.field.course.stakes.size(), terrain.field.route_feats.size()])
	t0 = Time.get_ticks_usec()
	terrain.update_stream(0, 0, INF)
	var ms := (Time.get_ticks_usec() - t0) / 1000.0
	var nc := 0
	for k in terrain.chunks:
		for c in terrain.chunks[k]["colliders"]:
			nc += 1
	print("update_stream(0,0,INF): %d chunks in %.0f ms (seg=%d, last chunk build %.0f ms on a worker, finalize %.1f ms), %d colliders" % [
		terrain.chunks.size(), ms, terrain.seg, terrain.last_build_ms, terrain.last_finalize_ms, nc])
	var pts := [[0, 0], [10, 5], [37.5, -12.25], [100, 20], [60, 0.5], [-60, 40], [120, -70], [-100, -100]]
	for p in pts:
		var x: float = p[0]
		var z: float = p[1]
		var cols := terrain.colliders_near(x, z)
		var kinds := {}
		for c in cols:
			var k := "fence" if c.has("fence") else ("tape" if c.has("tape") else ("cactus" if c.has("cactus") else ("rock" if c.has("top") else "tree/shed")))
			kinds[k] = kinds.get(k, 0) + 1
		print("(%7.2f, %7.2f) height=%9.4f deck=%9.4f surface=%d biome=%-15s jump=%s colliders=%s colour=%s" % [x, z, terrain.height(x, z),
			terrain.deck_height(x, z), terrain.surface(x, z), terrain.biome_name(x, z), str(terrain.jump(x, z)), str(kinds), terrain.ground_color(x, z).to_html(false)])
	# find something breakable near spawn
	var found := {}
	for k in terrain.chunks:
		for c in terrain.chunks[k]["colliders"]:
			for kind in ["fence", "cactus", "tape", "top"]:
				if c.has(kind) and not found.has(kind):
					found[kind] = c
	for kind in found:
		var c: Dictionary = found[kind]
		print("first %s collider: x=%.2f z=%.2f r=%.2f top=%s base=%s ceil=%s fence_style=%s near=%d" % [kind, c["x"], c["z"], c["r"], c.get("top", "-"), c.get("base", "-"),
			c.get("ceil", "-"), c.get("fence_style", "-"), terrain.colliders_near(c["x"], c["z"]).size()])
	for kind in ["fence", "cactus", "tape"]:
		if found.has(kind):
			var c: Dictionary = found[kind]
			var before := terrain.colliders_near(c["x"], c["z"]).size()
			var ok := terrain.break_collider(c, Vector3(6, 0, 1))
			var again := terrain.break_collider(c, Vector3(6, 0, 1))
			print("break %s -> %s (again -> %s), colliders near %d -> %d, debris bodies %d" % [kind, ok, again, before,
				terrain.colliders_near(c["x"], c["z"]).size(), terrain._debris.get_child_count()])
	# timing: 100k height() calls along a ride-like path
	var r := WorldRng.new(7)
	t0 = Time.get_ticks_usec()
	var s := 0.0
	var x := 0.0
	var z := 0.0
	for i in 100000:
		x += 0.01 + r.next() * 0.02
		z += (r.next() - 0.5) * 0.02
		s += terrain.height(x, z)
	var us := (Time.get_ticks_usec() - t0) / 100000.0
	print("100k height() along a path: %.2f us/call (%.0f ms total)" % [us, us * 100])
	t0 = Time.get_ticks_usec()
	for i in 100000:
		s += terrain.height(-150 + r.next() * 300, -150 + r.next() * 300)
	us = (Time.get_ticks_usec() - t0) / 100000.0
	print("100k height() random within 150 m: %.2f us/call" % us)
	t0 = Time.get_ticks_usec()
	for i in 20000:
		s += terrain.surface(r.next() * 100, r.next() * 100)
	print("20k surface(): %.2f us/call" % ((Time.get_ticks_usec() - t0) / 20000.0))
	t0 = Time.get_ticks_usec()
	for i in 20000:
		terrain.colliders_near(r.next() * 100, r.next() * 100)
	print("20k colliders_near(): %.2f us/call" % ((Time.get_ticks_usec() - t0) / 20000.0))
	terrain.update_water(0, 0, 0.0)
	terrain.clear_dynamic()
	print("after clear_dynamic: debris=%d" % terrain._debris.get_child_count())


func _process(delta: float) -> bool:
	frames += 1
	# ride away along +x: time-sliced streaming with a 4 ms budget
	if frames <= 240:
		var t0 := Time.get_ticks_usec()
		terrain.update_stream(frames * 1.0, 0.0, 4.0)
		var ms := (Time.get_ticks_usec() - t0) / 1000.0
		if ms > worst:
			worst = ms
		terrain.update_water(frames * 1.0, 0.0, frames / 60.0)
		return false
	print("streaming 240 frames to x=240: worst update_stream %.1f ms, chunks loaded %d, jobs pending %d" % [worst, terrain.chunks.size(), terrain._jobs.size()])
	terrain._join_all()
	return true

var worst := 0.0
