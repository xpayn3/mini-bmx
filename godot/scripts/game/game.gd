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
## ride light: a clear afternoon. A strong warm sun against a cool blue sky fill (warm light, cool shade)
const RIDE_SUN := 1.8
const RIDE_SUN_COL := Color("fff1de")
const RIDE_FAR := 2600.0   # camera far plane: the far hills (FarHills) reach the horizon
const RIDE_FOG := Color(0.74, 0.85, 0.98)
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
var atmos := Atmos.new()
var grime: Grime
var dust: RideDust
var sun_energy := RIDE_SUN
var speed_k := 0.0           # 0..1 speed feel (FOV boost, edge blur)
var photo := false           # photo mode: time frozen, HUD hidden, focus on the rider
var _photo_last := 0
var _landed := 0.0           # landing impact to feed the mud next step
var _cloud_t := 0.0
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
var sky_mat: ShaderMaterial
var scenic := false          # title screen: golden hour, a lookout camera, far hills to the horizon
var far_hills: FarHills

func _ready() -> void:
	bike_cfg = GameState.bike_config()
	Tune.set_ride(bike_cfg.ride)
	_build_environment()
	terrain = load("res://scripts/world/terrain.gd").new(GameState.seed)
	add_child(terrain)
	terrain.view_scale = float(Settings.get_v("view_distance"))   # before the first chunks are built
	terrain.update_stream(0, 0, INF)
	far_hills = FarHills.new()   # the distant landscape behind the streamed chunks
	far_hills.setup(terrain)
	add_child(far_hills)
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
	rider.set_look(RiderPanels.load_look())
	rider.set_style(RiderPanels.load_pose(GameState.bike_id, bike_cfg.pose))
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
	cam.far = RIDE_FAR
	cam.set_mode(Settings.get_v("camera"))
	hud = load("res://scripts/ui/hud.gd").new()
	hud.game = self
	add_child(hud)
	grime = Grime.new()
	add_child(grime)
	grime.watch(rig)
	grime.watch(rider, true)
	dust = RideDust.new()
	add_child(dust)
	if dust.sim != null and dust.sim.compositor != null:   # the dust is drawn as a compositor effect
		var comp := Compositor.new()
		comp.compositor_effects = [dust.sim.compositor]
		cam.compositor = comp
	audio = load("res://scripts/game/ride_audio.gd").new()
	audio.game = self
	add_child(audio)
	Tune.changed.connect(func(): phys.T = Tune.v)
	Settings.changed.connect(_apply_settings)
	_apply_settings()
	respawn(false)
	# shader warm-up behind the opening fade (pipeline cache + ubershaders do the rest)
	grime.warm_frames = 4
	dust.warm_up(Vector3(0, phys.y + 0.5, 0))
	fx.puff(Vector3(0, phys.y + 0.4, 0), Vector3.ZERO, Color.WHITE, 0.3, 0.2, 0.0)
	fx.chunk(Vector3(0, phys.y + 0.4, 0), Vector3.ZERO, Color.WHITE, 0.01, 0.2)

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
	sm.set_shader_parameter("sunny", 1.0)
	sm.set_shader_parameter("light_energy", 0.55)
	sky.radiance_size = Sky.RADIANCE_SIZE_256
	sky.sky_material = sm
	sky_mat = sm
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_sky_contribution = 0.8   # the rest: a flat cool blue, so shade reads as sky light
	env.ambient_light_color = Color(0.55, 0.68, 0.9)
	env.ambient_light_energy = 0.42   # the web version: sky env 0.55 + a 0.32 hemisphere fill
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 0.8
	env.tonemap_white = 6.0
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_light_color = RIDE_FOG   # the HDRI's horizon, a clear day
	_ride_fog()
	env.ssao_radius = 0.6
	env.ssao_intensity = 2.0
	env.ssao_power = 1.5
	env.ssao_detail = 0.5
	env.ssao_horizon = 0.06
	env.ssao_light_affect = 0.15      # a touch of AO in direct light too: contact under the bike, rocks
	env.ssil_radius = 4.0
	env.ssil_intensity = 0.7
	env.sdfgi_use_occlusion = true
	env.sdfgi_read_sky_light = true
	env.sdfgi_cascades = 4
	env.sdfgi_min_cell_size = 0.25
	env.sdfgi_energy = 0.8
	env.sdfgi_y_scale = Environment.SDFGI_Y_SCALE_75_PERCENT
	env.ssr_max_steps = 48
	env.ssr_fade_in = 0.15
	env.ssr_fade_out = 2.0
	env.glow_intensity = 0.25
	env.glow_strength = 0.9
	env.glow_bloom = 0.02
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	env.glow_hdr_threshold = 0.92
	env.set_glow_level(0, 0.0); env.set_glow_level(1, 0.6); env.set_glow_level(2, 1.0)
	env.set_glow_level(3, 0.6); env.set_glow_level(4, 0.3)
	# volumetric fog: a light haze the sun shines through (shafts past trees, lit dust clouds); the
	# depth fog above still does the far fade, so this stays thin
	env.volumetric_fog_density = 0.0012
	env.volumetric_fog_albedo = Color(0.86, 0.9, 0.95)
	env.volumetric_fog_anisotropy = 0.55
	env.volumetric_fog_length = 72.0
	env.volumetric_fog_detail_spread = 1.6
	env.volumetric_fog_ambient_inject = 0.12   # haze lit by the sun (shafts), not a milky veil
	env.volumetric_fog_sky_affect = 0.0
	env.volumetric_fog_temporal_reprojection_enabled = true
	env.volumetric_fog_temporal_reprojection_amount = 0.9
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.22
	env.adjustment_contrast = 1.12
	we.environment = env
	cam_attr = CameraAttributesPractical.new()
	cam_attr.dof_blur_amount = 0.06
	cam_attr.auto_exposure_enabled = false
	we.camera_attributes = cam_attr
	add_child(we)
	sun = DirectionalLight3D.new()
	sun.light_color = RIDE_SUN_COL
	sun.light_energy = RIDE_SUN
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_split_1 = 0.06
	sun.directional_shadow_split_2 = 0.18
	sun.directional_shadow_split_3 = 0.45
	sun.directional_shadow_blend_splits = true
	sun.directional_shadow_fade_start = 0.85
	sun.directional_shadow_max_distance = 90.0
	sun.directional_shadow_pancake_size = 30.0
	sun.shadow_bias = 0.02
	sun.shadow_normal_bias = 1.2
	sun.light_volumetric_fog_energy = 1.4
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

