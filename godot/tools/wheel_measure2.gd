extends SceneTree
## Stock wheel details: spoke ends (angles / z at hub and rim), rim + tyre cross-section profiles.

func _initialize() -> void:
	var root3d: Node3D = load("res://assets/dh.glb").instantiate()
	var bike := root3d.find_child("dh", true, false) as Node3D
	for wn in ["wheel_front", "wheel_rear"]:
		var w := bike.find_child(wn, true, false) as MeshInstance3D
		print("==== ", wn)
		var black: PackedVector3Array = w.mesh.surface_get_arrays(1)[Mesh.ARRAY_VERTEX]
		var rub: PackedVector3Array = w.mesh.surface_get_arrays(2)[Mesh.ARRAY_VERTEX]
		# spoke heads near hub: angle clusters
		var heads := {}
		for p in black:
			var r := Vector2(p.x, p.y).length()
			if r < 0.03 and r > 0.019:
				var a := roundi(rad_to_deg(atan2(p.y, p.x)) / 2.0) * 2
				var key := "%d_%s" % [a, "L" if p.z < 0.007 else "R"]
				heads[key] = heads.get(key, 0) + 1
		print(" head clusters: ", heads.size())
		# spokes passing r in [0.20,0.201]: angle + z + thickness
		var mid := []
		for p in black:
			var r := Vector2(p.x, p.y).length()
			if r > 0.19 and r < 0.23:
				mid.append(p)
		print(" verts r 19-23cm: ", mid.size())
		# rim profile (black r>0.25): max |z| per 0.5mm of r
		var prof := {}
		for p in black:
			var r := Vector2(p.x, p.y).length()
			if r < 0.25: continue
			var k := int(r * 2000.0)
			prof[k] = maxf(prof.get(k, 0.0), absf(p.z))
		var ks := prof.keys(); ks.sort()
		var s := ""
		for k in ks: s += " %.1f:%.1f" % [k * 0.5, prof[k] * 1000.0]
		print(" rim profile r(mm):|z|max(mm)", s)
		prof = {}
		for p in rub:
			var r := Vector2(p.x, p.y).length()
			var k := int(r * 1000.0)
			prof[k] = maxf(prof.get(k, 0.0), absf(p.z))
		ks = prof.keys(); ks.sort()
		s = ""
		for k in ks: s += " %d:%.1f" % [k, prof[k] * 1000.0]
		print(" tyre profile r(mm):|z|max(mm)", s)
		# knob count around: rubber verts with r > max-2mm, angle buckets of 1 deg
		var rmax := 0.0
		for p in rub: rmax = maxf(rmax, Vector2(p.x, p.y).length())
		var ang := {}
		for p in rub:
			if Vector2(p.x, p.y).length() > rmax - 0.002:
				ang[int(rad_to_deg(atan2(p.y, p.x)) + 180.0)] = 1
		print(" rmax=", rmax, " degrees with outer verts: ", ang.size())
	quit()
