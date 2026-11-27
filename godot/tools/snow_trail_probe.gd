extends SceneTree
## stretches of the main trail that run through snow (TerrainField.cl_snow on the centreline every 10 m).  -- [seed] [length m]
func _init() -> void:
	var a := OS.get_cmdline_user_args()
	var sd := int(a[0]) if a.size() > 0 else 4242
	var L := float(a[1]) if a.size() > 1 else 4000.0
	var t := Terrain.new(sd)
	var f: TerrainField = t.field
	var C = f.course
	var s := 0.0
	var run0 := -1.0
	while s < L:
		var p: Array = C.at(s)
		var x: float = p[0]; var z: float = p[1]
		var h := f.ground(x, z)
		var e := 1.0
		var nx := f.ground(x - e, z) - f.ground(x + e, z)
		var nz := f.ground(x, z - e) - f.ground(x, z + e)
		f.color_layers(x, z, h, 2.0 * e / sqrt(nx * nx + 4.0 * e * e + nz * nz))
		var on := f.cl_snow > 0.4
		if on and run0 < 0.0: run0 = s
		if not on and run0 >= 0.0:
			if s - run0 >= 30.0:
				var q: Array = C.at(run0 + 10.0)
				print("SNOWTRAIL s=%.0f..%.0f start at %.1f,%.1f" % [run0, s, q[0], q[1]])
			run0 = -1.0
		s += 10.0
	t.free(); quit()