## Title screen look: golden hour from a lookout. The camera faces the best view from the spawn, the sun
## sits low ahead and to the right of it, and a coarse copy of the landscape fills the view to the
## horizon. Off = the normal ride light, as built above.
func set_scenic(on: bool) -> void:
	if on == scenic: return
	scenic = on
	if on:
		var best := _best_view()
		var sy := best - 0.62
		var el := deg_to_rad(10.0)
		sun.look_at_from_position(Vector3(cos(sy) * cos(el), sin(el), -sin(sy) * cos(el)), Vector3.ZERO, Vector3.UP)
		sun.light_color = Color(1.0, 0.62, 0.34)
		# a grazing sun: more bias or the ground shades itself in thin stripes (acne); softer edges so
		# the long tree shadows don't read as flat black bands
		sun.shadow_bias = 0.08
		sun.shadow_normal_bias = 3.0
		sun.shadow_blur = 2.0
		sun_energy = 2.3
		sky_mat.set_shader_parameter("golden", 1.0)
		sky_mat.set_shader_parameter("sunny", 0.0)
		sky_mat.set_shader_parameter("light_energy", 0.85)
		env.fog_light_color = Color(0.93, 0.70, 0.52)
		env.fog_aerial_perspective = 0.0
		env.fog_sun_scatter = 0.35
		env.fog_sky_affect = 0.0
		env.fog_depth_curve = 1.25
		env.fog_density = 0.7
		env.volumetric_fog_albedo = Color(1.0, 0.82, 0.62)
		env.volumetric_fog_density = 0.0012
		env.tonemap_exposure = 0.95
		cam.far = 3500.0
		cam.vista_yaw = best
		cam.set_mode("vista")
	else:
		sun.look_at_from_position(SUN_DIR.normalized(), Vector3.ZERO, Vector3.UP)
		sun.light_color = RIDE_SUN_COL
		sun.shadow_bias = 0.02
		sun.shadow_normal_bias = 1.2
		sun.shadow_blur = 1.0
		sun_energy = RIDE_SUN
		sky_mat.set_shader_parameter("golden", 0.0)
		sky_mat.set_shader_parameter("sunny", 1.0)
		sky_mat.set_shader_parameter("light_energy", 0.55)
		env.fog_light_color = RIDE_FOG
		env.fog_sun_scatter = 0.0
		_ride_fog()
		env.volumetric_fog_albedo = Color(0.86, 0.9, 0.95)
		env.volumetric_fog_density = 0.0012
		env.tonemap_exposure = 0.8
		cam.far = RIDE_FAR

## the heading with the best view from the rider: nothing close blocking the eye line (ground + room
## for trees) and hills rising far off. Seen from a few metres up, like the lookout camera.
func _best_view() -> float:
	var eye: float = phys.y + 6.0
	var best := 0.0
	var best_s := -INF
	for i in 48:
		var a := TAU * i / 48.0
		var ca := cos(a); var sa := -sin(a)
		var block := -1.0
		var r := 25.0
		while r < 450.0:
			block = maxf(block, (terrain.height(phys.x + ca * r, phys.z + sa * r) + 5.0 - eye) / r)
			r *= 1.25
		var hills := -1.0
		r = 450.0
		while r < 1600.0:
			hills = maxf(hills, (terrain.height(phys.x + ca * r, phys.z + sa * r) - eye) / r)
			r += 100.0
		var s := hills - block * 0.5 - maxf(0.0, block + 0.03) * 6.0
		if s > best_s:
			best_s = s; best = a
	return best

