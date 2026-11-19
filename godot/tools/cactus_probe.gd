extends SceneTree
## Cactus kinds + Voronoi fracture check: every body closed and outward (volume > 0), every fracture
## piece closed (same volume wherever it is moved), piece volumes add up to the whole, timings.
## run: --headless -s res://tools/cactus_probe.gd   -> must end with PASS


func _open_edges(g: GeoBuf, n: int) -> int:
	var e := {}
	for i in range(0, n, 3):
		for k in 3:
			var a := CactusGeo._key(g.pos[i + k])
			var b := CactusGeo._key(g.pos[i + (k + 1) % 3])
			if a == b: continue
			var key := [a, b]
			var rk := [b, a]
			if e.has(rk):
				e[rk] -= 1
				if e[rk] == 0: e.erase(rk)
			else:
				e[key] = e.get(key, 0) + 1
	return e.size()


## signed volume in doubles (Vector3 is single precision), about the point o
func _vol(g: GeoBuf, n: int, o := Vector3.ZERO) -> float:
	var v := 0.0
	for i in range(0, n, 3):
		var ax: float = g.pos[i].x - o.x; var ay: float = g.pos[i].y - o.y; var az: float = g.pos[i].z - o.z
		var bx: float = g.pos[i + 1].x - o.x; var by: float = g.pos[i + 1].y - o.y; var bz: float = g.pos[i + 1].z - o.z
		var cx: float = g.pos[i + 2].x - o.x; var cy: float = g.pos[i + 2].y - o.y; var cz: float = g.pos[i + 2].z - o.z
		v += (ax * (by * cz - bz * cy) + ay * (bz * cx - bx * cz) + az * (bx * cy - by * cx)) / 6.0
	return v


func _init() -> void:
	var ok := true
	for k in CactusGeo.KINDS:
		var t0 := Time.get_ticks_msec()
		var d := CactusGeo.build(k)
		var t1 := Time.get_ticks_msec()
		var vol := 0.0
		var tris := 0
		for b in d["bodies"]:
			var oe := _open_edges(b, b.pos.size())
			var v := _vol(b, b.pos.size())
			vol += v
			tris += b.pos.size() / 3
			if oe > 0 or v <= 0.0:
				print("  body open=%d vol=%.4f" % [oe, v]); ok = false
		var etris := 0
		for e in d["extras"]:
			etris += e["g"].pos.size() / 3
		var fr := CactusGeo.fracture(d, CactusGeo.CELLS[k], 9001 + k * 77, k)
		var t2 := Time.get_ticks_msec()
		var pv := 0.0
		var bad := 0
		for p in fr:
			var g: GeoBuf = p["g"]
			var n: int = p["nbody"]
			var v0 := _vol(g, n)
			pv += v0
			# a closed mesh keeps its volume when moved; a hole changes it
			var dv := absf(_vol(g, n, Vector3(3, 5, 7)) - v0)
			if dv > 1e-4 + absf(v0) * 1e-3:   # ~1 cm2 of missing cap; slivers (mm2) pass
				bad += 1
				print("   open piece: vol %.5f, moved differs by %.7f" % [v0, dv])
		print("%-13s body_tris=%d spine_tris=%d build=%dms pieces=%d fracture=%dms vol=%.4f pieces_vol=%.4f open_pieces=%d broken_loops=%d bad_tri=%d" %
			[CactusGeo.NAMES[k], tris, etris, t1 - t0, fr.size(), t2 - t1, vol, pv, bad, CactusGeo.fails[0], CactusGeo.fails[1]]); CactusGeo.fails = [0, 0]
		if bad > 0 or absf(pv - vol) > vol * 0.01 or fr.size() < CactusGeo.CELLS[k] / 2: ok = false
	print("PASS" if ok else "FAIL")
	quit()
