extends SceneTree
## Flow of the laid-out trail, Phase B rules on vs off (BMX_OLD_FLOW): per seed, grown to `len` m:
##  brake  = how much speed the bends take off a good rider per km (sum of TrailCourse.VA's drops, m/s per km): less = flowier
##  vavg   = the mean arrival speed (km/h)
##  kjump  = curvature steps: 99th percentile of |change of curvature| between 2 m points (1/m^2, x1000): an abrupt
##           straight-to-arc corner is a big step
##  alt    = share of consecutive bends (|curvature| > 0.02 for 6+ m) that turn the other way
##  dips   = grade reversals per km (the height goes up again for 1+ m after going down)
## -s res://tools/flow_probe.gd -- [len m] [seed ...]
func _init() -> void:
	var a := OS.get_cmdline_user_args()
	var want := float(a[0]) if a.size() > 0 else 10000.0
	var seeds := []
	for i in range(1, a.size()): seeds.append(int(a[i]))
	if seeds.is_empty(): seeds = [4242, 5, 12]
	for sd in seeds:
		for old in [true, false]:
			TrailCourse.OLD_FLOW = old
			var f := TerrainField.new()
			f.setup(sd, {})
			var guard := 0
			while f.course.end_s() < want and guard < 8:
				guard += 1
				var k := f.fork()
				k.grow_course(f.course.end_s() + 3000.0)
				f.adopt_course(k)
			var C: TrailCourse = f.course
			var n: int = mini(C.n, int(want / TrailCourse.STEP))
			var brake := 0.0
			var vs := 0.0
			var bk := [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
			for i in range(1, n):
				brake += maxf(0.0, C.VA[i - 1] - C.VA[i])
				bk[C.KD[i]] += maxf(0.0, C.VA[i - 1] - C.VA[i])
				vs += C.VA[i]
			if OS.get_environment("FLOW_DEBUG") != "" and not old:
				var shown := 0
				for i in range(2, n):
					if C.KD[i] == TrailCourse.ROAD and C.VA[i - 1] - C.VA[i] > 0.3 and shown < 25:
						shown += 1
						var R := 1.0 / maxf(absf(C.KAP[i]), 1e-4)
						print("BRAKEPT i=%d va %.1f -> %.1f R=%.0f BT=%.2f cap=%.1f VAmax_before=%.1f" % [i, C.VA[i - 1], C.VA[i], R, C.BT[i],
							sqrt((TrailCourse.A_RIDE + 9.81 * absf(C.BT[i])) * R), C.VA[maxi(0, i - 15)]])
			# braking proper: speed a bend's cap takes off (TrailCourse._speed_profile's loop, the cap's loss counted);
			# climbing: metres of height gained per km
			var v2 := TrailCourse.VA_START * TrailCourse.VA_START
			var bcap := 0.0
			var climb := 0.0
			for i in range(1, n):
				var v := sqrt(v2)
				var acc := -TrailCourse.VA_ROLL - TrailCourse.VA_DRAG * v2 + (TrailCourse.VA_PEDAL if v < TrailCourse.VA_PED_TOP else 0.0)
				v2 = clampf(v2 + 2.0 * (9.81 * (C.E[i - 1] - C.E[i]) + acc * TrailCourse.STEP), 4.0, TrailCourse.VA_MAX * TrailCourse.VA_MAX)
				climb += maxf(0.0, C.E[i] - C.E[i - 1])
				var kk := absf(C.KAP[i])
				if kk > 0.004:
					var cap := (TrailCourse.A_RIDE + 9.81 * absf(C.BT[i])) / kk
					if cap < v2:
						bcap += sqrt(v2) - sqrt(cap)
						v2 = cap
			print("FLOWBRAKE seed=%d %s bend braking %.1f m/s per km, climbing %.1f m per km" % [sd, "old" if old else "new", bcap / (n * TrailCourse.STEP / 1000.0), climb / (n * TrailCourse.STEP / 1000.0)])
			print("FLOWKD seed=%d %s brake by kind (start road switch esses rocks jump finish): %s" % [sd, "old" if old else "new", str(bk.map(func(q): return snappedf(q, 1.0)))])
			var ks := PackedFloat32Array()
			for i in range(1, n - 2):
				var t0 := atan2(C.Z[i] - C.Z[i - 1], C.X[i] - C.X[i - 1])
				var t1 := atan2(C.Z[i + 1] - C.Z[i], C.X[i + 1] - C.X[i])
				var t2 := atan2(C.Z[i + 2] - C.Z[i + 1], C.X[i + 2] - C.X[i + 1])
				var k0 := TrailCourse.wrap_angle(t1 - t0) / 2.0
				var k1 := TrailCourse.wrap_angle(t2 - t1) / 2.0
				ks.append(absf(k1 - k0) / 2.0)
			ks.sort()
			var bends := []
			var cur := 0
			var run := 0
			for i in n:
				var sg := 0
				if C.KAP[i] > 0.02: sg = 1
				elif C.KAP[i] < -0.02: sg = -1
				if sg != 0 and sg == cur:
					run += 1
				else:
					if cur != 0 and run >= 3: bends.append(cur)
					cur = sg; run = 1
			var alt := 0
			for i in range(1, bends.size()):
				if bends[i] != bends[i - 1]: alt += 1
			var dips := 0
			var down := false
			for i in range(1, n):
				if C.E[i] < C.E[i - 1] - 0.01: down = true
				elif C.E[i] > C.E[i - 1] + 0.005 and down:
					dips += 1; down = false
			var km := n * TrailCourse.STEP / 1000.0
			print("FLOW seed=%d %s brake=%.1f m/s/km vavg=%.1f km/h kjump99=%.2f bends=%d alt=%.0f %% dips=%.1f /km" % [
				sd, "old" if old else "new", brake / km, vs / n * 3.6, ks[int(ks.size() * 0.99)] * 1000.0, bends.size(),
				100.0 * alt / maxi(bends.size() - 1, 1), dips / km])
	quit()