func _apply_settings() -> void:
	terrain.set_view_scale(float(Settings.get_v("view_distance")))
	var sq: int = Settings.get_v("shadows")
	# shadows: Low = 2 cascades, hard-ish; Ultra = 4 blended cascades + contact-hardening soft shadows
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS if sq == 0 else DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_blend_splits = sq >= 2
	sun.light_angular_distance = 0.6 if sq >= 3 else 0.0
	env.ssao_enabled = Settings.get_v("ssao")
	var gi: int = Settings.get_v("gi")
	env.ssil_enabled = gi >= 1
	env.sdfgi_enabled = gi >= 2
	# SDFGI adds its own sky light and occlusion: drop the flat ambient so valleys can go dark
	env.ambient_light_energy = 0.26 if gi >= 2 else 0.36
	env.volumetric_fog_enabled = Settings.get_v("vol_fog")
	dust.fog_on = env.volumetric_fog_enabled
	atmos.wind_on = Settings.get_v("wind")
	atmos.clouds_on = Settings.get_v("cloud_shadows")
	grime.enabled = Settings.get_v("grime")
	dust.emitter.amount = int(RideDust.MAX_RATE * 3.2 * clampf(float(Settings.get_v("fx_density")), 0.2, 1.5))
	env.ssr_enabled = Settings.get_v("ssr")
	env.adjustment_brightness = float(Settings.get_v("brightness"))
	env.glow_enabled = Settings.get_v("bloom")
	(grade_rect.material as ShaderMaterial).set_shader_parameter("grade_amt", 1.0 if Settings.get_v("grade") else 0.0)
	grade_rect.visible = Settings.get_v("grade") or Settings.get_v("speed_fx")
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

const GRASS_SOIL_DUST := Color(0.52, 0.4, 0.28)   # what a tyre digs up through grass: brown soil

## the colour of the dust kicked up here. With the smoke sim: the road's own colour (barely lighter: fine
## dust), and on grass the brown soil under it (never green). The old sprites used a paler mix.
func ground_dust(px: float, pz: float, s: int) -> Color:
	if s == 2: return DUST_SPLASH
	var c: Color = terrain.ground_color(px, pz)
	if dust != null and dust.sim != null:
		if s == 0: return GRASS_SOIL_DUST
		return c.lerp(Color.WHITE, 0.08)
	return c.lerp(Color.WHITE, 0.42 if s == 0 else 0.28)

func burst(pos: Vector3, n: int, s: int, power: float, with_dust := true) -> void:
	if s == 2: return
	var dc := ground_dust(pos.x, pos.z, s)
	if dust.sim != null and with_dust:   # real smoke sim: one dust burst instead of sprite puffs
		dust.puff_burst(pos, power, dc, (1.0 if s == 1 else 0.8 if s == 3 else 0.45) * clampf(float(n) / 20.0, 0.4, 2.0))
	for i in n:
		var a := randf() * TAU
		var r := (0.6 + randf()) * power
		if dust.sim == null: fx.puff(pos + Vector3(cos(a) * 0.15, 0.05, sin(a) * 0.15), Vector3(cos(a) * r, 0.25 + randf() * 0.6, sin(a) * r), dc, 0.6, 3.4, 0.6 if s == 1 else 0.5 if s == 3 else 0.3)
		if i % 2 == 0:
			var cc: Color = DIRT_CHUNK if s == 1 else (dc * 0.8 if s == 3 else (GRASS_CHUNK if randf() < 0.5 else ROCK_CHUNK))
			fx.chunk(Vector3(pos.x, pos.y + 0.05, pos.z), Vector3(cos(a) * r * 0.9, 1.2 + randf() * 1.8 * power, sin(a) * r * 0.9), cc, 0.028)
	# no thud sound on landings or knocks (the user found it annoying); smashing things still crunches

func smash(c: Dictionary, vel: Vector3, pos: Vector3) -> bool:
	if not terrain.break_collider(c, vel):
		return false
	var col := Color("c9a06a")
	if c.get("cactus", false): col = Color("8fc25a")
	elif c.get("tape", false): col = Color("e8322b")
	for k in 12:
		fx.chunk(Vector3(c.x, pos.y + 0.3 + randf() * 0.6, c.z), Vector3(vel.x * 0.4 + (randf() - .5) * 3, 1 + randf() * 2.5, vel.z * 0.4 + (randf() - .5) * 3), col, 0.025)
	if dust.sim != null: dust.puff_burst(Vector3(c.x, pos.y + 0.1, c.z), 0.6, Color("cdb894"), 0.5)
	for k in (0 if dust.sim != null else 3):
		fx.puff(Vector3(c.x, pos.y + 0.4, c.z), Vector3((randf() - .5) * 1.5, 0.4 + randf() * 0.5, (randf() - .5) * 1.5), Color("cdb894"), 0.35, 1.4, 0.4)
	if audio and not c.get("tape", false): audio.crunch()
	return true

