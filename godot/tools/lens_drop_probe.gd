extends SceneTree
## -s res://tools/lens_drop_probe.gd -- [wind=0.8]: one splash, then the biggest drops' paths every 0.1 s
## (how long they cling, how straight they run: heading change per step)
func _init() -> void:
	var wind := 0.8
	for a in OS.get_cmdline_user_args():
		if a.begins_with("wind="): wind = float(a.substr(5))
	var d = load("res://scripts/fx/LensDropsCs.cs").new()
	d.Splash(60, 1.78, 0.0015, 0.016)
	# follow the 4 biggest by position (indices shift as drops merge / cull)
	var pts := []
	for i in d.Count(): pts.append(d.Get(i))
	pts.sort_custom(func(a, b): return a.z > b.z)
	var track := []
	for k in 4: track.append([Vector2(pts[k].x, pts[k].y)])
	# every step, so a drop isn't mixed up with the beads it leaves: the nearest one of about its size
	var cur := []
	for k in 4: cur.append(pts[k])
	for step in 300:   # 2.5 s at 120 Hz
		d.Step(1.0 / 120.0, 0.0, wind, 1.78, 0.89, 0.5, 1.0, 0.0, 1.0)
		for k in 4:
			var c: Vector4 = cur[k]
			var best := Vector4.ZERO
			var score := INF
			for i in d.Count():
				var g: Vector4 = d.Get(i)
				if g.z < c.z * 0.7: continue
				var s := Vector2(g.x - c.x, g.y - c.y).length()
				if s < score:
					score = s
					best = g
			if score < 0.06: cur[k] = best
			if step % 12 == 11: track[k].append(Vector2(cur[k].x, cur[k].y))
	for k in 4:
		var line := "DROP %d r=%.4f:" % [k, pts[k].z]
		var t0 := -1.0
		var turns := 0.0
		for j in range(1, track[k].size()):
			var dv: Vector2 = track[k][j] - track[k][j - 1]
			if t0 < 0.0 and dv.length() > 0.002: t0 = j * 0.1
			if j > 1:
				var dp: Vector2 = track[k][j - 1] - track[k][j - 2]
				if dv.length() > 0.002 and dp.length() > 0.002: turns += absf(dv.angle_to(dp))
			line += " %.3f,%.3f" % [track[k][j].x, track[k][j].y]
		print(line)
		print("DROP %d starts_moving=%.1fs heading_change_sum=%.0fdeg" % [k, t0, rad_to_deg(turns)])
	quit()
