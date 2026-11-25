extends SceneTree
## Shaded-relief map of the land (TerrainField.landform, GDScript reference), old (BMX_OLD_LAND) vs new, side by side.
## -s res://tools/land_map.gd -- out.png [seed] [x0] [z0] [metres]
func _init() -> void:
	var a := OS.get_cmdline_user_args()
	var out: String = a[0] if a.size() > 0 else "land_map.png"
	var sd := int(a[1]) if a.size() > 1 else 4242
	var x0 := float(a[2]) if a.size() > 2 else 2600.0
	var z0 := float(a[3]) if a.size() > 3 else -900.0
	var span := float(a[4]) if a.size() > 4 else 1800.0
	var N := 450
	var step := span / N
	var f := TerrainField.new()
	f.setup(sd, {})
	var img := Image.create(N * 2 + 10, N, false, Image.FORMAT_RGB8)
	img.fill(Color.WHITE)
	for pass_i in 2:
		TerrainField.OLD_LAND = pass_i == 0
		var H := PackedFloat32Array(); H.resize((N + 2) * (N + 2))
		for j in N + 2:
			for i in N + 2:
				H[j * (N + 2) + i] = f.landform(x0 + (i - 1) * step, z0 + (j - 1) * step)
		for j in N:
			for i in N:
				var h: float = H[(j + 1) * (N + 2) + i + 1]
				var dx: float = (H[(j + 1) * (N + 2) + i + 2] - H[(j + 1) * (N + 2) + i]) / (2.0 * step)
				var dz: float = (H[(j + 2) * (N + 2) + i + 1] - H[j * (N + 2) + i + 1]) / (2.0 * step)
				var n := Vector3(-dx, 1.0, -dz).normalized()
				var sh := clampf(n.dot(Vector3(-0.5, 0.75, -0.45).normalized()), 0.0, 1.0)
				var t := clampf((h + 10.0) / 70.0, 0.0, 1.0)
				var base := Color(0.30, 0.50, 0.25).lerp(Color(0.75, 0.70, 0.55), t)
				if h < -2.2: base = Color(0.2, 0.35, 0.6)
				var c := base * (0.35 + 0.9 * sh)
				c.a = 1.0
				img.set_pixel(i + pass_i * (N + 10), j, c)
	img.save_png(out)
	print("LANDMAP ", out)
	quit()