func rock_chips(c: Dictionary) -> void:
	for k in 6:
		fx.chunk(Vector3(c.x, c.top, c.z), Vector3((randf() - .5) * 2, 1 + randf(), (randf() - .5) * 2), ROCK_CHUNK, 0.02)

func start_crash(reason: String) -> void:
	phys.crash_pending = ""
	if phys.crash_on: return
	if OS.get_environment("BMX_TRICK") != "": print("CRASH ", reason, " v=%.1f air=%s" % [phys.v, phys.air])   # tests
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
	# (no dust right where the crash starts with the smoke sim: only where the body / bike hit and slide)
	burst(Vector3(phys.x, phys.y + 0.05, phys.z), 30 if dust.sim == null else 10, terrain.surface(phys.x, phys.z), 1.5, dust.sim == null)
	var cs: int = terrain.surface(phys.x, phys.z)
	# (with the smoke sim the ragdoll's own impacts throw the dust: _crash_dust)
	if cs != 2 and dust.sim == null: dust.cloud(Vector3(phys.x, phys.y, phys.z), f * phys.v * 0.3, ground_dust(phys.x, phys.z, cs), 3.2, 1.2)
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

func on_trick(trick: String) -> void:
	if hud: hud.on_trick(trick)

func on_takeoff() -> void:
	takeoff = Vector3(phys.x, phys.y, phys.z)
	air_peak = phys.y
	if hud: hud.on_takeoff()

func on_landing(air_time: float, impact: float) -> void:
	var dist := Vector2(phys.x - takeoff.x, phys.z - takeoff.z).length()
	var height := air_peak - maxf(takeoff.y, phys.y)
	if hud: hud.on_landing(air_time, dist, maxf(0.0, height), impact)
	_landed = clampf(impact / 6.0, 0.0, 1.0) if air_time > 0.25 else 0.0
	var ls: int = terrain.surface(phys.x, phys.z)
	if dust.sim != null and air_time > 0.3 and ls != 2:   # real smoke sim: a ring of dust blasted outward
		var lf := phys.fwd()
		var lbb: float = phys.BB_REAR
		var tyres := [Vector3(phys.x - lf.x * lbb, phys.y, phys.z - lf.z * lbb),
			Vector3(phys.x + lf.x * (phys.L - lbb), phys.y, phys.z + lf.z * (phys.L - lbb))]
		dust.landing_dust(tyres, lf * phys.v, impact, ground_dust(phys.x, phys.z, ls),
			(1.0 if ls == 1 else 0.85 if ls == 3 else 0.3) * clampf(air_time / 0.8, 0.4, 1.3))
	elif air_time > 0.45 and (ls == 1 or ls == 3):
		dust.cloud(Vector3(phys.x, phys.y, phys.z), phys.fwd() * phys.v * 0.3, ground_dust(phys.x, phys.z, ls), 2.6 + impact * 0.15, 1.1)
	if air_time > 0.2: Settings.rumble(clampf(impact / 8, 0.15, 1), clampf(impact / 12, 0, 1), 0.12 + minf(0.25, impact * 0.02))

## how far each drawn tyre is inside the ground: [front, rear] (m, > 0 = sunk). The lowest point of each
## tyre circle (in its own leaned / steered plane) against the real terrain height under it.
func _tyre_pens() -> Array:
	var out := []
	for k in 2:
		var w: Node3D = rig.wheel_f if k == 0 else rig.wheel_r
		var R: float = rig.wheel_rf if k == 0 else rig.wheel_rr
		var c := w.global_position
		var n := w.global_basis.z.normalized()
		var down := Vector3.DOWN - n * Vector3.DOWN.dot(n)
		if down.length() < 1e-3:
			out.append(-1.0)
			continue
		var lp := c + down.normalized() * R
		out.append(terrain.height(lp.x, lp.z) - lp.y)
	return out

