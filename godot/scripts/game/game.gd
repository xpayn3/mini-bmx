class_name Game
extends Node3D
## One ride: world, bike, rider, camera, HUD. Port of the scene setup + frame loop of src/main.js.
## Physics runs in _physics_process at 120 Hz (project setting); the bike is drawn between the last
## two physics states so motion stays smooth at any frame rate.

signal quit_to_menu

## the sun: the web version's compass direction, at the HDRI's real sun height (48 deg)
const SUN_AZ := Vector2(-0.55, 0.42)
const SUN_ELEV := 0.8376   # 48 deg
const HDRI_SUN_U := 0.5952  # where the sun is across the HDRI (tools/hdri_sun.gd)
static var SUN_DIR := Vector3(SUN_AZ.normalized().x * cos(SUN_ELEV), sin(SUN_ELEV), SUN_AZ.normalized().y * cos(SUN_ELEV))
const SKY := Color("a9d6ea")
const DUST_SPLASH := Color("eef6fa")
const DIRT_CHUNK := Color("7a5534")
const ROCK_CHUNK := Color("8d8a84")
const GRASS_CHUNK := Color("4f8a2e")
const TRACK_DIRT := Color("4a3220")
const TRACK_GRASS := Color("3d5a22")

var terrain
var fx
var ragdoll
var rider
var rig: BikeRig
var phys: BikePhysics
var cam: CameraRig
var hud
var audio
var sun: DirectionalLight3D
var env: Environment
var cam_attr: CameraAttributesPractical
var grade_rect: ColorRect
var susp = null
var pedal_a0 := [0.0, PI]

var bike_cfg: Dictionary
var t := 0.0
var drawn_pos := Vector3.ZERO
var _prev := {}
var _last_good := {}
var msg_t := 0.0
var biome_t := 0.0
var biome_cur := "Green Hills"
var biome_next := ""
var biome_hold := 0
var takeoff := Vector3.ZERO
var air_peak := 0.0
var input_enabled := true

func _ready() -> void:
	bike_cfg = GameState.bike_config()
	Tune.set_ride(bike_cfg.ride)
	_build_environment()
	terrain = load("res://scripts/world/terrain.gd").new()
	add_child(terrain)
	terrain.set_seed(GameState.seed)
	terrain.update_stream(0, 0, INF)
	fx = load("res://scripts/fx/fx.gd").new()
	add_child(fx)
	if fx.has_method("setup"): fx.setup(terrain)
	rig = BikeRig.new()
	add_child(rig)
	rig.load_bike(bike_cfg, bike_cfg.get("build", {}))
	susp = rig.susp
	pedal_a0 = rig.pedal_a0
	phys = BikePhysics.new(self)
	phys.T = Tune.v
	phys.setup(rig.extras, bike_cfg)
	ragdoll = Ragdoll.new(terrain)
	rider = load("res://scripts/rider/rider.gd").new()
	rig.lean_g.add_child(rider)
	rider.set_look(Rider.DEFAULT_LOOK)
	rider.set_style(bike_cfg.pose)
	phys.bike_rock = float(rider.style.get("bikeRock", 1.0)) if rider.get("style") is Dictionary else 1.0
	if rig.seat != null: rider.seat = rig.seat
	var grip := rig.grip_mid()
	rider.fit = Vector3((grip.x - 0.4388) * 0.5, ((grip.y - 0.9646) + (rig.crank_n.position.y - 0.297)) * 0.5, 0)
	var hs: Node3D = load("res://assets/helmet.glb").instantiate()
	var helmet := hs.find_child("helmet", true, false)
	if helmet:
		helmet.get_parent().remove_child(helmet)
		rider.set_helmet(helmet)
	hs.free()
	cam = CameraRig.new()
	cam.game = self
	add_child(cam)
	cam.current = true
	cam.set_mode(Settings.get_v("camera"))
	hud = load("res://scripts/ui/hud.gd").new()
	hud.game = self
	add_child(hud)
	audio = load("res://scripts/game/ride_audio.gd").new()
	audio.game = self
	add_child(audio)
	Tune.changed.connect(func(): phys.T = Tune.v)
	Settings.changed.connect(_apply_settings)
	_apply_settings()
	respawn(false)

