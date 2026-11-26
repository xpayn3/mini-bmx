extends SceneTree
## Trail builders' rules measured on the laid-out trail (first 4 km; seeds as args):
## RUNIN  jump with a bend (radius < 60 m) in the 1.5 s before its lip; RUNOUT  a bend in the 1 s after its landing
## BLIND  a crest in the 25 m before a lip (the trail falls away > 0.6 m below the line from 25 m back to the lip: can't see it)
## STEEP  50 m windows steeper than 15 % (outside drops); BRAKE  rider speed (VA) must fall > 30 % within 30 m
## HALF   trail grade > 8 % and > half the hillside's slope across (straight down a fall line)
func _init() -> void:
	var a := OS.get_cmdline_user_args()
	var seeds: Array = [4242, 5, 12, 2, 31]
	if not a.is_empty():
		seeds = []
		for x in a: seeds.append(int(x))
	var T := {"jumps": 0, "runin": 0, "runout": 0, "blind": 0, "steep_m": 0.0, "brake": 0, "half_m": 0.0, "len": 0.0}
	for sd in seeds:
		var t := Terrain.new(int(sd))
		var f: TerrainField = t.field
		var C = f.course
		var L: float = minf(4000.0, (C.n - 30) * 2.0)
		T.len += L
		for ft in f.route_feats:
			if not TerrainField.AIR_TYPES.has(ft.type) or ft.s > L: continue
			T.jumps += 1
			var v: float = C.VA[clampi(int(ft.s / 2.0), 0, C.n - 1)] * TerrainField.RIDER_K
			var air: Array = f.sized_air(ft.type, ft.size) if f.has_method("sized_air") else []
			var land_end: float = ft.s + ft.len
			var kin := _kmax(C, ft.s - v * 1.5, ft.s)
			var kout := _kmax(C, land_end, land_end + v * 1.0)
			if kin > 1.0 / 60.0: T.runin += 1; print("RUNIN seed=%d s=%.0f %s radius=%.0f m (v %.0f km/h)" % [sd, ft.s, ft.type, 1.0 / kin, v * 3.6])
			if kout > 1.0 / 60.0: T.runout += 1; print("RUNOUT seed=%d s=%.0f %s radius=%.0f m" % [sd, ft.s, ft.type, 1.0 / kout])
			var e0 := f._course_e(ft.s - 25.0); var e1 := f._course_e(ft.s)
			var hide := 0.0
			for k in range(1, 25):
				var los := e0 + (e1 - e0) * k / 25.0
				hide = maxf(hide, f._course_e(ft.s - 25.0 + k) - los)
			if hide > 0.6: T.blind += 1; print("BLIND seed=%d s=%.0f %s crest %.1f m over the sight line" % [sd, ft.s, ft.type, hide])
		var s := 20.0
		while s < L - 50.0:
			var g := (f._course_e(s + 50.0) - f._course_e(s)) / 50.0
			var dr := false
			for d in C.drops:
				if s + 50.0 > d[0] * 2.0 and s < d[1] * 2.0: dr = true
			if absf(g) > 0.15 and not dr: T.steep_m += 10.0
			var i := int(s / 2.0)
			var v0: float = C.VA[i]; var v1: float = C.VA[mini(i + 15, C.n - 1)]
			if v1 < v0 * 0.7 and v0 > 8.0: T.brake += 1; print("BRAKE seed=%d s=%.0f %.0f -> %.0f km/h in 30 m" % [sd, s, v0 * 3.6 * 1.4, v1 * 3.6 * 1.4]); s += 40.0
			var p: Array = C.at(s)
			var nx: float = -p[3]; var nz: float = p[2]
			var side := absf(f.landform(p[0] + nx * 8.0, p[1] + nz * 8.0) - f.landform(p[0] - nx * 8.0, p[1] - nz * 8.0)) / 16.0
			var gr := absf((f._course_e(s + 10.0) - f._course_e(s - 10.0)) / 20.0)
			if gr > 0.08 and gr > 0.5 * side: T.half_m += 10.0
			s += 10.0
		t.free()
	print("RULESUM km=%.0f jumps=%d runin_bend=%d runout_bend=%d blind_lip=%d steep>15%%_m=%.0f brake_zones=%d fall_line_m=%.0f (%.1f%%)" % [T.len / 1000.0, T.jumps, T.runin, T.runout, T.blind, T.steep_m, T.brake, T.half_m, 100.0 * T.half_m / T.len])
	quit()


static func _kmax(C, s0: float, s1: float) -> float:
	var m := 0.0
	var s := maxf(0.0, s0)
	while s <= s1:
		m = maxf(m, absf(C.KAP[clampi(int(s / 2.0), 0, C.n - 1)]))
		s += 2.0
	return m