## Tyres never drawn inside the ground. The ride physics treats tyres as springs that can squash into
## the terrain (and samples it at a few points), so on slopes, in dips and on landings the drawn bike
## could sink up to ~20 cm. After posing, lift and tilt the DRAWN bike just enough that neither tyre is
## below the real surface (the physics is untouched). Two poses per frame: one to see how pitch moves
## each tyre, then the corrected one.
const SEAT_EPS := 0.004
func _seat_tyres(args: Array) -> void:
	var p0 := _tyre_pens()
	if maxf(p0[0], p0[1]) <= SEAT_EPS:
		return
	var y0: float = args[1]
	var pt0: float = args[4]
	var e := 0.02
	args[4] = pt0 + e
	rig.callv("pose", args)
	var p1 := _tyre_pens()
	var df: float = (p1[0] - p0[0]) / e
	var dr: float = (p1[1] - p0[1]) / e
	var dp := 0.0
	# both tyres down near the ground: tilt so they sink the same, then lift both out together
	if minf(p0[0], p0[1]) > -0.06 and absf(df - dr) > 0.05:
		dp = clampf((p0[1] - p0[0]) / (df - dr), -0.3, 0.3)
	var dy := maxf(0.0, maxf(p0[0] + df * dp, p0[1] + dr * dp)) + SEAT_EPS * 0.5
	args[1] = y0 + dy
	args[4] = pt0 + dp
	rig.callv("pose", args)
	# whatever is left (curved ground under a leaned tyre...): lift straight out
	var p2 := _tyre_pens()
	var rest := maxf(p2[0], p2[1])
	if rest > SEAT_EPS * 0.5:
		args[1] = y0 + dy + rest
		rig.callv("pose", args)

## tests (BMX_TYRE_CLIP=1): how far the drawn tyres sink into the ground (lowest point of each tyre
## circle vs the terrain height under it); prints the worst every half second with the situation
var _clip := {}
func _tyre_clip_probe(dt: float, st) -> void:
	if st.crash_on: return
	for k in 2:
		var w: Node3D = rig.wheel_f if k == 0 else rig.wheel_r
		var R: float = rig.wheel_rf if k == 0 else rig.wheel_rr
		var c := w.global_position
		var n := w.global_basis.z.normalized()
		var down := Vector3.DOWN - n * Vector3.DOWN.dot(n)
		if down.length() < 1e-3: continue
		var lp := c + down.normalized() * R
		var pen: float = terrain.height(lp.x, lp.z) - lp.y
		if pen > _clip.get("worst", -1e9):
			_clip.worst = pen
			_clip.what = "%s pen=%.3f air=%s v=%.1f lean=%.2f pitch=%.2f compress=%.2f y_draw-y=%.3f" % [
				"front" if k == 0 else "rear", pen, st.air, st.v, st.bike_lean, st.pitch, st.compress, st.y_draw - st.y]
	_clip.t = _clip.get("t", 0.0) + dt
	if _clip.t > 0.5:
		print("TYRECLIP ", _clip.get("what", ""))
		_clip = {}

## the bike and rider as solid shapes the dust sim's air has to go round: two spinning wheels, the
## frame and the rider's body
func _body_parts(st: BikePhysics) -> Array:
	var f: Vector3 = st.fwd()
	var vel := f * st.v + Vector3(0, st.vy if st.air else 0.0, 0)
	var axle := f.cross(Vector3.UP).normalized()
	var base := drawn_pos
	var rr: float = st.RWR
	var rf: float = st.RWF
	var rear := base - f * st.BB_REAR + Vector3(0, rr, 0)
	var front := base + f * (st.L - st.BB_REAR) + Vector3(0, rf, 0)
	return [
		{p = rear, v = vel, r = rr * 1.05, spin = -axle * (st.v / rr)},
		{p = front, v = vel, r = rf * 1.05, spin = -axle * (st.v / rf)},
		{p = (rear + front) * 0.5 + Vector3(0, 0.08, 0), v = vel, r = 0.24, spin = Vector3.ZERO},
		{p = base + Vector3(0, rr + 0.45, 0) - f * 0.05, v = vel, r = 0.3, spin = Vector3.ZERO},
	]

