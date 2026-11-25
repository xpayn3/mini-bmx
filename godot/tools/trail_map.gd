extends SceneTree
## Top-down map of the world: shaded land (TerrainField.base), the route spine (yellow) and the trail (red), the
## course grown to `len` m. Prints TRAILMAP stats: the box it covers, how far it heads back (-x), the closest two
## legs of the spine come (more than 1.5 km apart along it), the trail's grade.
## -s res://tools/trail_map.gd -- out.png [seed] [course m] [m per px]   (BMX_OLD_ROUTE=1: the old straight corridor)
func _init() -> void:
	var a := OS.get_cmdline_user_args()
	var out: String = a[0] if a.size() > 0 else "trail_map.png"
	var sd := int(a[1]) if a.size() > 1 else 4242
	var want := float(a[2]) if a.size() > 2 else 4000.0
	var mpp := float(a[3]) if a.size() > 3 else 12.0
	var t0 := Time.get_ticks_msec()
	var f := TerrainField.new()
	f.setup(sd, {})
	var t_setup := Time.get_ticks_msec() - t0
	var guard := 0
	while f.course.end_s() < want and guard < 12:
		guard += 1
		var k := f.fork()
		k.grow_course(f.course.end_s() + 3000.0)
		f.adopt_course(k)
	var C = f.course
	var sp = f.spine
	var minx := INF; var maxx := -INF; var minz := INF; var maxz := -INF
	for i in sp.n:
		minx = minf(minx, sp.X[i]); maxx = maxf(maxx, sp.X[i]); minz = minf(minz, sp.Z[i]); maxz = maxf(maxz, sp.Z[i])
	minx -= 500; maxx += 500; minz -= 500; maxz += 500
	var W := int((maxx - minx) / mpp) + 1
	var H := int((maxz - minz) / mpp) + 1
	var img := Image.create(W, H, false, Image.FORMAT_RGB8)
	var G := PackedFloat32Array(); G.resize((W + 1) * (H + 1))
	for j in H + 1:
		for i in W + 1:
			G[j * (W + 1) + i] = f.base(minx + i * mpp, minz + j * mpp)
	for j in H:
		for i in W:
			var h: float = G[j * (W + 1) + i]
			var dx: float = (G[j * (W + 1) + i + 1] - h) / mpp
			var dz: float = (G[(j + 1) * (W + 1) + i] - h) / mpp
			var nn := Vector3(-dx, 1.0, -dz).normalized()
			var sh := clampf(nn.dot(Vector3(-0.5, 0.75, -0.45).normalized()), 0.0, 1.0)
			var t := clampf((h + 20.0) / 160.0, 0.0, 1.0)
			var c := Color(0.30, 0.50, 0.25).lerp(Color(0.80, 0.74, 0.60), t)
			if h < -2.2: c = Color(0.2, 0.35, 0.6)
			c = c * (0.35 + 0.9 * sh); c.a = 1.0
			img.set_pixel(i, j, c)
	for i in sp.n:
		var ii := int((sp.X[i] - minx) / mpp); var jj := int((sp.Z[i] - minz) / mpp)
		if ii >= 0 and ii < W and jj >= 0 and jj < H: img.set_pixel(ii, jj, Color(1, 0.9, 0.1))
	for k in C.n:
		var ii := int((C.X[k] - minx) / mpp); var jj := int((C.Z[k] - minz) / mpp)
		for d in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)]:
			if ii + d.x >= 0 and ii + d.x < W and jj + d.y >= 0 and jj + d.y < H:
				img.set_pixel(ii + d.x, jj + d.y, Color(0.85, 0.05, 0.05))
	# the closest two legs of the spine (> 1.5 km apart along it)
	var gap := INF
	for i in range(0, sp.n, 4):
		for j in range(0, sp.n, 4):
			if sp.S[i] - sp.S[j] > 1500.0:
				gap = minf(gap, Vector2(sp.X[i] - sp.X[j], sp.Z[i] - sp.Z[j]).length())
	var back := 0.0
	for k in range(1, C.n):
		if C.X[k] < C.X[k - 1]: back += 2.0
	var gmax := 0.0
	var steep := 0
	var cnt := 0
	for k in range(10, C.n - 10, 5):
		var in_drop := false
		for dr in C.drops:
			if k + 10 >= dr[0] and k - 10 <= dr[1]: in_drop = true
		if in_drop: continue
		var gg: float = absf(C.E[k + 10] - C.E[k - 10]) / 40.0
		if gg > gmax:
			gmax = gg
			print("TRAILMAP steepest so far %.1f %% at %d (x %.0f z %.0f) kind %d" % [gg * 100.0, k, C.X[k], C.Z[k], C.KD[k]])
		cnt += 1
		if gg > 0.15: steep += 1
	print("TRAILMAP 40 m windows over 15 %%: %.1f %% (drops left out)" % [100.0 * steep / maxi(cnt, 1)])
	print("TRAILMAP seed=%d setup=%d ms spine=%.0f m course=%d pts (%.0f m) box %.1f x %.1f km, trail heading -x %.0f %%, closest legs %.0f m, steepest 40 m %.1f %%" % [
		sd, t_setup, sp.S[sp.n - 1], C.n, C.n * 2.0, (maxx - minx) / 1000.0, (maxz - minz) / 1000.0, 100.0 * back / (C.n * 2.0), gap, gmax * 100.0])
	img.save_png(out)
	print("TRAILMAP ", out)
	quit()
