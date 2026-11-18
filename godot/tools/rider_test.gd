extends SceneTree
## Rider + Ragdoll smoke test.
##   headless:  Godot --headless --path godot -s tools/rider_test.gd
##   render:    Godot --path godot -s tools/rider_test.gd -- --png=<path>   (saves a side view of the pose)

class FlatTerrain:
	func height(_x: float, _z: float) -> float:
		return 0.0
	func colliders_near(_x: float, _z: float) -> Array:
		return []

var rider: Rider
var png := ""
var frames := 0
var ok := true


func _feet(crank: float) -> Array:
	var bb := Vector3(0, 0.297, 0)
	var r := 0.17
	var fr := bb + Vector3(cos(crank) * r, sin(crank) * r, 0.17)
	var fl := bb + Vector3(-cos(crank) * r, -sin(crank) * r, -0.17)
	return [fl, fr]


func _finite(v: Vector3) -> bool:
	return is_finite(v.x) and is_finite(v.y) and is_finite(v.z)


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--png="):
			png = a.substr(6)
	rider = Rider.new()
	root.add_child(rider)
	rider.set_look(Rider.DEFAULT_LOOK)
	var helm = load("res://assets/helmet.glb")
	if helm:
		var scene: Node = helm.instantiate()
		var h := scene.find_child("helmet", true, false)
		if h:
			var t0 := Time.get_ticks_msec()
			rider.set_helmet(h)
			print("helmet fitted in ", Time.get_ticks_msec() - t0, " ms, goggles: ", rider.goggles != null)
		scene.free()
	rider.set_style({hipX = -0.07, hipY = 0.075, lean = 0.22, elbowsOut = 0.0, shoulders = 0.165, kneesOut = 0.2, stance = -0.025, seatFloor = true})
	rider.seat = {top = 0.83, rear = -0.3, front = -0.05}
	var dt := 1.0 / 60
	var crank := 0.0
	for f in 120:
		crank += dt * 8.0
		var ft := _feet(crank)
		rider.update_pose(dt, {footL = ft[0], footR = ft[1], handL = Vector3(0.44, 0.96, -0.3), handR = Vector3(0.44, 0.96, 0.3),
			v = 6.0, lean = 0.0, steer = 0.05, yawRate = 0.0, counter = 0.0, rockRoll = 0.0, headRoll = 0.0, absorb = 0.0,
			pitch = 0.0, bodyLevel = 0.85, attackDrop = 0.18, pedal = 0.6, sprint = 0.0, crank = crank, air = 0.0,
			compress = 0.0, hipShift = 0.0, t = f * dt})
	var pts := rider.joints_world()
	var names := ["head", "chest", "pelvis", "shL", "elL", "haL", "shR", "elR", "haR", "hipL", "knL", "ftL", "hipR", "knR", "ftR"]
	for i in pts.size():
		print("  %-6s %s" % [names[i], pts[i]])
		if not _finite(pts[i]):
			ok = false
	# limb lengths should match the IK bones
	print("thigh L %.3f shin L %.3f upper arm L %.3f forearm L %.3f" % [
		(pts[9] as Vector3).distance_to(pts[10]), (pts[10] as Vector3).distance_to(pts[11] + Vector3(-0.04, 0.04, 0)),
		(pts[3] as Vector3).distance_to(pts[4]), (pts[4] as Vector3).distance_to(pts[5])])

	if png == "":
		_ragdoll(pts)
		quit(0 if ok else 1)
	else:
		_setup_view()


func _ragdoll(pts: Array) -> void:
	var rd := Ragdoll.new(FlatTerrain.new())
	rd.start(pts, Vector3(4, 0.5, 0), Vector3(0, 0, 0), 1.0 / 60)
	for s in 300:
		rd.step(1.0 / 60, [])
		for v in rd.p:
			if not _finite(v):
				ok = false
	var pel: Vector3 = rd.p[Ragdoll.PELVIS]
	print("ragdoll after 300 steps: pelvis ", pel, "  speed %.4f" % rd.speed, "  head ", rd.p[Ragdoll.HEAD])
	rider.pose_ragdoll(rd.p)
	rider.reset_pose()
	if absf(pel.y - 0.12) > 0.08 or rd.speed > 0.5:
		print("FAIL: pelvis not resting near the ground")
		ok = false
	print("RESULT: ", "PASS" if ok else "FAIL")


func _setup_view() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.75, 0.82, 0.9)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.6, 0.6, 0.65)
	e.ambient_light_energy = 0.6
	env.environment = e
	root.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.9, 0.6, 0)
	sun.shadow_enabled = true
	root.add_child(sun)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(6, 6)
	ground.mesh = pm
	root.add_child(ground)
	var cam := Camera3D.new()
	root.add_child(cam)
	var view := OS.get_environment("RIDER_VIEW")
	if view == "front":
		cam.look_at_from_position(Vector3(2.6, 1.0, 0.8), Vector3(0.0, 0.85, 0), Vector3.UP)
	elif view == "head":
		cam.look_at_from_position(Vector3(0.5, 1.75, 0.9), Vector3(0.05, 1.45, 0), Vector3.UP)
		cam.fov = 35
	else:
		cam.look_at_from_position(Vector3(0.6, 1.1, 2.8), Vector3(0.05, 0.8, 0), Vector3.UP)
	cam.current = true


func _process(_delta: float) -> bool:
	if png == "":
		return true
	frames += 1
	if frames == 8:
		var img := root.get_viewport().get_texture().get_image()
		img.save_png(png)
		print("saved ", png)
		return true
	return false
