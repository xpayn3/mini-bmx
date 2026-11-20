extends SceneTree
## Prints, per frame model, the crank mesh's surfaces and where the pedal geometry is (tools for the pedal swap).
## ..._console.exe --headless --path godot -s res://tools/pedal_probe.gd

func _init() -> void:
	for f in ["dh", "tues", "fuzz", "dhframe"]:
		var sc: Node = load("res://assets/%s.glb" % f).instantiate()
		var cr := sc.find_child("crank", true, false) as MeshInstance3D
		print("== ", f, " crank ", cr != null)
		if cr == null: sc.free(); continue
		var m := cr.mesh
		var pc := {}
		for si in m.get_surface_count():
			var nm: String = m.surface_get_material(si).resource_name if m.surface_get_material(si) else "?"
			var P: PackedVector3Array = m.surface_get_arrays(si)[Mesh.ARRAY_VERTEX]
			var lo := Vector3.INF; var hi := -Vector3.INF
			for p in P: lo = lo.min(p); hi = hi.max(p)
			print("  surf %d %s verts=%d lo=%s hi=%s" % [si, nm, P.size(), lo, hi])
			if nm == "plastic":
				for side in [-1.0, 1.0]:
					var c := Vector3.ZERO; var n := 0; var l2 := Vector3.INF; var h2 := -Vector3.INF
					for p in P:
						if signf(p.z) == side: c += p; n += 1; l2 = l2.min(p); h2 = h2.max(p)
					if n: print("    pedal side %d centre=%s lo=%s hi=%s" % [side, c / n, l2, h2]); pc[side] = c / n
		# non-plastic vertices near a pedal centre (x/y within 6 cm, outside the crank arm in z)
		for si in m.get_surface_count():
			var nm: String = m.surface_get_material(si).resource_name if m.surface_get_material(si) else "?"
			if nm == "plastic": continue
			var P: PackedVector3Array = m.surface_get_arrays(si)[Mesh.ARRAY_VERTEX]
			for side in pc:
				var c: Vector3 = pc[side]
				var k := 0; var zl := INF; var zh := -INF
				for p in P:
					if Vector2(p.x - c.x, p.y - c.y).length() < 0.06 and signf(p.z) == side:
						k += 1; zl = minf(zl, p.z); zh = maxf(zh, p.z)
				if k: print("    near pedal %d in %s: %d verts z %.3f..%.3f" % [side, nm, k, zl, zh])
		sc.free()
	quit()
