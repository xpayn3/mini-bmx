extends Node3D
## Solid crowns (back row) vs card crowns (front row), pines + leafy trees as the world places them, golden-hour sun.
## godot --path godot res://tools/tree_gallery.tscn -- out.png [yaw=deg] [dist=m] [sun=deg] [h=cam height] [look=y]

const PINES := [0x2f6e45, 0x3b7d4b, 0x2a5f44]
const LEAVES := [0x4f9a3a, 0x6cb544, 0x3f8a3f, 0x86c24a]


func _ready() -> void:
	var out := "tree_gallery.png"
	var yaw := 15.0
	var dist := 22.0
	var sun := 22.0
	var ch := 4.0
	var look := 4.0
	for a in OS.get_cmdline_user_args():
		if a.begins_with("yaw="): yaw = float(a.substr(4))
		elif a.begins_with("dist="): dist = float(a.substr(5))
		elif a.begins_with("sun="): sun = float(a.substr(4))
		elif a.begins_with("h="): ch = float(a.substr(2))
		elif a.begins_with("look="): look = float(a.substr(5))
		elif not a.contains("="): out = a
	TerrainGeo.ensure()
	# the near-card band round the origin (deco_fade.gdshaderinc): front row is inside it
	RenderingServer.global_shader_parameter_set("deco_fade", Vector4(0, 0, 100, 124))
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
	sun_l.directional_shadow_max_distance = 80
	add_child(sun_l)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(120, 120)
	ground.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.36, 0.36, 0.2)
	gm.roughness = 1.0
	ground.material_override = gm
	add_child(ground)
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	for row in 2:
		for i in 6:
			var pine := i < 4
			var sc := (0.7 + rng.randf() * 0.8) * 1.4
			var yaw_t := rng.randf() * TAU
			var x := (i - 2.5) * 6.0
			var z := -6.0 if row == 0 else 4.0
			var col: Color
			var crown: Transform3D
			var trunk: Transform3D
			if pine:
				var py := sc * (1.5 + rng.randf() * 0.7)
				var cb := sc * 0.6
				trunk = Transform3D(Basis(Vector3.UP, yaw_t).scaled(Vector3(sc, cb + 0.2 + py * 0.15, sc)), Vector3(x, -0.1, z))
				crown = Transform3D(Basis(Vector3.UP, yaw_t).scaled(Vector3(sc * 1.1, py, sc * 1.1)), Vector3(x, cb, z))
				col = TerrainGeo.lin(PINES[i % 3])
			else:
				var th := sc * (1.1 + rng.randf() * 0.6)
				trunk = Transform3D(Basis(Vector3.UP, yaw_t).scaled(Vector3(sc, th + 0.3, sc)), Vector3(x, -0.1, z))
				crown = Transform3D(Basis(Vector3.UP, yaw_t).scaled(Vector3(sc * 1.2, sc * 1.05, sc * 1.2)), Vector3(x, th + sc * 0.7, z))
				col = TerrainGeo.lin(LEAVES[i % 4])
			_one(TerrainGeo.MESH["trunk"], TerrainGeo.MAT["trunk_pine" if pine else "trunk"], trunk, Color(1, 1, 1), 1.0, true)
			var solid: Mesh = TerrainGeo.MESH["pine" if pine else "blob"]
			var smat: Material = TerrainGeo.MAT["leaf" if pine else "leafSoft"]
			if row == 0:
				_one(solid, smat, crown, col, 1.0, true)
			else:
				# the world's pair: solid (casts the shadow, hidden near) + its card twin
				var smi := _one(solid, smat, crown, col, 1.0, true)
				CardTree.add_twin(smi, "pine" if pine else "blob")
	var cam := Camera3D.new()
	cam.fov = 45
	add_child(cam)
	var yr := deg_to_rad(yaw)
	cam.position = Vector3(sin(yr) * dist, ch, cos(yr) * dist)
	cam.look_at(Vector3(0, look, 0.0))
	for i in 14:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(out)
	print("SAVED ", out)
	get_tree().quit()


func _one(mesh: Mesh, mat: Material, t: Transform3D, col: Color, mode: float, cast: bool) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = mesh
	mm.instance_count = 1
	mm.set_instance_transform(0, t)
	mm.set_instance_custom_data(0, col)
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if cast else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	mi.set_instance_shader_parameter("fade_mode", mode)
	return mi
