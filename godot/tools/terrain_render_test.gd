extends SceneTree
## Renders real frames (not headless) so the terrain / deco / flower / tape / water shaders compile.
## Saves screenshots to user://terrain_render_*.png.
var terrain: Terrain
var cam: Camera3D
var frames := 0
var shots := [
	[Vector3(-30, 118, 30), Vector3(10, 104, 0)],
	[Vector3(70, 108, 14), Vector3(95, 100, 0)],
]
var shot := 0


func _initialize() -> void:
	terrain = Terrain.new()
	get_root().add_child(terrain)
	terrain.set_seed(12345)
	terrain.update_stream(0, 0, INF)
	cam = Camera3D.new()
	cam.far = 600
	get_root().add_child(cam)
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
	_aim()


func _aim() -> void:
	var s: Array = shots[shot]
	cam.look_at_from_position(s[0], s[1])
	terrain.update_water(s[0].x, s[0].z, 0.0)


func _process(_d: float) -> bool:
	frames += 1
	terrain.update_stream(cam.position.x, cam.position.z, 4.0)
	terrain.update_water(cam.position.x, cam.position.z, frames / 60.0)
	if frames % 20 == 0:
		var img := get_root().get_texture().get_image()
		var path := "user://terrain_render_%d.png" % shot
		img.save_png(path)
		print("saved ", ProjectSettings.globalize_path(path))
		shot += 1
		if shot >= shots.size():
			return true
		_aim()
	return false
