extends Node3D
## Old blob bushes (back row) vs leaf-card bushes (front row) on flat ground, close up, golden-hour sun.
## godot --path godot res://tools/bush_gallery.tscn -- out.png [yaw=deg] [dist=m] [sun=deg]

const GREENS := [0x3f7f33, 0x4c8c38, 0x5a8f3a, 0x6a9a3e, 0x7a8f3a]


func _ready() -> void:
	var out := "bush_gallery.png"
	var yaw := 20.0
	var dist := 7.0
	var sun := 18.0
	for a in OS.get_cmdline_user_args():
		if a.begins_with("yaw="): yaw = float(a.substr(4))
		elif a.begins_with("dist="): dist = float(a.substr(5))
		elif a.begins_with("sun="): sun = float(a.substr(4))
		elif not a.contains("="): out = a
	TerrainGeo.ensure()
	var old_blob := TerrainGeo._crown(11, 2, true).translate(0, 0.55, 0).scale(1, 0.7, 1).to_mesh(true)
	var kinds := ["bush", "bush1", "bush2", "bushdry", "bushdry"]
	var scrub := [0x9a7a48, 0xb08a52, 0x8c6c3e, 0x7f8a4a]
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.62, 0.74, 0.9)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.62, 0.75)
	env.ambient_light_energy = 0.6
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun_l := DirectionalLight3D.new()
	sun_l.rotation_degrees = Vector3(-sun, 140, 0)
	sun_l.light_color = Color(1.0, 0.82, 0.62)
	sun_l.light_energy = 2.2
	sun_l.shadow_enabled = true
	add_child(sun_l)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(60, 60)
	ground.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.42, 0.36, 0.22)
	gm.roughness = 1.0
	ground.material_override = gm
	add_child(ground)
	# back row: the current blob bush; front row: leaf cards (same scales + colours)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for row in 2:
		for i in 5:
			var dry: bool = row == 1 and kinds[i] == "bushdry"
			var col := TerrainGeo.lin(scrub[i % 4] if dry else GREENS[i])
			var sc := 0.75 + rng.randf() * 0.5
			# INSTANCE_CUSTOM (the tint) is only set by a MultiMesh: one instance each
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.use_custom_data = true
			mm.mesh = old_blob if row == 0 else TerrainGeo.MESH[kinds[i]]
			mm.instance_count = 1
			var t := Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(sc, sc * (0.9 + rng.randf() * 0.4), sc)),
				Vector3((i - 2) * 2.3 + rng.randf_range(-0.3, 0.3), 0, -1.6 if row == 0 else 1.4))
			mm.set_instance_transform(0, t)
			mm.set_instance_custom_data(0, col)
			var mmi := MultiMeshInstance3D.new()
			mmi.multimesh = mm
			mmi.material_override = TerrainGeo.MAT["leafSoft"] if row == 0 else (TerrainGeo.MAT["leafCardDry"] if dry else TerrainGeo.MAT["leafCard"])
			add_child(mmi)
	var cam := Camera3D.new()
	cam.fov = 40
	add_child(cam)
	var yr := deg_to_rad(yaw)
	cam.position = Vector3(sin(yr) * dist, 2.2, cos(yr) * dist)
	cam.look_at(Vector3(0, 0.6, 0.0))
	for i in 12:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(out)
	print("SAVED ", out)
	get_tree().quit()
