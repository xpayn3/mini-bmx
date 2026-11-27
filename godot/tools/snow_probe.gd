extends SceneTree
## where the snow lies (TerrainField.cl_snow, the ground shader's snow layer): samples every 40 m over a square round the
## trail's start and lists the snowiest spots near the trail + the share of the land covered.  -- [seed] [half size m]
func _init() -> void:
	var a := OS.get_cmdline_user_args()
	var sd := int(a[0]) if a.size() > 0 else 4242
	var half := float(a[1]) if a.size() > 1 else 3000.0
	var t := Terrain.new(sd)
	var f: TerrainField = t.field
	var n := 0; var any := 0; var full := 0
	var best: Array = []
	var hmax := -1e9; var smax := 0.0; var dmin := 9.0
	print("SNOW snow_h=", TerrainField.SNOW_H)
	var x := -half
	while x <= half:
		var z := -half
		while z <= half:
			var h := f.ground(x, z)
			var e := 1.0
			var nx := f.ground(x - e, z) - f.ground(x + e, z)
			var nz := f.ground(x, z - e) - f.ground(x, z + e)
			var ny := 2.0 * e / sqrt(nx * nx + 4.0 * e * e + nz * nz)
			f.color_layers(x, z, h, ny)
			n += 1
			if h > TerrainField.SNOW_H:
				smax = maxf(smax, f.cl_snow); dmin = minf(dmin, f.cp_dry)
			hmax = maxf(hmax, h)
			if f.cl_snow > 0.05: any += 1
			if f.cl_snow > 0.8:
				full += 1
				f.query(x, z)
				best.append([f.q_d, x, z, h, f.cl_snow])
			z += 40.0
		x += 40.0
	best.sort_custom(func(p, q): return p[0] < q[0])
	print("SNOW hmax=%.0f snow_max_above_line=%.2f dry_min_above=%.2f" % [hmax, smax, dmin])
	print("SNOW seed=%d points=%d some=%.1f%% full=%.1f%%" % [sd, n, 100.0 * any / n, 100.0 * full / n])
	for i in mini(8, best.size()):
		var b: Array = best[i]
		print("SNOW near trail d=%.0f at %.0f,%.0f h=%.0f snow=%.2f" % [b[0], b[1], b[2], b[3], b[4]])
	t.free(); quit()
