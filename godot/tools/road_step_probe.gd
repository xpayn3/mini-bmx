extends SceneTree
## The ridden trail's ground: (1) steps / kinks along the centreline (height change over 0.5 m vs the slope around it:
## a little ledge the rider feels), (2) embankments: stretches where the trail sits well above the land on BOTH sides
## (falls each side). -- [seed] [metres] ; prints STEP / BANKUP lines + ROADSUM
func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var sd := int(args[0]) if args.size() > 0 else 4242
	var L := float(args[1]) if args.size() > 1 else 4000.0
	var t := Terrain.new(sd)
	var f: TerrainField = t.field
	var C = f.course
	L = minf(L, C.length - 50.0)
	var d := 0.5
	var steps := 0; var worst := 0.0
	var prev_h := f.ground(C.at(20.0)[0], C.at(20.0)[1])
	var prev_g := 0.0
	var s := 20.0 + d
	var last_rep := -100.0
	while s < L:
		var p: Array = C.at(s)
		var h := f.ground(p[0], p[1])
		var g := (h - prev_h) / d
		var kink := absf(g - prev_g)   # change of slope over 0.5 m
		if kink > 0.25 and s - last_rep > 3.0:
			var i: int = p[4]
			steps += 1
			worst = maxf(worst, kink)
			last_rep = s
			if steps <= 40:
				print("STEP s=%.1f x=%.1f z=%.1f kink=%.2f slope %.2f->%.2f kind %d->%d jump=%s" % [s, p[0], p[1], kink, prev_g, g,
					C.KD[maxi(0, i - 1)], C.KD[mini(C.n - 1, i + 1)], str(f.jump_mask(p[0], p[1]) if f.has_method("jump_mask") else "")])
		prev_g = g; prev_h = h
		s += d
	# embankments
	var up_m := 0.0; var run := 0.0; var runs := 0; var max_up := 0.0
	s = 30.0
	while s < L:
		var p: Array = C.at(s)
		var h := f.ground(p[0], p[1])
		var nx: float = -p[3]; var nz: float = p[2]
		var lo := INF
		for side in [-1.0, 1.0]:
			var m := -INF
			for o in [14.0, 20.0, 28.0]:
				m = maxf(m, f.ground(p[0] + nx * o * side, p[1] + nz * o * side))
			lo = minf(lo, h - m)   # how far the trail is above the higher of that side's land
		if lo > 3.0:
			up_m += 2.0; run += 2.0; max_up = maxf(max_up, lo)
		else:
			if run >= 20.0:
				runs += 1
				if runs <= 25:
					var sm := s - run * 0.5
					var q: Array = C.at(sm)
					var ii: int = q[4]
					var qx: float = -q[3]; var qz: float = q[2]
					var lf := f.landform(q[0], q[1])
					var g_side := 0.0; var l_side := 0.0
					for sd2 in [-1.0, 1.0]:
						g_side += 0.5 * f.ground(q[0] + qx * 20.0 * sd2, q[1] + qz * 20.0 * sd2)
						l_side += 0.5 * f.landform(q[0] + qx * 20.0 * sd2, q[1] + qz * 20.0 * sd2)
					print("BANKUP s=%.0f..%.0f len=%.0f  trail=%.1f E=%.1f landform_here=%.1f  side20: ground=%.1f landform=%.1f kind=%d drop=%s" % [s - run, s, run,
						f.ground(q[0], q[1]), C.E[ii], lf, g_side, l_side, C.KD[ii], str(_in_drop(C, ii))])
			run = 0.0
		s += 2.0
	print("ROADSUM seed=%d len=%.0f steps=%d worst_kink=%.2f bankup_m=%.0f (%.1f%%) runs>=20m=%d max_above=%.1f" % [sd, L, steps, worst, up_m, 100.0 * up_m / L, runs, max_up])
	t.free()
	quit()


static func _in_drop(C, i: int) -> bool:
	for d in C.drops:
		if i >= d[0] and i <= d[1]: return true
	return false
