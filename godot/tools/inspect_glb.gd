extends SceneTree
func _init():
	for f in ["res://assets/dh.glb", "res://assets/bmx.glb", "res://assets/helmet.glb"]:
		var s = load(f).instantiate()
		print("=== ", f)
		_dump(s, 0)
	quit()
func _dump(n, d):
	if d > 4: return
	var extra = ""
	for m in n.get_meta_list(): extra += " META[%s]=%s" % [m, str(n.get_meta(m)).substr(0, 600)]
	var info = ""
	if n is MeshInstance3D:
		var mats = []
		for i in n.mesh.get_surface_count(): mats.append(n.mesh.surface_get_material(i).resource_name if n.mesh.surface_get_material(i) else "-")
		info = " mats=" + str(mats)
	print("  ".repeat(d), n.name, " <", n.get_class(), "> pos=", n.position if n is Node3D else "", info, extra)
	for c in n.get_children(): _dump(c, d + 1)
