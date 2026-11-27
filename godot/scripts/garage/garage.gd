class_name Garage
extends Node3D
## The garage: the downhill bike stands on a concrete floor under a spotlight while you change its
## paint, logos, wheels, suspension and gearing. Every change rebuilds the bike live; "Save & ride"
## writes user://garage.json and the next ride uses it.

signal closed(ride: bool)
signal anim_requested   # Insert in the rider room: the Anim Studio (the standing rider's animation library)

## "bike" = the garage (paint, logos, wheels, bars, shocks, gears; the bike stands on the floor);
## "rider" = the rider room (riding position on the training rollers, kit beside the bike).
## Set before adding to the tree.
var mode := "bike"

const SWATCHES := ["e8432e", "ff6a00", "ffb000", "ffd21f", "c6ff1a", "35d04a", "00a86b", "00c2c7", "2f7de1", "1d2b64",
	"7b3fe4", "d22fbf", "ff4f9a", "f4f4f0", "b8bcc0", "6b6f75", "2b2d31", "111214", "c8a24a", "8a5a2b", "4a6b3a", "e0d3b8"]
## the paint-shop chip names of SWATCHES (same order; made up, like the rest of the game's names); code = RO 1xx
const SWATCH_NAMES := ["Signal Red", "Blaze", "Amber", "Race Yellow", "Acid Lime", "Fern", "Jade", "Lagoon", "Cobalt", "Navy",
	"Violet", "Magenta", "Bubblegum", "Chalk", "Alloy", "Gunmetal", "Graphite", "Jet Black", "Brass", "Saddle", "Olive", "Sand"]

const DOOR_W := 3.6
const DOOR_H := 3.2
const DOOR_X := 0.0   # the door is straight behind the bike
## the garage's sun: low, behind the open door (toward -Z), a little to the left, so daylight falls
## in through the doorway across the floor
## where the sun is (towards it): late afternoon, ~30 deg up behind the door and 45 deg to the left, so a
## slanted shaft comes in through the doorway (seen in the dusty air, motes drifting in it) and lays a
## warm patch across the floor right of the bike (clear of the menu card). Above the door's top edge from the camera: no glare.
const SUN := Vector3(-0.6, 0.5, -0.6)

var build: Dictionary
var rig: BikeRig
var outside: Node3D
var _outside_terrain: Node3D   # the Terrain out of the door, still streaming its outer chunks while set
var _outside_spot := Vector2.ZERO
var rider: Rider = null
var rider_on := false
var rider_pose := {}
var rider_preview := "pedal"
var tab_buttons := {}
var thumbs: PartThumbs
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
const STAND_AT := Vector3(0.55, 0.0, 1.05)   # in front of the bike (camera side), the bike right behind them
var preview_crank := 0.6
const WALL_IN := -4.075   # z of the back wall's inside face (the wall is 0.25 thick, centred on z = -4.2)
const DOOR_DELAY := 1.0     # s (after the garage is on screen) before the door starts to roll up
const DOOR_TIME := 8.0      # s to roll it all the way up (the motor recording runs ~12 s)
static var _door_opened_once := false   # the door rolls up on the first visit; it stays open after
var door_slats: Node3D
var _mote_mat: ShaderMaterial = null   # sun-shaft dust motes (lit up to the door's open height)
var door_open := 1.0
var _door_hold := false   # BMX_GARAGE_DOOR: the door stays where the test put it
var door_t := 0.0
## the door's sound: the user's recording (assets/audio/garage_door_open.mp3, ~12 s of the motor running,
## then the stop clunk at ~12.5 s). The door rolls up in DOOR_TIME, so the motor plays from the start and,
## when the door reaches the top, fades out under the clunk from the end of the recording.
const DOOR_SOUND := "res://assets/audio/garage_door_open.mp3"
const DOOR_CLUNK_AT := 12.3   # s into the recording: the stop
var _door_motor: AudioStreamPlayer3D = null
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
const HANDHELD := 0.2          # how much of the original handheld sway is left (1 = the old, too-strong one)
const HANDHELD_SPEED := 0.6    # and how fast it drifts
var auto_spin := false   # the camera stays put unless you drag it
var hq: HqStill = null
## the SHOP (mode "shop", garage/store_page.gd): the studio instead of the workshop, bikes + parts for sale
var store: StorePage = null
var studio: StudioSet = null
var shop_reveal := false      # a purchase reveal is playing (StorePurchase drives the camera + studio lamps)
var _shop_frame := ""         # the frame on show in the shop (never GameState.bike_id: looking changes nothing)   # the showroom's HQ still: averages jittered frames once the camera rests (fx/hq_still.gd)
var _idle_t := 0.0       # s since the last camera input; the handheld sway stops after HQ_IDLE so a still can build
const HQ_IDLE := 1.0
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
	"bars": [0.9, 14.0, 1.7, Vector3(0.45, 1.0, 0)],
	"suspension": [1.0, 10.0, 2.2, Vector3(0.05, 0.6, 0)],
	"brakes": [2.2, 8.0, 2.4, Vector3(0.0, 0.45, 0)],   # the brake side: both rotors + calipers
	"drive": [-1.3, 8.0, 1.5, Vector3(-0.3, 0.35, 0)],   # the drive side: chainring + cassette
	"rider": [0.0, 7.0, 4.3, Vector3(-0.05, 1.0, 0)],
	"kit": [0.2, 6.0, 4.2, Vector3(0.3, 0.85, 0.6)],
	"show": [0.5, 6.0, 6.4, Vector3(0, 0.3, 0)],   # the showroom: still camera, the bike a little turned (3/4 side), centred above the frame strip
}

## the garage opens as a showroom: the bike, a strip of frames, BACK / EDIT / RIDE. EDIT opens the customizer
## (category tabs, options card, build card); its BACK comes back here.
var editing := true
var _edit_only: Array[Control] = []
var _show_only: Array[Control] = []
var _show_strip: PicStrip

func _ready() -> void:
	build = BikeBuild.load_build()
	rider_pose = RiderPanels.load_pose(_pose_bike(), GameState.BIKES[_pose_bike()].pose)
	var env_tab := Env.s("BMX_GARAGE_TAB")
	if Env.s("BMX_GARAGE_RIDER") != "" or env_tab in ["rider", "kit"]:
		mode = "rider"   # tests: the rider tabs live in the rider room
	var rcf := ConfigFile.new()
	if rcf.load(RiderPanels.PATH) == OK:
		rider_preview = rcf.get_value("garage", "preview", "pedal")
	# the garage is about the bike (no rider, no rollers); the rider room always has the rider on the
	# rollers (Position) and standing beside the bike (Kit)
	rider_on = mode == "rider"
	stand_on = mode == "rider"
	tab = "rider" if mode == "rider" else "paint"
	if Env.s("BMX_GARAGE_RIDER") != "":   # tests: a preview
		rider_preview = Env.s("BMX_GARAGE_RIDER")
		for kv in Env.s("BMX_POSE").split(",", false):   # tests: "spineCurve=0.2,pelvisRoll=0.1" (not saved)
			var p := kv.split("=")
			if p.size() == 2: rider_pose[p[0]] = float(p[1])
	if not PREVIEWS.has(rider_preview): rider_preview = "pedal"
	_probe_t = Time.get_ticks_usec()
	_open_t = _probe_t
	_showcase_quality(true)
	if mode == "shop":
		rider_on = false; stand_on = false
		store = StorePage.new(self)
		_shop_frame = store.base_frame
		build = store.base_build.duplicate(true)
		tab = "bikes" if not Catalog.TABS.any(func(t): return t[0] == env_tab) else env_tab
		_build_studio()
	else:
		_build_room()
	_probe("room")
	add_child(cam)
	cam.fov = 38
	cam.current = true
	if mode == "shop": cam.cull_mask &= ~StudioSet.PANEL_LAYER   # the softboxes: in reflections only
	if mode == "bike" or mode == "shop":
		hq = HqStill.new()
		hq.cam = cam
		hq.show_badge = true
		add_child(hq)
	_rebuild_bike()
	_probe("bike")
	add_child(ui)
	_build_ui()
	_probe("ui")
	var first := tab
	tab = ""   # so _set_tab frames the camera on the first page
	if mode == "bike" and env_tab == "":
		# the showroom: the customizer's first page is built when EDIT is pressed (_set_edit), not now. Built
		# out of sight it rendered a picture of every paintable part (a whole bike each, ~100 ms a frame)
		# and the garage stuttered for its first ~1.2 s
		tab = first
	else:
		_set_tab(env_tab if env_tab != "" and _has_tab(env_tab) else first)
	if mode == "bike": _set_edit(env_tab != "", false)   # tests that name a tab go straight to the customizer
	if mode == "shop" and Env.s("BMX_SHOP_BUY") != "":   # tests: buy what's picked, 2 s in
		get_tree().create_timer(2.0).timeout.connect(func(): store._buy())
	_probe("page")
	if Env.s("BMX_TYRE_PROBE") != "":
		_tyre_probe.call_deferred()
	if PartThumbs.BAKE != "":
		_bake_thumbs.call_deferred()
	var cv := Env.s("BMX_GARAGE_CAM").split(",", false)   # tests: "orbit_rad,pitch_deg,dist"
	if cv.size() == 3:
		orbit_t = float(cv[0]); pitch_t = float(cv[1]); dist_t = float(cv[2])
		orbit = orbit_t; pitch = pitch_t; dist = dist_t

## The garage is the showcase: whatever the graphics preset, it renders at the top quality (4x MSAA + TAA,
## full resolution, 16x anisotropic, full mesh detail, 8K soft-ultra shadows, ultra SSAO / SSIL, more GI
## rays, sharp glossy reflections). Leaving it puts the player's settings back (Settings.apply + the
## project's own defaults for the global qualities).
func _showcase_quality(on: bool) -> void:
	showcase_quality(get_viewport(), on)

## top render quality whatever the preset (the garage, the instant replay); off = back to the Settings.
## heavy = false (the replay, out in the open world): no 8K shadow maps / 128-ray GI / ultra SSAO-SSIL, the rest
static func showcase_quality(vp: Viewport, on: bool, heavy := true) -> void:
	if vp == null: return
	if not on:
		Settings.apply()
		RenderingServer.environment_set_ssao_quality(ProjectSettings.get_setting("rendering/environment/ssao/quality", 2),
			true, 0.5, 2, 50.0, 300.0)
		RenderingServer.environment_set_ssil_quality(ProjectSettings.get_setting("rendering/environment/ssil/quality", 2),
			true, 0.5, 4, 50.0, 300.0)
		RenderingServer.environment_set_sdfgi_ray_count(ProjectSettings.get_setting("rendering/global_illumination/sdfgi/probe_ray_count", 1))
		RenderingServer.positional_soft_shadow_filter_set_quality(ProjectSettings.get_setting("rendering/lights_and_shadows/positional_shadow/soft_shadow_filter_quality", 2))
		return
	vp.scaling_3d_scale = 1.0
	vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	vp.msaa_3d = Viewport.MSAA_4X
	vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	vp.use_taa = true
	vp.mesh_lod_threshold = 0.0
	vp.anisotropic_filtering_level = Viewport.ANISOTROPY_16X
	if not heavy: return
	vp.positional_shadow_atlas_size = 8192
	RenderingServer.directional_shadow_atlas_set_size(8192, true)
	RenderingServer.directional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_SOFT_ULTRA)
	RenderingServer.positional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_SOFT_ULTRA)
	RenderingServer.environment_set_ssao_quality(RenderingServer.ENV_SSAO_QUALITY_ULTRA, false, 0.5, 2, 50.0, 300.0)
	RenderingServer.environment_set_ssil_quality(RenderingServer.ENV_SSIL_QUALITY_ULTRA, false, 0.5, 4, 50.0, 300.0)
	RenderingServer.environment_set_sdfgi_ray_count(RenderingServer.ENV_SDFGI_RAY_COUNT_128)

func _exit_tree() -> void:
	_flush_pose()
	_showcase_quality(false)

## The release bake (BMX_BAKE_THUMBS=<dir>, run by tools/bake_thumbs.ps1 on a fresh user folder): every
## picture a new player can see here, made and written out to ship with the game. Bike garage: every frame
## with its stock build in the showroom and on every customizer tab; rider room: its tabs. Then quits.
func _bake_thumbs() -> void:
	var settle := func() -> void:   # until the picture maker has had nothing to do for a few frames
		var quiet := 0
		while quiet < 4:
			await get_tree().process_frame
			quiet = quiet + 1 if thumbs.idle() else 0
	if mode == "bike":
		for id in GameState.BIKES:
			if not GameState.BIKES[id].get("garage", false): continue
			GameState.bike_id = id
			build = BikeBuild.load_build(id)
			_show_pick = id
			_rebuild_bike()
			_set_edit(false)
			_fill_showroom()
			await settle.call()
			_set_edit(true)
			for t in _tabs():
				_set_tab(t[0])
				await settle.call()
			print("BAKE frame=%s pictures=%d" % [id, PartThumbs.baked_count()])
	else:
		for t in _tabs():
			_set_tab(t[0])
			await settle.call()
	print("BAKE done mode=%s pictures=%d" % [mode, PartThumbs.baked_count()])
	GameState.quit()

## tests (BMX_GARAGE_PROBE=1): how long each part of opening the garage takes (`GARAGE <step> ms=`)
## and the first frames after it (`GARAGEFRAME`)
var _probe_t := 0
var _open_t := 0
var _probe_frames := 0
func _probe(step: String) -> void:
	if Env.s("BMX_GARAGE_PROBE") == "": return
	var now := Time.get_ticks_usec()
	print("GARAGE %s ms=%.1f" % [step, (now - _probe_t) / 1000.0])
	_probe_t = now

# ================================================================ the room
func _mat(c: Color, rough := 0.8, metal := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c; m.roughness = rough; m.metallic = metal
	return m

## how far the camera can back away from `from` along `dir` and stay inside the room (walls at x = +-7,
## back wall z = -4.2, front wall z = 7.8, ceiling 5), keeping a little clearance
const ROOM_MIN := Vector3(-6.9, 0.15, -4.075)
const ROOM_MAX := Vector3(6.9, 4.9, 7.7)
func _room_reach(from: Vector3, dir: Vector3) -> float:
	var best := INF
	for a in 3:
		if absf(dir[a]) < 1e-5: continue
		var lim: float = (ROOM_MAX[a] if dir[a] > 0 else ROOM_MIN[a]) - signf(dir[a]) * 0.35
		var t: float = (lim - from[a]) / dir[a]
		# a focus already past this wall's margin gives a negative reach: ignore it (it used to clamp to 0.5 m
		# = the camera snapped right under the bike). The floor is handled by the pitch limit in _process.
		if t <= 0.0 or is_nan(t): continue
		best = minf(best, t)
	return best

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
	env.fog_depth_begin = 90.0
	env.fog_depth_end = 420.0
	env.fog_sky_affect = 0.0
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.56, 0.49, 0.41)   # a warm, lived-in workshop: walls and the bike's sides never go black
	env.ambient_light_energy = 0.32
	# real light bounce: daylight off the floor and brick fills the shed (SDFGI)
	env.sdfgi_enabled = true
	env.sdfgi_use_occlusion = true
	env.sdfgi_min_cell_size = 0.1
	env.sdfgi_cascades = 4
	env.sdfgi_energy = 1.0
	env.sdfgi_bounce_feedback = 0.6
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.0
	env.tonemap_white = 6.0
	env.ssao_enabled = true
	env.ssao_radius = 0.5
	env.ssao_intensity = 2.0
	env.ssil_enabled = true          # light bouncing between close surfaces (bike, floor, bench) on top of SDFGI
	env.ssil_radius = 3.0
	env.ssil_intensity = 0.8
	env.ssr_enabled = true
	env.ssr_max_steps = 96
	env.glow_enabled = true
	env.glow_intensity = 0.3
	env.glow_hdr_threshold = 1.2
	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = 0.004          # a little dust in the air: the beams show, the room stays clear
	env.volumetric_fog_albedo = Color(0.95, 0.9, 0.82)
	env.volumetric_fog_gi_inject = 0.1
	env.volumetric_fog_anisotropy = -0.1   # no glare haze looking down the shaft towards the door
	env.volumetric_fog_length = 14.0
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.16
	env.adjustment_saturation = 1.18
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
	# the roller door (RollerDoor: slats, hood, guides, bottom bar, wall switch), mounted on the wall's
	# inside face (z = WALL_IN), never cutting into the brick or sharing a face with it (shared faces flicker)
	var thr := StandardMaterial3D.new()   # brushed aluminium threshold strip
	thr.albedo_color = Color(0.62, 0.63, 0.65); thr.metallic = 1.0; thr.roughness = 0.4
	thr.normal_enabled = true; thr.normal_texture = load(RollerDoor.METAL % "normal"); thr.normal_scale = 0.5
	thr.roughness_texture = load(RollerDoor.METAL % "rough")
	thr.uv1_triplanar = true; thr.uv1_scale = Vector3.ONE / 0.4
	_box(Vector3(DOOR_W - 0.02, 0.03, 0.24), Vector3(DOOR_X, 0.015, -4.2), thr)
	# the curtain rolls up into the hood (animated the first time)
	door_slats = RollerDoor.build(self, DOOR_X, DOOR_W, DOOR_H, WALL_IN)
	door_open = 1.0 if _door_opened_once else 0.0
	var hold := Env.s("BMX_GARAGE_DOOR")   # tests: hold the door this far open (0 = shut, 1 = open)
	if hold != "":
		door_open = clampf(float(hold), 0.0, 0.999)
		_door_hold = true
	_place_slats()
	_box(Vector3(14.2, 5, 0.2), Vector3(0, 2.5, 7.8), wall)   # front wall (the side opposite the door)
	_box(Vector3(0.2, 5, 12), Vector3(-7, 2.5, 1.8), wall)
	_box(Vector3(0.2, 5, 12), Vector3(7, 2.5, 1.8), wall)
	_box(Vector3(14.2, 0.2, 12.2), Vector3(0, 5, 1.8), _mat(Color(0.08, 0.08, 0.09)))
	_probe("room shell")
	_build_outside()
	_probe("outside")
	# workbench + pegboard with tools on the left of the back wall
	var wood := _mat(Color("6b4a2b"), 0.7)
	var steel := _mat(Color(0.25, 0.27, 0.3), 0.4, 0.8)
	_box(Vector3(2.6, 0.08, 0.8), Vector3(-5.0, 0.92, -3.6), wood)
	for x in [-6.2, -3.8]:
		_box(Vector3(0.06, 0.9, 0.7), Vector3(x, 0.45, -3.6), steel)
	var peg := _mat(Color("a67c52"), 0.9)
	_box(Vector3(2.6, 1.3, 0.04), Vector3(-5.0, 1.8, -4.06), peg)
	var chrome := _mat(Color(0.8, 0.82, 0.85), 0.15, 1.0)
	# the tools on it, our parts on the bench, framesets + wheels on the wall: WorkshopProps, built after
	# the garage is on screen (a piece a frame)
	WorkshopProps.build_async.call_deferred(self)
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
	spot.light_volumetric_fog_energy = 0.35
	spot.shadow_enabled = true
	spot.shadow_blur = 1.5
	add_child(spot)
	# the bulb's own glow round the room (the shade only throws light down)
	var bulb := OmniLight3D.new()
	bulb.position = Vector3(0, 3.3, 0); bulb.light_color = Color(1.0, 0.78, 0.52)
	bulb.light_energy = 0.7; bulb.omni_range = 7.0; bulb.light_volumetric_fog_energy = 0.08
	add_child(bulb)
	# fluorescent strip over the bench
	var strip := StandardMaterial3D.new()
	strip.emission_enabled = true; strip.emission = Color(1.0, 0.9, 0.75); strip.emission_energy_multiplier = 2.5
	_box(Vector3(1.6, 0.04, 0.08), Vector3(-5.0, 2.6, -3.7), strip)   # just over the pegboard, under the wheels
	var fl_l := OmniLight3D.new()
	fl_l.position = Vector3(-5.0, 2.45, -3.4); fl_l.light_color = Color(1.0, 0.88, 0.7); fl_l.light_energy = 0.6; fl_l.omni_range = 4.0
	add_child(fl_l)
	# workshop lighting so the bike reads from every side (it went black once orbited off the doorway):
	# two cool-white ceiling tubes over the work area, a soft key from the front-right (true paint colour)
	# and a rim from behind that lifts the bike off the background
	var tube := StandardMaterial3D.new()
	tube.emission_enabled = true; tube.emission = Color(1.0, 0.9, 0.76); tube.emission_energy_multiplier = 3.0
	for tx in [-2.6, 2.6]:
		_box(Vector3(0.12, 0.05, 2.4), Vector3(tx, 4.55, 1.2), tube)
		_box(Vector3(0.2, 0.04, 2.5), Vector3(tx, 4.6, 1.2), steel)
		var tl := OmniLight3D.new()
		tl.position = Vector3(tx, 4.3, 1.2); tl.light_color = Color(1.0, 0.88, 0.72)
		tl.light_energy = 1.3; tl.omni_range = 8.0; tl.omni_attenuation = 0.8
		tl.light_volumetric_fog_energy = 0.03
		add_child(tl)
	var key := SpotLight3D.new()
	add_child(key)
	key.look_at_from_position(Vector3(2.8, 2.6, 3.2), Vector3(0, 0.8, 0), Vector3.UP)
	key.spot_range = 9.0; key.spot_angle = 38.0; key.spot_angle_attenuation = 1.2
	key.light_energy = 4.5; key.light_color = Color(1.0, 0.92, 0.82)
	key.shadow_enabled = true; key.shadow_blur = 2.5
	key.light_volumetric_fog_energy = 0.05
	var rim := SpotLight3D.new()
	add_child(rim)
	rim.look_at_from_position(Vector3(-2.6, 2.4, -3.2), Vector3(0, 1.0, 0), Vector3.UP)
	rim.spot_range = 8.0; rim.spot_angle = 35.0; rim.spot_angle_attenuation = 1.0
	rim.light_energy = 3.5; rim.light_color = Color(1.0, 0.86, 0.68)
	rim.light_volumetric_fog_energy = 0.03

