class_name Garage
extends Node3D
## The garage: the downhill bike stands on a concrete floor under a spotlight while you change its
## paint, logos, wheels, suspension and gearing. Every change rebuilds the bike live; "Save & ride"
## writes user://garage.json and the next ride uses it.

signal closed(ride: bool)

const SWATCHES := ["e8432e", "ff6a00", "ffb000", "ffd21f", "c6ff1a", "35d04a", "00a86b", "00c2c7", "2f7de1", "1d2b64",
	"7b3fe4", "d22fbf", "ff4f9a", "f4f4f0", "b8bcc0", "6b6f75", "2b2d31", "111214", "c8a24a", "8a5a2b", "4a6b3a", "e0d3b8"]

const DOOR_W := 3.6
const DOOR_H := 3.2
const DOOR_X := 0.0   # the door is straight behind the bike
## the garage's sun: low, behind the open door (toward -Z), a little to the left, so daylight falls
## in through the doorway across the floor
const SUN := Vector3(0.12, 0.38, -0.92)

var build: Dictionary
var rig: BikeRig
var outside: Node3D
var rider: Rider = null
var rider_on := false
var rider_pose := {}
var rider_preview := "pedal"
var tab_buttons := {}
# rollers: three drums in a frame; with the rider on, the bike stands on them and pedals in place
const DRUM_R := 0.055
const DRUM_Y := 0.075                  # drum centre height
const ROLLER_TOP := DRUM_Y + DRUM_R    # where the tyres sit
var rollers: Node3D = null
var drums: Array[Node3D] = []
var bike_x := 0.0
var ride_y := ROLLER_TOP
const DRUM_GAP := 0.13   # rear drums sit this far either side of the rear axle
var wheel_ang := 0.0
# the rider standing next to the bike (Kit tab)
var stand_rider: Rider = null
var stand_on := false
const STAND_AT := Vector3(1.75, 0.0, 0.55)
var preview_crank := 0.6
const SLAT := 0.2
const DOOR_DELAY := 1.0     # s (after the garage is on screen) before the door starts to roll up
const DOOR_TIME := 3.2      # s to roll it all the way up
static var _door_opened_once := false   # the door rolls up on the first visit; it stays open after
var door_slats: Node3D
var door_open := 1.0
var door_t := 0.0
var cam := Camera3D.new()
var orbit := 0.0
var orbit_t := 0.0
var pitch := 10.0
var pitch_t := 10.0
var dist := 4.4
var dist_t := 4.4
var focus := Vector3(0, 0.85, 0)
var focus_t := Vector3(0, 0.85, 0)
var hand_t := 0.0   # handheld-camera clock
var auto_spin := false   # the camera stays put unless you drag it
var dragging := false
var ui := CanvasLayer.new()
var panel: PanelContainer
var body: VBoxContainer
var stats_box: VBoxContainer
var tab := "paint"
var part := "frame"
var logo_slot := "downtube"
var _dirty := 0.0
var _file_dialog: FileDialog
var _stat_bars := {}

const VIEWS := {
	"paint": [0.0, 10.0, 4.4, Vector3(0, 0.85, 0)],
	"logos": [PI / 2, 6.0, 3.0, Vector3(0, 0.6, 0)],
	"wheels": [0.25, 8.0, 2.4, Vector3(0.6, 0.4, 0)],
	"suspension": [1.0, 10.0, 2.2, Vector3(0.05, 0.6, 0)],
	"drive": [PI / 2 + 0.3, 6.0, 2.0, Vector3(-0.3, 0.35, 0)],
	"rider": [0.0, 7.0, 4.3, Vector3(-0.05, 1.0, 0)],
	"kit": [0.25, 4.0, 3.2, Vector3(1.55, 1.0, 0.55)],
}

func _ready() -> void:
	build = BikeBuild.load_build()
	rider_pose = RiderPanels.load_pose("dh", GameState.BIKES.dh.pose)
	var rcf := ConfigFile.new()
	if rcf.load(RiderPanels.PATH) == OK:
		rider_on = rcf.get_value("garage", "rider_on", false)
		rider_preview = rcf.get_value("garage", "preview", "pedal")
		stand_on = rcf.get_value("garage", "stand_on", true)
	if OS.get_environment("BMX_GARAGE_RIDER") != "":   # tests: rider on, a preview, Rider tab
		rider_on = true; rider_preview = OS.get_environment("BMX_GARAGE_RIDER"); stand_on = true
		for kv in OS.get_environment("BMX_POSE").split(",", false):   # tests: "spineCurve=0.2,pelvisRoll=0.1" (not saved)
			var p := kv.split("=")
			if p.size() == 2: rider_pose[p[0]] = float(p[1])
	if not PREVIEWS.has(rider_preview): rider_preview = "pedal"
	_build_room()
	add_child(cam)
	cam.fov = 38
	cam.current = true
	_rebuild_bike()
	add_child(ui)
	_build_ui()
	_set_tab(OS.get_environment("BMX_GARAGE_TAB") if OS.get_environment("BMX_GARAGE_TAB") != "" else ("rider" if OS.get_environment("BMX_GARAGE_RIDER") != "" else "paint"))

