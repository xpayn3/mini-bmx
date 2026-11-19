class_name BikeTurntable
extends SubViewportContainer
## A live 3D bike on a white podium that turns slowly, on an endless white backdrop (the ride setup screen).
## set_bike(id) swaps the model; dragging turns it by hand, it keeps spinning when let go.

const SPIN := 0.5            # rad/s
const LENS_MM := 100.0   # product / bike photographers shoot a 85-135 mm: flat perspective, no wide-angle stretch
const BACKDROP := Color("e7e3da")   # subtle eggshell, not pure white
const PODIUM_H := 0.03   # a low round platform, a couple of cm

var vp := SubViewport.new()
var pivot := Node3D.new()
var cam := Camera3D.new()
var _rig: Node3D
var _yaw_extra := 0.0
var _drag := false
var _bike_id := ""
var _rider: Rider
var _hand_t := 0.0
var _r := 1.0
var _h := 1.0
var _keep_r := 1.0
var _keep_h := 1.0


func _init() -> void:
	stretch = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_4X
	vp.handle_input_locally = false
	add_child(vp)
	# no lamps: the one studio HDRI lights and reflects everything, the backdrop stays pure white
	var sky := Sky.new()
	var pm_sky := PanoramaSkyMaterial.new()
	pm_sky.panorama = _studio_hdri()
	sky.sky_material = pm_sky
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = BACKDROP
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 1.0
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR   # keeps the backdrop exactly the eggshell colour
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.15
	env.adjustment_saturation = 1.08
	var we := WorldEnvironment.new(); we.environment = env
	vp.add_child(we)
	# endless white floor, the low round platform and a soft contact shadow under the bike
	var floor_m := StandardMaterial3D.new()
	floor_m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	floor_m.albedo_color = BACKDROP
	var fl := MeshInstance3D.new()
	var pm := PlaneMesh.new(); pm.size = Vector2(400, 400)
	fl.mesh = pm; fl.material_override = floor_m
	fl.position.y = -PODIUM_H
	vp.add_child(fl)
	var pod_m := StandardMaterial3D.new()
	pod_m.albedo_color = Color(0.84, 0.82, 0.78)
	pod_m.roughness = 0.4
	var pod := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 1.0; cm.bottom_radius = 1.0; cm.height = PODIUM_H; cm.radial_segments = 96
	pod.mesh = cm; pod.material_override = pod_m
	pod.position.y = -PODIUM_H * 0.5
	vp.add_child(pod)
	var g := Gradient.new()
	g.colors = PackedColorArray([Color(0, 0, 0, 0.45), Color(0, 0, 0, 0)])
	var gt := GradientTexture2D.new()
	gt.gradient = g; gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5); gt.fill_to = Vector2(1.0, 0.5)
	var sh_m := StandardMaterial3D.new()
	sh_m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sh_m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sh_m.albedo_texture = gt
	var sh := MeshInstance3D.new()
	var sq := QuadMesh.new(); sq.size = Vector2(2.1, 1.0); sq.orientation = PlaneMesh.FACE_Y
	sh.mesh = sq; sh.material_override = sh_m
	sh.position.y = 0.004
	pivot.add_child(sh)   # turns with the bike, so it stays under the wheels
	vp.add_child(pivot)
	cam.fov = rad_to_deg(2.0 * atan(12.0 / LENS_MM))   # full-frame (24 mm tall sensor) vertical field of view
	vp.add_child(cam)
	resized.connect(_fit)


## one studio HDRI made in code (equirectangular, 512 x 256): a big softbox over the top, strip lights
## round the sides, a mid-grey room and a darker floor so glossy paint has something to reflect
static func _studio_hdri() -> ImageTexture:
	var w := 512; var h := 256
	var img := Image.create(w, h, false, Image.FORMAT_RGBF)
	for y in h:
		var el := (0.5 - (y + 0.5) / h) * PI   # + up
		for x in w:
			var az := (x + 0.5) / w * TAU
			var v := 0.06 + 0.06 * sin(el)   # a dark room: most of the shape comes from the lights
			if el < -0.05: v = 0.02
			# tall softboxes to the left, right and behind (nothing overhead): bright edges down the frame,
			# forks and tyres, and long reflections along the paint
			for ca in [PI * 0.5, PI * 1.5]:
				var sa := absf(angle_difference(az, ca))
				v += (1.0 - smoothstep(0.30, 0.42, sa)) * smoothstep(-0.12, 0.0, el) * (1.0 - smoothstep(0.75, 0.9, el)) * 7.0
			var ba := absf(angle_difference(az, PI))
			v += (1.0 - smoothstep(0.10, 0.18, ba)) * smoothstep(-0.12, 0.0, el) * (1.0 - smoothstep(0.7, 0.85, el)) * 12.0
			# a weak front fill so the camera side is not black
			var fa := absf(angle_difference(az, 5.4))
			v += (1.0 - smoothstep(0.3, 0.7, fa)) * smoothstep(-0.1, 0.1, el) * (1.0 - smoothstep(0.4, 0.7, el)) * 0.8
			img.set_pixel(x, y, Color(v, v, v * 1.04))
	return ImageTexture.create_from_image(img)