# ---------------------------------------------------------------- environment
func _build_environment() -> void:
	var we := WorldEnvironment.new()
	env = Environment.new()
	var sky := Sky.new()
	var sm := ShaderMaterial.new()
	sm.shader = load("res://shaders/sky_hdri.gdshader")
	var htex: Texture2D = load("res://assets/hdri/kloofendal_48d_partly_cloudy_puresky_4k.hdr")
	sm.set_shader_parameter("hdri", htex)
	# turn the sky so the photographed sun lines up with our sun light
	var target := atan2(SUN_DIR.x, -SUN_DIR.z)
	sm.set_shader_parameter("rotation", target - (HDRI_SUN_U - 0.5) * TAU)
	sm.set_shader_parameter("energy", 1.0)
	sm.set_shader_parameter("light_energy", 0.7)
	sky.radiance_size = Sky.RADIANCE_SIZE_256
	sky.sky_material = sm
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_sky_contribution = 1.0
	env.ambient_light_energy = 0.42   # the web version: sky env 0.55 + a 0.32 hemisphere fill
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 0.85
	env.tonemap_white = 6.0
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_light_color = Color(0.7, 0.78, 0.86)   # the HDRI's hazy horizon
	env.fog_density = 1.0
	env.fog_sky_affect = 0.25
	env.fog_depth_curve = 1.0
	env.ssao_radius = 0.6
	env.ssao_intensity = 2.0
	env.ssao_power = 1.5
	env.glow_intensity = 0.2
	env.glow_bloom = 0.0
	env.glow_hdr_threshold = 0.92
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.22
	env.adjustment_contrast = 1.08
	we.environment = env
	cam_attr = CameraAttributesPractical.new()
	cam_attr.dof_blur_amount = 0.06
	we.camera_attributes = cam_attr
	add_child(we)
	sun = DirectionalLight3D.new()
	sun.light_color = Color("ffd7a3")
	sun.light_energy = 1.6
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 90.0
	sun.shadow_bias = 0.03
	sun.shadow_normal_bias = 1.0
	add_child(sun)
	sun.look_at_from_position(SUN_DIR.normalized(), Vector3.ZERO, Vector3.UP)
	# colour grade (split tone) + vignette, drawn over the 3D view
	var cl := CanvasLayer.new(); cl.layer = -1
	grade_rect = ColorRect.new()
	grade_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	grade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var gm := ShaderMaterial.new(); gm.shader = load("res://shaders/grade.gdshader")
	grade_rect.material = gm
	cl.add_child(grade_rect)
	add_child(cl)

func _apply_settings() -> void:
	env.ssao_enabled = Settings.get_v("ssao")
	env.ssr_enabled = Settings.get_v("ssr")
	env.adjustment_brightness = float(Settings.get_v("brightness"))
	env.glow_enabled = Settings.get_v("bloom")
	grade_rect.visible = Settings.get_v("grade")
	cam_attr.dof_blur_far_enabled = Settings.get_v("tilt_shift")
	cam_attr.dof_blur_near_enabled = Settings.get_v("tilt_shift")
	if hud: hud.apply_settings()

# ---------------------------------------------------------------- host API used by BikePhysics
func flash(text: String) -> void:
	msg_t = 1.4
	if hud: hud.flash(text)

func msg_idle() -> bool:
	return msg_t <= 0

func flow_up() -> void:
	phys.flow_up()

func ground_dust(px: float, pz: float, s: int) -> Color:
	if s == 2: return DUST_SPLASH
	var c: Color = terrain.ground_color(px, pz)
	return c.lerp(Color.WHITE, 0.42 if s == 0 else 0.28)