# ================================================================ the room
func _mat(c: Color, rough := 0.8, metal := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c; m.roughness = rough; m.metallic = metal
	return m

func _box(size: Vector3, pos: Vector3, mat: Material, rot := Vector3.ZERO) -> MeshInstance3D:
	var b := BoxMesh.new(); b.size = size
	var mi := MeshInstance3D.new(); mi.mesh = b; mi.material_override = mat
	mi.position = pos; mi.rotation = rot
	add_child(mi)
	return mi

func _cyl(r: float, h: float, pos: Vector3, mat: Material, rot := Vector3.ZERO) -> MeshInstance3D:
	var c := CylinderMesh.new(); c.top_radius = r; c.bottom_radius = r; c.height = h
	var mi := MeshInstance3D.new(); mi.mesh = c; mi.material_override = mat
	mi.position = pos; mi.rotation = rot
	add_child(mi)
	return mi

func _build_room() -> void:
	var we := WorldEnvironment.new()
	var env := Environment.new()
	# the sky seen through the open door: the same real HDRI as the rides, turned so its sun sits
	# where this garage's sun light is (low, behind the door)
	var sky := Sky.new()
	var sm := ShaderMaterial.new()
	sm.shader = load("res://shaders/sky_hdri.gdshader")
	sm.set_shader_parameter("hdri", load("res://assets/hdri/kloofendal_48d_partly_cloudy_puresky_4k.hdr"))
	sm.set_shader_parameter("rotation", atan2(SUN.x, -SUN.z) - (Game.HDRI_SUN_U - 0.5) * TAU)
	sm.set_shader_parameter("energy", 1.0)
	sm.set_shader_parameter("light_energy", 0.6)
	sky.sky_material = sm
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_light_color = Color(0.7, 0.78, 0.86)
	env.fog_depth_begin = 40.0
	env.fog_depth_end = 260.0
	env.fog_sky_affect = 0.0
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.3, 0.26, 0.22)   # a warm, dim shed (most light comes in by the door)
	env.ambient_light_energy = 0.22
	# real light bounce: daylight off the floor and brick fills the shed (SDFGI)
	env.sdfgi_enabled = true
	env.sdfgi_use_occlusion = true
	env.sdfgi_min_cell_size = 0.1
	env.sdfgi_cascades = 4
	env.sdfgi_energy = 1.0
	env.sdfgi_bounce_feedback = 0.6
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.05
	env.ssao_enabled = true
	env.ssao_radius = 0.5
	env.ssao_intensity = 2.0
	env.ssr_enabled = true
	env.ssr_max_steps = 48
	env.glow_enabled = true
	env.glow_intensity = 0.5
	env.glow_hdr_threshold = 0.9
	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = 0.012          # dusty air: the sunbeam through the door shows
	env.volumetric_fog_albedo = Color(0.95, 0.9, 0.82)
	env.volumetric_fog_gi_inject = 0.3
	env.volumetric_fog_length = 14.0
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.06
	env.adjustment_saturation = 1.08
	we.environment = env
	add_child(we)
	# floor: polished concrete with a painted work-bay outline
	# floor: polished concrete (Poly Haven "Concrete Floor 02", CC0)
	# floor: Poly Haven "Painted Concrete 02" (CC0), used as is
	var floor_m := StandardMaterial3D.new()
	var tex := "res://assets/textures/painted_concrete_02/painted_concrete_02_%s_2k.jpg"
	floor_m.albedo_texture = load(tex % "diff")
	floor_m.normal_enabled = true
	floor_m.normal_texture = load(tex % "nor_gl")
	floor_m.roughness_texture = load(tex % "rough")
	floor_m.roughness = 1.0
	floor_m.ao_enabled = true
	floor_m.ao_texture = load(tex % "ao")
	floor_m.uv1_scale = Vector3(4.6, 4.0, 1)   # ~3 m per tile, the scan's real size
	floor_m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	var floor_mesh := PlaneMesh.new(); floor_mesh.size = Vector2(14, 12.2)
	var fl := MeshInstance3D.new(); fl.mesh = floor_mesh; fl.material_override = floor_m
	fl.position.z = 1.8   # the floor stops at the back wall (outside is the real ground)
	add_child(fl)
	# walls
	var wall := _mat(Color(0.2, 0.21, 0.23), 0.9)
	# back wall: Poly Haven "Broken Brick Wall" (CC0) round a wide doorway centred behind the bike;
	# world-space triplanar UVs so the three wall pieces line up (one tile = 1.8 m)
	var brick := StandardMaterial3D.new()
	var btex := "res://assets/textures/broken_brick_wall/broken_brick_wall_%s_2k.jpg"
	brick.albedo_texture = load(btex % "diff")
	brick.normal_enabled = true
	brick.normal_texture = load(btex % "nor_gl")
	brick.roughness_texture = load(btex % "rough")
	brick.roughness = 1.0
	brick.ao_enabled = true
	brick.ao_texture = load(btex % "ao")
	brick.uv1_triplanar = true
	brick.uv1_world_triplanar = true
	brick.uv1_scale = Vector3.ONE / 1.8
	brick.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	var dw := DOOR_W / 2.0
	var dl := DOOR_X - dw   # door's left edge
	var dr := DOOR_X + dw   # and right edge
	_box(Vector3(dl + 7, 5, 0.25), Vector3((dl - 7) / 2.0, 2.5, -4.2), brick)      # wall left of the door (behind the bike)
	_box(Vector3(7 - dr, 5, 0.25), Vector3((7 + dr) / 2.0, 2.5, -4.2), brick)      # wall right of the door
	_box(Vector3(DOOR_W, 5 - DOOR_H, 0.25), Vector3(DOOR_X, (5 + DOOR_H) / 2.0, -4.2), brick)   # header
	# the roller door, rolled up into its drum above the opening, and its guide rails
	var steel_dark := _mat(Color(0.18, 0.19, 0.21), 0.45, 0.7)
	_cyl(0.3, DOOR_W + 0.3, Vector3(DOOR_X, DOOR_H + 0.34, -4.0), _mat(Color(0.55, 0.57, 0.6), 0.45, 0.6), Vector3(0, 0, PI / 2))
	_box(Vector3(DOOR_W + 0.5, 0.08, 0.66), Vector3(DOOR_X, DOOR_H + 0.68, -3.95), steel_dark)
	for sx in [-1, 1]:
		_box(Vector3(0.1, DOOR_H, 0.14), Vector3(DOOR_X + sx * (dw + 0.05), DOOR_H / 2.0, -4.05), steel_dark)
	_box(Vector3(DOOR_W + 0.2, 0.03, 0.3), Vector3(DOOR_X, 0.015, -4.2), _mat(Color(0.3, 0.3, 0.32), 0.5, 0.8))   # threshold strip
	# the door curtain: ribbed steel slats that roll up into the drum (animated the first time)
	door_slats = Node3D.new()
	door_slats.name = "DoorSlats"
	add_child(door_slats)
	var slat_mat := _mat(Color(0.5, 0.52, 0.55), 0.5, 0.55)
	var slat_n := ceili(DOOR_H / SLAT)
	for i in slat_n:
		var b := BoxMesh.new(); b.size = Vector3(DOOR_W - 0.04, SLAT - 0.012, 0.05)
		var mi := MeshInstance3D.new(); mi.mesh = b; mi.material_override = slat_mat
		mi.set_meta("y0", SLAT * (i + 0.5))
		door_slats.add_child(mi)
	door_slats.position = Vector3(DOOR_X, 0, -4.12)
	door_open = 1.0 if _door_opened_once else 0.0
	_place_slats()
	_box(Vector3(0.2, 5, 12), Vector3(-7, 2.5, 1.8), wall)
	_box(Vector3(0.2, 5, 12), Vector3(7, 2.5, 1.8), wall)
	_box(Vector3(14.2, 0.2, 12.2), Vector3(0, 5, 1.8), _mat(Color(0.08, 0.08, 0.09)))
	_build_outside()
	# workbench + pegboard with tools on the left of the back wall
	var wood := _mat(Color("6b4a2b"), 0.7)
	var steel := _mat(Color(0.25, 0.27, 0.3), 0.4, 0.8)
	_box(Vector3(2.6, 0.08, 0.8), Vector3(-5.0, 0.92, -3.6), wood)
	for x in [-6.2, -3.8]:
		_box(Vector3(0.06, 0.9, 0.7), Vector3(x, 0.45, -3.6), steel)
	var peg := _mat(Color("a67c52"), 0.9)
	_box(Vector3(2.6, 1.3, 0.04), Vector3(-5.0, 1.8, -4.06), peg)
	var tool := _mat(Color("c0392b"), 0.4, 0.5)
	var chrome := _mat(Color(0.8, 0.82, 0.85), 0.15, 1.0)
	for i in 7:
		var x := -6.1 + i * 0.36
		_box(Vector3(0.04, 0.32 + (i % 3) * 0.08, 0.02), Vector3(x, 1.85, -4.02), chrome if i % 2 else tool)
	_cyl(0.18, 0.04, Vector3(-4.1, 2.25, -4.01), chrome, Vector3(PI / 2, 0, 0))   # a chainring on the wall
	# red tool cabinet + a stack of tyres on the right
	var red := _mat(Color("b3261e"), 0.35, 0.3)
	_box(Vector3(1.0, 1.1, 0.55), Vector3(3.4, 0.55, -3.75), red)
	for i in 5:
		_box(Vector3(0.92, 0.01, 0.02), Vector3(3.4, 0.2 + i * 0.2, -3.47), chrome)
	var rubber := _mat(Color(0.06, 0.06, 0.06), 0.85)
	for i in 4:
		var t := TorusMesh.new(); t.inner_radius = 0.25; t.outer_radius = 0.37
		var mi := MeshInstance3D.new(); mi.mesh = t; mi.material_override = rubber
		mi.position = Vector3(5.6, 0.06 + i * 0.12, -2.6); mi.rotation.y = i * 0.4
		add_child(mi)
	# a work stand leaning in the corner and a floor pump
	_cyl(0.02, 1.4, Vector3(-6.5, 0.7, -2.2), steel, Vector3(0, 0, 0.12))
	_cyl(0.03, 0.6, Vector3(1.9, 0.3, -1.9), _mat(Color("2f7de1"), 0.4, 0.3))
	# lights: the spotlight right above the bike, with a visible lamp and beam
	var lamp := _cyl(0.28, 0.18, Vector3(0, 3.6, 0), _mat(Color(0.1, 0.1, 0.11), 0.4, 0.7))
	lamp.rotation = Vector3.ZERO
	var glow := StandardMaterial3D.new()
	glow.emission_enabled = true; glow.emission = Color(1, 0.78, 0.5); glow.emission_energy_multiplier = 5.0
	glow.albedo_color = Color(1, 1, 1)
	_cyl(0.24, 0.01, Vector3(0, 3.505, 0), glow)
	_cyl(0.008, 1.3, Vector3(0, 4.35, 0), steel)
	var spot := SpotLight3D.new()
	spot.position = Vector3(0, 3.5, 0)
	spot.rotation = Vector3(-PI / 2, 0, 0)
	spot.spot_range = 6.0
	spot.spot_angle = 50.0                       # an old enamel shop lamp: warm, wide, soft-edged
	spot.spot_angle_attenuation = 1.4
	spot.light_energy = 7.0
	spot.light_color = Color(1.0, 0.8, 0.58)
	spot.light_volumetric_fog_energy = 1.0
	spot.shadow_enabled = true
	spot.shadow_blur = 1.5
	add_child(spot)
	# the bulb's own glow round the room (the shade only throws light down)
	var bulb := OmniLight3D.new()
	bulb.position = Vector3(0, 3.3, 0); bulb.light_color = Color(1.0, 0.78, 0.52)
	bulb.light_energy = 0.7; bulb.omni_range = 7.0; bulb.light_volumetric_fog_energy = 0.2
	add_child(bulb)
	# fluorescent strip over the bench
	var strip := StandardMaterial3D.new()
	strip.emission_enabled = true; strip.emission = Color(0.92, 0.95, 1.0); strip.emission_energy_multiplier = 2.5
	_box(Vector3(1.6, 0.04, 0.08), Vector3(-5.0, 3.0, -3.7), strip)
	var fl_l := OmniLight3D.new()
	fl_l.position = Vector3(-5.0, 2.8, -3.4); fl_l.light_color = Color(0.92, 0.95, 1.0); fl_l.light_energy = 0.6; fl_l.omni_range = 4.0
	add_child(fl_l)

