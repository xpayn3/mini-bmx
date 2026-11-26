extends Node3D
## Every rock type (rows: granite, desert, tundra, basalt; columns: variant 0, variant 1 at LOD0, variant 0 at LOD1, pebble),
## close up, low sun. Rows get moss 0 / 0 / 0.4 / 0.2, granite row's variant 1 full moss (forest).
## godot --path godot res://tools/rock_gallery.tscn -- out.png [yaw=deg] [dist=m] [sun=deg] [wire=1]

func _ready() -> void:
	var out := "rock_gallery.png"
	var yaw := 25.0
	var dist := 12.0
	var sun := 22.0
	for a in OS.get_cmdline_user_args():
		if a.begins_with("yaw="): yaw = float(a.substr(4))
		elif a.begins_with("dist="): dist = float(a.substr(5))
		elif a.begins_with("sun="): sun = float(a.substr(4))
		elif a == "wire=1": get_viewport().debug_draw = Viewport.DEBUG_DRAW_WIREFRAME
		elif not a.contains("="): out = a
	var t0 := Time.get_ticks_msec()
	TerrainGeo.ensure()
	print("ROCKGEN ensure_ms=", Time.get_ticks_msec() - t0)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.62, 0.74, 0.9)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.62, 0.75)
	env.ambient_light_energy = 0.5
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun_l := DirectionalLight3D.new()
	sun_l.rotation_degrees = Vector3(-sun, 140, 0)
	sun_l.light_color = Color(1.0, 0.88, 0.74)
	sun_l.light_energy = 2.6
	sun_l.shadow_enabled = true
	add_child(sun_l)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(80, 80)
	ground.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.36, 0.33, 0.26)
	gm.roughness = 1.0
	ground.material_override = gm
	add_child(ground)
	var moss := [[0.3, 1.0], [0.0, 0.0], [0.4, 0.4], [0.2, 0.2]]
	for r in RockGen.TYPES.size():
		var t: String = RockGen.TYPES[r]
		var cells := [[RockGen.list_name(t, 0) + "_lod0", moss[r][0]], [RockGen.list_name(t, 1) + "_lod0", moss[r][1]],
			[RockGen.list_name(t, 0), moss[r][0]], ["pebble_" + t, moss[r][0]]]
		for c in cells.size():
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.use_custom_data = true
			mm.mesh = TerrainGeo.MESH[cells[c][0]]
			mm.instance_count = 1
			var sc := 1.1 if c < 3 else 0.45
			mm.set_instance_transform(0, Transform3D(Basis(Vector3.UP, 0.6 * c + r).scaled(Vector3(sc * 1.2, sc * 0.9, sc)),
				Vector3((c - 1.5) * 3.2, -sc * 0.25, (r - 1.5) * 3.0)))
			mm.set_instance_custom_data(0, Color(1, 1, 1, cells[c][1]))
			var mmi := MultiMeshInstance3D.new()
			mmi.multimesh = mm
			mmi.material_override = TerrainGeo.MAT["rock_" + t]
			add_child(mmi)
	var cam := Camera3D.new()
	cam.fov = 40
	add_child(cam)
	var yr := deg_to_rad(yaw)
	var ch := dist * 0.55
	for a in OS.get_cmdline_user_args():
		if a.begins_with("h="): ch = float(a.substr(2))
	cam.position = Vector3(sin(yr) * dist, ch, cos(yr) * dist)
	cam.look_at(Vector3(0, 0.3, 0.0))
	for i in 12:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(out)
	print("SAVED ", out)
	get_tree().quit()
