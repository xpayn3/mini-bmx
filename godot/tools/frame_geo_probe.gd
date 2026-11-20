extends SceneTree
## Prints each garage frame's geometry from its glb extras + meshes (wheelbase, head angle, BB height, chainstay,
## travel, mass proxy): the numbers the per-frame ride character is built from.
## ..._console.exe --headless --path godot -s res://tools/frame_geo_probe.gd

func _init() -> void:
	for f in ["dh", "tues", "dhframe", "fuzz"]:
		var sc: Node = load("res://assets/%s.glb" % f).instantiate()
		var m: Node = sc.find_child("dh", true, false)
		if m == null: m = sc
		var ex: Dictionary = m.get_meta("extras", {})
		var sa: Array = ex.get("steerAxis", [0, 1, 0])
		var head := rad_to_deg(atan2(absf(float(sa[1])), absf(float(sa[0]))))   # from horizontal
		var wf := m.find_child("wheel_front", true, false) as Node3D
		var wr := m.find_child("wheel_rear", true, false) as Node3D
		var cr := m.find_child("crank", true, false) as Node3D
		var gp := func(n: Node3D) -> Vector3:
			var t := Transform3D.IDENTITY
			var p: Node = n
			while p != sc and p != null:
				if p is Node3D: t = (p as Node3D).transform * t
				p = p.get_parent()
			return t.origin
		var pf: Vector3 = gp.call(wf); var pr: Vector3 = gp.call(wr); var pc: Vector3 = gp.call(cr)
		var susp: Dictionary = ex.get("suspension", {})
		var tri := 0
		for mi in m.find_children("*", "MeshInstance3D", true, false):
			var mesh: Mesh = (mi as MeshInstance3D).mesh
			if mesh: for si in mesh.get_surface_count(): tri += mesh.surface_get_array_len(si)
		print("%s: wheelbase=%.3f (axles %.3f) head=%.1f deg  bb_drop=%.3f  chainstay=%.3f  front_centre=%.3f  wheelR=%.3f/%.3f  fork=%s rear=%s  keys=%s" % [
			f, float(ex.get("wheelbase", -1)), Vector2(pf.x - pr.x, pf.y - pr.y).length(), head,
			(pf.y + pr.y) / 2.0 - pc.y, float(ex.get("bbToRearAxle", -1)), pf.x - pc.x,
			float(ex.get("wheelRadius", -1)), float(ex.get("wheelRadiusRear", ex.get("wheelRadius", -1))),
			susp.get("fork", {}).get("travel", "?"), susp.get("rear", {}).get("travel", "?"), ex.keys()])
		sc.free()
	quit()
