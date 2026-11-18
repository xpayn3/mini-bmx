extends SceneTree
## Measures the stock dh.glb wheels: per-surface AABB, radius bands, Z layers (hub flanges, rotor, rim).
## godot --headless --path godot -s res://tools/wheel_measure.gd

func _initialize() -> void:
	var root3d: Node3D = load("res://assets/dh.glb").instantiate()
	get_root().add_child(root3d)
	var bike := root3d.find_child("dh", true, false) as Node3D
	for wn in ["wheel_front", "wheel_rear"]:
		var w := bike.find_child(wn, true, false) as MeshInstance3D
		print("==== ", wn, " parent=", w.get_parent().name, " xform=", w.transform, " global=", w.global_transform.origin)
		print(" aabb=", w.mesh.get_aabb())
		for s in w.mesh.get_surface_count():
			var arr := w.mesh.surface_get_arrays(s)
			var P: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var idx = arr[Mesh.ARRAY_INDEX]
			var mat := w.mesh.surface_get_material(s)
			var mn := mat.resource_name if mat else "?"
			var col = (mat as BaseMaterial3D).albedo_color if mat is BaseMaterial3D else null
			var met = (mat as BaseMaterial3D).metallic if mat is BaseMaterial3D else null
			var rou = (mat as BaseMaterial3D).roughness if mat is BaseMaterial3D else null
			print(" -- surface ", s, " mat=", mn, " col=", col, " met=", met, " rough=", rou, " verts=", P.size(), " tris=", (idx.size() if idx else P.size()) / 3)
			# histogram: radius buckets (1cm) -> z min/max, count
			var buckets := {}
			for p in P:
				var r := Vector2(p.x, p.y).length()
				var k := int(r * 100.0)
				var b = buckets.get(k)
				if b == null:
					buckets[k] = [1, p.z, p.z]
				else:
					b[0] += 1
					b[1] = minf(b[1], p.z)
					b[2] = maxf(b[2], p.z)
			var keys := buckets.keys()
			keys.sort()
			for k in keys:
				var b = buckets[k]
				print("    r=%3d cm n=%5d z=[%.4f, %.4f]" % [k, b[0], b[1], b[2]])
			# z layers for small-radius stuff (hub)
			var zs := {}
			for p in P:
				var r := Vector2(p.x, p.y).length()
				if r > 0.2: continue
				var k := roundi(p.z * 1000.0)
				var b = zs.get(k)
				if b == null:
					zs[k] = [1, r, r]
				else:
					b[0] += 1
					b[1] = minf(b[1], r)
					b[2] = maxf(b[2], r)
			var zk := zs.keys()
			zk.sort()
			var line := ""
			for k in zk:
				var b = zs[k]
				if b[0] >= 8:
					line += "\n    z=%4d mm n=%4d r=[%.4f, %.4f]" % [k, b[0], b[1], b[2]]
			print("   z-layers (r<0.2):", line)
	quit()
