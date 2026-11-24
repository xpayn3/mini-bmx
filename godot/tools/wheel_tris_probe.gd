extends SceneTree
## triangles per wheel part (tyre / rim / spokes / hub / chrome) at a few detail levels:  --headless -s res://tools/wheel_tris_probe.gd
func _init() -> void:
	for rear in [false, true]:
		for det in [1.0, 0.75, 0.5, 0.35]:
			var m: ArrayMesh = WheelGen.build({"rear": rear, "detail": det})
			var parts := []
			var tot := 0
			for i in m.get_surface_count():
				var a := m.surface_get_arrays(i)
				var idx = a[Mesh.ARRAY_INDEX]
				var n: int = (idx.size() if idx != null else (a[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()) / 3
				parts.append("%s=%d" % [m.surface_get_name(i), n])
				tot += n
			print("WHEELTRIS %s detail=%.2f total=%d  %s" % ["rear" if rear else "front", det, tot, " ".join(parts)])
	quit()