## The real procedural world outside the door: the world seed you ride, turned so you look down the
## start of the trail (+X in the world) through the doorway (-Z here), with the spawn point just
## outside the threshold and its ground level with the garage floor.
func _build_outside() -> void:
	outside = Node3D.new()
	outside.name = "Outside"
	add_child(outside)
	var t = load("res://scripts/world/terrain.gd").new()
	t.name = "Terrain"
	outside.add_child(t)
	t.set_seed(GameState.seed)
	var spot := Vector2(-6.0, 0.0)   # just behind spawn on the flat hilltop: the trail runs away from here
	t.update_stream(spot.x, spot.y, INF)
	outside.rotation.y = PI / 2   # world +X (down the trail) -> garage -Z (out of the door)
	var to_world := func(gx: float, gz: float) -> Vector2:   # garage floor point -> terrain x / z
		var w := Basis(Vector3.UP, -PI / 2) * Vector3(gx - DOOR_X, 0, gz + 4.35)
		return Vector2(spot.x + w.x, spot.y + w.z)
	# sink the ground so none of it pokes up through the garage floor: the highest point under the
	# building (with a margin) goes 5 cm below the floor; the threshold covers any step at the door
	var h_top := -INF
	for gz in range(-4, 9):
		for gx in range(-8, 9):
			var w: Vector2 = to_world.call(float(gx), float(gz))
			h_top = maxf(h_top, t.height(w.x, w.y))
	outside.position = Vector3(DOOR_X, -h_top - 0.05, -4.35) - Basis(Vector3.UP, PI / 2) * Vector3(spot.x, 0, spot.y)
	var sun := DirectionalLight3D.new()
	sun.light_color = Color("ffe2bd")
	sun.light_energy = 1.5
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_max_distance = 120.0
	sun.light_volumetric_fog_energy = 1.0
	add_child(sun)
	sun.look_at_from_position(SUN.normalized(), Vector3.ZERO, Vector3.UP)

# ================================================================ bike
func _rebuild_bike() -> void:
	if rig:
		rig.queue_free()
	rig = BikeRig.new()
	add_child(rig)
	var cfg: Dictionary = GameState.BIKES.dh
	rig.load_bike(cfg, build)
	var L := float(rig.extras.get("wheelbase", 1.25))
	var bb := float(rig.extras.get("bbToRearAxle", 0.44))
	# stand the bike in the middle of the bay, wheels on the floor
	if rig.susp:
		for i in 60:
			rig.susp.update(1.0 / 60, {"air": false, "load": 0.0, "brake": 0.0, "bumpF": 0.0, "bumpR": 0.0})
	bike_x = -(L / 2 - bb)
	ride_y = DRUM_Y + sqrt(pow(rig.wheel_rr + DRUM_R, 2) - DRUM_GAP * DRUM_GAP) - rig.wheel_rr
	rig.pose(bike_x, ride_y if rider_on else 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0 if rider_on else -0.25, 0.0, 0.0, 0.6)
	rider = null
	_build_rollers(L, bb)
	if rider_on:
		_add_rider()
	_update_stand_rider()
	_rider_visibility()
	for mi in rig.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON

# ---------------------------------------------------------------- the rider on the bike
## the rider in the garage: same look and pose (sliders) as on the trail, posed every frame from the
## bike's grips and pedals like a ride, in the chosen preview situation
func _add_rider() -> void:
	rider = Rider.new()
	rig.lean_g.add_child(rider)
	rider.set_look(RiderPanels.load_look())
	rider.set_style(rider_pose)
	if rig.seat != null: rider.seat = rig.seat
	var grip := rig.grip_mid()
	rider.fit = Vector3((grip.x - 0.4388) * 0.5, ((grip.y - 0.9646) + (rig.crank_n.position.y - 0.297)) * 0.5, 0)
	var hs: Node3D = load("res://assets/helmet.glb").instantiate()
	var helmet := hs.find_child("helmet", true, false)
	if helmet:
		helmet.get_parent().remove_child(helmet)
		rider.set_helmet(helmet)
	hs.free()

