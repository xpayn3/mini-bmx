extends SceneTree
## Knee pad check: legs bent 0..165 deg (row 1 from the side, row 2 from the front at an angle, row 3 twisted /
## bent sideways / backwards), saved as a PNG. Run (not headless):
##   ..._console.exe --path godot -s res://tools/kneepad_gallery.gd -- out.png [cam=side|front|close]

var frames := 0
var out := "user://kneepad_gallery.png"
var cam_mode := "all"
var yaw := 0.7


func _init() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("cam="): cam_mode = a.substr(4)
		elif a.begins_with("yaw="): yaw = float(a.substr(4))
		elif a.ends_with(".png"): out = a
	root.size = Vector2i(1600, 900)
	var w := Node3D.new()
	root.add_child(w)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color("#8d98a6")
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color("#c9d3e0")
	e.ambient_light_energy = 0.55
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = e
	w.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.8, 0.6, 0)
	sun.light_energy = 1.4
	sun.shadow_enabled = true
	w.add_child(sun)
	var cam := Camera3D.new()
	w.add_child(cam)
	var pants := KneePad._mat("#1d2b64", 0.8)
	var angles := [0, 25, 50, 75, 100, 125, 150, 165]
	var rows := []
	# row 0: plain bends seen from the side; row 1: same bends, leg rotated toward the camera;
	# row 2: odd cases (sideways bends, backwards, twisted hint, a leg pointing up)
	for k in angles.size():
		rows.append([0, k, angles[k], Vector3.RIGHT, 0.0])
		rows.append([1, k, angles[k], Vector3.RIGHT, 0.9])
	var odd := [[60, Vector3(0, 0, 1)], [110, Vector3(0, 0, -1)], [-30, Vector3.RIGHT], [-70, Vector3.RIGHT],
		[90, Vector3(1, 0, 1).normalized()], [140, Vector3(-1, 0, 0.4).normalized()], [5, Vector3(0, 0, 1)], [160, Vector3(0, 0, 1)]]
	for k in odd.size():
		rows.append([2, k, odd[k][0], odd[k][1], 0.0])
	var spacing := 0.62
	if cam_mode == "close":
		rows = []
		spacing = 0.42
		for k in 4:
			rows.append([0, k + 2, [0, 60, 105, 150][k], Vector3.RIGHT, yaw])
	for r in rows:
		var origin := Vector3((r[1] - 3.5) * spacing, 1.55 - r[0] * 0.95, 0)
		var bend := deg_to_rad(float(r[2]))
		var fwd: Vector3 = r[3]
		var hip := origin + Vector3(0, 0.3, 0)
		var thigh_dir := Vector3.DOWN
		var knee := hip + thigh_dir * 0.38
		# the shin bends back by `bend` in the plane of (down, fwd): the knee points along fwd
		var shin_dir := thigh_dir.rotated(fwd.cross(Vector3.DOWN).normalized(), bend) if bend != 0.0 else thigh_dir
		var ankle := knee + shin_dir * 0.38
		var leg := Node3D.new()
		leg.position = Vector3.ZERO
		w.add_child(leg)
		leg.rotate_y(float(r[4]))
		var piv := origin
		hip = piv + (hip - piv).rotated(Vector3.UP, r[4])
		knee = piv + (knee - piv).rotated(Vector3.UP, r[4])
		ankle = piv + (ankle - piv).rotated(Vector3.UP, r[4])
		var hint: Vector3 = fwd.rotated(Vector3.UP, r[4])
		leg.transform = Transform3D()
		_cyl(leg, hip, knee, 0.062, 0.075, pants)
		_cyl(leg, knee, ankle, 0.05, 0.062, pants)
		var pad := KneePad.new()
		leg.add_child(pad)
		pad.set_colors(Color("#1b1c20"), Color("#ffd21f"))
		pad.pose(hip, knee, knee, ankle, hint)
	if cam_mode == "close":
		cam.look_at_from_position(Vector3(0.0, 1.5, 1.75), Vector3(0.0, 1.38, 0))
		cam.fov = 38
	else:
		cam.look_at_from_position(Vector3(0, 0.6, 5.2) if cam_mode != "front" else Vector3(4.5, 0.6, 2.0), Vector3(0, 0.6, 0))
		cam.fov = 42
	process_frame.connect(_tick)


static func _cyl(parent: Node3D, a: Vector3, b: Vector3, ra: float, rb: float, m: Material) -> void:
	var c := CylinderMesh.new()
	c.top_radius = rb
	c.bottom_radius = ra
	c.height = 1.0
	c.radial_segments = 16
	var mi := MeshInstance3D.new()
	mi.mesh = c
	mi.material_override = m
	parent.add_child(mi)
	_place(mi, a, b)


func _tick() -> void:
	frames += 1
	if frames == 8:
		var img := root.get_texture().get_image()
		img.save_png(out)
		print("KNEEPAD saved ", ProjectSettings.globalize_path(out))
		quit()


static func _place(n: Node3D, a: Vector3, b: Vector3) -> void:
	var d := b - a
	var l := d.length()
	n.transform = Transform3D(Basis(Quaternion(Vector3.UP, d / l)).scaled_local(Vector3(1, l, 1)), a + d * 0.5)
