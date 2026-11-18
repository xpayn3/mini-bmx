extends SceneTree
## Bike finish + decals + bolts on the real dh.glb: car paint, rotor glow, projected decals, pivot bolts.
func _initialize() -> void:
	var root3d: Node3D = load("res://assets/dh.glb").instantiate()
	get_root().add_child(root3d)
	var bike := root3d.find_child("dh", true, false) as Node3D
	var data: Dictionary = bike.get_meta("extras")
	var ok := true
	var paint := BikeFX.apply_paint(bike)
	print("paint shader ok=", paint.shader != null, " albedo=", paint.get_shader_parameter("albedo"))
	var t0 := Time.get_ticks_msec()
	var decals := BikeDecals.add_bike_decals(bike, BikeDecals.DH_DECALS)
	print("decals: %d meshes in %d ms" % [decals.size(), Time.get_ticks_msec() - t0])
	for d in decals:
		print("  ", d.get_parent().name, "/", d.name, " tris=", (d.mesh as ArrayMesh).surface_get_array_len(0) / 3)
	if decals.size() != 12:
		ok = false
	for w in ["wheel_front", "wheel_rear"]:
		var wheel := bike.find_child(w, true, false) as MeshInstance3D
		var t1 := Time.get_ticks_msec()
		var rg := BikeFX.find_rotor(wheel)
		if rg == null:
			print(w, ": no rotor found")
			ok = false
			continue
		rg.set_heat(0.8)
		print("%s rotor: tris=%d r0=%.3f heat=%.2f (%d ms)" % [w, rg.mesh_instance.mesh.surface_get_array_len(0) / 3, rg.material.get_shader_parameter("r0"), rg.material.get_shader_parameter("heat"), Time.get_ticks_msec() - t1])
	var r: Dictionary = data["suspension"]["rear"]
	var bolts := BikeDecals.add_pivot_bolts(bike, [{"node": "rocker", "at": r["G2"], "z": 0.029}, {"node": "rocker", "at": r["C2"], "z": 0.029}, {"node": "rocker", "at": r["D"], "z": 0.031, "r": 0.005}])
	for b in bolts:
		print("bolt at (rocker space) ", b.position)
	if bolts.size() != 3:
		ok = false
	await process_frame
	await process_frame
	print("SUSP_PARTS_TEST ", "PASS" if ok else "FAIL")
	quit(0 if ok else 1)