## training rollers: an alloy frame with two drums under the rear tyre and one under the front;
## only there while the rider is on (the bike stands on them and spins in place)
func _build_rollers(L: float, bb: float) -> void:
	if rollers: rollers.queue_free()
	rollers = null
	drums.clear()
	if not rider_on: return
	rollers = Node3D.new()
	rollers.name = "Rollers"
	add_child(rollers)
	var alu := _mat(Color(0.72, 0.74, 0.77), 0.3, 0.9)
	var drum_m := _mat(Color(0.12, 0.12, 0.13), 0.35, 0.4)
	var black := _mat(Color(0.05, 0.05, 0.06), 0.6)
	var rear_x := bike_x - bb
	var front_x := bike_x + (L - bb)
	var x0 := rear_x - 0.32
	var x1 := front_x + 0.22
	for sz in [-0.26, 0.26]:   # side rails
		var rail := _box(Vector3(x1 - x0, 0.035, 0.05), Vector3((x0 + x1) / 2, 0.03, sz), alu)
		rail.reparent(rollers)
	for x in [x0 + 0.03, x1 - 0.03]:   # end bars + rubber feet
		_box(Vector3(0.05, 0.035, 0.56), Vector3(x, 0.03, 0), alu).reparent(rollers)
		for sz in [-0.26, 0.26]:
			_box(Vector3(0.08, 0.015, 0.08), Vector3(x, 0.0075, sz), black).reparent(rollers)
	# a drum touches the tyre where the wheel circle meets ROLLER_TOP: rear pair straddles the axle
	for x in [rear_x - DRUM_GAP, rear_x + DRUM_GAP, front_x]:
		var d := Node3D.new()
		d.position = Vector3(x, DRUM_Y if x != front_x else ride_y - DRUM_R, 0)
		rollers.add_child(d)
		var c := CylinderMesh.new(); c.top_radius = DRUM_R; c.bottom_radius = DRUM_R; c.height = 0.44
		var mi := MeshInstance3D.new(); mi.mesh = c; mi.material_override = drum_m
		mi.rotation = Vector3(PI / 2, 0, 0)
		d.add_child(mi)
		for sz in [-0.24, 0.24]:   # end caps / bearings
			var cap := CylinderMesh.new(); cap.top_radius = 0.03; cap.bottom_radius = 0.03; cap.height = 0.03
			var ci := MeshInstance3D.new(); ci.mesh = cap; ci.material_override = alu
			ci.rotation = Vector3(PI / 2, 0, 0); ci.position = Vector3(0, 0, sz)
			d.add_child(ci)
		drums.append(d)
	# the belt from the rear drum to the front one, on the drive side
	var belt := _box(Vector3(front_x - (rear_x + 0.13), 0.008, 0.012), Vector3((front_x + rear_x + 0.13) / 2, DRUM_Y + DRUM_R * 0.6, 0.235), black)
	belt.reparent(rollers)
	for mi in rollers.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON

## wheels and drums spin with the pedalling (on the rollers the bike goes nowhere)
func _spin_on_rollers(dt: float, speed: float) -> void:
	if rollers == null: return
	wheel_ang += speed / rig.wheel_rr * dt
	rig.wheel_r.rotation.z = -wheel_ang
	rig.wheel_f.rotation.z = -wheel_ang * rig.wheel_rr / rig.wheel_rf
	for d in drums:
		d.rotation.z += speed / DRUM_R * dt   # drums turn the other way to the tyres

# ---------------------------------------------------------------- the rider standing next to the bike
func _update_stand_rider() -> void:
	if stand_on and stand_rider == null:
		stand_rider = Rider.new()
		add_child(stand_rider)
		stand_rider.position = STAND_AT
		stand_rider.rotation.y = -PI / 2 + 0.35   # facing the camera, turned a little toward the bike
		stand_rider.set_look(RiderPanels.load_look())
		stand_rider.set_style(STAND_POSE)
		# a soft warm fill from in front, so the kit colours read against the bright door
		var fill := OmniLight3D.new()
		fill.position = Vector3(0.9, 1.5, 0.6)   # rider space: in front of them, above head height
		fill.light_color = Color(1.0, 0.9, 0.8); fill.light_energy = 1.1; fill.omni_range = 3.5
		fill.light_volumetric_fog_energy = 0.0
		stand_rider.add_child(fill)
		var hs: Node3D = load("res://assets/helmet.glb").instantiate()
		var helmet := hs.find_child("helmet", true, false)
		if helmet:
			helmet.get_parent().remove_child(helmet)
			stand_rider.set_helmet(helmet)
		hs.free()
	elif not stand_on and stand_rider:
		stand_rider.queue_free()
		stand_rider = null

## standing upright: the riding pose's numbers turned into a relaxed stand (see Rider.update_pose)
const STAND_POSE := {"hipX": 0.17, "hipY": 0.16, "lean": -0.66, "crouch": 0.0, "standPedal": 0.0, "sway": 0.0,
	"elbowsOut": -0.2, "kneesOut": 0.0, "stance": 0.0, "headTilt": 0.08, "headTurn": 0.0, "hipSway": 0.0}

## one rider at a time: on the Kit tab they stand next to the bike, everywhere else they ride it
func _rider_visibility() -> void:
	var kit := tab == "kit" and stand_on
	if stand_rider: stand_rider.visible = kit
	if rider and is_instance_valid(rider): rider.visible = not kit

func _pose_stand_rider(dt: float) -> void:
	if stand_rider == null: return
	var breathe := sin(hand_t * 1.6) * 0.006
	stand_rider.update_pose(dt, {"footL": Vector3(0.0, 0.0, -0.13), "footR": Vector3(0.02, 0.0, 0.13),
		"handL": Vector3(0.02, 0.83 + breathe, -0.29), "handR": Vector3(0.04, 0.83 + breathe, 0.29),
		"v": 0.0, "lean": 0.0, "steer": 0.0, "yawRate": 0.0, "counter": 0.0, "rockRoll": 0.0, "headRoll": 0.0,
		"absorb": breathe, "pitch": 0.0, "bodyLevel": 0.85, "attackDrop": 0.0, "pedal": 0.0, "sprint": 0.0,
		"crank": 0.0, "air": 0.0, "compress": 0.0, "hipShift": 0.0, "t": hand_t})

const PREVIEWS := {
	"coast": {"label": "Coasting", "pedal": 0.0, "pitch": 0.0, "air": 0.0, "compress": 0.0, "v": 4.0},
	"pedal": {"label": "Pedalling", "pedal": 1.0, "pitch": 0.0, "air": 0.0, "compress": 0.0, "v": 6.0},
	"sprint": {"label": "Sprinting", "pedal": 1.0, "sprint": 1.0, "pitch": 0.0, "air": 0.0, "compress": 0.0, "v": 9.0},
	"descend": {"label": "Descending", "pedal": 0.0, "pitch": -0.35, "air": 0.0, "compress": 0.06, "v": 10.0},
	"air": {"label": "In the air", "pedal": 0.0, "pitch": 0.1, "air": 1.0, "compress": 0.1, "v": 10.0},
}

