extends SceneTree
## Shoe check: the rider's shoe with a shin (the real shin tube) going in at its ankle point at 50 / 70 / 90 / 120 deg
## between sole and shin; top row from the side, bottom row from behind at an angle. Run (not headless):
##   ..._console.exe --path godot -s res://tools/shoe_gallery.gd -- out.png      (BMX_OLD_SHOE=1 = the old shoe)
const GEAR := preload("res://scripts/rider/rider_gear.gd")
var frames := 0
var out := "user://shoe_gallery.png"

func _init() -> void:
	for a in OS.get_cmdline_user_args():
		if a.ends_with(".png"): out = a
	root.size = Vector2i(1600, 900)
	var w := Node3D.new()
	root.add_child(w)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color("#8d98a6")
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color("#c9d3e0")
	e.ambient_light_energy = 0.6
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = e
	w.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.8, 0.6, 0)
	sun.light_energy = 1.5
	sun.shadow_enabled = true
	w.add_child(sun)
	var mat := func(c: String) -> StandardMaterial3D:
		var m := StandardMaterial3D.new(); m.albedo_color = Color(c); m.roughness = 0.8; m.cull_mode = BaseMaterial3D.CULL_DISABLED; return m
	var M := {upper = mat.call("#ecebe6"), accent = mat.call("#d8232a"), sole = mat.call("#111214"), mid = mat.call("#f2f2ee"), laces = mat.call("#f2f2ee")}
	var pants: StandardMaterial3D = mat.call("#1d2b64")
	var shin_mesh := CylinderMesh.new()
	shin_mesh.top_radius = 0.04; shin_mesh.bottom_radius = 0.055; shin_mesh.height = 1.0; shin_mesh.radial_segments = 20
	var angs := [50.0, 70.0, 90.0, 120.0]
	for row in 2:
		for k in 4:
			var o := Vector3((k - 1.5) * 0.42, 0.55 - row * 0.5, 0)
			var sh: Node3D = GEAR.build_shoe(M, 1.0)
			w.add_child(sh)
			sh.position = o
			if row == 1: sh.rotation.y = 2.4 if k < 2 else PI * 0.5 + 0.5
			var ank := sh.transform * Vector3(-0.055, 0.09, 0)
			# the shin's direction: the angle from the sole's forward (+x) in the shoe's side plane
			var a := deg_to_rad(angs[k])
			var d: Vector3 = sh.transform.basis * Vector3(cos(a), sin(a), 0)
			var knee := ank + d * 0.42
			var tip := ank - d * 0.04
			var mi := MeshInstance3D.new()
			mi.mesh = shin_mesh
			mi.material_override = pants
			w.add_child(mi)
			# a cone like the shin tube (4 cm at the ankle), y -0.5 knee .. +0.5 ankle
			var ax := (tip - knee)
			var b := Basis(Quaternion(Vector3.UP, ax.normalized())).scaled_local(Vector3(1, ax.length(), 1))
			mi.transform = Transform3D(b, (knee + tip) * 0.5)
	var cam := Camera3D.new()
	w.add_child(cam)
	cam.look_at_from_position(Vector3(0, 0.62, 1.25), Vector3(0, 0.3, 0))
	cam.fov = 40
	process_frame.connect(_tick)

func _tick() -> void:
	frames += 1
	if frames == 8:
		root.get_texture().get_image().save_png(out)
		print("SHOE saved ", out)
		quit()
