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
	for step in 300:   # 2.5 s at 120 Hz
		d.Step(1.0 / 120.0, 0.0, wind, 1.78, 0.89, 0.5, 1.0, 0.0, 1.0)
		if step % 12 == 11:
			for k in 4:
				var last: Vector2 = track[k][-1]
				var best := Vector2.INF
				for i in d.Count():
					var g: Vector4 = d.Get(i)
					var p := Vector2(g.x, g.y)
					if p.distance_to(last) < best.distance_to(last): best = p
				track[k].append(best)
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