func _pose_rider(dt: float) -> void:
	if rider == null or not is_instance_valid(rider): return
	var P: Dictionary = PREVIEWS[rider_preview]
	if P.pedal > 0.5:
		var cad := 7.0 if P.get("sprint", 0.0) > 0 else 5.0
		preview_crank += dt * cad
		rig.crank_n.rotation.z = -preview_crank
		for pv in rig.pedal_pivots: pv.rotation.z = preview_crank
		_spin_on_rollers(dt, cad * 2.78 * rig.wheel_rr * 0.55)   # wheel speed from the crank (gear ~2.8)
	else:
		_spin_on_rollers(dt, 2.0)   # coasting: the wheels keep turning on the drums
	var lt := rig.limb_targets()
	rider.update_pose(dt, {"footL": lt.footL, "footR": lt.footR, "handL": lt.handL, "handR": lt.handR,
		"v": P.v, "lean": 0.0, "steer": 0.0, "yawRate": 0.0, "counter": 0.0, "rockRoll": 0.0, "headRoll": 0.0,
		"absorb": 0.0, "pitch": P.pitch, "bodyLevel": 0.85, "attackDrop": 0.18, "pedal": P.pedal,
		"sprint": P.get("sprint", 0.0), "crank": preview_crank, "air": P.air, "compress": P.compress, "hipShift": 0.0, "t": hand_t})

func _changed() -> void:
	_dirty = 0.12   # rebuild after the slider settles
	_update_stats()

# ================================================================ camera
## slats ride up by door_open * DOOR_H; any that reach the drum disappear into it
func _place_slats() -> void:
	var lift := DOOR_H * door_open
	for mi in door_slats.get_children():
		var y: float = mi.get_meta("y0") + lift
		mi.position.y = y
		mi.visible = y < DOOR_H - SLAT * 0.3

func _process(dt: float) -> void:
	if door_open < 1.0:
		door_t += minf(dt, 0.05)   # the first frame after the long build has a huge dt: don't let it eat the wait
		var k := clampf((door_t - DOOR_DELAY) / DOOR_TIME, 0.0, 1.0)
		var e := k * k * (3.0 - 2.0 * k)
		door_open = minf(1.0, e + sin(k * 37.0) * 0.004 * (1.0 - k) * k * 4.0)   # a little motor judder
		if k >= 1.0:
			door_open = 1.0
			_door_opened_once = true
		_place_slats()
	if _dirty > 0:
		_dirty -= dt
		if _dirty <= 0: _rebuild_bike()
	if auto_spin and not dragging: orbit_t += dt * 0.12
	orbit = lerpf(orbit, orbit_t, minf(1.0, dt * 4))
	pitch = lerpf(pitch, pitch_t, minf(1.0, dt * 4))
	dist = lerpf(dist, dist_t, minf(1.0, dt * 4))
	focus = focus.lerp(focus_t, minf(1.0, dt * 4))
	var p := deg_to_rad(pitch)
	cam.position = focus + Vector3(sin(orbit) * cos(p), sin(p), cos(orbit) * cos(p)) * dist
	cam.look_at(focus, Vector3.UP)
	# HANDHELD: someone holding the camera -- a slow few-cm drift and a fraction of a degree of wobble,
	# from a few unrelated sine waves (never repeats visibly, never jerks)
	hand_t += dt
	_pose_rider(dt)
	_pose_stand_rider(dt)
	var t := hand_t
	cam.position += cam.basis * Vector3(
		(sin(t * 0.53) + 0.6 * sin(t * 1.31 + 1.7)) * 0.018,
		(sin(t * 0.71 + 0.4) + 0.5 * sin(t * 1.77 + 2.9)) * 0.012,
		sin(t * 0.37 + 2.2) * 0.02)
	cam.rotate_object_local(Vector3.RIGHT, (sin(t * 0.83 + 0.9) + 0.4 * sin(t * 2.1)) * 0.0022)
	cam.rotate_object_local(Vector3.UP, (sin(t * 0.61 + 3.1) + 0.4 * sin(t * 1.9 + 0.5)) * 0.0028)
	cam.rotate_object_local(Vector3.FORWARD, sin(t * 0.47 + 1.3) * 0.004)
	cam.h_offset = 0.0   # the bike sits in the middle of the frame

func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventMouseButton:
		if e.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]:
			dragging = e.pressed
			if e.pressed: auto_spin = false
		elif e.button_index == MOUSE_BUTTON_WHEEL_UP and e.pressed: dist_t = clampf(dist_t * 0.9, 1.2, 7)
		elif e.button_index == MOUSE_BUTTON_WHEEL_DOWN and e.pressed: dist_t = clampf(dist_t * 1.1, 1.2, 7)
	elif e is InputEventMouseMotion and dragging:
		orbit_t -= e.relative.x * 0.008
		pitch_t = clampf(pitch_t + e.relative.y * 0.2, -2, 70)
	elif e.is_action_pressed("pause"):
		_close(false)

# ================================================================ UI
func _build_ui() -> void:
	var root := Control.new()
	root.theme = UITheme.get_theme()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(root)
	var title := UITheme.label("GARAGE", 40, UITheme.ACCENT, true)
	title.position = Vector2(32, 18)
	root.add_child(title)
	panel = PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	panel.offset_left = 24; panel.offset_right = 470; panel.offset_top = 80; panel.offset_bottom = -90
	root.add_child(panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	panel.add_child(vb)
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 6)
	var grp := ButtonGroup.new()
	for t in [["paint", "Paint"], ["logos", "Logos"], ["wheels", "Wheels"], ["suspension", "Suspension"], ["drive", "Gears"], ["rider", "Rider"], ["kit", "Kit"]]:
		var b := Button.new()
		b.text = t[1]; b.toggle_mode = true; b.button_group = grp
		b.button_pressed = t[0] == tab
		b.add_theme_font_size_override("font_size", 15)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(_set_tab.bind(t[0]))
		tabs.add_child(b)
		tab_buttons[t[0]] = b
	vb.add_child(tabs)
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vb.add_child(sc)
	body = VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 8)
	sc.add_child(body)
	# performance bars, top right
	var sp := PanelContainer.new()
	sp.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	sp.offset_left = -330; sp.offset_right = -24; sp.offset_top = 24
	root.add_child(sp)
	stats_box = VBoxContainer.new()
	sp.add_child(stats_box)
	var name_e := LineEdit.new()
	name_e.text = build.name
	name_e.placeholder_text = "Bike name"
	name_e.text_changed.connect(func(t): build.name = t)
	stats_box.add_child(name_e)
	for k in BikeBuild.stats(build):
		var row := VBoxContainer.new()
		row.add_child(UITheme.label(k.to_upper(), 12, UITheme.MUTED))
		var bar := StatBar.new()
		bar.custom_minimum_size = Vector2(280, 12)
		row.add_child(bar)
		stats_box.add_child(row)
		_stat_bars[k] = bar
	_update_stats()
	# bottom buttons
	var bot := HBoxContainer.new()
	bot.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bot.offset_left = 24; bot.offset_right = -24; bot.offset_top = -72; bot.offset_bottom = -20
	bot.add_theme_constant_override("separation", 10)
	root.add_child(bot)
	bot.add_child(UITheme.button("◀  Back", func(): _close(false)))
	bot.add_child(UITheme.button("Stock", func(): build = BikeBuild.default_build(); _rebuild_bike(); _set_tab(tab); _update_stats()))
	bot.add_child(UITheme.button("Randomise", _randomise))
	var spacer := Control.new(); spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL; bot.add_child(spacer)
	bot.add_child(UITheme.label("Drag to rotate · wheel to zoom", 13, UITheme.MUTED))
	var spacer2 := Control.new(); spacer2.size_flags_horizontal = Control.SIZE_EXPAND_FILL; bot.add_child(spacer2)
	var save := UITheme.button("Save", func(): BikeBuild.save_build(build); _toast("Saved"))
	bot.add_child(save)
	var ride := UITheme.button("Save & ride  ▶", func(): _close(true), 20)
	ride.custom_minimum_size.x = 200
	bot.add_child(ride)
	# solid backs: the buttons sit over the sunlit floor
	for b in bot.get_children():
		if b is Button:
			b.add_theme_stylebox_override("normal", UITheme.box(Color(0.06, 0.11, 0.15, 0.92), 10, 16))
			b.add_theme_stylebox_override("hover", UITheme.box(Color(0.14, 0.22, 0.28, 0.95), 10, 16))
	ride.add_theme_stylebox_override("normal", UITheme.box(UITheme.ACCENT, 10, 16))
	ride.add_theme_color_override("font_color", UITheme.NAVY)
	_file_dialog = FileDialog.new()
	_file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_file_dialog.filters = PackedStringArray(["*.png ; PNG images"])
	_file_dialog.use_native_dialog = true
	_file_dialog.file_selected.connect(_on_logo_file)
	root.add_child(_file_dialog)

