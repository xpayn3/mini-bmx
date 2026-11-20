extends Node
## Glove check: the rider's hand (GloveFingers on a RiderSkeleton + RiderGear.build_hand + forearm) at curls
## 0 / 0.4 / 0.7 / 1 (columns), round a 32 mm grip; rows: left hand from the side (bar end on), left hand 3/4
## from the front, right hand from above. Run (not headless):
##   ..._console.exe --path godot res://tools/hand_gallery.tscn -- out.png

var frames := 0
var out := "user://hand_gallery.png"


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.ends_with(".png"): out = a
	get_window().size = Vector2i(1600, 900)
	var w := Node3D.new()
	add_child(w)
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
	var glove := _mat("#ffd21f"); var dark := _mat("#1b1d22"); var coral := _mat("#ff6a4d"); var grip := _mat("#222222")
	var curls := [0.0, 0.4, 0.7, 1.0]
	var rows := [[0, Basis()], [0, Basis(Vector3.UP, 1.0)], [1, Basis(Vector3.RIGHT, -1.2) * Basis(Vector3.UP, -0.4)]]
	for r in rows.size():
		for c in curls.size():
			var at := Vector3((c - 1.5) * 0.3, 0.24 - r * 0.2, 0)
			var rider := Node3D.new()
			rider.position = at
			w.add_child(rider)
			var skel := RiderSkeleton.new()
			rider.add_child(skel)
			skel.make_fingers(glove)
			var i: int = rows[r][0]
			var hb: Basis = rows[r][1]
			var ht := Transform3D(hb, Vector3.ZERO)
			for k in 2:
				var other := Transform3D(hb, Vector3(0, -50, 0))   # the other hand: far away
				var t_h: Transform3D = ht if k == i else other
				for bt in GloveFingers.pose(k, curls[c]):
					var t: Transform3D = bt[1]
					skel._put(bt[0], t_h * t.origin, t_h.basis * t.basis)
			var hand := RiderGear.build_hand({glove = glove, knuckle = dark, palm = dark, cuff = dark}, -1 if i == 0 else 1)
			hand.transform = ht
			rider.add_child(hand)
			_cyl(rider, ht * Vector3(-0.14, 0, 0), ht * Vector3(-0.062, 0, 0), 0.047, 0.04, coral)
			if c == 3: _cyl(rider, ht * Vector3(0, 0, -0.08), ht * Vector3(0, 0, 0.08), 0.016, 0.016, grip)
	cam.look_at_from_position(Vector3(0.02, 0.04, 0.95), Vector3(0.02, 0.04, 0))
	cam.fov = 34
	get_tree().process_frame.connect(_tick)


static func _mat(c: String) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(c)
	m.roughness = 0.8
	return m


static func _cyl(parent: Node3D, a: Vector3, b: Vector3, ra: float, rb: float, m: Material) -> void:
	var c := CylinderMesh.new()
	c.top_radius = rb
	c.bottom_radius = ra
	c.height = 1.0
	c.radial_segments = 12
	var mi := MeshInstance3D.new()
	mi.mesh = c
	mi.material_override = m
	parent.add_child(mi)
	var d := b - a
	var l := d.length()
	mi.transform = Transform3D(Basis(Quaternion(Vector3.UP, d / l)).scaled_local(Vector3(1, l, 1)), a + d * 0.5)


func _tick() -> void:
	frames += 1
	if frames == 8:
		get_viewport().get_texture().get_image().save_png(out)
		print("HANDS saved ", ProjectSettings.globalize_path(out))
		get_tree().quit()