## a crash kicks up dust where the ragdoll hits the ground: every time a body part slams down while
## tumbling it throws a puff (bigger the harder it hits), and a light dusting where it slides
var _rd_air: PackedByteArray = PackedByteArray()
func _crash_dust() -> void:
	var pts: Array = ragdoll.p
	var prv: Array = ragdoll.q
	var h: float = maxf(ragdoll.last_h, 1e-4)
	if _rd_air.size() != pts.size():
		# first frame of a crash: only parts actually off the ground can "land" (no puff at the crash spot)
		_rd_air.resize(pts.size())
		for i in pts.size():
			var p0: Vector3 = pts[i]
			_rd_air[i] = 1 if p0.y - terrain.height(p0.x, p0.z) > 0.3 else 0
	var made := 0
	for i in pts.size():
		var pp: Vector3 = pts[i]
		var g: float = terrain.height(pp.x, pp.z)
		var above := pp.y - g
		if above > 0.3:
			_rd_air[i] = 1   # off the ground: the next touch-down is an impact
			continue
		if above > 0.2: continue
		var v: Vector3 = (pp - (prv[i] as Vector3)) / h
		var s: int = terrain.surface(pp.x, pp.z)
		if s == 2: continue
		var amt := 1.0 if s == 1 else (0.85 if s == 3 else 0.3)
		var hs := Vector2(v.x, v.z).length()
		var at := Vector3(pp.x, g + 0.1, pp.z)
		if _rd_air[i] == 1:
			_rd_air[i] = 0
			var hit := maxf(0.0, -v.y) + hs * 0.35
			if hit > 1.5 and made < 6:
				# the slam: a puff blown out round the impact, carried on a little the way it was going
				var k := clampf((hit - 1.5) / 6.0, 0.15, 1.0)
				if OS.get_environment("BMX_SMOKE_PROBE") != "": print("CRASHDUST impact i=%d t=%.2f hit=%.1f" % [i, phys.crash_t, hit])
				dust.sim.burst(at, Vector3(v.x * 0.25, 0.6 + k * 0.8, v.z * 0.25), 0.3 + k * 0.25, (50.0 + 110.0 * k) * amt,
					1.2 + k * 2.2, 0.08 + k * 0.05, ground_dust(pp.x, pp.z, s), 20.0)
				dust.grit_burst(at, Vector3(v.x * 0.3, 0.8 + k * 1.6, v.z * 0.3), 1.0 + k * 2.5, 600.0 * k * amt, 0.06, ground_dust(pp.x, pp.z, s))
				made += 1
		elif hs > 1.2 and made < 10:
			# sliding / rolling along the ground
			if OS.get_environment("BMX_SMOKE_PROBE") != "": print("CRASHDUST slide i=%d t=%.2f hs=%.1f" % [i, phys.crash_t, hs])
			dust.sim.add_source(at, Vector3(v.x * 0.3, 0.4, v.z * 0.3), 0.25, minf(hs, 6.0) * 4.0 * amt, 6.0, 0.3, ground_dust(pp.x, pp.z, s))
			made += 1
	# the bike sliding / tumbling along the ground
	var bs: int = terrain.surface(phys.x, phys.z)
	if absf(phys.v) > 0.6 and bs != 2 and phys.crash_t > 0.25:
		var g2: float = terrain.height(phys.x, phys.z)
		var ba := 1.0 if bs == 1 else (0.85 if bs == 3 else 0.3)
		var f := phys.fwd()
		if OS.get_environment("BMX_SMOKE_PROBE") != "": print("CRASHDUST bike t=%.2f v=%.1f" % [phys.crash_t, phys.v])
		for e in [-0.5, 0.5]:   # both wheels / the frame scraping
			dust.sim.add_source(Vector3(phys.x + f.x * e, g2 + 0.1, phys.z + f.z * e), f * phys.v * 0.3 + Vector3(0, 0.6, 0),
				0.3, minf(absf(phys.v), 10.0) * 9.0 * ba, 8.0, 0.5, ground_dust(phys.x, phys.z, bs))

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
		# riding fast on dry ground throws a real trail: rises from ~18 km/h, full by ~50 km/h
		var dust_k := clampf((va - 5.0) / 9.0, 0.0, 1.0) if dust.sim != null else 0.0
		var rate := 0.0
		if in_water: rate = 0.0
		elif dirt: rate = fast_k * 14 + dust_k * 150.0 + (clampf(va / 7.0, 0, 1) * 12.0 if dust.sim != null else 0.0) + (50.0 if skid_fx else 0.0) + carve_k * 60 + st.pedal * (6.0 if va < 3 else 0.0)
		elif sand: rate = fast_k * 10 + dust_k * 130.0 + (clampf(va / 7.0, 0, 1) * 10.0 if dust.sim != null else 0.0) + (40.0 if skid_fx else 0.0) + carve_k * 45 + st.pedal * (4.0 if va < 3 else 0.0)
		else: rate = (14.0 if skid_fx else 0.0) + carve_k * 12
		var fxd: float = Settings.get_v("fx_density")
		# the dust trail: a GPU particle emitter at the rear tyre (fx/ride_dust.gd), thrown back and up,
		# flung outward in a carve
		var d_out := turn_dir * carve_k * 3.5
		var d_back := va * 0.3 * (1 - carve_k * 0.55)
		var d_ev := Vector3(-f.x * d_back + side.x * d_out, 0.7 + carve_k * 0.4 + dust_k * 1.4, -f.z * d_back + side.z * d_out)
		var d_fan := rad_to_deg(atan2((1.6 + va * 0.18) * (1 - carve_k * 0.6) * 0.5, maxf(d_back, 0.6))) + dust_k * 25.0
		var d_a := (0.62 if skid_fx else 0.45) if dirt else ((0.55 if skid_fx else 0.4) if sand else 0.26)
		dust.feed(rear, d_ev, rate * fxd, dcol, d_a, clampf(d_fan, 12.0, 70.0))
		# the front tyre dusts too, less: it rolls (no drive / little skid), so it mostly lifts dust
		# sideways and up as it carves
		var f_ev := Vector3(-f.x * d_back * 0.4 + side.x * d_out * 0.6, 0.5 + carve_k * 0.3, -f.z * d_back * 0.4 + side.z * d_out * 0.6)
		dust.feed_front(front, f_ev, rate * fxd * 0.35, d_a)
		# a hard skid on loose ground kicks up a real cloud now and then (volumetric fog)
		_cloud_t -= dt
		if (dirt or sand) and skid_fx and va > 5 and _cloud_t <= 0:
			_cloud_t = 0.45
			dust.cloud(rear, d_ev * 0.5, dcol, 2.2 + va * 0.08, 0.9)
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
	if st.air or va <= 0.6 or in_water:
		dust.feed(rear, Vector3.ZERO, 0.0, dcol, 0.0, 20.0)
		dust.feed_front(front, Vector3.ZERO, 0.0, 0.0)
	grime.feed(dt, 2 if in_water else s, va, skid_fx, st.air, _landed, terrain.ground_color(rear.x, rear.z))
	_landed = 0.0
	var on_ground := not st.air and not in_water and va > 0.2
	var tc: Color = TRACK_DIRT if s == 1 else (dcol * 0.6 if sand else TRACK_GRASS)
	var ta := 0.85 if s == 1 else (0.75 if sand else 0.45)
	fx.track(0, front, f, ta if on_ground else 0.0, tc, 0.085)
	fx.track(1, rear, f, (minf(1.0, ta + 0.2) if skid_fx else ta) if on_ground else 0.0, tc, 0.12 if skid_fx else 0.095, skid_fx)