func _close(ride: bool) -> void:
	BikeBuild.save_build(build)
	closed.emit(ride)

func _toast(t: String) -> void:
	var l := UITheme.label(t, 28, UITheme.ACCENT, true)
	l.set_anchors_preset(Control.PRESET_CENTER_TOP)
	l.position = Vector2(-60, 90)
	ui.get_child(0).add_child(l)
	var tw := create_tween()
	tw.tween_interval(0.8); tw.tween_property(l, "modulate:a", 0.0, 0.4); tw.tween_callback(l.queue_free)

func _update_stats() -> void:
	var s := BikeBuild.stats(build)
	for k in s:
		if _stat_bars.has(k): _stat_bars[k].target = s[k]

func _set_tab(t: String) -> void:
	# only switching to another tab frames the camera on that area; refreshing the page after a
	# change (colour, finish, part, logo...) leaves the camera wherever you put it
	if t != tab:
		var v: Array = VIEWS[t]
		orbit_t = v[0] + round((orbit_t - v[0]) / TAU) * TAU
		pitch_t = v[1]; dist_t = v[2]; focus_t = v[3]
		auto_spin = false
	tab = t
	if tab_buttons.has(t): tab_buttons[t].button_pressed = true   # (pressed, not toggled, drives _set_tab: no loop)
	_rider_visibility()
	for c in body.get_children(): c.queue_free()
	match t:
		"paint": _paint_page()
		"logos": _logos_page()
		"wheels": _wheels_page()
		"suspension": _susp_page()
		"drive": _drive_page()
		"rider": _rider_page()
		"kit": _kit_page()

# ---------------------------------------------------------------- widgets
func _h(text: String) -> void:
	body.add_child(UITheme.label(text, 13, UITheme.ACCENT, true))

func _row(text: String, ctl: Control) -> void:
	var hb := HBoxContainer.new()
	var l := UITheme.label(text, 15)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(l)
	ctl.custom_minimum_size.x = maxf(ctl.custom_minimum_size.x, 200)
	hb.add_child(ctl)
	body.add_child(hb)

func _choice(text: String, items: Array, current, cb: Callable) -> OptionButton:
	## items: [[value, label], ...]
	var ob := OptionButton.new()
	var sel := 0
	for i in items.size():
		ob.add_item(str(items[i][1]))
		if str(items[i][0]) == str(current): sel = i
	ob.selected = sel
	ob.item_selected.connect(func(i): cb.call(items[i][0]); _changed())
	_row(text, ob)
	return ob

func _slide(text: String, lo: float, hi: float, stp: float, cur: float, unit: String, cb: Callable) -> void:
	var hb := HBoxContainer.new()
	var s := HSlider.new()
	s.min_value = lo; s.max_value = hi; s.step = stp; s.value = cur
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var fmt := "%d " + unit if stp >= 1 else "%.1f " + unit
	var vl := UITheme.label(fmt % cur, 14, UITheme.MUTED)
	vl.custom_minimum_size.x = 64
	s.value_changed.connect(func(v): vl.text = fmt % v; cb.call(v); _changed())
	hb.add_child(s); hb.add_child(vl)
	_row(text, hb)

func _color(text: String, cur: String, cb: Callable) -> void:
	var cp := ColorPickerButton.new()
	cp.color = Color(cur)
	cp.edit_alpha = false
	cp.custom_minimum_size = Vector2(200, 34)
	cp.color_changed.connect(func(c): cb.call(c.to_html(false)); _changed())
	_row(text, cp)

func _swatches(cur: String, cb: Callable) -> void:
	var g := GridContainer.new()
	g.columns = 11
	g.add_theme_constant_override("h_separation", 5)
	g.add_theme_constant_override("v_separation", 5)
	for hex in SWATCHES:
		var b := Button.new()
		b.custom_minimum_size = Vector2(32, 32)
		var on: bool = hex == cur
		b.add_theme_stylebox_override("normal", UITheme.box(Color(hex), 8, 0, Color.WHITE if on else Color(1, 1, 1, 0.15), 3 if on else 1))
		b.add_theme_stylebox_override("hover", UITheme.box(Color(hex).lightened(0.15), 8, 0, UITheme.ACCENT, 2))
		b.add_theme_stylebox_override("pressed", UITheme.box(Color(hex), 8, 0, UITheme.ACCENT, 3))
		b.pressed.connect(func(): cb.call(hex); _changed(); _set_tab(tab))
		g.add_child(b)
	body.add_child(g)

# ---------------------------------------------------------------- pages
func _paint_page() -> void:
	_h("PART")
	var g := GridContainer.new()
	g.columns = 2
	g.add_theme_constant_override("h_separation", 6)
	g.add_theme_constant_override("v_separation", 6)
	var grp := ButtonGroup.new()
	for k in BikeBuild.PARTS:
		var b := Button.new()
		b.text = BikeBuild.PARTS[k][0]; b.toggle_mode = true; b.button_group = grp
		b.button_pressed = k == part
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.add_theme_font_size_override("font_size", 14)
		b.pressed.connect(func(): part = k; _set_tab("paint"))
		g.add_child(b)
	body.add_child(g)
	var P: Dictionary = build.paint[part]
	_h("COLOUR")
	_swatches(P.color, func(h): P.color = h)
	_color("Custom colour", P.color, func(h): P.color = h)
	_h("FINISH")
	var fg := GridContainer.new()
	fg.columns = 4
	fg.add_theme_constant_override("h_separation", 6)
	fg.add_theme_constant_override("v_separation", 6)
	var fgrp := ButtonGroup.new()
	for f in BikeBuild.FINISHES:
		var b := Button.new()
		b.text = BikeBuild.FINISHES[f].label; b.toggle_mode = true; b.button_group = fgrp
		b.button_pressed = f == P.finish
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.add_theme_font_size_override("font_size", 13)
		b.pressed.connect(func(): P.finish = f; _changed(); _set_tab("paint"))
		fg.add_child(b)
	body.add_child(fg)
	if P.finish == "pearl":
		_color("Shift colour (at the edges)", P.color2, func(h): P.color2 = h)
	var copy := UITheme.button("Copy this paint to the whole frame", func():
		for k in ["frame", "rear"]: build.paint[k] = P.duplicate()
		_changed(), 14)
	body.add_child(copy)

