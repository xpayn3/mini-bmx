extends SceneTree
## -s res://tools/drop_probe.gd --headless [-- seed]: the trail's drop-offs (TrailCourse.drops) as built: height, face
## length, steepest slope, and a point-mass rider rolling off the level top at 10..20 m/s: where he lands, EFH.
## BMX_OLD_DROPS=1 = the old smoothstep faces, for comparison.

func _init() -> void:
	var sd := int(OS.get_cmdline_user_args()[0]) if not OS.get_cmdline_user_args().is_empty() else 4242
	var f := TerrainField.new()
	f.setup(sd)
	var C: TrailCourse = f.course
	print("DROPS seed=%d n=%d old=%s" % [sd, C.drops.size(), TrailCourse.OLD_DROPS])
	for dr in C.drops.slice(0, 8):
		var i0: int = dr[0]; var i1: int = dr[1]
		# the top: highest point; the face: from the last level point to the bottom
		var top := i0
		for i in range(i0, i1 + 1):
			if C.E[i] > C.E[top] + 1e-4: top = i
		var lvl := top
		while lvl + 1 <= i1 and absf(C.E[lvl + 1] - C.E[lvl]) < 0.03: lvl += 1
		var hh: float = C.E[lvl] - C.E[i1]
		var smax := 0.0
		for i in range(lvl, i1): smax = maxf(smax, (C.E[i] - C.E[i + 1]) / TrailCourse.STEP)
		var line := "DROP s=%.0f height=%.1f face=%.0f m steepest=%.0f deg |" % [lvl * TrailCourse.STEP, hh, (i1 - lvl) * TrailCourse.STEP, rad_to_deg(atan(smax))]
		for v in [10.0, 13.0, 16.0, 18.0, 20.0]:
			var x := 0.0; var y: float = C.E[lvl]; var vy := 0.0; var t := 0.0
			var res := "rolls"
			while t < 4.0:
				t += 0.002; x += v * 0.002; vy -= 9.81 * 0.002; y += vy * 0.002
				var gi := lvl + x / TrailCourse.STEP
				var a := int(gi)
				if a + 1 > C.n - 1: break
				var g := lerpf(C.E[a], C.E[a + 1], gi - a)
				if y <= g:
					if t < 0.05: break   # (never left)
					var sl: float = (C.E[a] - C.E[a + 1]) / TrailCourse.STEP
					var n := Vector2(sl, 1.0).normalized()   # ground falling along +x: normal (s, 1)
					var vn: float = -(v * n.x + vy * n.y)
					res = "%.0fm efh=%.2f" % [x, maxf(0.0, vn) * maxf(0.0, vn) / 19.62]
					break
			line += " %.0f: %s |" % [v * 3.6, res]
		print(line)
	quit()
