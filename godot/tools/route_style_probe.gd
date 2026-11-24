extends SceneTree
## RouteStyle probe: sets up fields for a few seeds / styles, prints a hash of the laid-out trail (the default style
## must give the same hashes as before the style existed), the build time, and the feature / bend counts.
## -s res://tools/route_style_probe.gd --headless [-- seed ...]

func _init() -> void:
	var seeds := [4242, 5]
	var styles := {"default": RouteStyle.DEFAULT, "flow": RouteStyle.PRESETS[0][1], "jumps": RouteStyle.PRESETS[2][1], "tech": RouteStyle.PRESETS[3][1], "gnarly": RouteStyle.PRESETS[4][1]}
	for sd in seeds:
		for nm in styles:
			var t0 := Time.get_ticks_usec()
			var f := TerrainField.new()
			f.setup(sd, styles[nm])
			var ms := (Time.get_ticks_usec() - t0) / 1000.0
			var C: TrailCourse = f.course
			var h := PackedFloat64Array()
			for i in range(0, C.n, 7): h.append(C.X[i]); h.append(C.Z[i]); h.append(C.E[i])
			var jumps := 0
			for ft in f.route_feats:
				if String(ft.type) in ["table", "double", "kicker", "tableLine", "flow", "doubleLine", "woodKicker"]: jumps += 1
			var tight := 0
			var jl := 0
			var sw := 0
			for i in C.n:
				if C.X[i] > 1500.0:
					if absf(C.KAP[i]) > 0.06: tight += 1
					if C.KD[i] == TrailCourse.JUMP: jl += 1
					if C.KD[i] == TrailCourse.SWITCH: sw += 1
			print("ROUTE seed=%d style=%s n=%d hash=%d feats=%d jumps=%d tightpts=%d jumpline_pts=%d switch_pts=%d drops=%d end=%.0f,%.0f build_ms=%.0f" % [sd, nm, C.n, hash(h), f.route_feats.size(), jumps, tight, jl, sw, C.drops.size(), C.X[C.n - 1], C.Z[C.n - 1], ms])
	# the preview's difficulty + time per style (what the ROUTE page shows)
	var names := ["GREEN", "BLUE", "BLACK", "DOUBLE BLACK"]
	for sd in seeds:
		for nm in styles:
			var rp := RoutePreview.new()
			rp._work(sd, styles[nm])
			var st: Dictionary = rp._stats(rp._result)
			print("RATING seed=%d style=%s score=%.0f %s time=%d:%02d avg=%.0f km/h steepest=%.0f tight=%d jumps=%d" % [sd, nm, st.score, names[st.rating], int(st.time) / 60, int(st.time) % 60, st.avg_kmh, st.steepest, st.tight, st.jumps])
	# the same over 12 seeds: mean / range of the score per style (calibrates the green / blue / black cut-offs)
	for nm in styles:
		var tot := 0.0
		var lo := 999.0
		var hi := 0.0
		var tsum := 0.0
		for sd in range(1, 13):
			var rp2 := RoutePreview.new()
			rp2._work(sd * 37, styles[nm])
			var s2: Dictionary = rp2._stats(rp2._result)
			tot += s2.score; lo = minf(lo, s2.score); hi = maxf(hi, s2.score); tsum += s2.time
		print("RATINGMEAN style=%s mean=%.0f min=%.0f max=%.0f time=%.1f min" % [nm, tot / 12.0, lo, hi, tsum / 12.0 / 60.0])
	quit()
