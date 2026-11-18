extends SceneTree
## Wooden decks must be climbable from an angle: drives straight lines onto every bridge / skinny /
## kicker ramp near spawn at several entry angles and reports the steepest step the bike's
## cliff-wall test (bike_physics.gd: slope > 1.6 and rise > 5 cm per physics step) would see.
## godot --headless --path godot --script res://tools/wood_edge_probe.gd

func _init() -> void:
	var f := TerrainField.new()
	f.setup(4242)
	var walls := 0
	var lines := 0
	var feats := 0
	for gz in range(-12, 13):
		for gx in range(-12, 13):
			var j = f.jump_at(gx, gz)
			if j == null or j.wood == null:
				continue
			feats += 1
			# entry lines: start beside / before the ramp, end on the ramp's low part, angles 0..60 deg
			for ang in [0.0, 15.0, 30.0, 45.0, 60.0]:
				for side in [-1.0, 1.0]:
					var a: float = deg_to_rad(ang) * side
					var du := cos(a); var dw := sin(a)
					var u_end := 1.4 if j.type != "woodKicker" else 1.6
					var start_u := u_end - du * 3.0
					var start_w := -dw * 3.0
					var stp := 6.0 / 120.0   # 6 m/s at 120 Hz
					var prev := NAN
					var px := 0.0; var pz := 0.0
					lines += 1
					for k in int(3.0 / stp) + 1:
						var u := start_u + du * stp * k
						var w := start_w + dw * stp * k
						var x: float = j.x + j.dx * u - j.dz * w
						var z: float = j.z + j.dz * u + j.dx * w
						var g := f.deck(x, z)
						if not is_nan(prev) and (g - prev) / stp > 1.6 and g - prev > 0.05:
							walls += 1
							print("WALL %s at (%.1f, %.1f) angle %d rise %.2f" % [j.type, x, z, int(ang * side), g - prev])
							break
						prev = g
	print("WOOD_PROBE features=%d lines=%d walls=%d" % [feats, lines, walls])
	quit()
