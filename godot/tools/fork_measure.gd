extends SceneTree
func _init():
	var s = load("res://assets/dh.glb").instantiate()
	var fl: MeshInstance3D = s.find_child("fork_lower", true, false)
	for i in fl.mesh.get_surface_count():
		var m = fl.mesh.surface_get_material(i)
		var v: PackedVector3Array = fl.mesh.surface_get_arrays(i)[Mesh.ARRAY_VERTEX]
		var a := Vector3(-0.03, 0.07, 0); var b := Vector3(-0.165, 0.335, 0)
		var d := (b - a).normalized(); var n := Vector3(-d.y, d.x, 0)
		var lo := 1e9; var hi := -1e9; var alo := 1e9; var ahi := -1e9; var zlo := 1e9; var zhi := -1e9
		for p in v:
			if p.z < 0.06: continue   # the drive-side leg only
			var q := p - a
			lo = minf(lo, q.dot(n)); hi = maxf(hi, q.dot(n)); alo = minf(alo, q.dot(d)); ahi = maxf(ahi, q.dot(d)); zlo = minf(zlo, p.z); zhi = maxf(zhi, p.z)
		print(m.resource_name, " across=", snappedf(hi - lo, 0.001), " along=", snappedf(alo, 0.001), "..", snappedf(ahi, 0.001), " z=", snappedf(zlo,0.001), "..", snappedf(zhi,0.001))
	quit()
