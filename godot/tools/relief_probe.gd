extends SceneTree
## the relief layers (TerrainField._relief) over an area: how much of it each reaches, the trail-distance map.
## -s res://tools/relief_probe.gd -- [seed] [x0] [z0] [size]
func _init() -> void:
	var a := OS.get_cmdline_user_args()
	var sd := int(a[0]) if a.size() > 0 else 4242
	var x0 := float(a[1]) if a.size() > 1 else 1400.0
	var z0 := float(a[2]) if a.size() > 2 else -1500.0
	var s := float(a[3]) if a.size() > 3 else 2400.0
	var f := TerrainField.new()
	f.setup(sd)
	print("RELIEF far grid ", f.c_far_nx, "x", f.c_far_nz, " origin ", f.c_far_x0 * TerrainField.FAR_CELL, ",", f.c_far_z0 * TerrainField.FAR_CELL)
	var n := 60
	var far_hist := [0, 0, 0, 0]
	var r_min := INF; var r_max := -INF; var wm0 := 0; var reg_on := 0
	var t0 := Time.get_ticks_usec()
	for j in n:
		for i in n:
			var x := x0 + s * i / (n - 1)
			var z := z0 + s * j / (n - 1)
			var fr := f.trail_far(x, z)
			far_hist[0 if fr < 50 else (1 if fr < 200 else (2 if fr < 420 else 3))] += 1
			if f.wild_mask(x, z) == 0.0: wm0 += 1
			if f.noise((x + 9100.0) * TerrainField.PK_RI, (z - 5300.0) * TerrainField.PK_RI) > -0.1: reg_on += 1
			f.landform(x, z)
			var r := f._relief(x, z)
			r_min = minf(r_min, r); r_max = maxf(r_max, r)
	var us := float(Time.get_ticks_usec() - t0) / (n * n)
	print("RELIEF far <50 / <200 / <420 / more: ", far_hist, "  wild_mask 0: ", wm0, "  peak region on: ", reg_on, " of ", n * n)
	print("RELIEF relief min %.1f max %.1f  (%.1f us a point, GDScript, incl. landform)" % [r_min, r_max, us])
	quit()
