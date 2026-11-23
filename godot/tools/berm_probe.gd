extends SceneTree
## The ground's real tilt across the trail where the racing line (TrailCourse.LN) runs, on banked bends, vs the bank the
## course asks for (BT). Seed 4242, the first 4 km. Run: --headless -s res://tools/berm_probe.gd
func _init() -> void:
	var tg := Terrain.new()
	tg.use_cs = false
	tg.set_seed(4242)
	var f = tg.field
	var c: TrailCourse = f.course
	var rows := 0; var sum_bt := 0.0; var sum_real := 0.0; var sum_c := 0.0
	var hist := {}
	for i in range(10, c.n - 10, 3):
		var bt := absf(c.BT[i])
		if bt < 0.2: continue
		# across the trail at the line: (q_a positive side) = (-TZ, TX)
		var ax := -c.TZ[i]; var az := c.TX[i]
		var lx: float = c.X[i] + ax * c.LN[i]; var lz: float = c.Z[i] + az * c.LN[i]
		var h0: float = tg.deck_height(lx - ax * 0.5, lz - az * 0.5)
		var h1: float = tg.deck_height(lx + ax * 0.5, lz + az * 0.5)
		var real := absf(atan2(h1 - h0, 1.0))
		var hc0: float = tg.deck_height(c.X[i] - ax * 0.5, c.Z[i] - az * 0.5)
		var hc1: float = tg.deck_height(c.X[i] + ax * 0.5, c.Z[i] + az * 0.5)
		sum_bt += atan(bt); sum_real += real; sum_c += absf(atan2(hc1 - hc0, 1.0)); rows += 1
		var b := int(rad_to_deg(atan(bt)) / 5) * 5
		var hs: Array = hist.get(b, [0, 0.0])
		hs[0] += 1; hs[1] += real; hist[b] = hs
	print("BERMPROBE points=%d asked=%.1fdeg  on the line=%.1fdeg  on the centreline=%.1fdeg" % [rows, rad_to_deg(sum_bt / maxf(1, rows)), rad_to_deg(sum_real / maxf(1, rows)), rad_to_deg(sum_c / maxf(1, rows))])
	var ks := hist.keys(); ks.sort()
	for k in ks: print("BERMPROBE asked %d-%d deg: n=%d real on the line %.1f deg" % [k, k + 5, hist[k][0], rad_to_deg(hist[k][1] / hist[k][0])])
	tg.free()
	quit()