func burst(pos: Vector3, n: int, s: int, power: float) -> void:
	if s == 2: return
	var dc := ground_dust(pos.x, pos.z, s)
	for i in n:
		var a := randf() * TAU
		var r := (0.6 + randf()) * power
		fx.puff(pos + Vector3(cos(a) * 0.15, 0.05, sin(a) * 0.15), Vector3(cos(a) * r, 0.25 + randf() * 0.6, sin(a) * r), dc, 0.6, 3.4, 0.6 if s == 1 else 0.5 if s == 3 else 0.3)
		if i % 2 == 0:
			var cc: Color = DIRT_CHUNK if s == 1 else (dc * 0.8 if s == 3 else (GRASS_CHUNK if randf() < 0.5 else ROCK_CHUNK))
			fx.chunk(Vector3(pos.x, pos.y + 0.05, pos.z), Vector3(cos(a) * r * 0.9, 1.2 + randf() * 1.8 * power, sin(a) * r * 0.9), cc, 0.028)
	if audio: audio.thud(power)

func smash(c: Dictionary, vel: Vector3, pos: Vector3) -> bool:
	if not terrain.break_collider(c, vel):
		return false
	var col := Color("c9a06a")
	if c.get("cactus", false): col = Color("8fc25a")
	elif c.get("tape", false): col = Color("e8322b")
	for k in 12:
		fx.chunk(Vector3(c.x, pos.y + 0.3 + randf() * 0.6, c.z), Vector3(vel.x * 0.4 + (randf() - .5) * 3, 1 + randf() * 2.5, vel.z * 0.4 + (randf() - .5) * 3), col, 0.025)
	for k in 3:
		fx.puff(Vector3(c.x, pos.y + 0.4, c.z), Vector3((randf() - .5) * 1.5, 0.4 + randf() * 0.5, (randf() - .5) * 1.5), Color("cdb894"), 0.35, 1.4, 0.4)
	if audio: audio.crunch()
	return true

func rock_chips(c: Dictionary) -> void:
	for k in 6:
		fx.chunk(Vector3(c.x, c.top, c.z), Vector3((randf() - .5) * 2, 1 + randf(), (randf() - .5) * 2), ROCK_CHUNK, 0.02)

func start_crash(reason: String) -> void:
	phys.crash_pending = ""
	if phys.crash_on: return
	var pts: Array = rider.joints_world()
	var f := phys.fwd()
	var body_vel := f * phys.v + Vector3(0, minf(maxf(phys.vy, 0), 6.0 if phys.air else 1.0) + 1.2, 0)
	var spin_v := f * (2.2 + absf(phys.v) * 0.25)
	phys.begin_crash()
	# detach the rider into world space
	rider.get_parent().remove_child(rider)
	add_child(rider)
	rider.transform = Transform3D.IDENTITY
	ragdoll.start(pts, body_vel, spin_v, 1.0 / 60)
	rider.pose_ragdoll(ragdoll.p)
	burst(Vector3(phys.x, phys.y + 0.05, phys.z), 30, terrain.surface(phys.x, phys.z), 1.5)
	flash(reason)
	if hud: hud.on_crash()
	if audio: audio.crash()
	Settings.rumble(1.0, 1.0, 0.45)

func get_up() -> void:
	phys.get_up()
	ragdoll.active = false
	if rider.get_parent() != rig.lean_g:
		rider.get_parent().remove_child(rider)
		rig.lean_g.add_child(rider)
	rider.transform = Transform3D.IDENTITY
	rider.reset_pose()
	_snap_prev()

func on_takeoff() -> void:
	takeoff = Vector3(phys.x, phys.y, phys.z)
	air_peak = phys.y
	if hud: hud.on_takeoff()

