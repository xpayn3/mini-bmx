extends SceneTree
## The level builder's checks over the procedural world's trail (-s, headless): every built route jump (table, double,
## kicker) flown at the speed a good rider arrives at (TrailCourse.VA) from its lip over the REAL ground (the feature on
## its sloped plane b0 -> b1, the land past it): where it comes down against where its shape was designed to be landed
## on (the AIR span's end - 2 m), and how hard (EFH). -- [seed ...] (default 4242 5 12 99 7)
## ROUTECHECK lines per jump, ROUTESUM per type: mean landing error, how many land > 3 m short / long, EFH > 1.5 m.
const G := 9.81

func _init() -> void:
	var seeds: Array = []
	for a in OS.get_cmdline_user_args(): seeds.append(int(a))
	if seeds.is_empty(): seeds = [4242, 5, 12, 99, 7]
	var stats := {}
	for sd in seeds:
		var t := Terrain.new(sd)
		var f: TerrainField = t.field
		var C: TrailCourse = f.course
		for j in f.route_feats:
			if not (j.type in ["table", "double", "kicker"]): continue
			var r := check(f, C, j)
			if r.is_empty(): continue
			var st: Dictionary = stats.get(j.type, {"n": 0, "err": 0.0, "short": 0, "long": 0, "hard": 0, "grade": 0.0})
			st.n += 1; st.err += r.err; st.grade += r.grade
			if r.err < -3.0: st.short += 1
			if r.err > 3.0: st.long += 1
			if r.efh > 1.5: st.hard += 1
			stats[j.type] = st
			print("ROUTECHECK seed=%d %s size=%d s=%.0f v=%.1f km/h grade=%+.1f%% lands %+.1f m from the aim (%s) efh=%.2f" % [sd, j.type, j.size, j.s, r.v * 3.6, r.grade * 100.0, r.err, r.spot, r.efh])
		t.free()
	for k in stats:
		var st: Dictionary = stats[k]
		print("ROUTESUM %s n=%d mean_err=%+.1f m short=%d long=%d hard(EFH>1.5)=%d mean_grade=%+.1f%%" % [k, st.n, st.err / st.n, st.short, st.long, st.hard, st.grade / st.n * 100.0])
	quit()


## {v, grade, err (m past the aim, - = short), spot, efh}
static func check(f: TerrainField, C: TrailCourse, j) -> Dictionary:
	var air: Array = Array(j.air)   # (its own: a sized jump has its own spans)
	if air.size() < 2 or C.n < 2: return {}
	var lip_u := float(air[0]); var aim_u := float(air[1]) - 2.0
	var i := clampi(int((float(j.s) + lip_u) / TrailCourse.STEP), 0, C.n - 1)
	var va := float(C.VA[i]) * TerrainField.RIDER_K   # (riders' real speed: TerrainField.RIDER_K x the free-rolling VA)
	var grade := (float(j.b1) - float(j.b0)) / maxf(1.0, float(j.len))
	var H := float(j.prof.ev(lip_u - 0.05))
	var slope := (float(j.prof.ev(lip_u - 0.05)) - float(j.prof.ev(lip_u - 0.45))) / 0.4 + grade
	var vl := sqrt(maxf(1.0, va * va - 2.0 * G * H - JumpDesign.FACE_LOSS * H * va))
	var a := atan(slope)
	var vx := vl * cos(a); var vy := vl * sin(a)
	var x0 := float(j.x) + float(j.dx) * lip_u; var z0 := float(j.z) + float(j.dz) * lip_u
	var y0 := f.deck(x0, z0)
	var t := 0.0
	while t < 5.0:
		t += 0.01
		var x := x0 + float(j.dx) * vx * t; var z := z0 + float(j.dz) * vx * t
		var y := y0 + vy * t - 0.5 * G * t * t
		var g := f.deck(x, z)
		if vx * t > 0.3 and y <= g:
			var u := lip_u + vx * t
			var gx := (f.deck(x + 0.1, z) - f.deck(x - 0.1, z)) / 0.2
			var gz := (f.deck(x, z + 0.1) - f.deck(x, z - 0.1)) / 0.2
			var n := Vector3(-gx, 1.0, -gz).normalized()
			var vel := Vector3(float(j.dx) * vx, vy - G * t, float(j.dz) * vx)
			var vn := -vel.dot(n)
			var spot := "landing" if absf(u - aim_u) <= 3.0 else ("short" if u < aim_u else "long")
			return {"v": va, "grade": grade, "err": u - aim_u, "spot": spot, "efh": vn * vn / (2.0 * G)}
	return {"v": va, "grade": grade, "err": 99.0, "spot": "?", "efh": 9.9}