# ---------------------------------------------------------------- ride control
func respawn(new_world: bool) -> void:
	if phys.crash_on: get_up()
	if new_world:
		GameState.new_seed()
		terrain.clear_dynamic()
		terrain.set_seed(GameState.seed)
		terrain.update_stream(0, 0, INF)
		far_hills.queue_free()   # the new world's distant landscape
		far_hills = FarHills.new()
		far_hills.setup(terrain)
		add_child(far_hills)
		flash("New world #%d" % GameState.seed)
	if fx.has_method("clear_tracks"): fx.clear_tracks()
	if new_world: grime.clean()
	phys.reset_at(0, 0, 0)
	rider.reset_pose()
	_snap_prev()
	cam.snap_to(Vector3(0, phys.y + 0.5, 0))

const DRAW_KEYS := ["x", "z", "y", "y_draw", "pitch", "pitch_draw", "heading", "body_y"]

func _snap_prev() -> void:
	for k in DRAW_KEYS: _prev[k] = phys.get(k)

func _unhandled_input(e: InputEvent) -> void:
	if get_tree().paused or not input_enabled: return
	if e.is_action_pressed("photo") and not e.is_echo(): toggle_photo(); return
	if photo: return
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
		phys.v = 0; phys.vy = 0; phys.air = false; phys.w_init = false
		phys.reset_body()
	else:
		for k in ["x", "z", "y", "heading", "course", "pitch", "lean", "steer", "slip", "compress"]:
			_last_good[k] = phys.get(k)

func toggle_photo() -> void:
	photo = not photo
	Engine.time_scale = 0.0 if photo else 1.0
	hud.visible = input_enabled and not photo
	_photo_last = Time.get_ticks_usec()
	if not photo:
		cam_attr.dof_blur_amount = 0.06
		_apply_settings()
	flash("Photo mode  ·  drag to orbit, wheel to zoom, F12 to save, O to leave" if photo else "")

## leave photo mode if it is on (pausing, the menu or a new ride must never inherit a frozen world)
func exit_photo() -> void:
	if photo:
		toggle_photo()

func _exit_tree() -> void:
	Engine.time_scale = 1.0

