extends SceneTree
## dumps ground / wood / jump / surface / biome / colour at the same 3000 points as the JS harness
func _init():
	var seed := 12345
	for a in OS.get_cmdline_user_args():
		seed = int(a)
	var f := TerrainField.new()
	f.setup(seed)
	var r := WorldRng.new(99)
	var pts := []
	for i in 1000:
		pts.append([-600 + r.next() * 2200, -500 + r.next() * 1000])
	var C := f.course
	for i in 1000:
		var p := C.at(r.next() * C.length)
		var a := (r.next() - 0.5) * 16
		pts.append([p[0] - p[3] * a, p[1] + p[2] * a])
	var feats: Array = f.route_feats.duplicate()
	for cx in range(-15, 46):
		for cz in range(-12, 13):
			var j := f.jump_at(cx, cz)
			if j != null:
				feats.append(j)
	for i in 1000:
		if feats.is_empty():
			break
		var j: TerrainField.Feat = feats[i % feats.size()]
		var u := r.next() * j.len
		var w := (r.next() - 0.5) * 2 * j.half
		pts.append([j.x + j.dx * u - j.dz * w, j.z + j.dz * u + j.dx * w])
	var lines := PackedStringArray(["feats %d" % feats.size()])
	for p in pts:
		var x: float = p[0]
		var z: float = p[1]
		var g := f.ground(x, z)
		var w = f.wood if f.has_wood else null
		var jj := f.jump(x, z)
		var col := f.color(x, z, g, 1.0)
		var surf := 0
		var h := f.deck(x, z)
		if h < TerrainField.WATER - 0.05: surf = 2
		elif f.trail(x, z) > 0.5: surf = 1
		else:
			f.biome(x, z)
			if h < TerrainField.WATER + 0.45 or f.b_dry > 0.7: surf = 3
		lines.append("%.12f %.12f %.12f %s %.12f %.12f %d %s %.6f %.6f %.6f" % [x, z, g, ("null" if w == null else "%.12f" % w), jj[0], jj[1], surf, f.biome_name(x, z), col.r, col.g, col.b])
	var fa := FileAccess.open("user://gd_dump.txt", FileAccess.WRITE)
	fa.store_string("\n".join(lines))
	fa.close()
	print("DUMP ", ProjectSettings.globalize_path("user://gd_dump.txt"))
	quit()