func on_landing(air_time: float, impact: float) -> void:
	var dist := Vector2(phys.x - takeoff.x, phys.z - takeoff.z).length()
	var height := air_peak - maxf(takeoff.y, phys.y)
	if hud: hud.on_landing(air_time, dist, maxf(0.0, height), impact)
	if air_time > 0.2: Settings.rumble(clampf(impact / 8, 0.15, 1), clampf(impact / 12, 0, 1), 0.12 + minf(0.25, impact * 0.02))

## dust / roost / tyre tracks for one physics step (bottom of physics() in main.js)
func ride_fx(dt: float, f: Vector3, va: float, in_water: bool) -> void:
	var st := phys
	var bb := st.BB_REAR
	var rear := Vector3(st.x - f.x * bb, st.y + 0.03, st.z - f.z * bb)
	var front := Vector3(st.x + f.x * (st.L - bb), st.y + 0.03, st.z + f.z * (st.L - bb))
	var s := st.surf
	var dcol := ground_dust(rear.x, rear.z, s)
	var sand := s == 3
	var skid_fx := st.skid_fx
	if st.air: air_peak = maxf(air_peak, st.y)
	if not st.air and va > 0.6:
		var dirt := s == 1
		var side := Vector3(-f.z, 0, f.x)
		var lat_a := absf(st.v * st.yaw_rate)
		var turn_dir := signf(st.yaw_rate)
		var carve_k := clampf((lat_a - 1.5) / 6, 0, 1)
		var fast_k := clampf((va - 8) / 6, 0, 1)
		var rate := 0.0
		if in_water: rate = 0.0
		elif dirt: rate = fast_k * 14 + (50.0 if skid_fx else 0.0) + carve_k * 60 + st.pedal * (6.0 if va < 3 else 0.0)
		elif sand: rate = fast_k * 10 + (40.0 if skid_fx else 0.0) + carve_k * 45 + st.pedal * (4.0 if va < 3 else 0.0)
		else: rate = (14.0 if skid_fx else 0.0) + carve_k * 12
		var fxd: float = Settings.get_v("fx_density")
		st.dust_acc += dt * rate * fxd
		while st.dust_acc > 1:
			st.dust_acc -= 1
			var out := turn_dir * carve_k * (2 + randf() * 3)
			var fan := (randf() - .5) * (1.6 + va * 0.18) * (1 - carve_k * 0.6)
			var back := va * 0.3 * (1 - carve_k * 0.55)
			var ev := Vector3(-f.x * back + side.x * (out + fan), 0.35 + randf() * 0.7 + carve_k * 0.4, -f.z * back + side.z * (out + fan))
			var a := (0.62 if skid_fx else 0.45) if dirt else ((0.55 if skid_fx else 0.4) if sand else 0.26)
			fx.puff(rear, ev, dcol * (0.86 if randf() < 0.3 else 1.0), 0.5 if skid_fx else 0.4, 3.2, a)
		if not in_water:
			var cr := 0.0
			if dirt: cr = (30.0 if skid_fx else 0.0) + carve_k * 28 + st.pedal * (9.0 if va < 8 else 2.0)
			elif sand: cr = (18.0 if skid_fx else 0.0) + carve_k * 16 + st.pedal * (4.0 if va < 8 else 1.0)
			elif skid_fx: cr = 6.0
			st.chunk_acc += dt * cr * fxd
			while st.chunk_acc > 1:
				st.chunk_acc -= 1
				var out := turn_dir * carve_k * (2.5 + randf() * 3.5) if carve_k > 0.05 else (randf() - .5) * 1.2
				var back := (1.5 + va * 0.35) * (1 - carve_k * 0.6)
				var ev := Vector3(-f.x * back + side.x * out, 1 + randf() * 2.2, -f.z * back + side.z * out)
				var cc: Color = (DIRT_CHUNK if randf() < 0.7 else ROCK_CHUNK) if dirt else (dcol * 0.8 if sand else GRASS_CHUNK)
				fx.chunk(rear, ev, cc, 0.022)
	var on_ground := not st.air and not in_water and va > 0.2
	var tc: Color = TRACK_DIRT if s == 1 else (dcol * 0.6 if sand else TRACK_GRASS)
	var ta := 0.6 if s == 1 else (0.5 if sand else 0.3)
	fx.track(0, front, f, ta if on_ground else 0.0, tc, 0.06)
	fx.track(1, rear, f, (minf(0.85, ta + 0.35) if skid_fx else ta) if on_ground else 0.0, tc, 0.08 if skid_fx else 0.065)