const WEDGE_BACK := 8.0    # m: the view wedge's tip, inside the room behind the door
const WEDGE_DEG := 70.0    # each side of straight out

## The real procedural world outside the door: the world seed you ride, turned so you look down the
## start of the trail (+X in the world) through the doorway (-Z here), with the spawn point just
## outside the threshold and its ground level with the garage floor.
## The world out of the door is the same every visit for a seed: built once, it waits out of the tree when the
## garage closes (NOTIFICATION_PREDELETE) and the next garage of the session takes it back (~0.2-0.3 s saved,
## and no streaming). A new seed builds a new one; main frees it on quit (free_kept). BMX_GARAGE_NO_KEEP=1 = old.
static var _kept: Node3D = null
static var _kept_seed := 0
static var _kept_streaming := false

static var _app_closing := false   # set on quit: a garage deleted after that keeps nothing (nobody would free it)

static func free_kept(app_closing := false) -> void:
	if app_closing: _app_closing = true
	if is_instance_valid(_kept): _kept.free()   # out of the tree: its workers were joined when it left
	_kept = null

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and is_instance_valid(outside) and not _app_closing and Env.s("BMX_GARAGE_NO_KEEP") == "":
		free_kept()
		if outside.get_parent() == self: remove_child(outside)
		_kept = outside
		_kept_seed = GameState.seed
		_kept_streaming = _outside_terrain != null
		outside = null

func _build_outside() -> void:
	var spot := Vector2(-6.0, 0.0)   # just behind spawn on the flat hilltop: the trail runs away from here
	if is_instance_valid(_kept) and _kept_seed == GameState.seed:
		outside = _kept
		_kept = null
		add_child(outside)
		_outside_spot = spot
		if _kept_streaming: _outside_terrain = outside.get_node("Terrain")
		_probe("  outside kept")
	else:
		free_kept()
		_build_outside_terrain(spot)
	var sun := DirectionalLight3D.new()
	sun.light_color = Color(1.0, 0.8, 0.56)   # late-afternoon gold
	sun.light_energy = 2.2
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_max_distance = 120.0
	sun.light_volumetric_fog_energy = 12.0   # the shaft through the door
	add_child(sun)
	sun.look_at_from_position(SUN.normalized(), Vector3.ZERO, Vector3.UP)
	_build_sun_shaft()

func _build_outside_terrain(spot: Vector2) -> void:
	outside = Node3D.new()
	outside.name = "Outside"
	add_child(outside)
	var t = load("res://scripts/world/terrain.gd").new(GameState.seed)
	t.name = "Terrain"
	outside.add_child(t)
	_probe("  terrain new")
	# only the chunks that can be seen through the door: a wedge opening out of the door (+X in the world) from a
	# point WEDGE_BACK inside the room, WEDGE_DEG either side (wide: a camera beside the door sees far to the side).
	# Chunks behind / beside the building never show; ~40 % fewer to build. BMX_GARAGE_ALL_CHUNKS=1 = all of them.
	if Env.s("BMX_GARAGE_ALL_CHUNKS") == "":
		var apex := spot - Vector2(WEDGE_BACK, 0.0)
		var lim := deg_to_rad(WEDGE_DEG)
		t.stream_filter = func(k: Vector2i) -> bool:
			var c: Vector2 = Vector2(k) * 48.0   # (Terrain.SIZE)
			for fx in [-0.5, 0.0, 0.5]:
				for fz in [-0.5, 0.0, 0.5]:
					var d: Vector2 = c + Vector2(fx, fz) * 48.0 - apex
					if d.x > 0.0 and absf(atan2(d.y, d.x)) < lim: return true
			return false
	# only the 3 x 3 chunks round the door are built before the first frame (all 7 x 7 took ~1.3 s); the
	# outer ring streams in over the next frames (_process), on the first visit behind the closed door
	t.update_stream(spot.x, spot.y, INF, 1)
	_probe("  near chunks")
	_outside_terrain = t
	_outside_spot = spot
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

## Dusty air inside the shed (a FogVolume only indoors, so the view out of the door stays clear): the
## sun through the doorway shows as a slanted shaft, and dust motes drift in it (`sun_motes.gdshader`
## lights only the ones the sun can reach through the door).
func _build_sun_shaft() -> void:
	var fog := FogVolume.new()
	fog.shape = RenderingServer.FOG_VOLUME_SHAPE_BOX
	fog.size = Vector3(13.8, 4.9, 11.8)
	fog.position = Vector3(0, 2.45, 1.8)
	var fm := FogMaterial.new()
	fm.density = 0.02
	fm.albedo = Color(1.0, 0.97, 0.92)
	fm.edge_fade = 0.05
	fog.material = fm
	add_child(fog)
	var sd := SUN.normalized()
	# the box the shaft passes through inside the room: from the doorway down to where it meets the floor
	var lo := Vector3(INF, 0.05, WALL_IN + 0.05)
	var hi := Vector3(-INF, DOOR_H + 0.1, -INF)
	for cx in [DOOR_X - DOOR_W / 2.0, DOOR_X + DOOR_W / 2.0]:
		for cy in [0.0, DOOR_H]:
			var p := Vector3(cx, cy, -4.2)
			var q: Vector3 = p - sd * (cy / sd.y)   # down the shaft to the floor
			lo.x = minf(lo.x, minf(p.x, q.x)); hi.x = maxf(hi.x, maxf(p.x, q.x))
			hi.z = maxf(hi.z, q.z)
	var mid := (lo + hi) / 2.0
	var ext := (hi - lo) / 2.0 + Vector3(0.2, 0, 0.2)
	var motes := GPUParticles3D.new()
	motes.name = "SunMotes"
	motes.amount = 7000
	motes.lifetime = 16.0
	motes.preprocess = 16.0
	motes.local_coords = false
	motes.position = mid
	motes.visibility_aabb = AABB(-ext - Vector3.ONE, (ext + Vector3.ONE) * 2.0)
	motes.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = ext
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 180.0
	pm.initial_velocity_min = 0.0
	pm.initial_velocity_max = 0.025
	pm.gravity = Vector3(0, -0.003, 0)
	pm.damping_min = 0.0; pm.damping_max = 0.01
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 1.0
	pm.turbulence_noise_scale = 1.7   # smaller swirls: the motes wander about instead of all drifting one way
	pm.turbulence_noise_speed = Vector3(0.03, 0.015, 0.02)
	pm.turbulence_noise_speed_random = 1.0
	pm.turbulence_influence_min = 0.004   # some hang almost still, some get caught by the air
	pm.turbulence_influence_max = 0.07
	pm.scale_min = 0.4
	pm.scale_max = 1.2
	motes.randomness = 1.0
	pm.lifetime_randomness = 0.6
	var fade := Gradient.new()   # fade in and out over the life, no popping
	fade.offsets = PackedFloat32Array([0.0, 0.15, 0.85, 1.0])
	fade.colors = PackedColorArray([Color(1, 1, 1, 0), Color.WHITE, Color.WHITE, Color(1, 1, 1, 0)])
	var ramp := GradientTexture1D.new(); ramp.gradient = fade
	pm.color_ramp = ramp
	motes.process_material = pm
	var quad := QuadMesh.new()
	quad.size = Vector2(0.0045, 0.0045)
	var sm := ShaderMaterial.new()
	sm.shader = load("res://shaders/sun_motes.gdshader")
	sm.set_shader_parameter("sun_dir", sd)
	sm.set_shader_parameter("wall_z", -4.2)
	quad.material = sm
	_mote_mat = sm
	_place_slats()
	motes.draw_pass_1 = quad
	add_child(motes)

