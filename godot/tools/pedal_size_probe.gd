extends SceneTree
## Pedal sizes per model (its pivot = the mesh's centre): top surface above the pivot, length / width.
## Run: --headless -s res://tools/pedal_size_probe.gd

func _init() -> void:
	var ids := ["stock"]
	for k in BikeBuild.PEDAL_GLB: ids.append(k)
	for id in ids:
		var set: Dictionary = BikeRig.pedal_set(id)
		for side in set:
			var m: Mesh = set[side][0]
			var bb := m.get_aabb()
			print("PEDAL %s side=%s centre=%s  x %.3f..%.3f  y %.3f..%.3f  z %.3f..%.3f" % [id, side, set[side][1], bb.position.x, bb.end.x, bb.position.y, bb.end.y, bb.position.z, bb.end.z])
	quit()