func _logos_page() -> void:
	_h("SPOT")
	var g := GridContainer.new()
	g.columns = 3
	g.add_theme_constant_override("h_separation", 6)
	g.add_theme_constant_override("v_separation", 6)
	var grp := ButtonGroup.new()
	var slots := BikeBuild.SLOTS.keys() + ["tyres", "rims"]
	for k in slots:
		var b := Button.new()
		b.text = "Tyre walls" if k == "tyres" else ("Rims" if k == "rims" else BikeBuild.SLOTS[k].label)
		b.toggle_mode = true; b.button_group = grp; b.button_pressed = k == logo_slot
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.add_theme_font_size_override("font_size", 14)
		b.pressed.connect(func(): logo_slot = k; _set_tab("logos"))
		g.add_child(b)
	body.add_child(g)
	var L: Dictionary = build.logos[logo_slot]
	if logo_slot in ["tyres", "rims"]:
		_h("SIDEWALL LETTERING" if logo_slot == "tyres" else "RIM LETTERING")
		_choice("Show", [["text", "On"], ["none", "Off"]], L.logo, func(v): L.logo = v)
		var te := LineEdit.new(); te.text = L.text; te.max_length = 14
		te.text_changed.connect(func(t): L.text = t.to_upper(); _changed())
		_row("Text", te)
		_h("COLOUR")
		_swatches(L.fill, func(h): L.fill = h)
		_color("Lettering", L.fill, func(h): L.fill = h)
		return
	_h("LOGO")
	var items := []
	var upright: bool = BikeBuild.SLOTS[logo_slot].tmpl.get("upright", false)
	for k in BikeBuild.LOGOS:
		var lg: Dictionary = BikeBuild.LOGOS[k]
		if upright and (lg.has("text") or k == "text"): continue
		items.append([k, lg.label])
	for f in BikeBuild.imported_logos():
		items.append(["file:" + f, "📁 " + f.get_file().get_basename()])
	_choice("Logo", items, L.logo, func(v): L.logo = v; _set_tab.call_deferred("logos"))
	var imp := UITheme.button("Import your own PNG…", func(): _file_dialog.popup_centered_ratio(0.6), 14)
	body.add_child(imp)
	body.add_child(UITheme.label("Transparent PNGs work best. Imported logos are kept in your garage.", 12, UITheme.MUTED))
	if L.logo == "text":
		var te := LineEdit.new(); te.text = L.text; te.max_length = 16; te.placeholder_text = "YOUR TEXT"
		te.text_changed.connect(func(t): L.text = t.to_upper(); _changed())
		_row("Text", te)
	if L.logo == "text" or BikeBuild.LOGOS.get(L.logo, {}).has("text"):
		_h("LETTERING COLOURS")
		_swatches(L.fill, func(h): L.fill = h)
		_color("Fill", L.fill, func(h): L.fill = h)
		_color("Outline", L.stroke, func(h): L.stroke = h)

func _on_logo_file(path: String) -> void:
	var p := BikeBuild.import_logo(path)
	if p == "":
		_toast("Couldn't read that image"); return
	if BikeBuild.SLOTS.has(logo_slot):
		build.logos[logo_slot].logo = "file:" + p
	_changed()
	_set_tab("logos")

func _wheels_page() -> void:
	var W: Dictionary = build.wheels
	var sizes := [["26", "26\""], ["27.5", "27.5\""], ["29", "29\""]]
	_h("SIZE")
	_choice("Front wheel", sizes, W.front, func(v): W.front = v)
	_choice("Rear wheel", sizes, W.rear, func(v): W.rear = v)
	body.add_child(UITheme.label("29\" front / 27.5\" rear is a mullet: big wheel rolls over, small one turns quick.", 12, UITheme.MUTED))
	_h("TYRES")
	_slide("Width", 2.3, 2.6, 0.1, W.tyre_w, "in", func(v): W.tyre_w = v)
	_choice("Tread", [["knobby", "Knobby (max grip)"], ["semi", "Semi-slick"], ["slick", "Slick (fast, sketchy)"]], W.tread, func(v): W.tread = v)
	_choice("Sidewall", [["black", "Black"], ["tan", "Tan wall"]], W.sidewall, func(v): W.sidewall = v)
	_h("RIMS")
	_swatches(W.rim_color, func(h): W.rim_color = h)
	_choice("Finish", [["matte", "Matte"], ["gloss", "Gloss"], ["chrome", "Polished"]], W.rim_finish, func(v): W.rim_finish = v)
	_slide("Rim depth", 20, 40, 1, W.rim_depth, "mm", func(v): W.rim_depth = v)
	_slide("Rim width", 25, 40, 1, W.rim_width, "mm", func(v): W.rim_width = v)
	_h("SPOKES")
	_choice("Count", [[24, "24"], [28, "28"], [32, "32"], [36, "36"]], W.spokes, func(v): W.spokes = v)
	_choice("Lacing", [[0, "Radial"], [1, "1-cross"], [2, "2-cross"], [3, "3-cross"]], W.lacing, func(v): W.lacing = v)
	_choice("Gauge", [[0, "Thin (light)"], [1, "Normal"], [2, "Thick (strong)"]], W.gauge, func(v): W.gauge = v)
	_color("Spoke colour", W.spoke_color, func(h): W.spoke_color = h)
	_color("Nipples", W.nipple_color, func(h): W.nipple_color = h)
	_color("Hubs", W.hub_color, func(h): W.hub_color = h)

func _susp_page() -> void:
	var S: Dictionary = build.suspension
	var rate := [[0, "Soft"], [1, "Medium"], [2, "Firm"]]
	_h("FORK")
	_slide("Travel", 160, 220, 10, S.fork_travel, "mm", func(v): S.fork_travel = int(v))
	_choice("Spring", rate, S.fork_spring, func(v): S.fork_spring = v)
	_h("REAR SHOCK")
	_slide("Travel", 160, 220, 10, S.shock_travel, "mm", func(v): S.shock_travel = int(v))
	_choice("Spring", rate, S.shock_spring, func(v): S.shock_spring = v)
	_h("DAMPING")
	_choice("Rebound", [[0, "Slow (planted)"], [1, "Medium"], [2, "Fast (poppy)"]], S.rebound, func(v): S.rebound = v)
	body.add_child(UITheme.label("More travel soaks bigger drops; firmer springs pop and pump harder but kick on rough ground.", 12, UITheme.MUTED))

func _drive_page() -> void:
	var D: Dictionary = build.drive
	_h("CHAINRING")
	_slide("Teeth", 30, 38, 2, D.ring, "T", func(v): D.ring = int(v))
	_h("CASSETTE")
	var items := []
	for k in BikeBuild.CASSETTES: items.append([k, BikeBuild.CASSETTES[k].label])
	_choice("Cassette", items, D.cassette, func(v): D.cassette = v)
	var cogs: Array = BikeBuild.CASSETTES[D.cassette].cogs
	var lo := float(D.ring) / float(cogs[cogs.size() - 1])
	var hi := float(D.ring) / float(cogs[0])
	body.add_child(UITheme.label("Ratios %.2f – %.2f. Bigger ring / smaller cog = higher top speed, harder to get going." % [lo, hi], 12, UITheme.MUTED))

func _save_rider_ui() -> void:
	var cf := ConfigFile.new(); cf.load(RiderPanels.PATH)
	cf.set_value("garage", "rider_on", rider_on)
	cf.set_value("garage", "preview", rider_preview)
	cf.set_value("garage", "stand_on", stand_on)
	cf.save(RiderPanels.PATH)