# ================================================================ bike
func _rebuild_bike() -> void:
	if hq: hq.reset()
	# keep the rider across part / paint changes: building one (helmet model, strap fitting) is the
	# slow part of a rebuild and would hitch on every click
	var keep: Rider = rider if rider_on and is_instance_valid(rider) else null
	if keep:
		keep.get_parent().remove_child(keep)
	var swap := _swap_next and rig != null and not rider_on
	_swap_next = false
	if swap:   # showroom: the old bike rolls away instead of vanishing (see _swap_step)
		if is_instance_valid(_leaving): _leaving.queue_free()
		_leaving = rig
		_leave_x0 = rig.position.x
		_leave_t = 0.0
	elif rig:
		rig.queue_free()
	rig = BikeRig.new()
	add_child(rig)
	var fid := _frame_id()
	var cfg: Dictionary = GameState.BIKES[fid] if GameState.BIKES[fid].get("garage", false) else GameState.BIKES.dh
	rig.load_bike(cfg, build)
	_probe("  bike load")
	var L := float(rig.extras.get("wheelbase", 1.25))
	var bb := float(rig.extras.get("bbToRearAxle", 0.44))
	# stand the bike in the middle of the bay, wheels on the floor
	if rig.susp:
		for i in 60:
			rig.susp.update(1.0 / 60, {"air": false, "load": 0.0, "brake": 0.0, "bumpF": 0.0, "bumpR": 0.0})
	bike_x = -(L / 2 - bb)
	rig.pose(bike_x, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0 if rider_on else -0.25, 0.0, 0.0, 0.6)
	# set the height from the real tyres (knob tips) and where the axles really sit after sag -- the
	# nominal radius and axle height left the tread a few mm inside the floor / the roller drums
	var tf := _tyre_circle(rig.wheel_f)
	var tr := _tyre_circle(rig.wheel_r)
	if rider_on:   # rear tyre resting on the two drums either side of its axle
		ride_y = DRUM_Y + sqrt(pow(tr.r + DRUM_R, 2) - DRUM_GAP * DRUM_GAP) - tr.c.y + 0.0005
	else:          # both tyres on the floor: the lower one just touches
		ride_y = -minf(tf.c.y - tf.r, tr.c.y - tr.r) + 0.0005
	rig.pose(bike_x, ride_y, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0 if rider_on else -0.25, 0.0, 0.0, 0.6)
	tf = _tyre_circle(rig.wheel_f)
	tr = _tyre_circle(rig.wheel_r)
	rig.set_meta("ride_y", ride_y)
	if not rider_on:   # parked: leaning over onto its stand, bars turned
		_show_pose(rig, bike_x, PARK_LEAN, PARK_STEER, 0.0, 0.0)
		# leaned over, the tyres no longer sit where the upright fit put them: measure round the casing and
		# drop (or lift) the bike until the lower tyre just touches the floor
		var floor0 := func(_x: float, _z: float) -> float: return 0.0
		var d := maxf(rig.tyre_depth(rig.wheel_f, tf.r, floor0), rig.tyre_depth(rig.wheel_r, tr.r, floor0))
		ride_y += d + 0.0005
		rig.set_meta("ride_y", ride_y)
		_show_pose(rig, bike_x, PARK_LEAN, PARK_STEER, 0.0, 0.0)
		# soft contact shadows where the tyres touch (they ride along when the bike rolls off / in)
		PartThumbs._ground_shadow(rig, 0.8)
		if Env.s("BMX_TYRE_PROBE") != "" or Env.s("BMX_GARAGE_PROBE") != "":
			var sh := []
			for c in rig.get_children():
				if c.has_meta("no_frame"): sh.append("%.3f,%.3f,%.3f" % [c.global_position.x, c.global_position.y, c.global_position.z])
			print("GARAGE park tyre depth f=%.4f r=%.4f (was %.4f) shadows=%s" % [rig.tyre_depth(rig.wheel_f, tf.r, floor0),
				rig.tyre_depth(rig.wheel_r, tr.r, floor0), d, sh])
	rider = null
	_build_rollers(tr.c.x, tf.c.x, tf.c.y - tf.r)
	if rider_on:
		_add_rider(keep)
	_update_stand_rider()
	_rider_visibility()
	for mi in rig.find_children("*", "MeshInstance3D", true, false):
		if mi.has_meta("no_frame"): continue   # the contact shadow quads cast nothing
		(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	if swap:
		_arrive_t = -SWAP_DELAY
		_swap_step(0.0)
	else:
		_arrive_t = INF

# ---------------------------------------------------------------- door sound
## the recording from `at` s, from the door's hood (3D: it comes from behind the bike)
func _door_sound(at: float) -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	p.stream = load(DOOR_SOUND)
	p.bus = Settings.bus_for("World")
	p.unit_size = 6.0
	p.position = Vector3(DOOR_X, DOOR_H, WALL_IN)
	add_child(p)
	p.play(at)
	p.finished.connect(p.queue_free)
	return p

## the door is up: the motor fades out, the stop clunk plays
func _door_stop() -> void:
	if is_instance_valid(_door_motor):
		var tw := create_tween()
		tw.tween_property(_door_motor, "volume_db", -40.0, 0.3)
		tw.tween_callback(_door_motor.queue_free)
	_door_motor = null
	_door_sound(DOOR_CLUNK_AT)

# ---------------------------------------------------------------- showroom: bikes roll out / in
## Picking another bike in the showroom, like a film cut: the parked bike stands itself up off its lean
## and straightens its bars, then rolls off forward, speeding up (the rear squats a touch as it pulls
## away). The new one rolls in from behind dead straight, brakes (the nose dips and springs back), and
## only once it has stopped settles over onto its lean while the bars swing round, with a small overshoot.
const PARK_LEAN := 0.085    # rad the parked bike leans over (away from the camera, onto its stand)
const PARK_STEER := -0.25   # rad the parked bars are turned
const OUT_UP_T := 0.45      # s: standing up + bars straight
const OUT_ROLL_T := 1.15    # s: rolling off (starts while it is still finishing standing up)
const OUT_ROLL_AT := 0.32
const IN_ROLL_T := 1.35     # s: rolling in and braking to a stop
const IN_PARK_T := 0.6      # s: leaning over + bars round
const SWAP_DELAY := 0.55    # the new one starts this long after the old one
const SWAP_D := 4.5         # m rolled (off screen at the showroom lens)
var _swap_next := false
var _leaving: BikeRig = null
var _leave_x0 := 0.0
var _leave_t := 0.0
var _arrive_t := INF

## a showroom bike drawn at x with this lean / bar angle, wheels turned by `roll` m, frame pitched
func _show_pose(r: BikeRig, x: float, lean: float, steer: float, roll: float, pitch: float, crank := 0.6) -> void:
	r.pose(x, float(r.get_meta("ride_y", ride_y)), 0.0, 0.0, pitch, 0.0, lean, steer,
		roll / r.wheel_rf, roll / r.wheel_rr, crank)

const SWAP_GEAR := 2.3   # wheel turns per crank turn riding away (a low gear: the pedals visibly go round)

static func _smooth(k: float) -> float:
	k = clampf(k, 0.0, 1.0)
	return k * k * k * (k * (k * 6.0 - 15.0) + 10.0)   # smootherstep

static func _back_out(k: float) -> float:   # eases out past 1 and back (a little overshoot)
	k = clampf(k, 0.0, 1.0) - 1.0
	return 1.0 + k * k * (2.7 * k + 1.7)

func _swap_step(dt: float) -> void:
	if is_instance_valid(_leaving):
		_leave_t += dt
		var up := _smooth(_leave_t / OUT_UP_T)                       # 0 parked -> 1 upright, bars straight
		var k := clampf((_leave_t - OUT_ROLL_AT) / OUT_ROLL_T, 0.0, 1.0)
		var d := SWAP_D * pow(k, 2.3)                                # pulling away, faster and faster
		var squat := 0.018 * sin(PI * minf(k * 2.2, 1.0))            # the rear sits down as it accelerates
		# pedalled away: the cranks go round with the back wheel through the gear
		_show_pose(_leaving, _leave_x0 + d, PARK_LEAN * (1.0 - up), PARK_STEER * (1.0 - up), d, squat,
			0.6 + d / _leaving.wheel_rr / SWAP_GEAR)
		if k >= 1.0:
			_leaving.queue_free()
			_leaving = null
	if _arrive_t < INF and rig:
		_arrive_t += dt
		var k := clampf(_arrive_t / IN_ROLL_T, 0.0, 1.0)
		var e := 1.0 - pow(1.0 - k, 3.0)                             # braking: fast in, slow to a stop
		var rest := SWAP_D * (1.0 - e)
		# the nose dips under the brakes near the end and springs back once stopped
		var dive := -0.022 * sin(PI * clampf((k - 0.55) / 0.45, 0.0, 1.0))
		var t2 := (_arrive_t - IN_ROLL_T) / IN_PARK_T
		if t2 > 0.0:
			dive = 0.012 * sin(t2 * 9.0) * exp(-t2 * 5.0)              # rebound, dying out
		var park := _back_out(t2) if t2 > 0.0 else 0.0
		_show_pose(rig, bike_x - rest, PARK_LEAN * minf(park, 1.08), PARK_STEER * park, -rest, dive)
		if t2 >= 1.0:
			_show_pose(rig, bike_x, PARK_LEAN, PARK_STEER, 0.0, 0.0)
			_arrive_t = INF

# ---------------------------------------------------------------- the rider on the bike
## the rider in the garage: same look and pose (sliders) as on the trail, posed every frame from the
## bike's grips and pedals like a ride, in the chosen preview situation
func _add_rider(existing: Rider = null) -> void:
	rider = existing if existing else Rider.new()
	rig.lean_g.add_child(rider)
	if rig.seat != null: rider.seat = rig.seat
	var grip := rig.grip_mid()
	rider.fit = Vector3((grip.x - 0.4388) * 0.5, ((grip.y - 0.9646) + (rig.crank_n.position.y - 0.297)) * 0.5, 0)
	if existing:
		return
	rider.set_look(RiderPanels.load_look())
	rider.set_style(rider_pose)
	rider.use_helmet(str(rider.look.get("helmet", "glory")))

## training rollers: an alloy frame with two drums under the rear tyre and one under the front;
## only there while the rider is on (the bike stands on them and spins in place)
## a wheel's tyre as a circle in the garage: {c: hub (world), r: outer radius to the knob tips}. The
## tyre is the widest round mesh on the wheel; its own bounding box is unaffected by the wheel's spin.
func _tyre_circle(w: Node3D) -> Dictionary:
	var best := {"c": w.global_position, "r": 0.0}
	for mi in w.find_children("*", "MeshInstance3D", true, false):
		if not (mi as MeshInstance3D).visible or (mi as MeshInstance3D).mesh == null: continue
		var bx: AABB = (mi as MeshInstance3D).mesh.get_aabb()
		var xf: Transform3D = (mi as MeshInstance3D).global_transform
		var r := bx.size.y * 0.5 * xf.basis.get_scale().y
		if r > best.r:
			best = {"c": xf * bx.get_center(), "r": r}
	return best

## rollers under the bike: rear_x / front_x = the axles, front_low = the front tyre's lowest point
func _build_rollers(rear_x: float, front_x: float, front_low: float) -> void:
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
		d.position = Vector3(x, DRUM_Y if x != front_x else front_low - DRUM_R - 0.0005, 0)
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
		stand_rider.use_helmet(str(stand_rider.look.get("helmet", "glory")))
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
	if stand_rider.animate(dt): return   # Mixamo clips (RiderAnim), if there are any
	var breathe := sin(hand_t * 1.6) * 0.006
	stand_rider.update_pose(dt, {"footL": Vector3(0.0, 0.0, -0.13), "footR": Vector3(0.02, 0.0, 0.13),
		"handL": Vector3(0.02, 0.83 + breathe, -0.29), "handR": Vector3(0.04, 0.83 + breathe, 0.29),
		"v": 0.0, "lean": 0.0, "steer": 0.0, "yawRate": 0.0, "counter": 0.0, "rockRoll": 0.0, "headRoll": 0.0,
		"absorb": breathe, "pitch": 0.0, "bodyLevel": 0.85, "attackDrop": 0.0, "pedal": 0.0, "sprint": 0.0,
		"crank": 0.0, "air": 0.0, "compress": 0.0, "hipShift": 0.0, "t": hand_t, "stand": 1.0, "relax": 1.0})

const PREVIEWS := {
	# coasting is the showcase pose: relaxed, sat on the saddle and sitting up (no attack crouch)
	"coast": {"label": "Coasting", "pedal": 0.0, "pitch": 0.0, "air": 0.0, "compress": 0.0, "v": 4.0, "pose_v": 1.0, "body": -0.55, "drop": 0.0, "relax": 1.0},
	"pedal": {"label": "Pedalling", "pedal": 1.0, "pitch": 0.0, "air": 0.0, "compress": 0.0, "v": 6.0},
	"sprint": {"label": "Sprinting", "pedal": 1.0, "sprint": 1.0, "pitch": 0.0, "air": 0.0, "compress": 0.0, "v": 9.0},
	"descend": {"label": "Descending", "pedal": 0.0, "pitch": -0.35, "air": 0.0, "compress": 0.06, "v": 10.0},
	"air": {"label": "In the air", "pedal": 0.0, "pitch": 0.1, "air": 1.0, "compress": 0.1, "v": 10.0},
}

func _pose_rider(dt: float) -> void:
	if rider == null or not is_instance_valid(rider): return
	var P: Dictionary = PREVIEWS[rider_preview]
	# the same pedalling as a ride (BikePhysics): wheels turn at the preview speed, the cranks follow
	# through the build's chainring + start cog and the Top speed tuning, the bike rocks with the stroke
	var spr: float = P.get("sprint", 0.0)
	var v: float = P.v if P.pedal > 0.5 else 2.0   # coasting / poses: the wheels keep turning on the drums
	_spin_on_rollers(dt, v)
	var rock := 0.0
	if P.pedal > 0.5:
		var m := BikeBuild.ride_mods(build)
		var cogs: Array = m.cogs
		var g := BikePhysics.start_gear(cogs, m.ring_k)
		var gk: float = m.ring_k * 16.0 / float(cogs[maxi(g, 0)])
		var ts: float = Tune.v.topSpeed * float((m.ride as Dictionary).get("topSpeed", 1.0))
		preview_crank += BikePhysics.crank_rate(v / rig.wheel_rf, gk, ts, spr) * dt
		rig.crank_n.rotation.z = -preview_crank
		for pv in rig.pedal_pivots: pv.rotation.z = preview_crank
		var br: float = float(rider.style.get("bikeRock", 1.0)) if rider.get("style") is Dictionary else 1.0
		rock = BikePhysics.pedal_rock(preview_crank, spr, 1.0, v, br)
	rig.lean_g.rotation = Vector3(-rock, 0, 0)
	var lt := rig.limb_targets()
	rider.update_pose(dt, {"footL": lt.footL, "footR": lt.footR, "handL": lt.handL, "handR": lt.handR, "gripX_L": lt.gripX_L, "gripX_R": lt.gripX_R, "gripZ": lt.gripZ,
		"v": P.get("pose_v", P.v), "bodyStick": P.get("body", 0.0), "relax": P.get("relax", 0.0), "lean": rock, "steer": 0.0, "yawRate": 0.0, "counter": 0.0, "rockRoll": rock, "headRoll": 0.0,
		"absorb": 0.0, "pitch": P.pitch, "bodyLevel": 0.85, "attackDrop": P.get("drop", 0.18), "pedal": P.pedal,
		"sprint": P.get("sprint", 0.0), "crank": preview_crank, "air": P.air, "inAir": P.air, "compress": P.compress, "hipShift": 0.0, "t": hand_t,
		"pedalTop": rig.pedal_top_in(rider)})
	# the pedals turn with the feet (foot angle + ankling), about their axle
	if rig.pedal_pivots.size() == 2:
		for fi in 2: rig.pedal_pivots[fi].rotation.z = preview_crank + rider.foot_pitch[fi]

## the frame the garage shows: in the shop the one on show, else the player's
func _frame_id() -> String:
	if mode == "shop" and _shop_frame != "": return _shop_frame
	return GameState.bike_id

## the shop: a bike / frameset onto the stand (rolls in when `swap`) or a part fitted to the bike on show
func shop_show(frame: String, b: Dictionary, swap: bool) -> void:
	_shop_frame = frame
	build = b
	_swap_next = swap
	_rebuild_bike()
	_update_stats()

## the shop's room: the photo studio, its environment, no door / workshop / world outside
func _build_studio() -> void:
	studio = StudioSet.new()
	add_child(studio)
	var we := WorldEnvironment.new()
	we.environment = studio.env
	add_child(we)
	door_open = 1.0
	_door_hold = true

func _changed() -> void:
	_dirty = 0.12   # rebuild after the slider settles
	if hq: hq.reset()
	_update_stats()

# ================================================================ camera
## slats ride up by door_open * DOOR_H; any that reach the drum disappear into it
func _place_slats() -> void:
	var lift := DOOR_H * door_open
	if _mote_mat:   # the motes light up only as far as the door has opened
		_mote_mat.set_shader_parameter("door", Vector4(DOOR_X - DOOR_W / 2.0, DOOR_X + DOOR_W / 2.0, -1.0, lift))
	for mi in door_slats.get_children():
		var y: float = mi.get_meta("y0") + lift
		mi.position.y = y
		mi.visible = y < DOOR_H + 0.3   # higher up it is inside the drum

func _process(dt: float) -> void:
	_swap_step(dt)
	if dt > 0.04 and _probe_frames >= 60 and Env.s("BMX_GARAGE_PROBE") != "":
		print("GARAGESLOW dt_ms=%.0f tab=%s thumbs_busy=%s" % [dt * 1000.0, tab, thumbs._busy if thumbs else false])
	var probe := _probe_frames < 60 and Env.s("BMX_GARAGE_PROBE") != ""
	if probe:
		_probe_frames += 1
		print("GARAGEFRAME %d dt_ms=%.1f pipelines=%d thumbs_busy=%s" % [_probe_frames, dt * 1000.0,
			RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_DRAW), thumbs._busy if thumbs else false])
	if _outside_terrain != null:   # the far chunks out of the door, a few ms a frame
		var t0 := Time.get_ticks_usec()
		_outside_terrain.update_stream(_outside_spot.x, _outside_spot.y, 3.0)
		if probe: print("  stream_ms=%.1f" % ((Time.get_ticks_usec() - t0) / 1000.0))
		if _outside_terrain.stream_complete():
			var n_chunks: int = _outside_terrain.chunks.size()
			_outside_terrain = null
			if Env.s("BMX_GARAGE_PROBE") != "":
				print("GARAGE outside streamed after ms=%.0f chunks=%d" % [(Time.get_ticks_usec() - _open_t) / 1000.0, n_chunks])
	if door_open < 1.0 and not _door_hold:
		door_t += minf(dt, 0.05)   # the first frame after the long build has a huge dt: don't let it eat the wait
		var k := clampf((door_t - DOOR_DELAY) / DOOR_TIME, 0.0, 1.0)
		var e := k * k * (3.0 - 2.0 * k)
		door_open = minf(1.0, e + sin(k * 37.0) * 0.004 * (1.0 - k) * k * 4.0)   # a little motor judder
		if door_t >= DOOR_DELAY and _door_motor == null:
			_door_motor = _door_sound(0.0)
		if k >= 1.0:
			door_open = 1.0
			_door_opened_once = true
			_door_stop()
		_place_slats()
	if _dirty > 0:
		_dirty -= dt
		if _dirty <= 0: _rebuild_bike()
	if _pose_save_t > 0.0:
		_pose_save_t -= dt
		if _pose_save_t <= 0.0: _flush_pose()
	if auto_spin and not dragging: orbit_t += dt * 0.12
	# Xbox: right stick orbits the camera, LT / RT zoom (raw axes: menus own the D-pad / left stick)
	var rs := Vector2(Input.get_joy_axis(0, JOY_AXIS_RIGHT_X), Input.get_joy_axis(0, JOY_AXIS_RIGHT_Y))
	_idle_t += dt
	if rs.length() > 0.2:
		_idle_t = 0.0
		orbit_t -= rs.x * dt * 2.2
		pitch_t = clampf(pitch_t + rs.y * dt * 60.0, -2, 70)
		auto_spin = false
	var zt := Input.get_joy_axis(0, JOY_AXIS_TRIGGER_RIGHT) - Input.get_joy_axis(0, JOY_AXIS_TRIGGER_LEFT)
	if absf(zt) > 0.15: _idle_t = 0.0
	if absf(zt) > 0.15: dist_t = clampf(dist_t * (1.0 - zt * dt * 1.2), 1.2, 7)
	orbit = lerpf(orbit, orbit_t, minf(1.0, dt * 4))
	cam.fov = lerpf(cam.fov, SHOW_FOV if (not editing and mode == "bike") or mode == "shop" else 38.0, minf(1.0, dt * 4))
	pitch = lerpf(pitch, pitch_t, minf(1.0, dt * 4))
	dist = lerpf(dist, dist_t, minf(1.0, dt * 4))
	var head_env := Env.s("BMX_GARAGE_HEAD")
	if head_env == "bike" and rider and rider_on:   # tests: frame the head + neck of the rider on the bike
		focus_t = rider.head.global_position + Vector3(0, -0.05, 0)
	elif head_env == "waist" and stand_rider and stand_rider.is_visible_in_tree():   # tests: the belt / jersey hem (standing rider, else the one on the bike)
		focus_t = stand_rider.pelvis_mesh.global_position + Vector3(0, 0.05, 0)
	elif head_env == "waist" and rider and rider_on:
		focus_t = rider.pelvis_mesh.global_position + Vector3(0, 0.05, 0)
	elif stand_rider and head_env == "neck":   # tests: the standing rider's neck, collar + goggle strap
		focus_t = stand_rider.head.global_position + Vector3(0, -0.1, 0)
	elif stand_rider and head_env != "":   # tests: frame the standing rider's helmet
		focus_t = stand_rider.head.global_position + Vector3(0, 0.15, 0)
	var aim := Env.raw("BMX_GARAGE_AIM").split(",", false)   # tests: "x,y,z" = look at this point
	if aim.size() == 3: focus_t = Vector3(float(aim[0]), float(aim[1]), float(aim[2]))
	focus = focus.lerp(focus_t, minf(1.0, dt * 4))
	var p := deg_to_rad(pitch)
	# never swing below the floor: lift the pitch so the camera stays above it at the full distance
	# (shrinking the distance instead made the camera jump to full zoom under the bike)
	var floor_y := ROOM_MIN.y + 0.35
	var d_cam := maxf(dist, 0.5)
	var s_min := (floor_y - focus.y) / d_cam
	if s_min > -1.0 and sin(p) < s_min:
		p = asin(clampf(s_min, -1.0, 1.0))
	var dir := Vector3(sin(orbit) * cos(p), sin(p), cos(orbit) * cos(p))
	var reach := _room_reach(focus, dir)
	cam.position = focus + dir * (minf(dist, reach) if reach < INF else dist)
	cam.position.y = maxf(cam.position.y, floor_y)
	cam.look_at(focus, Vector3.UP)
	# HANDHELD: someone holding the camera -- a slow few-cm drift and a fraction of a degree of wobble,
	# from a few unrelated sine waves (never repeats visibly, never jerks)
	if _idle_t < HQ_IDLE or hq == null: hand_t += dt   # resting: the sway holds still (a still can build)
	_pose_rider(dt)
	_pose_stand_rider(dt)
	# kept very small and slow (HANDHELD, HANDHELD_SPEED): the stronger sway made the player motion sick
	var t := hand_t * HANDHELD_SPEED
	var k := HANDHELD
	cam.position += cam.basis * Vector3(
		(sin(t * 0.53) + 0.6 * sin(t * 1.31 + 1.7)) * 0.018 * k,
		(sin(t * 0.71 + 0.4) + 0.5 * sin(t * 1.77 + 2.9)) * 0.012 * k,
		sin(t * 0.37 + 2.2) * 0.02 * k)
	cam.rotate_object_local(Vector3.RIGHT, (sin(t * 0.83 + 0.9) + 0.4 * sin(t * 2.1)) * 0.0022 * k)
	cam.rotate_object_local(Vector3.UP, (sin(t * 0.61 + 3.1) + 0.4 * sin(t * 1.9 + 0.5)) * 0.0028 * k)
	# (no roll: a tilting horizon is the worst for motion sickness)
	cam.h_offset = 0.0   # the bike sits in the middle of the frame
	if hq:
		hq.enabled = dragging == false and _idle_t >= HQ_IDLE and _leaving == null and _arrive_t == INF \
			and (door_open >= 1.0 or _door_hold) and _dirty <= 0.0

