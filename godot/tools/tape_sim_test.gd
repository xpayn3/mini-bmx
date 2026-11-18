extends SceneTree
## Headless check of the torn-tape ribbon sim (TapeSim): build the world, snap the tape span nearest spawn,
## step 3 s and verify the ribbons stay finite, pinned to their stakes and settle near the ground.
## Run: godot --headless --path godot --script res://tools/tape_sim_test.gd


static func find_tape(terrain: Terrain, near: Vector2) -> Dictionary:
	var best := {}
	var bd := INF
	for k in terrain.chunks:
		for c in terrain.chunks[k]["colliders"]:
			if c.has("tape") and not c["tape"]["broken"]:
				var d := Vector2(c["x"], c["z"]).distance_to(near)
				if d < bd:
					bd = d
					best = c
	return mid_collider(terrain, best)


## the collider of the same span nearest its middle (so the tear leaves two long halves)
static func mid_collider(terrain: Terrain, c: Dictionary) -> Dictionary:
	if c.is_empty():
		return c
	var sp: Dictionary = c["tape"]
	var m: Vector3 = sp["pts"][15]
	var best := c
	var bd := INF
	for k in terrain.chunks:
		for o in terrain.chunks[k]["colliders"]:
			if is_same(o.get("tape"), sp):
				var d := Vector2(o["x"], o["z"]).distance_to(Vector2(m.x, m.z))
				if d < bd:
					bd = d
					best = o
	return best


func _initialize() -> void:
	var terrain := Terrain.new()
	get_root().add_child(terrain)
	terrain.set_process(false)
	terrain.set_seed(12345)
	terrain.update_stream(0, 0, INF)
	var c := find_tape(terrain, Vector2.ZERO)
	if c.is_empty():
		print("FAIL: no tape near spawn"); quit(1); return
	var sp: Dictionary = c["tape"]
	print("tape collider at (%.1f, %.1f) ceil %.2f, span len %.2f" % [c["x"], c["z"], c["ceil"], sp["len"]])
	terrain.update_stream(c["x"], c["z"], INF)
	var ok := terrain.break_collider(c, Vector3(9, 0.5, 3))
	var again := terrain.break_collider(c, Vector3(9, 0.5, 3))
	print("broke: ", ok, "  second hit: ", again, "  colliders_near skips it: ", not terrain.colliders_near(c["x"], c["z"]).has(c))
	var sim: TapeSim = terrain._tapes
	print("strips: ", sim.strips.size())
	var t0 := Time.get_ticks_usec()
	var fail := false
	for f in 180:
		terrain._process(1.0 / 60.0)
		for s in sim.strips:
			for p in s["P"]:
				if not p.is_finite():
					fail = true
		if f % 30 == 29:
			var line := "t=%.1fs" % ((f + 1) / 60.0)
			for s in sim.strips:
				var P: PackedVector3Array = s["P"]
				var hmax := -INF
				var hsum := 0.0
				for p in P:
					var hh := p.y - terrain.height(p.x, p.z)
					hmax = maxf(hmax, hh)
					hsum += hh
				line += " | %s n=%d tip(%.1f,%.1f,%.1f) above-ground mean %.2f max %.2f" % ["pinned" if s["pin"] != null else "FREE", P.size(),
					P[-1].x, P[-1].y, P[-1].z, hsum / P.size(), hmax]
			print(line)
	print("sim ms/frame avg: %.3f" % ((Time.get_ticks_usec() - t0) / 1000.0 / 180.0))
	for s in sim.strips:
		var P: PackedVector3Array = s["P"]
		if s["pin"] != null and P[0].distance_to(s["pin"]) > 1e-3:
			print("FAIL: pin moved"); fail = true
		var stretch := 0.0
		for i in P.size() - 1:
			stretch = maxf(stretch, absf(P[i].distance_to(P[i + 1]) - s["seg"]) / s["seg"])
		print("max segment stretch %.1f%%" % (stretch * 100))
		for p in P:
			if p.y < terrain.height(p.x, p.z) - 0.05:
				print("FAIL: below ground"); fail = true; break
	terrain.clear_dynamic()
	print("after clear_dynamic: strips ", sim.strips.size(), ", span broken ", sp["broken"])
	print("FAIL" if fail else "PASS")
	quit(1 if fail else 0)
