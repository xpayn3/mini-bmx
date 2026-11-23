extends SceneTree
## Bends vs the speed riders arrive at (docs/research/ride_feel.md, change 1). For a few worlds' laid-out trail: every
## bend (a run of |curvature| > 0.02 = radius < 50 m), its kind, tightest radius, the free-rolling speed into it (no
## brakes since the last bend: TrailCourse.VA's model without the bend limits), its bank (peak |BT|, tan) and the speed
## that bank + A_RIDE of grip allow. "brake" = how much speed (km/h) the bend takes off a rider who arrives free-rolling.
## Run: --headless -s res://tools/bend_probe.gd [-- verbose=1]
const G := 9.81

func _init() -> void:
	var verbose := "verbose=1" in OS.get_cmdline_user_args()
	var tot := {n = 0, brake = 0, lost = 0.0, lost_kmh = 0.0, bank_deg = 0.0}
	for sd in [4242, 5, 12, 99]:
		var tg := Terrain.new()
		tg.use_cs = false
		tg.set_seed(sd)
		var c: TrailCourse = tg.field.course
		var n := c.n
		# free speed (no bend limits): where a rider would be without brakes
		var vf := PackedFloat32Array(); vf.resize(n)
		var v2 := TrailCourse.VA_START * TrailCourse.VA_START
		var i := 1
		var bends := []
		while i < n:
			# roll free from the end of the last bend (VA there = after braking for it)
			var a := -TrailCourse.VA_ROLL - TrailCourse.VA_DRAG * v2 + (TrailCourse.VA_PEDAL if sqrt(v2) < TrailCourse.VA_PED_TOP else 0.0)
			v2 = clampf(v2 + 2.0 * (G * (c.E[i - 1] - c.E[i]) + a * TrailCourse.STEP), 4.0, TrailCourse.VA_MAX ** 2)
			if absf(c.KAP[i]) > 0.02:
				var j := i
				var kmax := 0.0; var bmax := 0.0
				while j < n and absf(c.KAP[j]) > 0.02:
					kmax = maxf(kmax, absf(c.KAP[j])); bmax = maxf(bmax, absf(c.BT[j])); j += 1
				var v_in := sqrt(v2)
				var v_ok := sqrt((TrailCourse.A_RIDE + G * bmax) / kmax)
				bends.append([i, c.KD[i], 1.0 / kmax, v_in, bmax, v_ok])
				v2 = minf(v2, v_ok * v_ok)
				i = j
			else:
				i += 1
		var nb := 0; var nbrake := 0; var lost := 0.0; var bank := 0.0
		for b in bends:
			nb += 1
			var d: float = maxf(0.0, (b[3] - b[5]) * 3.6)
			if d > 3.0: nbrake += 1
			lost += maxf(0.0, b[3] * b[3] - b[5] * b[5]) * 0.5   # J/kg braked away
			bank += rad_to_deg(atan(b[4]))
			if verbose: print("BEND seed=%d s=%dm kind=%d R=%.1fm in=%.0fkmh bank=%.0fdeg ok=%.0fkmh brake=%.0fkmh" % [sd, b[0] * 2, b[1], b[2], b[3] * 3.6, rad_to_deg(atan(b[4])), b[5] * 3.6, d])
		print("BENDS seed=%d km=%.1f bends=%d need_brake(>3kmh)=%d (%.0f%%) braked_away=%.0f J/kg  mean_bank=%.1fdeg" % [sd, c.length / 1000.0, nb, nbrake, 100.0 * nbrake / maxf(1, nb), lost, bank / maxf(1, nb)])
		tot.n += nb; tot.brake += nbrake; tot.lost += lost; tot.bank_deg += bank
		tg.free()
	print("BENDS TOTAL bends=%d need_brake=%d (%.0f%%) braked_away=%.0f J/kg mean_bank=%.1fdeg" % [tot.n, tot.brake, 100.0 * tot.brake / maxf(1, tot.n), tot.lost, tot.bank_deg / maxf(1, tot.n)])
	quit()