func _unhandled_input(e: InputEvent) -> void:
	if Dev.on and mode == "rider" and e is InputEventKey and e.pressed and not e.echo and e.keycode == KEY_INSERT:
		anim_requested.emit()
		return
	if e is InputEventMouseButton or (e is InputEventMouseMotion and dragging):
		_idle_t = 0.0
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
		_back()
	elif editing and e is InputEventKey and e.pressed and not e.echo and (e.physical_keycode == KEY_Q or e.physical_keycode == KEY_E):
		_step_tab(-1 if e.physical_keycode == KEY_Q else 1)   # key position (AZERTY etc.), like every ride key

# ================================================================ UI
## tests (BMX_TYRE_PROBE=1): every wheel-size / tyre-width combination, rider off and on: how far the
## lowest point of each tyre is from the floor (or the roller drums), then quit. Nothing is saved.
func _tyre_probe() -> void:
	var lowest := func(n: Node3D) -> float:
		var lo := INF
		for mi in n.find_children("*", "MeshInstance3D", true, false):
			if not (mi as MeshInstance3D).visible or (mi as MeshInstance3D).mesh == null: continue
			var xf: Transform3D = (mi as MeshInstance3D).global_transform
			for s in mi.mesh.get_surface_count():
				for v in (mi.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX] as PackedVector3Array):
					lo = minf(lo, (xf * v).y)
		return lo
	for on in [false, true]:
		rider_on = on
		for fr in [["26", "26"], ["27.5", "27.5"], ["29", "29"], ["29", "27.5"]]:
			for tw in [2.2, 2.5, 2.8]:
				build.wheels.front = fr[0]; build.wheels.rear = fr[1]; build.wheels.tyre_w = tw
				_rebuild_bike()
				for i in 5: await get_tree().process_frame
				var f: float
				var r: float
				if not on:   # standing on the floor: the lowest point of each tyre (0 = touching)
					f = lowest.call(rig.wheel_f); r = lowest.call(rig.wheel_r)
				else:        # on the rollers: closest approach of each tyre to its drum(s) (0 = touching)
					f = _drum_gap(rig.wheel_f); r = _drum_gap(rig.wheel_r)
				print("TYRE rider=%s front=%s rear=%s w=%.1f  front=%+.4f  rear=%+.4f" % [on, fr[0], fr[1], tw, f, r])
	GameState.quit()

## tests: the smallest distance from a wheel's visible vertices to the surface of any roller drum
## (drums run along z; negative = the tyre cuts into a drum)
func _drum_gap(n: Node3D) -> float:
	var best := INF
	for d in drums:
		var c: Vector3 = (d as Node3D).global_position
		for mi in n.find_children("*", "MeshInstance3D", true, false):
			if not (mi as MeshInstance3D).visible or (mi as MeshInstance3D).mesh == null: continue
			var xf: Transform3D = (mi as MeshInstance3D).global_transform
			for s in mi.mesh.get_surface_count():
				for v in (mi.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX] as PackedVector3Array):
					var p := xf * v
					best = minf(best, Vector2(p.x - c.x, p.y - c.y).length() - DRUM_R)
	return best

## the garage UI is drawn smaller than the game's menus so the bike stays in view
const UI_SCALE := 0.82
const INK := Tokens.INK
const SUB := Tokens.INK_SOFT
const LINE := Tokens.LINE
const BIKE_TABS := [["paint", "PAINT"], ["logos", "LOGOS"], ["wheels", "WHEELS"], ["bars", "BARS"], ["suspension", "SHOCKS"],
	["brakes", "BRAKES"], ["drive", "GEARS"]]
const RIDER_TABS := [["rider", "POSITION"], ["kit", "KIT"]]
func _tabs() -> Array:
	if mode == "shop": return Catalog.TABS.map(func(t): return [t[0], t[1]])
	return RIDER_TABS if mode == "rider" else BIKE_TABS
func _has_tab(t: String) -> bool:
	for x in _tabs():
		if x[0] == t: return true
	return false
const EDGE := Tokens.S7          # gap between the cards and the screen edge
const BUILD_W := 330             # the build card (top right)
const STAT_LABEL_W := 112
const RIDE_W := 210

func _build_ui() -> void:
	thumbs = PartThumbs.new()
	add_child(thumbs)
	var root := Control.new()
	root.theme = UITheme.paper_theme()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(root)
	# draw the whole layer scaled down; the root is sized up to match so anchors still reach the edges
	ui.scale = Vector2(UI_SCALE, UI_SCALE)
	var fit := func(): root.size = get_viewport().get_visible_rect().size / UI_SCALE
	fit.call()
	get_viewport().size_changed.connect(fit)
	# header card: GARAGE + the category bar (Q / E or click)
	var head_card := PanelContainer.new()
	var hs := UITheme.card_style(); hs.content_margin_top = Tokens.S2; hs.content_margin_bottom = 0
	head_card.add_theme_stylebox_override("panel", hs)
	head_card.position = Vector2(EDGE, EDGE)
	root.add_child(head_card)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", Tokens.S6)
	head_card.add_child(head)
	var title := UITheme.display({"rider": "RIDER", "shop": "SHOP"}.get(mode, "GARAGE"), Tokens.T_3XL, INK, Tokens.SLANT_TITLE)
	title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(title)
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", Tokens.S1)
	head.add_child(bar)
	_edit_only.append(bar)
	bar.add_child(UITheme.key_cap("LB" if Settings.pad_active else "Q"))
	var grp := ButtonGroup.new()
	for t in _tabs():
		var b := UITheme.make_button(t[1], _set_tab.bind(t[0]), "tab", Tokens.T_XL)
		b.toggle_mode = true; b.button_group = grp
		b.button_pressed = t[0] == tab
		b.focus_mode = Control.FOCUS_NONE
		bar.add_child(b)
		tab_buttons[t[0]] = b
	bar.add_child(UITheme.key_cap("RB" if Settings.pad_active else "E"))
	if mode == "shop": head.add_child(store.make_wallet())
	# the options card under it
	panel = PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	panel.offset_left = EDGE; panel.offset_right = EDGE + Tokens.CARD_W
	panel.offset_top = EDGE + Tokens.H_CHIP + Tokens.S6 + Tokens.S5; panel.offset_bottom = -(EDGE + Tokens.H_BTN + Tokens.S5)
	root.add_child(panel)
	_edit_only.append(panel)
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	SmoothScroll.attach(sc)
	panel.add_child(sc)
	body = VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", Tokens.S3)
	sc.add_child(body)
	# the build card, top right: name + performance meters (the garage only)
	if mode == "bike" or mode == "shop":
		_build_card(root)
		_showroom(root)
	_bottom_bar(root)
	# Xbox: D-pad / stick between rows, left / right change a value, A press, B back, LB / RB categories
	PadNav.attach(root, {"tabs": func(d): if editing: _step_tab(d), "back": _back})

## the showroom's frame strip: a big picture of every frame with the garage build, bottom centre
func _showroom(root: Control) -> void:
	var card := PanelContainer.new()
	# a white band behind the frame cards only (from its left end), lined up with the button row under it: from BACK's
	# left edge to SAVE & RIDE's right edge; the buttons stay below it, over the room
	var band := UITheme.box(Color.WHITE, Tokens.R_SM, 0)
	band.content_margin_left = Tokens.S3; band.content_margin_right = Tokens.S3
	band.content_margin_top = Tokens.S3; band.content_margin_bottom = Tokens.S3
	card.add_theme_stylebox_override("panel", band)
	card.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	card.offset_left = EDGE; card.offset_right = -EDGE
	card.offset_bottom = -(EDGE + Tokens.H_BTN + Tokens.S5); card.offset_top = card.offset_bottom - SHOW_H - Tokens.S3 * 2
	root.add_child(card)
	_show_only.append(card)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", Tokens.S2)
	card.add_child(col)
	_show_strip = PicStrip.new(Tokens.S3)
	_show_strip.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_show_strip.row.alignment = BoxContainer.ALIGNMENT_BEGIN   # the first frame at the strip's left end
	_show_strip.row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(_show_strip)
	if mode == "bike": _fill_showroom()   # (the shop fills it per tab: StorePage)

const SHOW_FOV := 30.0   # the showroom: a longer lens, flatter product-shot look
const SHOW_H := 250.0
const SHOW_CARD := Vector2(330, 236)

var _show_pick := ""   # the showroom card in use: a frame id (your build on it) or "ed:<edition>"

func _fill_showroom() -> void:
	for c in _show_strip.row.get_children(): c.queue_free()
	var own := []
	for id in GameState.BIKES:
		if not GameState.BIKES[id].get("garage", false): continue
		var saved := BikeBuild.load_build(id)   # the frame cards show your saved build (with this frame's paint), whatever edition is up
		own.append({"key": id, "brand": "YOUR BUILD", "name": String(GameState.BIKES[id].label), "spec": _bike_line(id, saved),
			"thumb": PartThumbs.build_key(id, saved), "kind": "frame", "make": PartThumbs.make_bike_build.bind(id, saved),
			"view": Vector3(0.45, 0.2, 1.0), "speed": BikeBuild.stats(saved, id)["Top speed"]})
	# the editions: the same frames, factory colourways + part mixes, each set up for a riding style
	var eds := []
	for e in BikeBuild.EDITIONS:
		var ed: Dictionary = BikeBuild.EDITIONS[e]
		var eb := BikeBuild.edition_build(e)
		var style := String(BikeBuild.STYLES[ed.get("style", "allround")].label).to_upper()
		eds.append({"key": "ed:" + e, "brand": "%s  ·  %s" % [style, String(GameState.BIKES[ed.frame].label).to_upper()],
			"name": String(ed.label), "spec": _bike_line(ed.frame, eb),
			"thumb": PartThumbs.build_key(ed.frame, eb), "kind": "edition", "make": PartThumbs.make_bike_build.bind(ed.frame, eb),
			"view": Vector3(0.45, 0.2, 1.0), "speed": BikeBuild.stats(eb, ed.frame)["Top speed"]})
	# slow -> fast: your bikes first, then the editions
	var by_speed := func(a: Dictionary, b: Dictionary) -> bool: return float(a.speed) < float(b.speed)
	own.sort_custom(by_speed)
	eds.sort_custom(by_speed)
	var items := own + eds
	if _show_pick == "": _show_pick = GameState.bike_id
	_cards(items, _show_pick, func(v):
		if v == _show_pick: return
		if v.begins_with("ed:"):   # an edition: its frame + build, to ride as it is or to edit (SAVE keeps it)
			var e: String = v.substr(3)
			if not _show_pick.begins_with("ed:"): BikeBuild.save_build(build)   # (your own build stays saved)
			build = BikeBuild.edition_build(e)
			GameState.bike_id = BikeBuild.EDITIONS[e].frame
		else:
			if not _show_pick.begins_with("ed:"): BikeBuild.save_build(build)
			GameState.bike_id = v
			build = BikeBuild.load_build(v)   # your build, in this frame's own paint
		_show_pick = v
		GameState.save()
		_swap_next = true   # the old bike rolls off, the new one rolls in
		_rebuild_bike()
		_update_stats()
		_fill_showroom.call_deferred(), false, _show_strip, SHOW_CARD)

## showroom (false) / customizer (true)
func _set_edit(on: bool, open_page := true) -> void:
	editing = on
	for c in _edit_only: if is_instance_valid(c): c.visible = on
	for c in _show_only: if is_instance_valid(c): c.visible = not on
	if on and open_page:
		tab = ""
		_set_tab("paint")
	elif not on:
		var v: Array = VIEWS["show"]
		orbit_t = v[0] + round((orbit_t - v[0]) / TAU) * TAU
		pitch_t = v[1]; dist_t = v[2]; focus_t = v[3]
		auto_spin = false   # the showroom camera stands still

## BACK / Esc / pad B: the customizer goes back to the showroom, the showroom leaves the garage
func _back() -> void:
	if mode == "bike" and editing: _set_edit(false)
	else: _close(false)

func _build_card(root: Control) -> void:
	var sp := PanelContainer.new()
	sp.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	sp.offset_left = -(EDGE + BUILD_W); sp.offset_right = -EDGE; sp.offset_top = EDGE
	root.add_child(sp)
	_edit_only.append(sp)
	stats_box = VBoxContainer.new()
	stats_box.add_theme_constant_override("separation", Tokens.S2)
	sp.add_child(stats_box)
	stats_box.add_child(UITheme.caption("ON SHOW" if mode == "shop" else "YOUR BUILD"))
	var name_e := LineEdit.new()
	name_e.text = build.name
	name_e.placeholder_text = "Bike name"
	name_e.add_theme_font_override("font", UITheme.display_font(Tokens.W_BLACK, Tokens.SLANT))
	name_e.add_theme_font_size_override("font_size", Tokens.T_2XL)
	var clear := UITheme.btn_box(Tokens.CLEAR, Tokens.CLEAR, 0, 0, 0)
	name_e.add_theme_stylebox_override("normal", clear)
	name_e.add_theme_stylebox_override("focus", UITheme.marked(Tokens.CLEAR, Tokens.ACCENT, SIDE_BOTTOM, 0, 0))
	name_e.text_changed.connect(func(t): build.name = t)
	if mode != "shop": stats_box.add_child(name_e)
	for k in BikeBuild.stats(build, _frame_id()):
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", Tokens.S3)
		var l := UITheme.caption(k.to_upper(), INK)
		l.custom_minimum_size.x = STAT_LABEL_W
		row.add_child(l)
		var sbar := StatBar.new()
		sbar.custom_minimum_size.y = Tokens.S4
		sbar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sbar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(sbar)
		stats_box.add_child(row)
		_stat_bars[k] = sbar
	_class_lbl = UITheme.caption("", INK, Tokens.T_SM)   # ★★★☆☆  ·  RACE  ·  16.8 KG
	stats_box.add_child(_class_lbl)
	# the part under the cursor / pad focus: what it is and what fitting it would change (_part_preview)
	_part_box = VBoxContainer.new()
	_part_box.add_theme_constant_override("separation", 0)
	_part_box.visible = false
	stats_box.add_child(_part_box)
	_update_stats()

## bottom bar: back / stock / randomise left, hints in the middle, save + ride right
## (the rider room: back, hints, ride; its changes save as they're made)
func _bottom_bar(root: Control) -> void:
	var bot := HBoxContainer.new()
	bot.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bot.offset_left = EDGE; bot.offset_right = -EDGE; bot.offset_top = -(EDGE + Tokens.H_BTN); bot.offset_bottom = -EDGE
	bot.add_theme_constant_override("separation", Tokens.S3)
	root.add_child(bot)
	var mk := func(text: String, cb: Callable, kind := "secondary") -> Button:
		var b := UITheme.make_button(text, cb, kind, Tokens.T_XL if kind == "primary" else Tokens.T_LG)
		b.custom_minimum_size.y = Tokens.H_BTN
		return b
	bot.add_child(mk.call("BACK", _back))
	if mode == "bike":
		var stock: Button = mk.call("STOCK", func(): build = BikeBuild.default_build(); _rebuild_bike(); _set_tab(tab); _update_stats())
		var rnd: Button = mk.call("RANDOMISE", _randomise)
		bot.add_child(stock); bot.add_child(rnd)
		_edit_only.append_array([stock, rnd])
	var spacer := Control.new(); spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL; bot.add_child(spacer)
	var pill := PanelContainer.new()
	var ps := UITheme.card_style(Tokens.PILL, Tokens.R_PILL, Tokens.S4); ps.content_margin_top = Tokens.S2; ps.content_margin_bottom = Tokens.S2
	pill.add_theme_stylebox_override("panel", ps)
	pill.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var hints := HBoxContainer.new()
	hints.add_theme_constant_override("separation", Tokens.S2)
	pill.add_child(hints)
	var first := true
	var hint_list := [["DRAG", "rotate"], ["WHEEL", "zoom"], ["Q E", "category"], ["ESC", "back"]]
	if Settings.pad_active: hint_list = [["RS", "rotate"], ["LT RT", "zoom"], ["LB RB", "category"], ["B", "back"]]
	for h in hint_list:
		if not first:
			var gap := Control.new(); gap.custom_minimum_size.x = Tokens.S3; hints.add_child(gap)
		first = false
		hints.add_child(UITheme.key_cap(h[0]))
		hints.add_child(UITheme.caption(h[1].to_upper(), INK))
	bot.add_child(pill)
	if mode == "bike": _edit_only.append(pill)
	var spacer2 := Control.new(); spacer2.size_flags_horizontal = Control.SIZE_EXPAND_FILL; bot.add_child(spacer2)
	if mode == "bike":
		var ed: Button = mk.call("EDIT", func(): _set_edit(true))
		ed.custom_minimum_size.x = RIDE_W
		bot.add_child(ed)
		_show_only.append(ed)
		var sv: Button = mk.call("SAVE", func(): BikeBuild.save_build(build); _toast("SAVED"))
		bot.add_child(sv)
		_edit_only.append(sv)
	if mode != "shop":
		var ride: Button = mk.call("SAVE & RIDE" if mode == "bike" else "RIDE", func(): _close(true), "primary")
		ride.custom_minimum_size.x = RIDE_W
		bot.add_child(ride)
	_file_dialog = FileDialog.new()
	_file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_file_dialog.filters = PackedStringArray(["*.png ; PNG images"])
	_file_dialog.use_native_dialog = true
	_file_dialog.file_selected.connect(_on_logo_file)
	root.add_child(_file_dialog)

## Q / E step through the categories
func _step_tab(d: int) -> void:
	var i := 0
	var tabs := _tabs()
	for j in tabs.size():
		if tabs[j][0] == tab: i = j
	_set_tab(tabs[wrapi(i + d, 0, tabs.size())][0])

func _close(ride: bool) -> void:
	if mode == "shop":   # looking changes nothing (purchases + FIT saved as they happen)
		closed.emit(false)
		return
	_flush_pose()
	# a showroom edition being looked at is not your build: only SAVE / SAVE & RIDE keep it, BACK doesn't
	if ride or not _show_pick.begins_with("ed:"): BikeBuild.save_build(build)
	closed.emit(ride)

func _toast(t: String) -> void:
	var l := UITheme.display(t, Tokens.T_2XL, Tokens.ACCENT)
	l.add_theme_color_override("font_shadow_color", Tokens.SCENE_SHADOW)
	l.set_anchors_preset(Control.PRESET_CENTER_TOP)
	l.position = Vector2(-Tokens.S8, Tokens.S8 * 2)
	ui.get_child(0).add_child(l)
	var tw := create_tween()
	tw.tween_interval(0.8); tw.tween_property(l, "modulate:a", 0.0, 0.4); tw.tween_callback(l.queue_free)

