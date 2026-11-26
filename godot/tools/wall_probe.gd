extends SceneTree
## steep walls in the land round a spot: every 20 m out to r m, the steepest 20 m step (rise over run) found, where, how tall,
## and which layer made it (land / relief / mountain), for chasing "wall" faces. -- seed x z [r]
func _init() -> void:
	var a := OS.get_cmdline_user_args()
	var t := Terrain.new(int(a[0]))
	var f: TerrainField = t.field
	var cx := float(a[1]); var cz := float(a[2]); var r := float(a[3]) if a.size() > 3 else 1500.0
	var walls := []
	var d := 20.0
	var x := cx - r
	while x <= cx + r:
		var z := cz - r
		while z <= cz + r:
			var h := f.ground(x, z)
			var hx := f.ground(x + d, z); var hz := f.ground(x, z + d)
			var g := maxf(absf(hx - h), absf(hz - h)) / d
			if g > 1.2: walls.append([g, x, z, h, maxf(absf(hx - h), absf(hz - h))])
			z += d
		x += d
	walls.sort_custom(func(p, q): return p[0] > q[0])
	print("WALLS n=%d (> 50 deg over 20 m)" % walls.size())
	for w in walls.slice(0, 12):
		var lf := f.landform(w[1], w[2])
		var rl := f._relief(w[1], w[2]) if f.has_method("_relief") else 0.0
		print("WALL slope=%.1f step=%.0f m at %.0f,%.0f h=%.0f landform=%.0f relief=%.0f trail_d=%.0f" % [w[0], w[4], w[1], w[2], w[3], lf, rl, f.route_dist(w[1], w[2])])
	t.free(); quit()