## a rider standing in place of the bike (the Rider step); look = a RiderPanels look dictionary
func show_rider(look: Dictionary) -> void:
	if _rig != null: _rig.visible = false
	if _rider == null:
		_rider = Rider.new()
		pivot.add_child(_rider)
		_rider.set_look(look)
		_rider.set_style(Garage.STAND_POSE)
		var hs: Node3D = load("res://assets/helmet.glb").instantiate()
		var helmet := hs.find_child("helmet", true, false)
		if helmet:
			helmet.get_parent().remove_child(helmet)
			_rider.set_helmet(helmet)
		hs.free()
	else:
		_rider.set_look(look)
	_rider.visible = true
	pivot.rotation = Vector3.ZERO
	_r = 0.55; _h = 1.85
	_fit()

func set_look(look: Dictionary) -> void:
	if _rider != null: _rider.set_look(look)

## the paint of the shown bike follows the build (no rebuild)
func repaint(build: Dictionary) -> void:
	if _rig != null: BikeBuild.apply_paint((_rig as BikeRig).model, build)

## swap to this bike (GameState.BIKES id): its model sits centred on the podium, camera fitted to it
func set_bike(id: String, force := false) -> void:
	if _rider != null: _rider.visible = false
	if id == _bike_id and _rig != null and not force:
		_rig.visible = true
		_r = _keep_r; _h = _keep_h
		_fit()
		return
	_bike_id = id
	if _rig != null:
		pivot.remove_child(_rig); _rig.queue_free()
	pivot.rotation = Vector3.ZERO
	_rig = PartThumbs.make_bike(id)
	pivot.add_child(_rig)
	var box := AABB(); var first := true
	for mi in _rig.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null: continue
		var bb: AABB = pivot.global_transform.affine_inverse() * m.global_transform * m.get_aabb()
		box = bb if first else box.merge(bb)
		first = false
	if first: return
	var c := box.get_center()
	_rig.position = Vector3(-c.x, -box.position.y, -c.z)   # centred, tyres on the podium top
	_r = maxf(box.size.x, box.size.z) * 0.5
	_h = box.size.y
	_keep_r = _r; _keep_h = _h
	_fit()


## frame the whole bike, whatever the shape of the view and whichever way it is turned
func _fit() -> void:
	if _rig == null and _rider == null: return
	var aspect := maxf(size.x, 1.0) / maxf(size.y, 1.0)
	var ext := maxf(_h * 0.62, _r * 1.0 / aspect)   # half the height the view has to show
	var dist := ext * 1.1 / tan(deg_to_rad(cam.fov * 0.5))
	cam.position = Vector3(0, _h * 0.5 + dist * 0.14, dist)
	cam.look_at(Vector3(0, _h * 0.45, 0))


func _process(dt: float) -> void:
	if not visible: return
	if not _drag: pivot.rotation.y += SPIN * dt
	if _rider != null and _rider.visible:
		_hand_t += dt
		var breathe := sin(_hand_t * 1.6) * 0.006
		_rider.update_pose(dt, {"footL": Vector3(0.0, 0.0, -0.13), "footR": Vector3(0.02, 0.0, 0.13),
			"handL": Vector3(0.02, 0.83 + breathe, -0.29), "handR": Vector3(0.04, 0.83 + breathe, 0.29),
			"v": 0.0, "lean": 0.0, "steer": 0.0, "yawRate": 0.0, "counter": 0.0, "rockRoll": 0.0, "headRoll": 0.0,
			"absorb": breathe, "pitch": 0.0, "bodyLevel": 0.85, "attackDrop": 0.0, "pedal": 0.0, "sprint": 0.0,
			"crank": 0.0, "air": 0.0, "compress": 0.0, "hipShift": 0.0, "t": _hand_t, "stand": 1.0, "relax": 1.0})


func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		_drag = e.pressed
	elif e is InputEventMouseMotion and _drag:
		pivot.rotation.y += (e as InputEventMouseMotion).relative.x * 0.01
