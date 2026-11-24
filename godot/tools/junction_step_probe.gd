extends SceneTree
## side-path junctions vs the main trail: the steepest step in the ground (between 0.25 m neighbours, as a slope) in a
## 24 m square round each junction (junction_probe's test), and the same round plain trail spots for comparison.
## A seam like the level builder's old alt-line step would show as a slope far over the trail's own. -- [seed]
func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var sd := int(args[0]) if args.size() > 0 else 4242
	var t := Terrain.new(sd)
	var f: TerrainField = t.field
	var C = f.course
	var d := 0.375
	var u := 20.0
	var found := 0
	var j_worst := 0.0; var p_worst := 0.0
	while u < 3000.0 and found < 10:
		var pa: Array = C.at(u)
		var hit := Vector2.INF
		for ix in range(-40, 41):
			for iz in range(-40, 41):
				var x := snappedf(pa[0], d) + ix * d
				var z := snappedf(pa[1], d) + iz * d
				f.query(x, z)
				var on: bool = f.q_d < f.q_w + 2.6
				f.query(x + d, z)
				var on2: bool = f.q_d < f.q_w + 2.6
				if on != on2 and f.trail(x, z) > 0.5 and f.trail(x + d, z) > 0.5: hit = Vector2(x, z); break
			if hit.x != INF: break
		if hit.x != INF:
			var w := _worst(f, hit)
			var pw := _worst(f, Vector2(C.at(u + 60.0)[0], C.at(u + 60.0)[1]))
			j_worst = maxf(j_worst, w); p_worst = maxf(p_worst, pw)
			print("JSTEP u=%.0f junction worst slope=%.2f  plain trail 60 m on=%.2f" % [u, w, pw])
			found += 1
			u += 120.0
		else:
			u += 30.0
	print("JSTEPSUM junctions=%d worst=%.2f plain_worst=%.2f" % [found, j_worst, p_worst])
	t.free()
	quit()


static func _worst(f: TerrainField, c: Vector2) -> float:
	var w := 0.0
	for i in range(-48, 48):
		for j in range(-48, 48):
			var x := c.x + i * 0.25; var z := c.y + j * 0.25
			var h := f.ground(x, z)
			if f.trail(x, z) < 0.5: continue   # (the ridden ground only)
			w = maxf(w, maxf(absf(f.ground(x + 0.25, z) - h), absf(f.ground(x, z + 0.25) - h)) / 0.25)
	return w
