extends SceneTree
## Renders a few real frames (not headless) so the shaders compile: car paint, rotor glow, dust, decal text.
## Saves a screenshot to user://fx_render_test.png.
class Terrain:
	func height(_x: float, _z: float) -> float:
		return 0.0

var fx: FX
var frames := 0

func _initialize() -> void:
	var root3d: Node3D = load("res://assets/dh.glb").instantiate()
	get_root().add_child(root3d)
	var bike := root3d.find_child("dh", true, false) as Node3D
	BikeFX.apply_paint(bike)
	BikeDecals.add_bike_decals(bike, BikeDecals.DH_DECALS)
	for w in ["wheel_front", "wheel_rear"]:
		var rg := BikeFX.find_rotor(bike.find_child(w, true, false))
		if rg: rg.set_heat(1.0)
	var susp := Suspension.new(bike, bike.get_meta("extras"))
	susp.apply()
	var cam := Camera3D.new()
	cam.look_at_from_position(Vector3(0.1, 0.6, 1.9), Vector3(0.0, 0.45, 0.0))
	get_root().add_child(cam)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.9, 0.5, 0)
	get_root().add_child(sun)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.5, 0.6, 0.7)
	env.environment.ambient_light_color = Color(0.6, 0.6, 0.65)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	get_root().add_child(env)
	fx = FX.new(Terrain.new())
	get_root().add_child(fx)
	for i in 40:
		fx.puff(Vector3(-0.8 + randf() * 0.4, 0.1, randf() - 0.5), Vector3(randf() - 0.5, 0.3, 0), Color8(0xc8, 0xa8, 0x7a), 0.35, 3.0, 0.5)
		fx.chunk(Vector3(0.8, 0.3, 0.2), Vector3(randf() - 0.5, 2, randf() - 0.5), Color8(0x60, 0x50, 0x40))
	for k in 30:
		fx.track(1, Vector3(-1.5 + k * 0.15, 0, 0.0), Vector3.RIGHT, 0.8, Color8(0x40, 0x30, 0x20), 0.065)
	process_frame.connect(_tick)

func _tick() -> void:
	fx.update(1.0 / 60.0)
	frames += 1
	if frames == 30:
		var img := get_root().get_texture().get_image()
		img.save_png("user://fx_render_test.png")
		print("saved ", ProjectSettings.globalize_path("user://fx_render_test.png"))
		quit()
