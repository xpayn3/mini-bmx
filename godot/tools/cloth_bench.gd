extends SceneTree
## Times the cloth's parts in isolation: the C# solver, the pin/capsule maths, the mesh rebuild.
func _init():
	var r := Rider.new()
	root.add_child(r)
	r.set_style({})
	for i in 5:
		r.update_pose(1.0 / 60, {"footL": Vector3(0, 0.25, -0.15), "footR": Vector3(0, 0.25, 0.15), "handL": Vector3(0.44, 0.96, -0.3), "handR": Vector3(0.44, 0.96, 0.3), "v": 8.0, "pedal": 1.0, "t": i / 60.0})
	r.enable_cloth()
	await process_frame
	var c: RiderCloth = r.cloth
	var N := 200
	var t0 := Time.get_ticks_usec()
	for i in N: c._fr = []; c._capsules()
	var t_caps := (Time.get_ticks_usec() - t0) / float(N)
	t0 = Time.get_ticks_usec()
	for i in N: c._fr = []; c._hem_pins(); c._sleeve_pins(0); c._sleeve_pins(1)
	var t_pins := (Time.get_ticks_usec() - t0) / float(N)
	var cap := c._capsules()
	var pins: PackedVector3Array = c._hem_pins()
	t0 = Time.get_ticks_usec()
	for i in N: c._pieces[0].sim.StepFrame(1.0 / 180, 3, pins, pins, Vector3(10, 0, 0), cap[0], cap[1], 0.9, 0.985, 4)
	var t_hem := (Time.get_ticks_usec() - t0) / float(N)
	print("CLOTHBENCH inside C#: hem StepFrame(4 sub) = %.0fus" % c._pieces[0].sim.BenchSteps(200, pins, cap[0], cap[1]))
	t0 = Time.get_ticks_usec()
	for i in N:
		for p in c._pieces:
			var arr := []; arr.resize(Mesh.ARRAY_MAX)
			arr[Mesh.ARRAY_VERTEX] = p.sim.Positions(); arr[Mesh.ARRAY_NORMAL] = p.sim.Normals(); arr[Mesh.ARRAY_INDEX] = p.idx
			var m: ArrayMesh = p.mi.mesh if p.mi.mesh is ArrayMesh else ArrayMesh.new()
			m.clear_surfaces(); m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr); p.mi.mesh = m
	var t_mesh := (Time.get_ticks_usec() - t0) / float(N)
	t0 = Time.get_ticks_usec()
	for i in N: c._process(1.0 / 60)
	var t_all := (Time.get_ticks_usec() - t0) / float(N)
	print("CLOTHBENCH capsules=%.0fus pins=%.0fus hem_StepFrame(4 sub)=%.0fus mesh_rebuild(3)=%.0fus whole_frame=%.0fus" % [t_caps, t_pins, t_hem, t_mesh, t_all])
	quit()