# ---------------------------------------------------------------- ride control
func respawn(new_world: bool) -> void:
	if phys.crash_on: get_up()
	if new_world:
		GameState.new_seed()
		terrain.clear_dynamic()
		terrain.set_seed(GameState.seed)
		terrain.update_stream(0, 0, INF)
		flash("New world #%d" % GameState.seed)
	if fx.has_method("clear_tracks"): fx.clear_tracks()
	phys.reset_at(0, 0, 0)
	rider.reset_pose()
	_snap_prev()
	cam.snap_to(Vector3(0, phys.y + 0.5, 0))

const DRAW_KEYS := ["x", "z", "y", "y_draw", "pitch", "pitch_draw", "heading", "body_y"]

func _snap_prev() -> void:
	for k in DRAW_KEYS: _prev[k] = phys.get(k)

func _unhandled_input(e: InputEvent) -> void:
	if get_tree().paused or not input_enabled: return
	if e.is_action_pressed("new_world") and not e.is_echo(): respawn(true)
	elif e.is_action_pressed("respawn") and not e.is_echo(): respawn(false)
	elif e.is_action_pressed("bail") and not phys.crash_on: phys.crash_pending = "BAIL!"
	elif e.is_action_pressed("gear_easier") and not e.is_echo(): _shift(1)
	elif e.is_action_pressed("gear_harder") and not e.is_echo(): _shift(-1)
	elif e.is_action_pressed("camera_next") and not e.is_echo():
		flash(cam.next_mode())
		Settings.data["camera"] = cam.mode; Settings.save()
	elif e.is_action_pressed("next_bike") and not e.is_echo():
		var ids := GameState.BIKES.keys()
		GameState.bike_id = ids[(ids.find(GameState.bike_id) + 1) % ids.size()]
		GameState.save()
		get_parent().restart_ride.call_deferred()
	elif e.is_action_pressed("hop") and phys.crash_on:
		phys.crash_armed = true

func _shift(d: int) -> void:
	if not phys.geared:
		flash("Single speed"); return
	if phys.shift(d):
		hud.gear_changed()
		if audio: audio.shift()

func _read_input() -> Dictionary:
	if not input_enabled:
		return {"throttle": 0.0, "brake": 0.0, "steer": 0.0, "hop": false, "sprint": false}
	var steer := Input.get_action_strength("steer_left") - Input.get_action_strength("steer_right")
	steer = signf(steer) * pow(absf(steer), 1.0 / maxf(0.3, float(Settings.get_v("steer_sens"))))
	return {
		"throttle": Input.get_action_strength("pedal"),
		"brake": Input.get_action_strength("brake"),
		"steer": clampf(steer, -1, 1),
		"hop": Input.is_action_pressed("hop"),
		"sprint": Input.is_action_pressed("sprint"),
	}

func _physics_process(dt: float) -> void:
	_snap_prev()
	phys.step(dt, _read_input())
	if phys.crash_on:
		rider.pose_ragdoll(ragdoll.p)
	if not phys.is_sane():
		push_warning("physics went non-finite; restoring last good state")
		for k in _last_good: phys.set(k, _last_good[k])
		phys.v = 0; phys.vy = 0; phys.air = false; phys.lean_v = 0; phys.compress_v = 0; phys.body_v = 0
		phys.body_y = phys.y; phys.pitch_v = 0; phys.w_init = false
	else:
		for k in ["x", "z", "y", "heading", "course", "pitch", "lean", "steer", "slip", "compress"]:
			_last_good[k] = phys.get(k)