func _update_stats() -> void:
	var s := BikeBuild.stats(build, _frame_id())
	for k in s:
		if _stat_bars.has(k): _stat_bars[k].target = s[k]
	if is_instance_valid(_class_lbl):
		_class_lbl.text = _bike_line(_frame_id(), build)

var _class_lbl: Label
var _part_box: VBoxContainer
const UP_COL := Color("1f9d55")     # a stat this part would raise
const DOWN_COL := Color("d0342c")   # ... lower

## the whole build as it is, by reference: every Dictionary object with its values, so a trial change (a card's own
## apply callback, which may swap whole sub-dictionaries) can be put back exactly: the same objects the open page
## holds on to, with their old values (_put_back)
static func _capture(d: Dictionary) -> Dictionary:
	var vals := {}
	for k in d:
		var v = d[k]
		vals[k] = _capture(v) if v is Dictionary else (v.duplicate(true) if v is Array else v)
	return {"__obj": d, "vals": vals}

static func _put_back(cap: Dictionary) -> Dictionary:
	var d: Dictionary = cap.__obj
	d.clear()
	for k in cap.vals:
		var v = cap.vals[k]
		d[k] = _put_back(v) if v is Dictionary and v.has("__obj") else v
	return d

## what fitting this card's part would do: tries it on the build (its own apply callback), reads the stats and weight,
## puts the build back. The stat bars slide to the new values; the build card lists the part and every change.
func _part_preview(it: Dictionary, apply: Callable) -> void:
	if not is_instance_valid(_part_box) or not editing: return
	var frame := _frame_id()
	var s0 := BikeBuild.stats(build, frame)
	var kg0 := BikeBuild.bike_kg(frame, build)
	var kp0 := BikeBuild.kg_parts(frame, build)
	var pr0 := BikeBuild.props(build)
	var cap := _capture(build)
	apply.call(it.key)
	var s1 := BikeBuild.stats(build, frame)
	var kg1 := BikeBuild.bike_kg(frame, build)
	var st1 := BikeBuild.stars(build, frame)
	var kp1 := BikeBuild.kg_parts(frame, build)
	var pr1 := BikeBuild.props(build)
	_put_back(cap)
	for k in s1:
		if _stat_bars.has(k):
			_stat_bars[k].base = s0[k]
			_stat_bars[k].target = s1[k]
	for c in _part_box.get_children(): c.queue_free()
	_part_box.add_child(UITheme.spacer(Tokens.S2))
	var head := String(it.get("brand", ""))
	if head != "": _part_box.add_child(UITheme.caption(head.to_upper(), SUB, Tokens.T_XS))
	var nm := UITheme.display(String(it.get("name", "")).to_upper(), Tokens.T_LG, INK, Tokens.SLANT_TITLE)
	nm.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_part_box.add_child(nm)
	if String(it.get("spec", "")) != "":
		var sp := UITheme.text(String(it.spec), SUB, Tokens.T_XS)
		sp.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_part_box.add_child(sp)
	# every change, biggest first; nothing = says so
	var rows := []
	for k in s1:
		var dv: float = (float(s1[k]) - float(s0[k])) * 100.0
		if absf(dv) >= 0.5: rows.append([k, dv])
	rows.sort_custom(func(a, b): return absf(a[1]) > absf(b[1]))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", Tokens.S3)
	grid.add_theme_constant_override("v_separation", 0)
	var add_row := func(label: String, val: String, col: Color) -> void:
		grid.add_child(UITheme.caption(label.to_upper(), INK, Tokens.T_XS))
		var l := UITheme.caption(val, col, Tokens.T_XS)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(l)
	for r in rows:
		add_row.call(r[0], ("▲ +%d" if r[1] > 0 else "▼ %d") % roundi(r[1]), UP_COL if r[1] > 0 else DOWN_COL)
	var dkg := kg1 - kg0
	if absf(dkg) >= 0.01:
		add_row.call("Weight", "%+.2f kg  (%.1f)" % [dkg, kg1], DOWN_COL if dkg > 0 else UP_COL)   # (lighter = quicker)
	var st0 := BikeBuild.stars(build, frame)
	if st1 != st0:
		add_row.call("Class", "%s → %s" % [BikeBuild.star_text(st0), BikeBuild.star_text(st1)], UP_COL if st1 > st0 else DOWN_COL)
	if grid.get_child_count() == 0:
		add_row.call("Ride", "no change (looks only)", SUB)
	_part_box.add_child(UITheme.spacer(Tokens.S1))
	_part_box.add_child(grid)
	# the part's own weight: the parts of the bike whose weight it changes (else the slot it goes in, as it is)
	var wg := GridContainer.new()
	wg.columns = 2
	wg.add_theme_constant_override("h_separation", Tokens.S3)
	wg.add_theme_constant_override("v_separation", 0)
	for k in kp1:
		var dk: float = float(kp1[k]) - float(kp0[k])
		if absf(dk) < 0.005: continue
		wg.add_child(UITheme.caption(("%s weight" % k).to_upper(), INK, Tokens.T_XS))
		var l := UITheme.caption("%.2f kg  (%+.2f)" % [kp1[k], dk], DOWN_COL if dk > 0 else UP_COL, Tokens.T_XS)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		wg.add_child(l)
	if wg.get_child_count() > 0:
		_part_box.add_child(UITheme.spacer(Tokens.S1))
		_part_box.add_child(wg)
	# the bike with it: every property, the ones this part changes marked (yellow bar + ink)
	_part_box.add_child(UITheme.spacer(Tokens.S2))
	_part_box.add_child(UITheme.caption("THE BIKE WITH IT", SUB, Tokens.T_XS))
	for i in pr1.size():
		var changed: bool = pr1[i][1] != pr0[i][1]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", Tokens.S2)
		var bar := ColorRect.new()
		bar.color = Tokens.ACCENT if changed else Tokens.CLEAR
		bar.custom_minimum_size = Vector2(3, 0)
		row.add_child(bar)
		var lab := UITheme.caption(String(pr1[i][0]).to_upper(), INK if changed else SUB, Tokens.T_XS)
		lab.custom_minimum_size.x = 72
		row.add_child(lab)
		var val := UITheme.text(String(pr1[i][1]), INK if changed else SUB, Tokens.T_XS)
		val.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		val.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(val)
		_part_box.add_child(row)
	_part_box.visible = true

func _part_preview_end() -> void:
	if not is_instance_valid(_part_box): return
	_part_box.visible = false
	for k in _stat_bars: _stat_bars[k].base = -1.0
	_update_stats()

## "★★★☆☆  ·  RACE  ·  16.8 KG": a build on a frame, for the build card and the showroom cards
static func _bike_line(frame: String, b: Dictionary) -> String:
	var F: Dictionary = BikeBuild.FRAMES.get(frame, {})
	var cls := String(BikeBuild.CLASSES[F["class"]].label).to_upper() if F.has("class") else ""
	return "%s  ·  %s  ·  %.1f KG  ·  %s" % [BikeBuild.star_text(BikeBuild.stars(b, frame)), cls, BikeBuild.bike_kg(frame, b), Shop.fmt(Shop.build_price(b, frame))]

func _set_tab(t: String) -> void:
	if mode == "shop":
		tab = t
		if tab_buttons.has(t): tab_buttons[t].button_pressed = true
		store.show_tab(t)
		return
	_part_preview_end()   # the page (and the card under the cursor) is rebuilt
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
		"bars": _bars_page()
		"suspension": _susp_page()
		"brakes": _brakes_page()
		"drive": _drive_page()
		"rider": _rider_page()
		"kit": _kit_page()

# ---------------------------------------------------------------- widgets
## a small grey hint line that wraps to the card's width (never widens it)
func _note(t: String) -> void:
	var l := UITheme.text(t, SUB, Tokens.T_XS)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(l)

func _h(t: String) -> void:
	if body.get_child_count() > 0: body.add_child(UITheme.spacer(Tokens.S2))
	body.add_child(UITheme.heading(t))

## caption shorthand for the pages
func _cap(t: String, col := SUB) -> Label:
	return UITheme.caption(t, col)

func _row(t: String, ctl: Control) -> void:
	var hb := HBoxContainer.new()
	var l := UITheme.text(t)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# long names shorten with "…" (full name on hover) instead of widening the card
	l.clip_text = true
	l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	l.tooltip_text = t
	l.mouse_filter = Control.MOUSE_FILTER_PASS
	hb.add_child(l)
	ctl.custom_minimum_size.x = maxf(ctl.custom_minimum_size.x, Tokens.H_ROW_CTL)
	hb.add_child(ctl)
	hb.set_meta("nav_row", true)   # PadNav marks the row its control has focus in
	body.add_child(hb)

## a part / option picker like a racing game's tuning shop: ◀ VALUE ▶ with a dot per option
## items: [[value, label], ...]
## rebuild = false: a change that isn't the bike's (the rider room's look): skip the bike rebuild
func _choice(t: String, items: Array, current, cb: Callable, rebuild := true) -> Control:
	var sel := 0
	for i in items.size():
		if str(items[i][0]) == str(current): sel = i
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", Tokens.S1)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 0)
	var arrow := func(a: String) -> Button:
		var b := UITheme.make_button(a, Callable(), "chip", Tokens.T_SM)
		b.custom_minimum_size = Tokens.STEP_ARROW
		b.focus_mode = Control.FOCUS_NONE
		# colours come from the chip style: grey, light wash on hover, yellow only while pressed
		return b
	var prev: Button = arrow.call("◀")
	var next: Button = arrow.call("▶")
	var val := UITheme.display(" ", Tokens.T_MD, INK, 0.0, Tokens.W_BOLD)
	val.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	val.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	val.clip_text = true
	val.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	val.mouse_filter = Control.MOUSE_FILTER_PASS
	hb.add_child(prev); hb.add_child(val); hb.add_child(next)
	box.add_child(hb)
	var dots := HBoxContainer.new()
	dots.alignment = BoxContainer.ALIGNMENT_CENTER
	dots.add_theme_constant_override("separation", Tokens.S1)
	if items.size() <= 14:
		for i in items.size():
			var d := ColorRect.new()
			d.custom_minimum_size = Vector2(Tokens.S3, Tokens.S1)
			dots.add_child(d)
		box.add_child(dots)
	var show := func():
		val.text = str(items[sel][1]).to_upper()
		val.tooltip_text = str(items[sel][1])
		for i in dots.get_child_count():
			(dots.get_child(i) as ColorRect).color = Tokens.ACCENT_DOWN if i == sel else LINE
	show.call()
	var step := func(d: int):
		sel = wrapi(sel + d, 0, items.size())
		show.call()
		cb.call(items[sel][0])
		if rebuild: _changed()
	prev.pressed.connect(step.bind(-1))
	next.pressed.connect(step.bind(1))
	box.focus_mode = Control.FOCUS_ALL   # the pad lands on the stepper: left / right (or A) step it
	box.set_meta(&"nav_step", step)
	_row(t, box)
	return box

func _slide(text: String, lo: float, hi: float, stp: float, cur: float, unit: String, cb: Callable) -> void:
	var hb := HBoxContainer.new()
	var s := HSlider.new()
	s.scrollable = false   # (the wheel scrolls the list; it never changes a value by accident)
	s.min_value = lo; s.max_value = hi; s.step = stp; s.value = cur
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var u := unit.replace("%", "%%")
	var fmt := "%d " + u if stp >= 1 else "%.1f " + u
	var vl := UITheme.text(fmt % cur, SUB, Tokens.T_SM)
	vl.custom_minimum_size.x = Tokens.S8 + Tokens.S5
	s.value_changed.connect(func(v): vl.text = fmt % v; cb.call(v); _changed())
	hb.add_child(s); hb.add_child(vl)
	_row(text, hb)

func _color(text: String, cur: String, cb: Callable) -> void:
	var cp := ColorPickerButton.new()
	cp.color = Color(cur)
	cp.edit_alpha = false
	cp.custom_minimum_size = Vector2(200, 34)
	cp.color_changed.connect(func(c): cb.call(c.to_html(false)); _changed())
	# on a pad the picker is a stepper: left / right (or A) walk through the swatch palette from the nearest colour
	cp.set_meta(&"nav_step", func(dir: int) -> void:
		var best := 0
		var bd := INF
		for i in SWATCHES.size():
			var c := Color(SWATCHES[i])
			var d := Vector3(c.r - cp.color.r, c.g - cp.color.g, c.b - cp.color.b).length_squared()
			if d < bd: bd = d; best = i
		var hex: String = SWATCHES[wrapi(best + dir if bd < 1e-4 else best, 0, SWATCHES.size())]
		cp.color = Color(hex)
		cb.call(Color(hex).to_html(false)); _changed())
	_row(text, cp)

## paint-shop colour chips: a square of the colour over a white strip with its code + name. The picked chip's
## strip turns yellow with an ink bar (flat: no outlines), hover lightens the strip.
const CHIP := 68          # px: the colour square (5 chips fill the card's width)
const CHIP_STRIP := 36    # px: the label strip under it
func _swatches(cur: String, cb: Callable) -> void:
	cur = _hex(cur)
	var g := GridContainer.new()
	g.columns = 5
	g.add_theme_constant_override("h_separation", Tokens.S2)
	g.add_theme_constant_override("v_separation", Tokens.S2)
	for i in SWATCHES.size():
		var hex: String = SWATCHES[i]
		var nm: String = SWATCH_NAMES[i] if i < SWATCH_NAMES.size() else "#" + hex
		var code := "RO %d" % (101 + i)
		var on: bool = hex == cur
		var b := Button.new()
		b.custom_minimum_size = Vector2(CHIP, CHIP + CHIP_STRIP)
		b.tooltip_text = "%s  %s  #%s" % [code, nm, hex]
		var strip := Tokens.ACCENT_TINT if on else Color.WHITE
		b.add_theme_stylebox_override("normal", UITheme.marked(strip, INK, SIDE_BOTTOM, Tokens.R_SM, 0) if on else UITheme.box(strip, Tokens.R_SM, 0))
		b.add_theme_stylebox_override("hover", UITheme.marked(Tokens.ACCENT_TINT if on else Tokens.FILL, Tokens.ACCENT, SIDE_BOTTOM, Tokens.R_SM, 0))
		b.add_theme_stylebox_override("pressed", UITheme.marked(Tokens.ACCENT_TINT, Tokens.ACCENT, SIDE_BOTTOM, Tokens.R_SM, 0))
		b.add_theme_stylebox_override("focus", UITheme.marked(Color(Tokens.INK, 0.06), Tokens.INK, SIDE_BOTTOM, Tokens.R_SM, 0))
		var col := VBoxContainer.new()
		col.set_anchors_preset(Control.PRESET_FULL_RECT)
		col.add_theme_constant_override("separation", 0)
		col.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var sq := ColorRect.new()
		sq.color = Color(hex)
		sq.custom_minimum_size = Vector2(CHIP, CHIP)
		sq.mouse_filter = Control.MOUSE_FILTER_IGNORE
		col.add_child(sq)
		var lab := VBoxContainer.new()
		lab.add_theme_constant_override("separation", -3)
		lab.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var m := MarginContainer.new()
		m.add_theme_constant_override("margin_left", 4); m.add_theme_constant_override("margin_right", 2)
		m.add_theme_constant_override("margin_top", 2)
		m.mouse_filter = Control.MOUSE_FILTER_IGNORE
		m.add_child(lab)
		col.add_child(m)
		var c1 := UITheme.display(code, 14, INK, 0.0)
		var c2 := UITheme.caption(nm.to_upper(), SUB, 11)
		for l in [c1, c2]:
			(l as Label).clip_text = true
			(l as Label).text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			(l as Label).mouse_filter = Control.MOUSE_FILTER_IGNORE
			lab.add_child(l)
		b.add_child(col)
		b.pressed.connect(func(): cb.call(hex); _changed(); _set_tab(tab))
		g.add_child(b)
	body.add_child(g)

# ---------------------------------------------------------------- pages
func _paint_page() -> void:
	# (the frame is picked in the showroom, before EDIT)
	var P: Dictionary = build.paint[part]
	var F: Dictionary = BikeBuild.FINISHES.get(P.finish, BikeBuild.FINISHES.gloss)
	# the selected part's paint as a big material ball, its name, finish and colour code
	var hero := HBoxContainer.new()
	hero.add_theme_constant_override("separation", Tokens.S3)
	var ball := _ball_pic(P, Vector2(150, 120))
	hero.add_child(ball)
	var info := VBoxContainer.new()
	info.alignment = BoxContainer.ALIGNMENT_CENTER
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 0)
	info.add_child(UITheme.caption("PAINTING", SUB, Tokens.T_XS))
	var nm := UITheme.display(String(BikeBuild.PARTS[part][0]).to_upper(), Tokens.T_2XL, INK, Tokens.SLANT_TITLE)
	nm.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.add_child(nm)
	info.add_child(UITheme.caption("%s  ·  #%s" % [String(F.label).to_upper(), _hex(P.color).to_upper()], SUB, Tokens.T_XS))
	if part in ["frame", "rear"]:
		var copy := UITheme.make_button("APPLY TO WHOLE FRAME", func():
			for k in ["frame", "rear"]: build.paint[k] = P.duplicate()
			_changed(); _set_tab("paint"), "link", Tokens.T_SM)
		copy.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		info.add_child(copy)
	hero.add_child(info)
	body.add_child(hero)
	# the parts: a strip of tiles, each with its own paint as a little ball
	_h("PART")
	var ps := PicStrip.new(Tokens.S2)
	var grp := ButtonGroup.new()
	for k in BikeBuild.PARTS:
		var kp: Dictionary = build.paint[k]
		var b := _tile(String(BikeBuild.PARTS[k][0]), _part_pic(k, Vector2(0, 74)), Vector2(132, 116), k == part, grp)
		b.pressed.connect(ps.guard(func(): part = k; _set_tab("paint")))
		ps.add(b, k == part)
	body.add_child(ps)
	_h("COLOUR")
	# colours: paint-shop chips (a square of colour over its code + name)
	_swatches(_hex(P.color), func(h): P.color = h)
	_color("Custom colour", P.color, func(h): P.color = h)
	# finishes: the same colour as a ball in every finish
	_h("FINISH")
	var fs := GridContainer.new()   # all of them in view: 4 x 2
	fs.columns = 4
	fs.add_theme_constant_override("h_separation", Tokens.S2)
	fs.add_theme_constant_override("v_separation", Tokens.S2)
	var fgrp := ButtonGroup.new()
	for f in BikeBuild.FINISHES:
		var fp := P.duplicate()
		fp.finish = f
		var b := _tile(String(BikeBuild.FINISHES[f].label), _ball_pic(fp, Vector2(0, 66)), Vector2(0, 104), f == P.finish, fgrp)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(func(): P.finish = f; _changed(); _set_tab("paint"))
		fs.add_child(b)
	body.add_child(fs)
	if P.finish == "pearl":
		_color("Shift colour (at the edges)", P.color2, func(h): P.color2 = h)
	if part in ["frame", "rear"]:
		_livery_section(P)

