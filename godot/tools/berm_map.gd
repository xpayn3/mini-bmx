extends SceneTree
## Shaded relief of the ground (berm v2) over a window, old (BMX_OLD_BERM) | new, side by side, with contour lines every 25 cm.
## -s res://tools/berm_map.gd -- out.png [seed] [x0] [z0] [metres]
func _init() -> void:
	var a := OS.get_cmdline_user_args()
	var out: String = a[0] if a.size() > 0 else "berm_map.png"
	var sd := int(a[1]) if a.size() > 1 else 4242
	var x0 := float(a[2]) if a.size() > 2 else 2890.0
	var z0 := float(a[3]) if a.size() > 3 else -85.0
	var span := float(a[4]) if a.size() > 4 else 50.0
	var N := 400
	var step := span / N
	var f := TerrainField.new()
	f.setup(sd, {})
	var img := Image.create(N * 2 + 10, N, false, Image.FORMAT_RGB8)
	img.fill(Color.WHITE)
	for pass_i in 2:
		TerrainField.OLD_BERM = pass_i == 0
		var H := PackedFloat32Array(); H.resize((N + 2) * (N + 2))
		for j in N + 2:
			for i in N + 2:
				H[j * (N + 2) + i] = f.ground(x0 + (i - 1) * step, z0 + (j - 1) * step)
		for j in N:
			for i in N:
				var h: float = H[(j + 1) * (N + 2) + i + 1]
				var dx: float = (H[(j + 1) * (N + 2) + i + 2] - H[(j + 1) * (N + 2) + i]) / (2.0 * step)
				var dz: float = (H[(j + 2) * (N + 2) + i + 1] - H[j * (N + 2) + i + 1]) / (2.0 * step)
				var n := Vector3(-dx, 1.0, -dz).normalized()
				var sh := clampf(n.dot(Vector3(-0.6, 0.7, -0.4).normalized()), 0.0, 1.0)
				var t := clampf(fmod(h * 4.0, 1.0), 0.0, 1.0)
				var c := Color(0.55, 0.45, 0.32) * (0.3 + 0.9 * sh)
				if t < 0.08: c = c * 0.7
				c.a = 1.0
				img.set_pixel(i + pass_i * (N + 10), j, c)
	img.save_png(out)
	print("BERMMAP ", out)
	quit()