func _process(dt: float) -> void:
	if photo:
		# time stands still; the camera moves on real time
		var now := Time.get_ticks_usec()
		var rdt := minf((now - _photo_last) / 1e6, 0.1)
		_photo_last = now
		cam.update_cam(rdt)
		var fd := cam.global_position.distance_to(drawn_pos + Vector3(0, 0.7, 0))
		cam_attr.dof_blur_far_enabled = true; cam_attr.dof_blur_near_enabled = true
		cam_attr.dof_blur_amount = 0.16
		cam_attr.dof_blur_far_distance = fd + 1.0
		cam_attr.dof_blur_far_transition = maxf(2.0, fd * 0.5)
		cam_attr.dof_blur_near_distance = maxf(0.3, fd - 1.0)
		cam_attr.dof_blur_near_transition = maxf(0.5, fd * 0.3)
		(grade_rect.material as ShaderMaterial).set_shader_parameter("blur", 0.0)
		return
	dt = minf(dt, 0.1)
	t += dt
	var st := phys
	var a := Engine.get_physics_interpolation_fraction()
	if Vector2(st.x - _prev.x, st.z - _prev.z).length() > 2: a = 1.0
	var lerp_k := func(k: String) -> float: return lerpf(_prev[k], st.get(k), a)
	var y_draw: float = lerp_k.call("y") if st.crash_on else lerp_k.call("y_draw")
	# wrapped interpolation: mid-flip the pitch jumps +PI -> -PI between two steps
	var pk := "pitch" if st.crash_on else "pitch_draw"
	var p_draw: float = wrapf(_prev[pk] + BikePhysics.ang_diff(st.get(pk), _prev[pk]) * a, -PI, PI)
	if OS.get_environment("BMX_PITCH_POSE") != "": p_draw = wrapf(t * 4.0, -PI, PI) if OS.get_environment("BMX_PITCH_POSE") == "sweep" else float(OS.get_environment("BMX_PITCH_POSE"))   # tests: draw at a fixed pitch (flip poses)
	var hd: float = _prev.heading + BikePhysics.ang_diff(st.heading, _prev.heading) * a
	drawn_pos = Vector3(lerp_k.call("x"), lerp_k.call("y"), lerp_k.call("z"))
	var body_y: float = lerp_k.call("body_y")
	var wobble := sin(t * 2.3) * 0.025 * maxf(0.0, 1 - absf(st.v) / 2)
	var pose_y: float = y_draw + (1.5 if OS.get_environment("BMX_PITCH_POSE") != "" else 0.0)
	var pose_args := [drawn_pos.x, pose_y, drawn_pos.z, hd, p_draw, st.hop_nose, st.bike_lean + st.rock + wobble,
		st.steer - wobble * 1.5, st.wheel_f, st.wheel_r, st.crank]
	rig.callv("pose", pose_args)
	if not st.crash_on and OS.get_environment("BMX_TYRE_SINK") == "": _seat_tyres(pose_args)
	if OS.get_environment("BMX_TYRE_CLIP") != "": _tyre_clip_probe(dt, st)
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
			"air": st.air_k, "compress": maxf(0.0, -st.compress), "hipShift": st.hip_shift, "t": t,
			"airSpin": st.yaw_rate if st.air else 0.0, "turn": 0.0 if st.air else st.yaw_rate * clampf(absf(st.v) / 3.0, 0.3, 1.0)})
	var vd: float = Settings.get_v("view_distance")
	terrain.update_stream(st.x, st.z, 4.0)
	far_hills.follow(drawn_pos)
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
	# weather: wind, the bike parting the grass, cloud shadows (the sun dims with the shade at the rider)
	atmos.update(t, dt, drawn_pos, 0.0 if st.air or st.crash_on else clampf(absf(st.v) / 2.0, 0.0, 1.0))
	sun.light_energy = sun_energy * atmos.shade
	# the dust simulation around the rider (fx/smoke_sim.gd)
	if st.crash_on and dust.sim != null: _crash_dust()
	elif dust.sim != null: dust.sim.set_body(_body_parts(st))
	elif _rd_air.size() > 0: _rd_air.resize(0)
	dust.attach(terrain, sun)
	if dust.sim != null:
		dust.sim.cloud = Vector4(atmos.cloud_off.x, atmos.cloud_off.y, Atmos.CLOUD_DEPTH if atmos.clouds_on else 0.0, atmos.shade)
	dust.sim_step(dt, drawn_pos, st.fwd(), atmos.wind)
	grime.update(dt, rig)
	# speed feel: wider FOV and streaky screen edges when fast
	var sk := clampf((absf(st.v) - 8.0) / 14.0, 0.0, 1.0) if Settings.get_v("speed_fx") and not st.crash_on else 0.0
	speed_k += (sk - speed_k) * minf(1.0, dt * (2.5 if sk > speed_k else 1.2))
	cam.fov_boost = speed_k * 9.0
	(grade_rect.material as ShaderMaterial).set_shader_parameter("blur", speed_k * speed_k)
	cam.update_cam(dt)
	# fog + shadows sized to the zoom level, sun follows the rider
	if scenic:
		env.fog_depth_begin = 250.0
		env.fog_depth_end = 3100.0
		sun.directional_shadow_max_distance = 110.0
	else:
		env.fog_depth_begin = (cam.dist + 55) * vd
		env.fog_depth_end = (cam.dist * 1.6 + 100) * vd
		sun.directional_shadow_max_distance = clampf(cam.dist * 2.2, 30, 120) * (0.7 if int(Settings.get_v("shadows")) == 0 else 1.0)
	if cam_attr.dof_blur_far_enabled and scenic:   # lookout: keep the view sharp, soften only the horizon
		cam_attr.dof_blur_far_distance = 900.0
		cam_attr.dof_blur_far_transition = 900.0
		cam_attr.dof_blur_near_distance = 2.0
		cam_attr.dof_blur_near_transition = 1.0
	elif cam_attr.dof_blur_far_enabled:
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


## ride fog: a light, sunny distance haze that takes the sky's own colour (no grey wall at the horizon)
## and leaves the sky itself clear
func _ride_fog() -> void:
	env.fog_density = 0.6
	env.fog_sky_affect = 0.0
	env.fog_depth_curve = 1.6
	env.fog_aerial_perspective = 0.75
