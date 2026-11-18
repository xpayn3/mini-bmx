extends SceneTree
## Windowed render: the dh bike with stock wheels (left) vs WheelGen wheels (right), from several views.
## godot --path godot --resolution 960x720 -s res://tools/wheel_render.gd -- <out_dir>
## Saves <out_dir>/wheels_<shot>.png (stock | generated) and wheels_variants.png.

var out_dir := ""
var stock: Node3D
var gen: Node3D
var variants: Node3D
var cam: Camera3D
var wf: Vector3
var wr: Vector3
var shots := []
var shot_i := 0
var phase := 0
var wait := 0
var left_img: Image

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	out_dir = args[0] if args.size() > 0 else ProjectSettings.globalize_path("user://")
	get_root().msaa_3d = Viewport.MSAA_4X
	stock = _bike(false)
	gen = _bike(true)
	var b := stock.find_child("dh", true, false) as Node3D
	wf = _gpos(b.find_child("wheel_front", true, false) as Node3D)
	wr = _gpos(b.find_child("wheel_rear", true, false) as Node3D)
	print("wheel_front at ", wf, "  wheel_rear at ", wr)
	var c := (wf + wr) * 0.5
	shots = [
		["side", c + Vector3(0, 0.05, 2.3), c, 40.0],
		["34", c + Vector3(1.5, 0.75, 1.7), c, 40.0],
		["far5m", c + Vector3(1.6, 1.4, 4.5), c, 40.0],
		["rear_drive", wr + Vector3(0.2, 0.12, 0.5), wr, 40.0],
		["front_rotor", wf + Vector3(-0.15, 0.12, -0.55), wf, 40.0],
		["tread", wf + Vector3(0.75, 0.35, 0.35), wf + Vector3(0.2, 0.05, 0), 30.0],
	]
	cam = Camera3D.new()
	get_root().add_child(cam)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.8, 0.6, 0)
	sun.shadow_enabled = true
	get_root().add_child(sun)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	var sky := Sky.new()
	sky.sky_material = ProceduralSkyMaterial.new()
	env.environment.background_mode = Environment.BG_SKY
	env.environment.sky = sky
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	get_root().add_child(env)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(20, 20)
	ground.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.45, 0.4, 0.33)
	ground.material_override = gm
	ground.position = Vector3(c.x, wf.y - WheelGen.tyre_radius({}) - 0.002, c.z)
	get_root().add_child(ground)
	_variants()
	process_frame.connect(_tick)


## global position before the tree is live (_initialize): compose the parents' transforms by hand
func _gpos(n: Node3D) -> Vector3:
	var t := Transform3D.IDENTITY
	var o: Node = n
	while o is Node3D:
		t = (o as Node3D).transform * t
		o = o.get_parent()
	return t.origin


func _bike(swap: bool) -> Node3D:
	var root3d: Node3D = load("res://assets/dh.glb").instantiate()
	get_root().add_child(root3d)
	var bike := root3d.find_child("dh", true, false) as Node3D
	BikeFX.apply_paint(bike)
	for w in ["wheel_front", "wheel_rear"]:
		var mi := bike.find_child(w, true, false) as MeshInstance3D
		BikeFX.find_rotor(mi)
		if swap:
			mi.mesh = WheelGen.build({"rear": w == "wheel_rear"})
	BikeDecals.add_bike_decals(bike, BikeDecals.DH_DECALS)
	var susp := Suspension.new(bike, bike.get_meta("extras"))
	susp.apply()
	return root3d


func _variants() -> void:
	variants = Node3D.new()
	get_root().add_child(variants)
	var specs := [
		{},
		{"rear": true},
		{"bsd_mm": 559, "spokes": 36, "lacing": 0, "spoke_gauge": 2, "rim_color": Color(0.85, 0.65, 0.2),
			"rim_finish": "gloss", "spoke_color": Color(0.85, 0.65, 0.2), "nipple_color": Color(0.85, 0.65, 0.2),
			"hub_color": Color(0.85, 0.65, 0.2)},
		{"bsd_mm": 622, "spokes": 24, "lacing": 3, "rim_color": Color(0.1, 0.35, 0.8), "nipple_color": Color(0.9, 0.2, 0.1)},
		{"rear": true, "spokes": 28, "lacing": 2, "tread": "semi", "sidewall": "tan", "tyre_w_in": 2.35,
			"rim_width_mm": 30.0, "rim_depth_mm": 20.0, "spoke_gauge": 0},
		{"tread": "slick", "rim_finish": "chrome", "rim_depth_mm": 40.0, "tyre_w_in": 2.3,
			"hub_color": Color(0.8, 0.1, 0.1)},
	]
	for i in specs.size():
		var mi := MeshInstance3D.new()
		mi.mesh = WheelGen.build(specs[i])
		mi.position = Vector3(50.0 + (i % 3) * 0.85, 0.4 + (1 - i / 3) * 0.85, 0)
		mi.rotation = Vector3(0, 0.45, 0)
		variants.add_child(mi)


func _show(which: int) -> void:
	stock.visible = which == 0
	gen.visible = which == 1


func _tick() -> void:
	if wait > 0:
		wait -= 1
		return
	if shot_i < shots.size():
		var sh = shots[shot_i]
		if phase == 0:
			cam.fov = sh[3]
			cam.look_at_from_position(sh[1], sh[2])
			_show(0)
			phase = 1
			wait = 4
		elif phase == 1:
			left_img = get_root().get_texture().get_image()
			_show(1)
			phase = 2
			wait = 4
		else:
			var right := get_root().get_texture().get_image()
			var w := left_img.get_width()
			var out := Image.create(w * 2 + 4, left_img.get_height(), false, left_img.get_format())
			out.fill(Color.WHITE)
			out.blit_rect(left_img, Rect2i(Vector2i.ZERO, left_img.get_size()), Vector2i.ZERO)
			out.blit_rect(right, Rect2i(Vector2i.ZERO, right.get_size()), Vector2i(w + 4, 0))
			var p := out_dir.path_join("wheels_%s.png" % sh[0])
			out.save_png(p)
			print("saved ", p)
			shot_i += 1
			phase = 0
		return
	# standalone wheels: the variant grid, then close-ups of the stock front / rear hubs and the rim
	var az := Vector3(sin(0.45), 0, cos(0.45))   # the standalone wheels' axle direction
	var f0 := Vector3(50, 1.25, 0)
	var r0 := Vector3(50.85, 1.25, 0)
	var extra := [
		["variants", Vector3(50.85, 0.85, 2.6), Vector3(50.85, 0.82, 0), 40.0],
		["hub_front", f0 - az * 0.30 + Vector3(0.06, 0.07, 0), f0, 40.0],
		["hub_rear", r0 + az * 0.30 + Vector3(0.07, 0.08, 0), r0, 40.0],
		["rim_tyre", f0 + Vector3(0.0, 0.33, 0) + az * 0.22 + Vector3(0.2, 0.12, 0), f0 + Vector3(0, 0.33, 0), 40.0],
	]
	var ei := shot_i - shots.size()
	if ei >= extra.size():
		quit()
		return
	var e = extra[ei]
	if phase == 0:
		_show(-1)
		cam.fov = e[3]
		cam.look_at_from_position(e[1], e[2])
		phase = 1
		wait = 4
	else:
		var p := out_dir.path_join("wheels_%s.png" % e[0])
		get_root().get_texture().get_image().save_png(p)
		print("saved ", p)
		phase = 0
		shot_i += 1
