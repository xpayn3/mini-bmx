extends Node3D
## All five cactus kinds in a row, close up, low warm sun, in the desert ground colour.
## godot --path godot res://tools/cactus_gallery.tscn -- out.png [yaw=deg] [dist=m] [h=m] [sun=deg] [at=x] [old=1]
## old=1 = the flat stylised look (no skin, old greens) for comparison.

func _ready() -> void:
	var out := "cactus_gallery.png"
	var yaw := 20.0
	var dist := 9.0
	var sun := 24.0
	var at := 0.0
	var ch := -1.0
	var old := false
	for a in OS.get_cmdline_user_args():
		if a.begins_with("yaw="): yaw = float(a.substr(4))
		elif a.begins_with("dist="): dist = float(a.substr(5))
		elif a.begins_with("sun="): sun = float(a.substr(4))
		elif a.begins_with("at="): at = float(a.substr(3))
		elif a.begins_with("h="): ch = float(a.substr(2))
		elif a == "old=1": old = true
		elif not a.contains("="): out = a
	TerrainGeo.ensure()
	TerrainGeo.MAT["cactus"].set_shader_parameter("cactus_skin", not old)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.66, 0.76, 0.9)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.6, 0.66, 0.78)
	env.ambient_light_energy = 0.45
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun_l := DirectionalLight3D.new()
	sun_l.rotation_degrees = Vector3(-sun, 150, 0)
	sun_l.light_color = Color(1.0, 0.88, 0.74)
	sun_l.light_energy = 2.6
	sun_l.shadow_enabled = true
	add_child(sun_l)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(80, 80)
	ground.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.62, 0.5, 0.36)
	gm.roughness = 1.0
	ground.material_override = gm
	add_child(ground)
	var cols := [0x4f8a3c, 0x5c9a45, 0x6b9e4a] if old else [0x758a55, 0x82935e, 0x6b8050, 0x7d9068, 0x8a9258]
	for k in CactusGeo.KINDS:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true
		mm.mesh = CactusGeo.MESHES[k]
		mm.instance_count = 1
		mm.set_instance_transform(0, Transform3D(Basis(Vector3.UP, 0.7 * k), Vector3((k - 2) * 1.9, 0, 0)))
		var c := TerrainField.lin(cols[k % cols.size()])
		mm.set_instance_custom_data(0, c)
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = TerrainGeo.MAT["cactus"]
		add_child(mmi)
	var cam := Camera3D.new()
	cam.fov = 40
	add_child(cam)
	var yr := deg_to_rad(yaw)
	if ch < 0.0: ch = dist * 0.2 + 0.6
	cam.position = Vector3(at + sin(yr) * dist, ch, cos(yr) * dist)
	cam.look_at(Vector3(at, 1.0, 0.0))
	for i in 12:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(out)
	print("SAVED ", out)
	get_tree().quit()