## LIVERY: a pattern in a second colour over the frame paint (both triangles share one design: set the front
## and use APPLY TO WHOLE FRAME, or set them each)
func _livery_section(P: Dictionary) -> void:
	_h("LIVERY")
	var cur := String(P.get("livery", "none"))
	var lcol := String(P.get("lcolor", "ffffff"))
	var g := GridContainer.new()
	g.columns = 4
	g.add_theme_constant_override("h_separation", Tokens.S2)
	g.add_theme_constant_override("v_separation", Tokens.S2)
	var grp := ButtonGroup.new()
	for id in BikeBuild.LIVERIES:
		var sw := HBoxContainer.new()   # the two colours side by side: a hint, the bike shows the real thing
		sw.add_theme_constant_override("separation", 0)
		sw.custom_minimum_size = Vector2(0, 30)
		sw.size_flags_vertical = Control.SIZE_EXPAND_FILL
		sw.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var a := ColorRect.new(); a.color = Color(String(P.color)); a.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var b2 := ColorRect.new(); b2.color = Color(lcol) if id != "none" else Color(String(P.color)); b2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		a.mouse_filter = Control.MOUSE_FILTER_IGNORE; b2.mouse_filter = Control.MOUSE_FILTER_IGNORE
		sw.add_child(a); sw.add_child(b2)
		var t := _tile(String(BikeBuild.LIVERIES[id].label), sw, Vector2(0, 66), id == cur, grp)
		t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		t.pressed.connect(func(): P.livery = id; _changed(); _set_tab("paint"))
		g.add_child(t)
	body.add_child(g)
	if cur != "none":
		_swatches(lcol, func(h): P.lcolor = h)
		_color("Livery colour", lcol, func(h): P.lcolor = h)

## "#E8432E" / "e8432e" -> "e8432e"
static func _hex(c) -> String:
	return String(c).trim_prefix("#").to_lower()

## a picture of one paintable part alone, in its paint (re-rendered when that part's paint or the bike's shape changes)
func _part_pic(k: String, sz: Vector2) -> TextureRect:
	var pic := TextureRect.new()
	pic.custom_minimum_size = sz
	pic.size_flags_vertical = Control.SIZE_EXPAND_FILL
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var shape: Dictionary = build.duplicate(true)
	shape.erase("paint"); shape.erase("logos"); shape.erase("name")
	var key := "ppart|%s|%s|%s|%s" % [GameState.bike_id, k, JSON.stringify(build.paint[k]), str(JSON.stringify(shape).hash())]
	var ref: WeakRef = weakref(pic)
	thumbs.request(key, PartThumbs.make_paint_part.bind(GameState.bike_id, build.duplicate(true), k), Vector3(0.3, 0.2, 1.0), func(t):
		var pr = ref.get_ref()
		if pr: pr.texture = t)
	return pic

## a rendered ball in this paint (colour, shift colour, finish), cached by the paint
func _ball_pic(p: Dictionary, sz: Vector2) -> TextureRect:
	var pic := TextureRect.new()
	pic.custom_minimum_size = sz
	pic.size_flags_vertical = Control.SIZE_EXPAND_FILL
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ref: WeakRef = weakref(pic)
	var plain := p.duplicate()   # (a ball shows the paint itself: a livery lies across the whole frame, not a sphere)
	plain.livery = "none"
	thumbs.request("ball|%s|%s|%s" % [p.color, p.get("color2", ""), p.finish], PartThumbs.make_ball.bind(plain), Vector3(0.35, 0.3, 1.0), func(t):
		var pr = ref.get_ref()
		if pr: pr.texture = t)
	return pic

## a small picked-or-not tile: a picture over a name (paint parts, finishes)
func _tile(label: String, pic: Control, sz: Vector2, on: bool, grp: ButtonGroup) -> Button:
	var b := Button.new()
	b.toggle_mode = true; b.button_group = grp; b.button_pressed = on
	b.custom_minimum_size = sz
	b.tooltip_text = label
	b.add_theme_stylebox_override("normal", UITheme.marked(Tokens.ACCENT_TINT, Tokens.ACCENT, SIDE_BOTTOM, Tokens.R_LG, 0) if on else UITheme.box(Tokens.PAGE, Tokens.R_LG, 0))
	b.add_theme_stylebox_override("hover", UITheme.marked(Tokens.ACCENT_TINT if on else Tokens.FILL, Tokens.ACCENT if on else Tokens.LINE, SIDE_BOTTOM, Tokens.R_LG, 0))
	b.add_theme_stylebox_override("pressed", UITheme.marked(Tokens.ACCENT_TINT, Tokens.ACCENT, SIDE_BOTTOM, Tokens.R_LG, 0))
	b.add_theme_stylebox_override("focus", UITheme.marked(Color(Tokens.INK, 0.06), Tokens.INK, SIDE_BOTTOM, Tokens.R_LG, 0))
	var col := VBoxContainer.new()
	col.set_anchors_preset(Control.PRESET_FULL_RECT)
	col.offset_left = Tokens.S1; col.offset_right = -Tokens.S1; col.offset_top = Tokens.S1; col.offset_bottom = -Tokens.S2
	col.add_theme_constant_override("separation", 0)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(pic)
	var nm := UITheme.caption(label.to_upper(), INK, Tokens.T_XS)
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nm.clip_text = true
	nm.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	nm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(nm)
	b.add_child(col)
	return b

func _logos_page() -> void:
	_h("SPOT")
	var g := GridContainer.new()
	g.columns = 3
	g.add_theme_constant_override("h_separation", Tokens.S2)
	g.add_theme_constant_override("v_separation", Tokens.S2)
	var grp := ButtonGroup.new()
	var slots := BikeBuild.SLOTS.keys() + ["tyres", "rims"]
	for k in slots:
		var b := Button.new()
		b.text = "Tyre walls" if k == "tyres" else ("Rims" if k == "rims" else BikeBuild.SLOTS[k].label)
		b.toggle_mode = true; b.button_group = grp; b.button_pressed = k == logo_slot
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.add_theme_font_size_override("font_size", Tokens.T_MD)
		b.pressed.connect(func(): logo_slot = k; _set_tab("logos"))
		g.add_child(b)
	body.add_child(g)
	var L: Dictionary = build.logos[logo_slot]
	if L.logo != "none":
		_placement(L)
	if logo_slot == "rims":
		_h("RIM DECALS")
		var items := [["text", "Lettering"], ["none", "None"]]
		for k in BikeBuild.LOGOS:
			var lg: Dictionary = BikeBuild.LOGOS[k]
			if lg.has("image") or lg.has("text"): items.append([k, lg.label])
		for f in BikeBuild.imported_logos():
			items.append(["file:" + f, "Imported · " + f.get_file().get_basename()])
		_choice("Decal", items, L.logo, func(v): L.logo = v; _set_tab.call_deferred("logos"))
		_choice("Repeats", [[1, "1 per side"], [2, "2 per side"], [3, "3 per side"], [4, "4 per side"]], int(L.get("count", 2)),
			func(v): L.count = v)
		var imp := UITheme.make_button("Import your own PNG…", func(): _file_dialog.popup_centered_ratio(0.6), "chip", Tokens.T_MD)
		body.add_child(imp)
		if L.logo == "text":
			var te := LineEdit.new(); te.text = L.text; te.max_length = 14
			te.text_changed.connect(func(t): L.text = t.to_upper(); _changed())
			_row("Text", te)
		if L.logo == "text" or BikeBuild.LOGOS.get(L.logo, {}).has("text"):
			_h("COLOUR")
			_swatches(L.fill, func(h): L.fill = h)
			_color("Lettering", L.fill, func(h): L.fill = h)
		_note("Picking a rim model in the Wheels tab puts its brand on the rims.")
		return
	if logo_slot == "tyres":
		_h("SIDEWALL LETTERING")
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
	for k in BikeBuild.LOGOS:
		var lg: Dictionary = BikeBuild.LOGOS[k]
		items.append([k, lg.label])
	for f in BikeBuild.imported_logos():
		items.append(["file:" + f, "Imported · " + f.get_file().get_basename()])
	_choice("Logo", items, L.logo, func(v): L.logo = v; _set_tab.call_deferred("logos"))
	var imp := UITheme.make_button("Import your own PNG…", func(): _file_dialog.popup_centered_ratio(0.6), "chip", Tokens.T_MD)
	body.add_child(imp)
	_note("Transparent PNGs work best. Imported logos are kept in your garage.")
	if L.logo == "text":
		var te := LineEdit.new(); te.text = L.text; te.max_length = 16; te.placeholder_text = "YOUR TEXT"
		te.text_changed.connect(func(t): L.text = t.to_upper(); _changed())
		_row("Text", te)
	if L.logo == "text" or BikeBuild.LOGOS.get(L.logo, {}).has("text"):
		_h("LETTERING COLOURS")
		_swatches(L.fill, func(h): L.fill = h)
		_color("Fill", L.fill, func(h): L.fill = h)
		_color("Outline", L.stroke, func(h): L.stroke = h)

## slide the sticker along the tube it sits on, make it bigger / smaller, turn it
func _placement(L: Dictionary) -> void:
	_h("PLACEMENT")
	var round_it := logo_slot == "tyres" or logo_slot == "rims"
	if round_it:
		_slide("Turn round wheel", -180.0, 180.0, 1.0, float(L.get("rot", 0.0)), "°", func(v): L.rot = v)
	if logo_slot == "tyres":
		_slide("Height on sidewall", 0.0, 100.0, 1.0, float(L.get("lift", 0.1)) * 100.0, "%", func(v): L.lift = v / 100.0)
	else:
		_slide("Slide along tube", 0.0, 100.0, 1.0, float(L.get("pos", 0.5)) * 100.0, "%", func(v): L.pos = v / 100.0)
	_slide("Size", 40.0, 220.0, 1.0, float(L.get("scale", 1.0)) * 100.0, "%", func(v): L.scale = v / 100.0)
	if not round_it:
		_slide("Rotate", -90.0, 90.0, 1.0, float(L.get("rot", 0.0)), "°", func(v): L.rot = v)
	body.add_child(UITheme.make_button("Reset placement", func():
		L.pos = 0.5; L.scale = 1.0; L.rot = 0.0
		if logo_slot == "tyres": L.lift = 0.1
		_changed()
		_set_tab.call_deferred("logos"), "chip", Tokens.T_MD))
	if logo_slot == "bars":
		_note("One sticker on each side of the stem.")

func _on_logo_file(path: String) -> void:
	var p := BikeBuild.import_logo(path)
	if p == "":
		_toast("Couldn't read that image"); return
	if BikeBuild.SLOTS.has(logo_slot) or logo_slot == "rims":
		build.logos[logo_slot].logo = "file:" + p
	_changed()
	_set_tab("logos")

func _wheels_page() -> void:
	var W: Dictionary = build.wheels
	var sizes := [["26", "26\""], ["27.5", "27.5\""], ["29", "29\""]]
	_h("SIZE")
	_choice("Front wheel", sizes, W.front, func(v): W.front = v)
	_choice("Rear wheel", sizes, W.rear, func(v): W.rear = v)
	var tip := UITheme.text("29\" front / 27.5\" rear is a mullet: big wheel rolls over, small one turns quick.", SUB, Tokens.T_XS)
	tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART   # wraps instead of widening the card
	body.add_child(tip)
	_h("TYRES")
	_wheel_cards(BikeBuild.TYRE_MODELS, W.tyre_model, BikeBuild.apply_tyre_model,
		func(m): return "%.1f\"  ·  %s  ·  %s" % [m.tyre_w, m.tread.capitalize(), m.casing.capitalize()], "tyre")
	var tyre_custom := func(): W.tyre_model = "custom"
	_slide("Width", 2.3, 2.6, 0.1, W.tyre_w, "in", func(v): W.tyre_w = v; tyre_custom.call())
	_choice("Tread", [["knobby", "Knobby (max grip)"], ["semi", "Semi-slick"], ["slick", "Slick (fast, sketchy)"]], W.tread, func(v):
		W.tread = v; W.pattern = v; tyre_custom.call(); _set_tab.call_deferred("wheels"))
	if W.tread == "knobby":
		_choice("Knobs", BikeBuild.PATTERN_NAMES.slice(0, 6), W.pattern, func(v): W.pattern = v; tyre_custom.call())
	_choice("Profile", [["round", "Round"], ["square", "Square shoulders"]], W.casing, func(v): W.casing = v; tyre_custom.call())
	_choice("Sidewall", [["black", "Black"], ["tan", "Tan wall"]], W.sidewall, func(v): W.sidewall = v)
	_h("RIMS")
	_wheel_cards(BikeBuild.RIM_MODELS, W.rim_model, BikeBuild.apply_rim_model,
		func(m): return "%s  ·  %d mm wide  ·  %s" % [m.material.capitalize(), m.width, m.profile.capitalize()], "rim")
	var rim_custom := func(): W.rim_model = "custom"
	_choice("Profile", BikeBuild.RIM_PROFILE_NAMES, W.rim_profile, func(v): W.rim_profile = v; rim_custom.call())
	_choice("Material", [["alloy", "Alloy"], ["carbon", "Carbon"]], W.rim_material, func(v): W.rim_material = v; rim_custom.call())
	_swatches(W.rim_color, func(h): W.rim_color = h)
	if W.rim_material == "carbon":   # carbon takes any colour: raw, clear-coated, metallic flake or candy lacquer
		_choice("Finish", [["matte", "Matte"], ["gloss", "Gloss"], ["metallic", "Metallic"], ["candy", "Candy"]], W.rim_finish if W.rim_finish in ["matte", "gloss", "metallic", "candy"] else "gloss", func(v): W.rim_finish = v)
	else:
		_choice("Finish", [["matte", "Matte"], ["gloss", "Gloss"], ["chrome", "Polished"]], W.rim_finish if W.rim_finish in ["matte", "gloss", "chrome"] else "gloss", func(v): W.rim_finish = v)
	_slide("Rim depth", 20, 40, 1, W.rim_depth, "mm", func(v): W.rim_depth = v; rim_custom.call())
	_slide("Rim width", 25, 40, 1, W.rim_width, "mm", func(v): W.rim_width = v; rim_custom.call())
	_note("Rim and tyre lettering: Logos tab → Rims / Tyre walls.")
	_h("SPOKES")
	_choice("Count", [[24, "24"], [28, "28"], [32, "32"], [36, "36"]], W.spokes, func(v): W.spokes = v)
	_choice("Lacing", [[0, "Radial"], [1, "1-cross"], [2, "2-cross"], [3, "3-cross"]], W.lacing, func(v): W.lacing = v)
	_choice("Gauge", [[0, "Thin (light)"], [1, "Normal"], [2, "Thick (strong)"]], W.gauge, func(v): W.gauge = v)
	_color("Spoke colour", W.spoke_color, func(h): W.spoke_color = h)
	_color("Nipples", W.nipple_color, func(h): W.nipple_color = h)
	_color("Hubs", W.hub_color, func(h): W.hub_color = h)