func _rider_page() -> void:
	var on := CheckButton.new()
	on.text = "  Rider on the bike (on rollers)"
	on.button_pressed = rider_on
	on.add_theme_font_size_override("font_size", 17)
	on.toggled.connect(func(v):
		rider_on = v; _save_rider_ui()
		_rebuild_bike()   # onto / off the rollers
		_set_tab.call_deferred("rider"))
	body.add_child(on)
	if not rider_on:
		body.add_child(UITheme.label("Turn the rider on to see and shape the riding position: every joint has a slider, and the pose is used on the trail.", 13, UITheme.MUTED))
		body.get_child(body.get_child_count() - 1).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		return
	var items := []
	for k in PREVIEWS: items.append([k, PREVIEWS[k].label])
	_choice("Preview", items, rider_preview, func(v): rider_preview = v; _save_rider_ui())
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.add_child(UITheme.button("Reset pose", func():
		rider_pose = Rider.NEUTRAL.duplicate(); rider_pose.merge(GameState.BIKES.dh.pose, true)
		_apply_rider_pose(); _set_tab("rider"), 14))
	row.add_child(UITheme.button("Mirror L → R", func():
		rider_pose.elbowOutR = rider_pose.elbowOutL; rider_pose.kneeOutR = rider_pose.kneeOutL
		_apply_rider_pose(); _set_tab("rider"), 14))
	body.add_child(row)
	for g in RiderPanels.POSE_DEFS:
		_h(g[0].to_upper())
		for r in g[1]:
			var key: String = r[0]
			var unit: String = r[5]
			var stp: float = r[4]
			var hb := HBoxContainer.new()
			var s := HSlider.new()
			s.min_value = r[2]; s.max_value = r[3]; s.step = stp; s.value = float(rider_pose.get(key, 0.0))
			s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			s.focus_mode = Control.FOCUS_NONE
			var dec := clampi(ceili(-log(stp) / log(10.0)), 0, 3)
			var fmt := "%." + str(dec) + "f " + unit
			var vl := UITheme.label(fmt % s.value, 13, UITheme.MUTED)
			vl.custom_minimum_size.x = 70
			s.value_changed.connect(func(v): vl.text = fmt % v; rider_pose[key] = v; _apply_rider_pose())
			hb.add_child(s); hb.add_child(vl)
			_row(r[1], hb)

## Kit: the rider stands beside the bike; kits and a colour for every part of their gear
func _kit_page() -> void:
	var on := CheckButton.new()
	on.text = "  Rider next to the bike"
	on.button_pressed = stand_on
	on.add_theme_font_size_override("font_size", 17)
	on.toggled.connect(func(v):
		stand_on = v; _save_rider_ui(); _update_stand_rider(); _rider_visibility())
	body.add_child(on)
	var look := RiderPanels.load_look()
	_h("KITS")
	var kits := GridContainer.new(); kits.columns = 3
	kits.add_theme_constant_override("h_separation", 6); kits.add_theme_constant_override("v_separation", 6)
	for k in RiderPanels.KITS:
		var kit_look: Dictionary = Rider.DEFAULT_LOOK.duplicate()
		kit_look.merge(k[1], true)
		var b := Button.new()
		b.text = k[0]
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size.y = 52
		b.add_theme_font_size_override("font_size", 14)
		# a strip of the kit's colours along the bottom of the button
		var strip := HBoxContainer.new()
		strip.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
		strip.offset_top = -10; strip.offset_bottom = -4; strip.offset_left = 10; strip.offset_right = -10
		strip.add_theme_constant_override("separation", 0)
		strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		for part in ["shell", "jersey", "pants", "gloves", "lens"]:
			var c := ColorRect.new(); c.color = Color(kit_look[part]); c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			c.mouse_filter = Control.MOUSE_FILTER_IGNORE
			strip.add_child(c)
		b.add_child(strip)
		b.pressed.connect(func(): _set_look(kit_look); _set_tab("kit"))
		kits.add_child(b)
	body.add_child(kits)
	for g in RiderPanels.LOOK_ROWS:
		_h(g[0].to_upper())
		for row in g[1]:
			var key: String = row[0]
			var hb := HBoxContainer.new()
			hb.add_theme_constant_override("separation", 4)
			for hex in row[2]:
				var b := Button.new()
				b.custom_minimum_size = Vector2(24, 24)
				var sel: bool = str(look[key]).to_lower() == str(hex).to_lower()
				b.add_theme_stylebox_override("normal", UITheme.box(Color(hex), 12, 0, Color.WHITE if sel else Color(1, 1, 1, 0.2), 3 if sel else 1))
				b.add_theme_stylebox_override("hover", UITheme.box(Color(hex), 12, 0, UITheme.ACCENT, 2))
				b.add_theme_stylebox_override("pressed", UITheme.box(Color(hex), 12, 0, UITheme.ACCENT, 3))
				b.focus_mode = Control.FOCUS_NONE
				b.pressed.connect(func(): look[key] = hex; _set_look(look); _set_tab("kit"))
				hb.add_child(b)
			var cp := ColorPickerButton.new()
			cp.color = Color(look[key]); cp.edit_alpha = false
			cp.custom_minimum_size = Vector2(34, 24)
			cp.color_changed.connect(func(c): look[key] = "#" + c.to_html(false); _set_look(look))
			hb.add_child(cp)
			_row(row[1], hb)
	body.add_child(UITheme.button("Reset kit", func(): _set_look(Rider.DEFAULT_LOOK.duplicate()); _set_tab("kit"), 14))

func _set_look(l: Dictionary) -> void:
	RiderPanels.save_look(l)
	if stand_rider: stand_rider.set_look(l)
	if rider: rider.set_look(l)

func _apply_rider_pose() -> void:
	if rider: rider.set_style(rider_pose)
	RiderPanels.save_pose("dh", rider_pose)

func _randomise() -> void:
	for k in build.paint:
		var c: String = SWATCHES[randi() % SWATCHES.size()]
		build.paint[k].color = c
		build.paint[k].color2 = SWATCHES[randi() % SWATCHES.size()]
		build.paint[k].finish = BikeBuild.FINISHES.keys()[randi() % BikeBuild.FINISHES.size()]
	build.paint.rear = build.paint.frame.duplicate()
	var W: Dictionary = build.wheels
	W.rim_color = SWATCHES[randi() % SWATCHES.size()]
	W.spoke_color = SWATCHES[randi() % SWATCHES.size()]
	W.nipple_color = SWATCHES[randi() % SWATCHES.size()]
	W.spokes = [24, 28, 32, 36][randi() % 4]
	W.sidewall = ["black", "tan"][randi() % 2]
	_changed(); _set_tab(tab)

class StatBar extends Control:
	var target := 0.5
	var k := 0.0
	func _process(dt: float) -> void:
		k = lerpf(k, target, minf(1.0, dt * 6)); queue_redraw()
	func _draw() -> void:
		draw_style_box(UITheme.box(Color(1, 1, 1, 0.12), 4, 0), Rect2(Vector2.ZERO, size))
		draw_style_box(UITheme.box(UITheme.ACCENT, 4, 0), Rect2(Vector2.ZERO, Vector2(size.x * clampf(k, 0.02, 1), size.y)))
