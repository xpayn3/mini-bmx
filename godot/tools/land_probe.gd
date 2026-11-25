extends SceneTree
## Land shaping v2 vs the old land (BMX_OLD_LAND): slope distribution of the open land beside the trail, per seed.
## -s res://tools/land_probe.gd [-- seed ...]    prints LAND old / new: height range, slope percentiles, share steeper than 25 / 35 deg,
## share flatter than 4 deg, rms of the 6 m second difference (roughness).

func _stats(f: TerrainField, tag: String, sd: int) -> void:
	var sl: Array[float] = []
	var hs: Array[float] = []
	var rough := 0.0
	var rn := 0
	var step := 6.0
	for ox in [900.0, 2600.0, 3400.0, 5200.0]:
		for oz in [-420.0, -260.0, 260.0, 420.0]:
			var x0: float = ox
			var z0: float = f.zc(ox) + oz
			var n := 60
			for j in n:
				for i in n:
					var x := x0 + i * step
					var z := z0 + j * step
					var h := f.landform(x, z)
					hs.append(h)
					var hx := f.landform(x + step, z)
					var hz := f.landform(x, z + step)
					var s := sqrt((hx - h) * (hx - h) + (hz - h) * (hz - h)) / step
					sl.append(s)
					rough += pow(f.landform(x + step, z) - 2.0 * h + f.landform(x - step, z), 2)
					rn += 1
	sl.sort(); hs.sort()
	var t25 := tan(deg_to_rad(25.0)); var t35 := tan(deg_to_rad(35.0)); var t4 := tan(deg_to_rad(4.0))
	var a25 := 0; var a35 := 0; var f4 := 0
	for s in sl:
		if s > t25: a25 += 1
		if s > t35: a35 += 1
		if s < t4: f4 += 1
	var n2 := float(sl.size())
	print("LAND %s seed=%d h[min %.1f p5 %.1f p50 %.1f p95 %.1f max %.1f] slope[p50 %.2f p90 %.2f p99 %.2f] >25deg %.1f%% >35deg %.1f%% <4deg %.1f%% rough2 %.2f m" % [
		tag, sd, hs[0], hs[int(n2 * 0.05)], hs[int(n2 * 0.5)], hs[int(n2 * 0.95)], hs[-1], sl[int(n2 * 0.5)], sl[int(n2 * 0.9)], sl[int(n2 * 0.99)],
		100.0 * a25 / n2, 100.0 * a35 / n2, 100.0 * f4 / n2, sqrt(rough / rn)])


func _init() -> void:
	var seeds: Array = [4242, 5, 12]
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		seeds = []
		for a in args: seeds.append(int(a))
	for sd in seeds:
		var f := TerrainField.new()
		f.setup(sd, {})
		TerrainField.OLD_LAND = true
		_stats(f, "old", sd)
		TerrainField.OLD_LAND = false
		_stats(f, "new", sd)
	quit()