## part cards with a picture of the part alone (rendered by PartThumbs), brand, name and a spec line,
## two to a row; the fitted one is outlined. items: [{key, brand, name, spec, thumb (cache key), make, view}]
func _cards(items: Array, current: String, cb: Callable, bike := true, into: PicStrip = null, tile := Vector2.ZERO) -> void:
	var g := into if into else PicStrip.new(Tokens.S3)   # one slidable row: drag / wheel / focus moves along it
	for it in items:
		var on: bool = it.key == current
		var b := Button.new()
		b.custom_minimum_size = tile if tile != Vector2.ZERO else Vector2(Tokens.CARD_TILE_W, Tokens.CARD_TILE_H)
		b.tooltip_text = "%s %s" % [it.brand, it.name]
		# flat tiles: grey at rest, lighter on hover; the fitted one is yellow-washed with a yellow bar
		var rest := UITheme.marked(Tokens.ACCENT_TINT, Tokens.ACCENT, SIDE_BOTTOM, Tokens.R_LG, 0) if on else UITheme.box(Tokens.PAGE, Tokens.R_LG, 0)
		b.add_theme_stylebox_override("normal", rest)
		b.add_theme_stylebox_override("hover", UITheme.marked(Tokens.ACCENT_TINT if on else Tokens.FILL, Tokens.ACCENT if on else Tokens.LINE, SIDE_BOTTOM, Tokens.R_LG, 0))
		b.add_theme_stylebox_override("pressed", UITheme.marked(Tokens.ACCENT_TINT, Tokens.ACCENT, SIDE_BOTTOM, Tokens.R_LG, 0))
		b.add_theme_stylebox_override("focus", UITheme.marked(Color(Tokens.INK, 0.06), Tokens.INK, SIDE_BOTTOM, Tokens.R_LG, 0))
		var col := VBoxContainer.new()
		col.set_anchors_preset(Control.PRESET_FULL_RECT)
		col.offset_left = Tokens.S4; col.offset_right = -Tokens.S4; col.offset_top = Tokens.S3; col.offset_bottom = -Tokens.S3
		col.add_theme_constant_override("separation", Tokens.S1)
		col.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var pic := TextureRect.new()
		pic.custom_minimum_size.y = Tokens.CARD_THUMB_H
		if tile != Vector2.ZERO: pic.size_flags_vertical = Control.SIZE_EXPAND_FILL   # big tiles: the picture takes the room
		pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		col.add_child(pic)
		var pic_ref: WeakRef = weakref(pic)   # (a lambda capturing a freed node errors when called: the page may be gone)
		thumbs.request(it.thumb, it.make, it.view, func(t):
			var pr = pic_ref.get_ref()
			if pr: pr.texture = t)
		if String(it.brand) != "": col.add_child(UITheme.caption(String(it.brand), SUB, Tokens.T_XS))
		var nm := UITheme.display(String(it.name).to_upper(), Tokens.T_LG)
		nm.clip_text = true
		nm.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		col.add_child(nm)
		var spec := String(it.spec)
		var stars := ""
		if spec.begins_with("★") or spec.begins_with("☆"):   # "★★★☆☆  ·  ...": the stars a size up
			stars = spec.substr(0, 5)
			spec = spec.substr(5).strip_edges()   # "·  RACE  ·  17.3 KG"
		var sp := UITheme.text(spec, SUB, Tokens.T_XS)
		sp.clip_text = true
		sp.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		if stars != "":
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 0)
			row.mouse_filter = Control.MOUSE_FILTER_IGNORE
			row.add_theme_constant_override("separation", Tokens.S2)
			var st := UITheme.text(stars, Color("e9a400"), Tokens.T_LG)   # gold
			st.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			row.add_child(st)
			sp.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(sp)
			col.add_child(row)
		elif spec != "": col.add_child(sp)
		b.add_child(col)
		if it.has("badge"):   # the shop: OWNED
			var bg := UITheme.display(String(it.badge), Tokens.T_XS, Color.WHITE, 0.0)
			var bs := UITheme.btn_box(Color("2f9e55"), Tokens.CLEAR, 0, Tokens.R_SM, Tokens.S2)
			bs.content_margin_top = 0; bs.content_margin_bottom = 0
			bg.add_theme_stylebox_override("normal", bs)
			bg.position = Vector2(Tokens.S3, Tokens.S3)
			b.add_child(bg)
		elif on and mode != "shop":
			var tag := UITheme.display("FITTED", Tokens.T_XS, INK, 0.0)
			var ts := UITheme.btn_box(Tokens.ACCENT, Tokens.CLEAR, 0, Tokens.R_SM, Tokens.S2)
			ts.content_margin_top = 0; ts.content_margin_bottom = 0
			tag.add_theme_stylebox_override("normal", ts)
			tag.position = Vector2(Tokens.S3, Tokens.S3)
			b.add_child(tag)
		var kind := String(it.get("kind", ""))
		var pid := String(it.key).trim_prefix("ed:")
		var cost := int(it.price) if it.has("price") else (Shop.price(kind, pid) if kind != "" else 0)
		if cost > 0:   # price tag, top right (everything is unlocked while Shop.UNLOCK_ALL)
			var pt := UITheme.display(Shop.fmt(cost), Tokens.T_XS, INK, 0.0)
			var ps := UITheme.btn_box(Tokens.FILL, Tokens.CLEAR, 0, Tokens.R_SM, Tokens.S2)
			ps.content_margin_top = 0; ps.content_margin_bottom = 0
			pt.add_theme_stylebox_override("normal", ps)
			pt.mouse_filter = Control.MOUSE_FILTER_IGNORE
			pt.set_anchors_preset(Control.PRESET_TOP_RIGHT)
			pt.grow_horizontal = Control.GROW_DIRECTION_BEGIN
			pt.offset_top = Tokens.S3; pt.offset_right = -Tokens.S3
			b.add_child(pt)
			b.tooltip_text += "  ·  " + Shop.fmt(cost)
		b.pressed.connect(g.guard(func():
			if kind != "" and not it.has("price") and not Shop.unlocked(kind, pid): return
			cb.call(it.key)
			if bike: _changed()
			if into == null: _set_tab(tab)))
		if bike and into == null:   # the build card shows what this part is and would change (mouse over / pad focus)
			b.mouse_entered.connect(_part_preview.bind(it, cb))
			b.focus_entered.connect(_part_preview.bind(it, cb))
			b.mouse_exited.connect(_part_preview_end)
			b.focus_exited.connect(_part_preview_end)
		g.add(b, on)
	if into == null: body.add_child(g)

## [id, label] options as picture cards. `make(id)` builds the picture's subject with that option; `view` = the camera
## direction (or a Dictionary id -> direction, "" = the rest); `tag` + id = the picture's cache key
func _pic_cards(opts: Array, current: String, tag: String, make: Callable, view, cb: Callable, bike := true) -> void:
	var items := []
	for o in opts:
		var id := str(o[0])
		items.append({"key": id, "brand": "", "name": String(o[1]), "spec": "", "thumb": tag + "|" + id, "kind": tag.get_slice("|", 0),
			"make": make.bind(id), "view": view.get(id, view.get("", Vector3.ONE)) if view is Dictionary else view})
	_cards(items, current, cb, bike)

## the stock bike with `path` (e.g. "bars.stem") set to id, as a close-up of `spot` (PartThumbs.make_bike_spot)
func _spot_make(id: String, path: String, spot: String) -> Node3D:
	var tmp: Dictionary = BikeBuild.default_build()   # a product shot: on the stock bike, not the player's (see PRODUCT)
	var k := path.split(".")
	if not tmp.has(k[0]): tmp[k[0]] = {}
	tmp[k[0]][k[1]] = id
	if path == "camera.mount": spot = "fork" if id == "fork" else "bars"
	return PartThumbs.make_bike_spot(tmp, spot)

## the cache key part for pictures of the whole bike: they change with the build
func _build_sig() -> String:
	return str(JSON.stringify(build).hash())

## Product cards (bars, stems, forks, tyres, rims, rotors, calipers, levers, pedals, cassettes, saddles, action
## cams) show the product as it comes: on / in the stock bike's parts and paint, the camera with its default
## gear, never the player's build. So they never change, and all of them ship with the game (the bake).
## Only the Paint tab and the rider's own look are pictured as the player has them.
const PRODUCT := "product"
static func _product_paint(part: String) -> Dictionary:
	return BikeBuild.default_build().paint[part]
static func _product_gear() -> Dictionary:
	return ActionCam.gear_of(ActionCam.GEAR_DEFAULT.duplicate())

## the action cam with its gear row `gk` set to id (the rest as in `gear`)
static func _cam_make(id: String, gk: String, gear: Dictionary) -> Node3D:
	var g := gear.duplicate()
	g[gk] = id
	return PartThumbs.make_cam(g)

func _bars_page() -> void:
	var B: Dictionary = build.bars
	var cur: String = B.get("model", "custom")
	_h("HANDLEBARS")
	var items := []
	for k in Handlebar.MODELS:
		var m: Dictionary = Handlebar.MODELS[k]
		items.append({"key": k, "brand": m.brand, "name": m.label,
			"spec": "%d mm  ·  %s  ·  %s" % [m.width, ("%d mm rise" % m.rise) if m.rise > 0 else "flat", Handlebar.MATERIAL_SHORT[m.material]],
			"thumb": "bar|%s|%s" % [k, PRODUCT], "kind": "bar",
			"make": PartThumbs.make_bars.bind(m, _product_paint("crown"), _product_paint("grips")), "view": Vector3(1.0, 0.75, 0.55)})
	_cards(items, cur, func(k):
		var m: Dictionary = Handlebar.MODELS[k]
		B.model = k; B.width = m.width; B.rise = m.rise; B.material = m.material)
	_h("FINE TUNE")
	var custom := func(): B.model = "custom"
	if Handlebar.glb_of(B) != "":   # a model bar keeps its own width / rise; only the material changes
		_choice("Material", Handlebar.MATERIALS, B.material, func(v): B.material = v)
		_note("This bar is the bike model's own: width and rise are as modelled. Pick another bar to set them.")
	else:
		_choice("Width", Handlebar.WIDTHS.map(func(w): return [w, "%d mm" % w]), int(B.width), func(v): B.width = v; custom.call())
		_choice("Rise", Handlebar.RISES.map(func(r): return [r, "%d mm" % r if r > 0 else "Flat"]), int(B.rise), func(v): B.rise = v; custom.call())
		_choice("Material", Handlebar.MATERIALS, B.material, func(v): B.material = v; custom.call())
	_note("Wide bars steer slower but steadier; narrow bars turn quicker. Alloy bars take the bars / stem colour from Paint.")
	_h("STEM")
	_pic_cards(BikeBuild.STEMS, str(B.get("stem", "stock")), "stem|" + PRODUCT, _spot_make.bind("bars.stem", "stem"),
		Vector3(0.55, 0.85, 0.75), func(v): B.stem = v)
	_h("SEAT")
	var SE: Dictionary = build.seat
	_pic_cards(BikeBuild.SADDLES, str(SE.get("model", "stock")), "saddle", PartThumbs.make_saddle,
		Vector3(0.45, 0.6, 1.0), func(v): SE.model = v)
	_choice("Seat post", BikeBuild.POSTS, str(SE.get("post", "stock")), func(v): SE.post = v; _set_tab("bars"))
	if str(SE.get("post", "stock")) == "dropper":
		_slide("Post height", 0, 200, 10, float(SE.get("post_h", 0.0)) * 1000.0, "mm", func(v): SE.post_h = float(v) / 1000.0)
	_note("The dropper stands the saddle up along the seat tube (the rider follows). Saddle colour is in Paint > Saddle & pedals.")
	_h("ACTION CAM")
	if not build.has("camera"): build.camera = {"mount": "none"}.merged(ActionCam.GEAR_DEFAULT)
	_pic_cards(ActionCam.BIKE_MOUNTS, str(build.camera.get("mount", "none")), "bikecam|" + PRODUCT,
		_spot_make.bind("camera.mount", "bars"), {"": Vector3(0.75, 0.6, 0.75), "fork": Vector3(0.7, 0.15, 1.0)},
		func(v): build.camera.mount = v)
	for r in ActionCam.GEAR_ROWS:
		var gk: String = r[0]
		_h(String(r[1]).to_upper())
		_pic_cards(r[2], str(build.camera.get(gk, ActionCam.GEAR_DEFAULT[gk])), "cam|%s|%s" % [gk, PRODUCT],
			_cam_make.bind(gk, _product_gear()), Vector3(1.0, 0.45, 0.75), func(v): build.camera[gk] = v)
	_note("An action camera on the bike: the Bike cam view (C) looks out of it. The helmet camera is picked in the Rider room's Kit tab.")
	_h("LIGHTS")
	if not build.has("lights"): build.lights = {"model": "luma"}
	var sig := _build_sig()
	var litems := []
	for id in BikeLight.ORDER:
		var lm: Dictionary = BikeLight.MODELS[id]
		litems.append({"key": id, "brand": lm.brand, "name": lm.label, "kind": "light", "spec": BikeLight.spec_line(id),
			"thumb": "light|%s|%s" % [id, sig], "make": _spot_make.bind(id, "lights.model", "light"),
			"view": Vector3(0.9, 0.55, -0.7)})
	_cards(litems, str(build.lights.get("model", "luma")), func(v): build.lights.model = v)
	_note("A lamp on the bars (small to big: more lumens = a longer, wider beam) and a red tail light. They switch on by themselves when it gets dark.")

func _brakes_page() -> void:
	var S: Dictionary = build.suspension
	_h("DISC BRAKES")
	_pic_cards(BikeBuild.ROTORS, str(S.get("rotor", "stock")), "rotor|" + PRODUCT, _spot_make.bind("suspension.rotor", "rotor"),
		Vector3(0.15, 0.2, -1.0), func(v): S.rotor = v)
	_h("REAR CALIPER")
	_pic_cards(BikeBuild.REAR_CALIPERS, str(S.get("rear_caliper", "stock")), "caliper|" + PRODUCT,
		_spot_make.bind("suspension.rear_caliper", "caliper"), Vector3(-0.15, 0.3, -1.0), func(v): S.rear_caliper = v)
	_note("Rotors fit every frame. The front caliper comes with the fork (Shocks tab); the Tusk and Fizz rear calipers fit the RUNOUT's rear triangle, the new frames keep their own.")
	_h("LEVERS")
	var B: Dictionary = build.bars
	_pic_cards(BikeBuild.LEVERS, str(B.get("levers", "stock")), "levers|" + PRODUCT, _spot_make.bind("bars.levers", "levers"),
		Vector3(0.65, 0.85, -0.55), func(v): B.levers = v)