func _process(dt: float) -> void:
	dt = minf(dt, 0.1)
	t += dt
	var st := phys
	var a := Engine.get_physics_interpolation_fraction()
	if Vector2(st.x - _prev.x, st.z - _prev.z).length() > 2: a = 1.0
	var lerp_k := func(k: String) -> float: return lerpf(_prev[k], st.get(k), a)
	var y_draw: float = lerp_k.call("y") if st.crash_on else lerp_k.call("y_draw")
	var p_draw: float = lerp_k.call("pitch") if st.crash_on else lerp_k.call("pitch_draw")
	var hd: float = _prev.heading + BikePhysics.ang_diff(st.heading, _prev.heading) * a
	drawn_pos = Vector3(lerp_k.call("x"), lerp_k.call("y"), lerp_k.call("z"))
	var body_y: float = lerp_k.call("body_y")
	var wobble := sin(t * 2.3) * 0.025 * maxf(0.0, 1 - absf(st.v) / 2)
	rig.pose(drawn_pos.x, y_draw, drawn_pos.z, hd, p_draw, st.hop_nose, st.bike_lean + st.rock + wobble,
		st.steer - wobble * 1.5, st.wheel_f, st.wheel_r, st.crank)
	st.brake_heat *= exp(-dt / 3.5)
	rig.set_brake_heat((st.brake_heat - 0.35) / 0.9)
	if not st.crash_on:
		var lt := rig.limb_targets()
		var T: Dictionary = Tune.v
		rider.update_pose(dt, {"footL": lt.footL, "footR": lt.footR, "handL": lt.handL, "handR": lt.handR,
			"v": st.v, "lean": st.bike_lean + st.rock, "steer": st.steer, "yawRate": st.yaw_rate,
			"counter": st.counter, "rockRoll": st.rock, "headRoll": st.bike_lean * 0.85,
			"absorb": clampf(body_y - y_draw, -T.legComp, T.legExt), "pitch": p_draw, "bodyLevel": T.bodyLevel,
			"attackDrop": T.attackDrop, "pedal": st.pedal, "sprint": st.sprint * st.pedal, "crank": st.crank,
			"air": st.air_k, "compress": maxf(0.0, -st.compress), "hipShift": st.hip_shift, "t": t})
	var vd: float = Settings.get_v("view_distance")
	terrain.update_stream(st.x, st.z, 4.0)
	biome_t -= dt
	if biome_t <= 0:
		biome_t = 0.5
		var b: String = terrain.biome_name(st.x, st.z)
		if b != biome_cur:
			biome_hold = biome_hold + 1 if b == biome_next else 0
			biome_next = b
			if biome_hold >= 3:
				biome_cur = b
				if msg_t <= 0: flash(b)
	cam.update_cam(dt)
	# fog + shadows sized to the zoom level, sun follows the rider
	env.fog_depth_begin = (cam.dist + 26) * vd
	env.fog_depth_end = (cam.dist * 1.6 + 70) * vd
	sun.directional_shadow_max_distance = clampf(cam.dist * 2.2, 30, 120)
	if cam_attr.dof_blur_far_enabled:
		cam_attr.dof_blur_far_distance = cam.dist * 1.25 + 4
		cam_attr.dof_blur_far_transition = cam.dist * 0.9 + 6
		cam_attr.dof_blur_near_distance = maxf(0.5, cam.dist * 0.6)
		cam_attr.dof_blur_near_transition = maxf(0.5, cam.dist * 0.4)
	if terrain.has_method("update_water"): terrain.update_water(st.x, st.z, t)
	if fx.has_method("update"): fx.update(dt, cam)
	if msg_t > 0: msg_t -= dt
	hud.update_hud(dt)
	if audio: audio.update_audio(dt)
	if absf(st.v) * 3.6 > float(GameState.records.top_speed) + 0.5 and not st.crash_on:
		GameState.records.top_speed = absf(st.v) * 3.6
