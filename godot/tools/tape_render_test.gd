extends SceneTree
## Windowed render of torn tape: snaps the span nearest spawn mid-way and saves frames before / after.
## Run (not headless): godot --path godot --script res://tools/tape_render_test.gd -- <out_dir>
const TapeTest = preload("res://tools/tape_sim_test.gd")
var terrain: Terrain
var cam: Camera3D
var c: Dictionary
var t := 0.0
var t_break := -1.0
var shots := [[-0.01, "before"], [0.35, "t035"], [1.0, "t1"], [3.0, "t3"], [6.0, "t6"]]
var out_dir := "user://"


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0] + "/"
	terrain = Terrain.new()
	get_root().add_child(terrain)
	terrain.set_seed(12345)
	terrain.update_stream(0, 0, INF)
	c = TapeTest.find_tape(terrain, Vector2.ZERO)
	var sp: Dictionary = c["tape"]
	var pts: PackedVector3Array = sp["pts"]
	var a := pts[0]
	var b := pts[pts.size() - 1]
	var mid := (a + b) * 0.5
	var along := (b - a).normalized()
	var side := Vector3(-along.z, 0, along.x)
	terrain.update_stream(mid.x, mid.z, INF)
	cam = Camera3D.new()
	cam.fov = 60
	cam.far = 600
	get_root().add_child(cam)
	var eye := mid + side * 6.0 - along * 1.0
	eye.y = terrain.height(eye.x, eye.z) + 2.2
	cam.look_at_from_position(eye, mid + Vector3(0, -0.2, 0))
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.9, 0.6, 0)
	sun.shadow_enabled = true
	get_root().add_child(sun)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.6, 0.8, 0.95)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.7, 0.75, 0.8)
	env.environment.ambient_light_energy = 0.6
	get_root().add_child(env)


func _process(d: float) -> bool:
	t += d
	terrain.update_stream(c["x"], c["z"], 4.0)
	if t_break < 0 and t > 1.5:
		var fwd := Vector3(cam.global_basis.x.x, 0, cam.global_basis.x.z)   # ride across the camera view
		var sp: Dictionary = c["tape"]
		var ab: Vector3 = sp["pts"][30] - sp["pts"][0]
		fwd = Vector3(-ab.z, 0, ab.x).normalized() * -1.0   # through the tape, away from the camera
		print("break ", terrain.break_collider(c, fwd * 9.0 + Vector3(0, 0.3, 0)))
		t_break = t
	if shots.is_empty():
		return true
	var due: float = shots[0][0]
	if (due < 0 and t > 1.4) or (t_break >= 0 and t - t_break >= due and due >= 0):
		var img := get_root().get_texture().get_image()
		var path: String = out_dir + "tape_" + shots[0][1] + ".png"
		img.save_png(path)
		print("saved ", path)
		shots.pop_front()
	return false