func _susp_page() -> void:
	var S: Dictionary = build.suspension
	var rate := [[0, "Soft"], [1, "Medium"], [2, "Firm"]]
	_h("FORK")
	var items := []
	for k in BikeBuild.FORK_MODELS:
		var m: Dictionary = BikeBuild.FORK_MODELS[k]
		items.append({"key": k, "brand": m.brand, "name": m.label,
			"spec": "%s  ·  %d mm  ·  %s  ·  %s stanchions" % [BikeBuild.star_text(BikeBuild.part_stars("fork", k)), m.travel, m.spring, m.coat],
			"thumb": "fork|%s|%s" % [k, PRODUCT], "kind": "fork",
			"make": PartThumbs.make_fork.bind(m.lowers, m.stanchions, _product_paint("crown"), str(m.get("glb", ""))), "view": Vector3(0.35, 0.22, 1.0)})
	_cards(items, S.get("fork_model", "custom"), func(k): BikeBuild.apply_fork_model(build, k))
	_slide("Travel", 160, 220, 10, S.fork_travel, "mm", func(v): S.fork_travel = int(v); S.fork_model = "custom")
	# the setup, like on a real bike: sag (how far it sits into its travel: air pressure / spring rate), volume
	# spacers (how hard the end ramps up), and the damper's clicks. A damper only shows the adjusters it has
	var fmod: Dictionary = BikeBuild.FORK_MODELS.get(str(S.get("fork_model", "")), {})
	var f_air: bool = str(fmod.get("spring", "Air")).to_lower() != "coil"
	var f_adj: Array = fmod.get("adj", ["lsc", "hsc", "reb"])
	_slide("Sag (%s)" % ("air pressure" if f_air else "spring rate"), SuspSetup.SAG_MIN, SuspSetup.SAG_MAX, 1, float(SuspSetup.val(S, "fork_sag")), "%", func(v): S.fork_sag = int(v))
	_slide("Volume spacers" if f_air else "Bottom-out bumper", 0, 4, 1, float(SuspSetup.val(S, "fork_tokens")), "", func(v): S.fork_tokens = int(v))
	if f_adj.has("lsc"): _slide("LS compression", 0, SuspSetup.CLICKS, 1, float(SuspSetup.val(S, "fork_lsc")), "clicks", func(v): S.fork_lsc = int(v))
	if f_adj.has("hsc"): _slide("HS compression", 0, SuspSetup.CLICKS, 1, float(SuspSetup.val(S, "fork_hsc")), "clicks", func(v): S.fork_hsc = int(v))
	if f_adj.has("reb"): _slide("Rebound damping", 0, SuspSetup.CLICKS, 1, float(SuspSetup.val(S, "fork_reb")), "clicks", func(v): S.fork_reb = int(v))
	_h("REAR SHOCK")
	var shocks := []
	for sk in SuspSetup.SHOCK_MODELS:
		var smd: Dictionary = SuspSetup.SHOCK_MODELS[sk]
		shocks.append([sk, "%s %s" % [str(smd.brand).capitalize(), smd.label]])
	_choice("Shock", shocks, str(SuspSetup.val(S, "shock_model")), func(v): S.shock_model = v)
	var smod: Dictionary = SuspSetup.SHOCK_MODELS.get(str(SuspSetup.val(S, "shock_model")), SuspSetup.SHOCK_MODELS[SuspSetup.DEFAULT_SHOCK])
	var s_air: bool = str(smod.spring) == "air"
	var s_adj: Array = smod.adj
	_note(str(smod.note))
	_slide("Travel", 160, 220, 10, S.shock_travel, "mm", func(v): S.shock_travel = int(v))
	_slide("Sag (%s)" % ("air pressure" if s_air else "spring rate"), SuspSetup.SAG_MIN, SuspSetup.SAG_MAX, 1, float(SuspSetup.val(S, "shock_sag")), "%", func(v): S.shock_sag = int(v))
	_slide("Volume spacers" if s_air else "Bottom-out bumper", 0, 4, 1, float(SuspSetup.val(S, "shock_tokens")), "", func(v): S.shock_tokens = int(v))
	if s_adj.has("lsc"): _slide("LS compression", 0, SuspSetup.CLICKS, 1, float(SuspSetup.val(S, "shock_lsc")), "clicks", func(v): S.shock_lsc = int(v))
	if s_adj.has("hsc"): _slide("HS compression", 0, SuspSetup.CLICKS, 1, float(SuspSetup.val(S, "shock_hsc")), "clicks", func(v): S.shock_hsc = int(v))
	if s_adj.has("reb"): _slide("Rebound damping", 0, SuspSetup.CLICKS, 1, float(SuspSetup.val(S, "shock_reb")), "clicks", func(v): S.shock_reb = int(v))
	_h("TYRE PRESSURE")
	var W: Dictionary = build.wheels
	_slide("Front", SuspSetup.PSI_MIN, SuspSetup.PSI_MAX, 1, float(W.get("psi_f", SuspSetup.DEFAULTS.psi_f)), "psi", func(v): W.psi_f = int(v))
	_slide("Rear", SuspSetup.PSI_MIN, SuspSetup.PSI_MAX, 1, float(W.get("psi_r", SuspSetup.DEFAULTS.psi_r)), "psi", func(v): W.psi_r = int(v))
	var su := SuspSetup.resolve(build)
	_note("Fork: %s.
Shock: %s.
More sag = softer and grippier, but it bottoms sooner. Low-speed compression holds the bike up under braking and pumping; high-speed takes the big hits; slow rebound is planted, fast is lively. Soft tyres grip and soak up chatter but hit the rim on hard landings." % [SuspSetup.describe(su.f), SuspSetup.describe(su.r)])

## "Gripwell Raptor DHF" + GRIPWELL -> "Raptor DHF" (the card shows the brand above the name)
static func _model_name(label: String, brand: String) -> String:
	if label.to_upper().begins_with(brand): return label.substr(brand.length()).strip_edges()
	var w := label.split(" ", false, 1)
	if w.size() > 1 and brand.begins_with(w[0].to_upper()): return w[1]
	return label

## tyre / rim model cards: a front wheel built with that model on the current wheel
func _wheel_cards(models: Dictionary, current: String, apply: Callable, spec_line: Callable, kind: String) -> void:
	var items := []
	for k in models:
		var m: Dictionary = models[k]
		if not m.has("brand"): continue
		var tmp: Dictionary = BikeBuild.default_build()   # the product on the stock wheel (PRODUCT)
		apply.call(tmp, k)
		var spec := BikeBuild.wheel_spec(tmp, false)
		items.append({"key": k, "brand": m.brand, "name": _model_name(m.label, m.brand),
			"spec": BikeBuild.star_text(BikeBuild.part_stars(kind, k)) + "  ·  " + String(spec_line.call(m)),
			"thumb": "%s|%s|%s" % [kind, k, JSON.stringify(spec)], "kind": kind,
			"make": PartThumbs.make_wheel.bind(spec, 0.3) if kind == "tyre" else PartThumbs.make_wheelset.bind(spec),
			"view": Vector3(0.25, 0.75, 1.0) if kind == "tyre" else Vector3(0.05, 0.12, 1.0)})
	_cards(items, current, func(k): apply.call(build, k))

func _drive_page() -> void:
	var D: Dictionary = build.drive
	_h("CHAINRING")
	_slide("Teeth", 30, 38, 2, D.ring, "T", func(v): D.ring = int(v))
	_h("CASSETTE")
	var items := []
	for k in BikeBuild.CASSETTES:
		var m: Dictionary = BikeBuild.CASSETTES[k]
		var cg: Array = m.cogs
		var spec := "%d-speed  ·  %d–%dT" % [cg.size(), cg[0], cg[cg.size() - 1]] if cg.size() > 1 else "Single speed  ·  %dT" % cg[0]
		if cg[cg.size() - 1] >= 50: spec = "▲ " + spec   # a granny gear for climbing
		items.append({"key": k, "brand": m.brand, "name": m.name, "spec": spec,
			"thumb": "cassette|%s" % k, "kind": "cassette", "make": PartThumbs.make_cassette.bind(k), "view": Vector3(0.45, 0.35, 1.0)})
	_cards(items, D.cassette, func(k): D.cassette = k)
	var cogs: Array = BikeBuild.CASSETTES[D.cassette].cogs
	var lo := float(D.ring) / float(cogs[cogs.size() - 1])
	var hi := float(D.ring) / float(cogs[0])
	_note("Ratios %.2f – %.2f. Bigger ring / smaller cog = higher top speed, harder to get going. ▲ = a huge last cog (50T+): spins up the steepest hills." % [lo, hi])
	_h("PEDALS")
	var own := str(GameState.BIKES[GameState.bike_id].file)
	_pic_cards(BikeBuild.PEDALS, str(D.get("pedals", "stock")), "pedal|" + own, PartThumbs.make_pedal.bind(own),
		Vector3(0.55, 0.75, 1.0), func(v): D.pedals = v)
	_note("Flat pedals from the bike models, on any frame. Their colour is in Paint > Saddle & pedals.")

func _save_rider_ui() -> void:
	var cf := ConfigFile.new(); cf.load(RiderPanels.PATH)
	cf.set_value("garage", "preview", rider_preview)
	cf.save(RiderPanels.PATH)

## Position (rider room): the rider pedals on the rollers in a chosen situation; every joint has a
## slider, and the pose is the one used on the trail
func _rider_page() -> void:
	var items := []
	for k in PREVIEWS: items.append([k, PREVIEWS[k].label])
	_choice("Preview", items, rider_preview, func(v): rider_preview = v; _save_rider_ui())
	_pose_presets()
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", Tokens.S2)
	row.add_child(UITheme.make_button("Reset pose", func():
		rider_pose = PosePresets.preset(PosePresets.get_active())   # back to the chosen position
		_apply_rider_pose(); _set_tab("rider"), "chip", Tokens.T_MD))
	row.add_child(UITheme.make_button("Mirror L → R", func():
		rider_pose.elbowOutR = rider_pose.elbowOutL; rider_pose.kneeOutR = rider_pose.kneeOutL
		_apply_rider_pose(); _set_tab("rider"), "chip", Tokens.T_MD))
	body.add_child(row)
	for g in RiderPanels.POSE_DEFS:
		_h(g[0].to_upper())
		for r in g[1]:
			var key: String = r[0]
			var unit: String = r[5]
			var stp: float = r[4]
			var hb := HBoxContainer.new()
			var s := HSlider.new()
			s.scrollable = false   # (the wheel scrolls the list; it never changes a value by accident)
			s.min_value = r[2]; s.max_value = r[3]; s.step = stp; s.value = float(rider_pose.get(key, 0.0))
			s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			var dec := clampi(ceili(-log(stp) / log(10.0)), 0, 3)
			var fmt := "%." + str(dec) + "f " + unit
			var vl := UITheme.text(fmt % s.value, SUB, Tokens.T_XS)
			vl.custom_minimum_size.x = 70
			s.value_changed.connect(func(v): vl.text = fmt % v; rider_pose[key] = v; _apply_rider_pose())
			hb.add_child(s); hb.add_child(vl)
			_row(r[1], hb)

## Kit (rider room): the rider stands beside the bike; kits and a colour for every part of their gear
func _kit_page() -> void:
	var look := RiderPanels.load_look()
	_h("KITS")
	var kits := GridContainer.new(); kits.columns = 3
	kits.add_theme_constant_override("h_separation", Tokens.S2); kits.add_theme_constant_override("v_separation", Tokens.S2)
	for k in RiderPanels.KITS:
		var kit_look: Dictionary = Rider.DEFAULT_LOOK.duplicate()
		kit_look.merge(k[1], true)
		var b := Button.new()
		b.text = k[0]
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size.y = 52
		b.add_theme_font_size_override("font_size", Tokens.T_MD)
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
		b.pressed.connect(func():
			var cur := RiderPanels.load_look()
			var merged := kit_look.duplicate()
			for key in RiderPanels.NON_KIT: merged[key] = cur[key]   # a kit changes the clothes, not the head / plate
			_set_look(merged); _set_tab("kit"))
		kits.add_child(b)
	body.add_child(kits)
	for g in RiderPanels.LOOK_ROWS:
		var textured: bool = str(look.helmet) != "glory"   # the textured helmets carry their own paint + goggles: no colour rows
		if textured and g[0] == "Goggles":
			continue
		_h(g[0].to_upper())
		if g[0] == "Helmet":
			body.add_child(UITheme.text("Model (the textured ones come with their goggles)", SUB, Tokens.T_XS))
			var hl := []
			for hid in Rider.HELMETS: hl.append([hid, String(Rider.HELMETS[hid][0])])
			_pic_cards(hl, RiderPanels.helmet_choice(look), "head|helm|%s|%s" % [look.shell, look.peak],
				_head_make.bind(look, "helmet", 0.0, {"camMount": "none", "hairStyle": "short"}), Vector3(1.0, 0.25, 0.75), func(id):
				RiderPanels.helmet_set(look, id); _set_look(look), false)
			body.add_child(UITheme.text("Hair style", SUB, Tokens.T_XS))
			_pic_cards(Hair.HELMET_STYLES, str(look.hairStyle), "head|hair|%s|%s" % [look.helmet, look.hair],
				_head_make.bind(look, "hairStyle", 0.22, {"camMount": "none"}), Vector3(-1.0, 0.2, 0.55), func(id):
				look.hairStyle = id; _set_look(look), false)
		if g[0] == "Kit":
			body.add_child(UITheme.text("Knee pads design", SUB, Tokens.T_XS))
			body.add_child(RiderPanels.pad_style_picker(str(look.padStyle), func(id):
				look.padStyle = id; _set_look(look); _set_tab("kit")))
			body.add_child(UITheme.text("Pants fabric", SUB, Tokens.T_XS))
			body.add_child(RiderPanels.choice_picker(PantsLook.FABRICS, str(look.get("pantsFabric", PantsLook.DEFAULT_FABRIC)), func(id):
				look.pantsFabric = id; _set_look(look); _set_tab("kit"), 13, 3))
			body.add_child(UITheme.text("Pants pattern", SUB, Tokens.T_XS))
			body.add_child(RiderPanels.choice_picker(PantsLook.PATTERNS, str(look.get("pantsPattern", PantsLook.DEFAULT_PATTERN)), func(id):
				look.pantsPattern = id; _set_look(look); _set_tab("kit"), 13, 3))
		if g[0] == "Belt":
			body.add_child(UITheme.text("Style", SUB, Tokens.T_XS))
			body.add_child(RiderPanels.belt_style_picker(str(look.beltStyle), func(id):
				look.beltStyle = id; _set_look(look); _set_tab("kit")))
		for row in g[1]:
			if textured and g[0] == "Helmet" and row[0] != "hair":
				continue
			var key: String = row[0]
			var hb := HBoxContainer.new()
			hb.add_theme_constant_override("separation", Tokens.S2)
			# the part's name on its own line above its colours: the full name fits and the swatches line up
			body.add_child(UITheme.text(row[1], SUB, Tokens.T_XS))
			for hex in row[2]:
				var b := Button.new()
				b.custom_minimum_size = Vector2.ONE * Tokens.S6
				var sel: bool = str(look[key]).to_lower() == str(hex).to_lower()
				b.add_theme_stylebox_override("normal", UITheme.marked(Color(hex), INK, SIDE_BOTTOM, Tokens.R_SM, 0) if sel else UITheme.box(Color(hex), Tokens.R_SM, 0))
				b.add_theme_stylebox_override("hover", UITheme.marked(Color(hex), Tokens.ACCENT, SIDE_BOTTOM, Tokens.R_SM, 0))
				b.add_theme_stylebox_override("pressed", UITheme.marked(Color(hex), Tokens.ACCENT, SIDE_BOTTOM, Tokens.R_SM, 0))
				b.add_theme_stylebox_override("focus", UITheme.marked(Tokens.CLEAR, Tokens.INK, SIDE_TOP, Tokens.R_SM, 0))
				b.pressed.connect(func(): look[key] = hex; _set_look(look); _set_tab("kit"))
				hb.add_child(b)
			var cp := ColorPickerButton.new()
			cp.color = Color(look[key]); cp.edit_alpha = false
			cp.custom_minimum_size = Vector2(Tokens.S7, Tokens.S6)
			cp.focus_mode = Control.FOCUS_NONE
			cp.color_changed.connect(func(c): look[key] = "#" + c.to_html(false); _set_look(look, false))   # live while dragging
			cp.popup_closed.connect(func(): RiderPanels.save_look(look))   # written once, when the picker closes
			hb.add_child(cp)
			body.add_child(hb)
	# the helmet camera: where it sits, which camera, lens, housing, mic, top accessory
	_h("ACTION CAM")
	body.add_child(UITheme.text("Mount (the Helmet camera view looks out of it)", SUB, Tokens.T_XS))
	_pic_cards(ActionCam.HELMET_MOUNTS, str(look.get("camMount", "top")), "head|cam|%s|%s" % [look.helmet, ActionCam.gear_sig(ActionCam.gear_from_look(look))],
		_head_make.bind(look, "camMount", 0.0, {"hairStyle": "short"}), Vector3(0.75, 0.45, -1.0), func(id):
		look.camMount = id; _set_look(look), false)
	for r in ActionCam.GEAR_ROWS:
		var gk: String = r[0]
		var lk: String = ActionCam.GEAR_LOOK[gk]
		body.add_child(UITheme.text(r[1], SUB, Tokens.T_XS))
		_pic_cards(r[2], str(look.get(lk, ActionCam.GEAR_DEFAULT[gk])), "cam|%s|%s" % [gk, PRODUCT],   # the product (same pictures as the bike cam's)
			_cam_make.bind(gk, _product_gear()), Vector3(1.0, 0.45, 0.75), func(v): look[lk] = v; _set_look(look), false)
	_note("Lens mods change the Helmet view: the Max Lens Mod is wider. The Light Mod lights the trail at night.")
	body.add_child(UITheme.make_button("Reset kit", func(): _set_look(Rider.DEFAULT_LOOK.duplicate()); _set_tab("kit"), "chip", Tokens.T_MD))

## the rider's head for a picture: `look` with `key` = id (and `extra` keys) set
static func _head_make(id: String, look: Dictionary, key: String, below: float, extra: Dictionary) -> Node3D:
	var lk := look.duplicate()
	lk.merge(extra, true)
	lk[key] = id
	lk.helmetOn = "1"
	return PartThumbs.make_head(lk, below)

func _set_look(l: Dictionary, write := true) -> void:
	if write: RiderPanels.save_look(l)
	if stand_rider: stand_rider.set_look(l)
	if rider: rider.set_look(l)

## the frame whose riding pose the rider room edits: the selected garage frame (the ride loads its pose by bike id)
func _pose_bike() -> String:
	return GameState.bike_id if GameState.BIKES[GameState.bike_id].get("garage", false) else "dh"

## the pose is applied live on every slider tick but written to rider.cfg once it settles (not 60x a second)
var _pose_save_t := 0.0
var _pose_save_bike := ""
func _flush_pose() -> void:
	if _pose_save_t == 0.0 and _pose_save_bike == "": return
	_pose_save_t = 0.0
	RiderPanels.save_pose(_pose_save_bike, rider_pose)
	PosePresets.flush()   # an own preset that followed the sliders
	_pose_save_bike = ""
	if is_instance_valid(_pose_mod): _pose_mod.visible = PosePresets.is_builtin(PosePresets.get_active()) and PosePresets.modified(rider_pose)

func _apply_rider_pose() -> void:
	if rider: rider.set_style(rider_pose)
	var b := _pose_bike()
	if _pose_save_bike != "" and _pose_save_bike != b: _flush_pose()   # the bike changed under a pending save
	_pose_save_bike = b; _pose_save_t = 0.4
	PosePresets.bike = _pose_bike()
	PosePresets.pose_changed(rider_pose, false)   # in memory; written with the pose in _flush_pose
	if is_instance_valid(_pose_mod): _pose_mod.visible = PosePresets.is_builtin(PosePresets.get_active()) and PosePresets.modified(rider_pose)

## riding position presets: pick one (it is the pose you ride with), Save as your own, Delete yours
var _pose_mod: Label
func _pose_presets() -> void:
	PosePresets.bike = _pose_bike()
	var names: Array = PosePresets.names()
	var act := PosePresets.get_active()
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", Tokens.S2)
	var ob := OptionButton.new()
	ob.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for i in names.size():
		var n: String = names[i]
		if i == PosePresets.builtin_count(): ob.add_separator("Yours")
		ob.add_item(n if PosePresets.is_builtin(n) else "★ " + n, i)
		if n == act: ob.select(ob.get_item_index(i))
	ob.item_selected.connect(func(idx):
		_flush_pose()   # a pending slider pose goes to the old preset first
		PosePresets.select(names[ob.get_item_id(idx)])
		rider_pose = RiderPanels.load_pose(_pose_bike(), GameState.BIKES[_pose_bike()].pose)
		if rider: rider.set_style(rider_pose)
		_set_tab.call_deferred("rider"))
	hb.add_child(ob)
	if not PosePresets.is_builtin(act):
		var del := UITheme.make_button("Delete", func(): _flush_pose(); PosePresets.delete(act); _set_tab.call_deferred("rider"), "chip", Tokens.T_SM)
		hb.add_child(del)
	_row("Position", hb)
	_pose_mod = UITheme.text("Changed from \"%s\" — Save as to keep it" % act, SUB, Tokens.T_XS)
	_pose_mod.visible = PosePresets.is_builtin(act) and PosePresets.modified()
	body.add_child(_pose_mod)
	var sv := HBoxContainer.new()
	sv.add_theme_constant_override("separation", Tokens.S2)
	var le := LineEdit.new()
	le.placeholder_text = "New position name"
	le.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var save := func(): _flush_pose(); PosePresets.save_as(le.text); _set_tab.call_deferred("rider")   # save_as reads the saved pose
	le.text_submitted.connect(func(_t): save.call())
	sv.add_child(le)
	var sb := UITheme.make_button("Save as", save, "chip", Tokens.T_SM)
	sv.add_child(sb)
	body.add_child(sv)

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
	var base := -1.0   # >= 0 while a part is previewed: the value as fitted now (the change shows green / red)
	func _draw() -> void:
		# a slim rounded track with quarter ticks, the value filled in yellow, its number at the end. Previewing a part:
		# what it would add shows green past the fitted value, what it would take away red below it.
		var num_w := 26.0
		var bw := size.x - num_w
		var th := minf(size.y, 7.0)
		var y0 := (size.y - th) * 0.5
		var r := th * 0.5
		var pill := func(x0: float, x1: float, col: Color) -> void:
			if x1 - x0 < 0.5: return
			var sb := StyleBoxFlat.new()
			sb.bg_color = col
			sb.set_corner_radius_all(int(r))
			draw_style_box(sb, Rect2(x0, y0, x1 - x0, th))
		pill.call(0.0, bw, Tokens.TRACK)
		var v := clampf(k, 0.0, 1.0)
		if base >= 0.0:
			var b := clampf(base, 0.0, 1.0)
			pill.call(0.0, maxf(bw * minf(b, v), th), Tokens.ACCENT_DOWN)
			if v > b: pill.call(bw * b - th, bw * v, Color("1f9d55"))
			elif v < b: pill.call(bw * v - th, bw * b, Color(0.82, 0.2, 0.17, 0.55))
			pill.call(0.0, maxf(bw * minf(b, v), th), Tokens.ACCENT_DOWN)   # (the kept part on top of the change's round end)
		else:
			pill.call(0.0, maxf(bw * v, th), Tokens.ACCENT_DOWN)
		for q in [0.25, 0.5, 0.75]:   # quarter marks: thin cuts through the track
			draw_rect(Rect2(bw * q - 0.75, y0, 1.5, th), Color.WHITE)
		var f := get_theme_default_font()
		var txt := str(roundi(v * 100.0))
		var fs := Tokens.T_SM
		var tw := f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var col := Tokens.INK
		if base >= 0.0 and absf(v - base) > 0.004: col = Color("1f9d55") if v > base else Color("d0342c")
		draw_string(f, Vector2(size.x - tw, size.y * 0.5 + fs * 0.36), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
