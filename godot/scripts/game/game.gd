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
var wasted                  # crash slow-mo + "WASTED" look (fx/wasted.gd)
var audio
var sun: DirectionalLight3D
var env: Environment
var cam_attr: CameraAttributesPractical
var grade_rect: ColorRect
var atmos := Atmos.new()
var grime: Grime
var blood                    # blood on the ground + torn-off limbs after a crash (fx/blood.gd; loaded by path, no class cache needed)
var dust: RideDust
var sun_energy := RIDE_SUN
# level light (tuning card › Light, LightSettings): time of day, day / night cycle
var tod := 19.33             # the clock (hours); the cycle runs it, a slider move resets it
var light_ver := -1          # LightSettings.version last applied
var light_t := 0.0
var amb_base := 0.36         # flat ambient for the GI setting (SDFGI brings its own sky light)
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
# tests (BMX_CLIP_PROBE): how deep the drawn tyres went into the ground before / after unclipping
var clip_probe := OS.get_environment("BMX_CLIP_PROBE") != ""
var _lean_max := 0.0; var _lean_shot_t := -9.0; var _lean_shots := 0   # tests (BMX_LEAN_SHOT)
var _lip_t := -1.0; var _lip_shots := 0   # tests (BMX_LIP_SHOT)
var clip_stats := {"frames": 0, "fixed": 0, "bad": 0, "before": 0.0, "after": 0.0}
var _prev := {}
var _last_good := {}
# foot down at a stop (drawn only, the physics doesn't know): 0..1 eased, which foot (-1 left, +1 right)
var dab_lin := 0.0
var dab_k := 0.0
var dab_side := -1.0
const DAB_LEAN := 0.11       # rad the bike leans onto the foot
const DAB_OUT := 0.33        # m from the bike's centre line to the foot on the ground
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
var sheep: SheepHerd

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
	sheep = SheepHerd.new()   # woolly flocks that graze and run from the bike
	sheep.setup(terrain)
	add_child(sheep)
	fx = load("res://scripts/fx/fx.gd").new()
	add_child(fx)
	if fx.has_method("setup"): fx.setup(terrain)
	rig = BikeRig.new()
	add_child(rig)
	rig.load_bike(bike_cfg, bike_cfg.get("build", {}))
	susp = rig.susp
	if susp != null and OS.get_environment("BMX_NOUNCLIP") == "": susp.wheels_follow = true   # the wheels track the ground, the frame floats
	pedal_a0 = rig.pedal_a0
	phys = BikePhysics.new(self)
	phys.T = Tune.v
	phys.setup(rig.extras, bike_cfg)
	ragdoll = Ragdoll.new(terrain)
	rider = load("res://scripts/rider/rider.gd").new()
	rig.lean_g.add_child(rider)
	rider.set_look(RiderPanels.load_look())
	var pose: Dictionary = RiderPanels.load_pose(GameState.bike_id, bike_cfg.pose)
	for kv in OS.get_environment("BMX_POSE").split(",", false):   # tests: "bumpAbsorb=2,kneeOpen=0" (not saved)
		var pr := kv.split("=")
		if pr.size() == 2 and pose.has(pr[0]): pose[pr[0]] = float(pr[1])
	rider.set_style(pose)
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
	blood = preload("res://scripts/fx/blood.gd").new(terrain, fx)
	blood.ragdoll = ragdoll
	add_child(blood)
	dust = RideDust.new()
	add_child(dust)
	if dust.sim != null and dust.sim.compositor != null:   # the dust is drawn as a compositor effect
		var comp := Compositor.new()
		comp.compositor_effects = [dust.sim.compositor]
		cam.compositor = comp
	audio = load("res://scripts/game/ride_audio.gd").new()
	audio.game = self
	add_child(audio)
	wasted = preload("res://scripts/fx/wasted.gd").new(self)
	add_child(wasted)
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
	sun.directional_shadow_max_distance = 200.0
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
		light_ver = -1   # the level light (time of day) takes over on the next frame

## level light: time of day -> sun (or moon at night), sky mode, ambient, fog, haze, exposure.
## Applied when the Light sliders change; with the cycle on, the clock runs and it re-applies 10x / s.
func _update_light(dt: float) -> void:
	if scenic: return
	LightSettings.ensure_loaded()
	var L: Dictionary = LightSettings.current
	var changed := light_ver != LightSettings.version
	if changed:
		light_ver = LightSettings.version
		tod = float(L.time)
	if float(L.cycle) > 0.5:
		tod = fposmod(tod + dt * 24.0 / (maxf(float(L.day_min), 0.5) * 60.0), 24.0)
		light_t += dt
		if light_t < 0.1 and not changed: return
		light_t = 0.0
	elif not changed:
		return
	_apply_light(tod, L)


## sun height through the day: up at 6:00, 62 deg at 13:00, down at 20:00, -50 deg in the middle of the night
static func sun_elev_deg(h: float) -> float:
	var x := fposmod(h - 6.0, 24.0)
	return 62.0 * sin(PI * x / 14.0) if x <= 14.0 else -50.0 * sin(PI * (x - 14.0) / 10.0)


func _apply_light(h: float, L: Dictionary) -> void:
	var el_deg := sun_elev_deg(h)
	var x := fposmod(h - 6.0, 24.0)
	# the sun swings ~200 deg across the day; 16:00 = the old afternoon sun (SUN_AZ)
	var yaw := deg_to_rad(rad_to_deg(atan2(SUN_AZ.y, SUN_AZ.x)) + float(L.sun_turn) + (x - 10.0) * (100.0 / 7.0))
	var g := 1.0 - smoothstep(8.0, 30.0, el_deg)        # how golden (low sun)
	var n := 1.0 - smoothstep(-9.0, 0.5, el_deg)        # how much night
	var day := 1.0 - n
	var gw := clampf(g * day * float(L.warmth), 0.0, 1.0)
	var dirv: Vector3
	if el_deg > -3.0:
		var e := deg_to_rad(maxf(el_deg, 2.5))   # never light from below the ground
		dirv = Vector3(cos(yaw) * cos(e), sin(e), sin(yaw) * cos(e))
		sun.light_color = Color(1.0, 0.95, 0.87).lerp(Color(1.0, 0.6, 0.34), gw)
		sun_energy = lerpf(RIDE_SUN, 2.2, g) * smoothstep(-3.0, 5.0, el_deg) * float(L.sun)
	else:
		var e := deg_to_rad(38.0)   # the moon, opposite the sun
		dirv = Vector3(cos(yaw + PI) * cos(e), sin(e), sin(yaw + PI) * cos(e))
		sun.light_color = Color(0.62, 0.72, 1.0)
		sun_energy = 0.32 * float(L.moon) * smoothstep(-3.0, -10.0, el_deg)
	sun.look_at_from_position(dirv, Vector3.ZERO, Vector3.UP)
	# grazing light needs more bias (acne) and softer edges on the long shadows
	sun.shadow_bias = lerpf(0.02, 0.08, g)
	sun.shadow_normal_bias = lerpf(1.2, 3.0, g)
	sun.shadow_blur = lerpf(1.0, 2.0, g) * float(L.shadow_soft)
	# sky: blue + white clouds by day, golden low, stars at night; its photographed sun follows ours
	sky_mat.set_shader_parameter("rotation", atan2(dirv.x, -dirv.z) - (HDRI_SUN_U - 0.5) * TAU)
	sky_mat.set_shader_parameter("golden", gw)
	sky_mat.set_shader_parameter("sunny", day * (1.0 - gw))
	sky_mat.set_shader_parameter("night", n)
	sky_mat.set_shader_parameter("light_energy", lerpf(lerpf(0.55, 0.85, g), 0.3, n) * float(L.sky))
	env.ambient_light_energy = amb_base * float(L.sky) * lerpf(1.0, 0.5, n)
	env.ambient_light_color = Color(0.55, 0.68, 0.9).lerp(Color(0.3, 0.4, 0.78), n)
	# fog / haze
	_ride_fog()
	env.fog_density *= float(L.haze)
	env.fog_light_color = RIDE_FOG.lerp(Color(0.93, 0.72, 0.55), g * day).lerp(Color(0.07, 0.09, 0.16), n)
	env.fog_sun_scatter = 0.3 * g * day
	env.fog_aerial_perspective = 0.75 * (1.0 - n)
	env.volumetric_fog_albedo = Color(0.86, 0.9, 0.95).lerp(Color(1.0, 0.84, 0.66), g * day).lerp(Color(0.45, 0.55, 0.8), n)
	env.volumetric_fog_density = 0.0012 * float(L.haze)
	env.tonemap_exposure = lerpf(lerpf(0.8, 0.95, g), 1.6, n) * float(L.exposure)
	env.adjustment_saturation = float(L.saturation) * lerpf(1.0, 0.8, n)
	env.adjustment_contrast = float(L.contrast)
	# water: reflect this sky and glint where this sun is (it used to keep a fixed noon sky + sun)
	if terrain and terrain.has_method("water_light"):
		var hz := Color(0.784, 0.933, 0.969).lerp(Color(1.0, 0.78, 0.6), gw).lerp(Color(0.07, 0.09, 0.15), n)
		var zn := Color(0.424, 0.765, 0.925).lerp(Color(0.62, 0.62, 0.72), gw).lerp(Color(0.02, 0.03, 0.07), n)
		terrain.water_light(dirv, sun.light_color * clampf(sun_energy / maxf(RIDE_SUN, 0.01), 0.0, 1.5), hz, zn)


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
	amb_base = 0.26 if gi >= 2 else 0.36
	env.ambient_light_energy = amb_base
	light_ver = -1   # re-apply the level light on top
	env.volumetric_fog_enabled = Settings.get_v("vol_fog")
	dust.fog_on = env.volumetric_fog_enabled
	atmos.wind_on = Settings.get_v("wind")
	atmos.clouds_on = Settings.get_v("cloud_shadows")
	grime.enabled = Settings.get_v("grime")
	if blood: blood.enabled = Settings.get_v("blood")
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
		return c.lerp(Color.WHITE, 0.16)   # the road's colour, a touch lighter (fine dust scatters more)
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
	if not terrain.break_collider(c, vel, pos + Vector3(0, 0.45, 0)):
		return false
	var col := Color("c9a06a")
	if c.get("cactus", false): col = Color("8fc25a")
	elif c.get("tape", false): col = Color("e8322b")
	for k in 12:
		fx.chunk(Vector3(c.x, pos.y + 0.3 + randf() * 0.6, c.z), Vector3(vel.x * 0.4 + (randf() - .5) * 3, 1 + randf() * 2.5, vel.z * 0.4 + (randf() - .5) * 3), col, 0.025)
	if dust.sim != null: dust.puff_burst(Vector3(c.x, pos.y + 0.1, c.z), 0.6, Color("cdb894"), 0.5)
	for k in (0 if dust.sim != null else 3):
		fx.puff(Vector3(c.x, pos.y + 0.4, c.z), Vector3((randf() - .5) * 1.5, 0.4 + randf() * 0.5, (randf() - .5) * 1.5), Color("cdb894"), 0.35, 1.4, 0.4)
	if audio and not c.get("tape", false):
		if c.get("cactus", false): audio.crunch()
		else: audio.wood_crash(clampf(Vector2(vel.x, vel.z).length() / 12.0, 0.3, 1.5))
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
	# the body carries on with the bike's own motion (no extra pop up: it used to throw the body into the air)
	var body_vel := f * phys.v + Vector3(0, minf(maxf(phys.vy, 0), 6.0 if phys.air else 0.3) + 0.2, 0)
	var spin_v := f * (1.0 + absf(phys.v) * 0.08)   # the top of the body keeps going a little as the bike stops
	phys.begin_crash()
	# detach the rider into world space
	rider.get_parent().remove_child(rider)
	add_child(rider)
	rider.transform = Transform3D.IDENTITY
	ragdoll.start(pts, body_vel, spin_v, 1.0 / 60)
	if blood: blood.crash_start(Vector2(body_vel.x, body_vel.z).length())
	rider.pose_ragdoll(ragdoll.p)
	# (no dust right where the crash starts with the smoke sim: only where the body / bike hit and slide)
	burst(Vector3(phys.x, phys.y + 0.05, phys.z), 30 if dust.sim == null else 2, terrain.surface(phys.x, phys.z), 1.5, dust.sim == null)
	var cs: int = terrain.surface(phys.x, phys.z)
	# (with the smoke sim the ragdoll's own impacts throw the dust: _crash_dust)
	if cs != 2 and dust.sim == null: dust.cloud(Vector3(phys.x, phys.y, phys.z), f * phys.v * 0.3, ground_dust(phys.x, phys.z, cs), 3.2, 1.2)
	if _wasted_on(): wasted.start(reason)
	else: flash(reason)
	if hud: hud.on_crash()
	if audio: audio.crash()
	Settings.rumble(1.0, 1.0, 0.45)

## the crash slow-mo is on (Settings › Gameplay; autotests keep normal time unless BMX_WASTED=1)
func _wasted_on() -> bool:
	if OS.get_environment("BMX_WASTED") != "": return true
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--autotest"): return false
	return bool(Settings.get_v("wasted"))

func get_up() -> void:
	phys.get_up()
	if wasted: wasted.finish()
	ragdoll.active = false
	if blood: blood.crash_end()
	if rider.get_parent() != rig.lean_g:
		rider.get_parent().remove_child(rider)
		rig.lean_g.add_child(rider)
	rider.transform = Transform3D.IDENTITY
	rider.reset_pose()
	_snap_prev()

func on_trick(trick: String) -> void:
	if hud: hud.on_trick(trick)

func on_style(points: int, label: String) -> void:
	if hud: hud.on_style(points, label)
	if OS.get_environment("BMX_TRICK") != "": print("STYLE +%d %s" % [points, label])   # tests

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
## how much dust a crash throws (kept low so the blood on the ground shows: fx/blood.gd)
const CRASH_DUST_BODY := 0.08
const CRASH_DUST_BIKE := 0.15
## how much grit / dirt chunks fly off the body when it hits (1 = the old amount): kept low so the rider stays readable
const CRASH_DEBRIS := 0.2
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
				dust.sim.burst(at, Vector3(v.x * 0.25, 0.6 + k * 0.8, v.z * 0.25), 0.3 + k * 0.25, (50.0 + 110.0 * k) * amt * CRASH_DUST_BODY,
					1.2 + k * 2.2, 0.08 + k * 0.05, ground_dust(pp.x, pp.z, s), 20.0)
				dust.grit_burst(at, Vector3(v.x * 0.3, 0.8 + k * 1.6, v.z * 0.3), 1.0 + k * 2.5, 600.0 * k * amt * 0.2 * CRASH_DEBRIS, 0.06, ground_dust(pp.x, pp.z, s))
				made += 1
		elif hs > 1.2 and made < 10:
			# sliding / rolling along the ground
			if OS.get_environment("BMX_SMOKE_PROBE") != "": print("CRASHDUST slide i=%d t=%.2f hs=%.1f" % [i, phys.crash_t, hs])
			dust.sim.add_source(at, Vector3(v.x * 0.3, 0.4, v.z * 0.3), 0.25, minf(hs, 6.0) * 4.0 * amt * CRASH_DUST_BODY, 6.0, 0.3, ground_dust(pp.x, pp.z, s))
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
				0.3, minf(absf(phys.v), 10.0) * 9.0 * ba * CRASH_DUST_BIKE, 8.0, 0.5, ground_dust(phys.x, phys.z, bs))

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
		elif dirt: rate = fast_k * 14 + dust_k * 280.0 + (clampf(va / 7.0, 0, 1) * 12.0 if dust.sim != null else 0.0) + (50.0 if skid_fx else 0.0) + carve_k * 60 + st.pedal * (6.0 if va < 3 else 0.0)
		elif sand: rate = fast_k * 10 + dust_k * 240.0 + (clampf(va / 7.0, 0, 1) * 10.0 if dust.sim != null else 0.0) + (40.0 if skid_fx else 0.0) + carve_k * 45 + st.pedal * (4.0 if va < 3 else 0.0)
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
		dust.feed_front(front, f_ev, 0.0 if st.front_air else rate * fxd * 0.35, d_a)   # none with the front up (wheelie)
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
		sheep.reset()
		flash("New world #%d" % GameState.seed)
	if fx.has_method("clear_tracks"): fx.clear_tracks()
	if new_world: grime.clean()
	if blood: blood.clear()
	var sp := _water_spawn() if OS.get_environment("BMX_WATER_SPAWN") != "" else Vector3.ZERO
	phys.reset_at(sp.x, sp.z, sp.y)
	if sp != Vector3.ZERO: terrain.update_stream(sp.x, sp.z, INF)
	rider.reset_pose()
	_snap_prev()
	cam.snap_to(Vector3(0, phys.y + 0.5, 0))

## tests (BMX_WATER_SPAWN=1): a dry spot 6 m from the nearest lake, facing it -> (x, heading, z)
func _water_spawn() -> Vector3:
	for r in range(20, 1600, 8):
		for k in 48:
			var a := TAU * k / 48.0
			var x := cos(a) * r
			var z := sin(a) * r
			if terrain.field.ground(x, z) < Terrain.WATER - 0.3:
				var bx := x - cos(a) * 9.0
				var bz := z - sin(a) * 9.0
				print("WATERSPAWN %.0f %.0f" % [bx, bz])
				return Vector3(bx, -a, bz)
	return Vector3.ZERO

const DRAW_KEYS :=["x", "z", "y", "y_draw", "pitch", "pitch_draw", "heading", "body_y"]

func _snap_prev() -> void:
	for k in DRAW_KEYS: _prev[k] = phys.get(k)

func _unhandled_input(e: InputEvent) -> void:
	if get_tree().paused or not input_enabled: return
	if e.is_action_pressed("photo") and not e.is_echo(): toggle_photo(); return
	if e.is_action_pressed("save_log") and not e.is_echo():   # the last 60 s of physics + inputs to a CSV
		var lp := ride_log.save()
		flash("Ride log saved (last 60 s)" if lp != "" else "Couldn't save the ride log")
		if lp != "": print("RIDELOG ", lp)
		return
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
		return {"throttle": 0.0, "brake": 0.0, "steer": 0.0, "hop": false, "sprint": false, "body_fwd": 0.0, "body_lean": 0.0}
	var steer := Input.get_action_strength("steer_left") - Input.get_action_strength("steer_right")
	# a thumbstick needs a curve: fine near the centre (the first bit of stick only tips the bike in a little),
	# full lock at the edge. Keys (all or nothing) are unaffected. Steering response (Settings) scales it
	var expo: float = float(Settings.get_v("pad_expo")) if Settings.pad_active else 1.0
	steer = signf(steer) * pow(absf(steer), expo / maxf(0.3, float(Settings.get_v("steer_sens"))))
	# the rider's body (gamepad right stick, numpad on keys): round stick gate -> square, so diagonals reach full
	var bf := Input.get_action_strength("body_fwd") - Input.get_action_strength("body_back")
	var bl := Input.get_action_strength("body_left") - Input.get_action_strength("body_right")
	var bm := maxf(absf(bf), absf(bl))
	if bm > 0.01:
		var sq := minf(Vector2(bf, bl).length() / bm, 1.4142)
		bf = clampf(bf * sq, -1, 1); bl = clampf(bl * sq, -1, 1)
	return {
		"pad": Settings.pad_active,
		"body_fwd": bf,
		"body_lean": bl,
		"throttle": Input.get_action_strength("pedal"),
		"brake": Input.get_action_strength("brake"),
		"steer": clampf(steer, -1, 1),
		"hop": Input.is_action_pressed("hop"),
		"sprint": Input.is_action_pressed("sprint"),
	}

## tests (BMX_BRAKETURN): which values vibrate - per value, how often its step-to-step change flips sign
## with a real size (a vibration), and the biggest such flip
var _base_bins := {}
var ride_log := RideLog.new()   # the last 60 s, saved with R3 / F8 (save_log)
var _log_lift := 0.0
var jitter_on := false
var _jit_skip := 0
var _jit_head := Vector3.INF
var _jit := {}
func _jitter_sample(key: String, val: float, thr: float) -> void:
	var j: Array = _jit.get(key, [NAN, 0.0, 0, 0.0, 0])   # last value, last delta, flips, biggest flip, samples
	if not is_nan(j[0]):
		var d: float = val - j[0]
		if absf(d) > thr and absf(j[1]) > thr and signf(d) != signf(j[1]):
			j[2] += 1; j[3] = maxf(j[3], absf(d - j[1]))
		j[1] = d
	j[0] = val; j[4] += 1
	_jit[key] = j

func jitter_report() -> void:
	var keys := _jit.keys()
	keys.sort_custom(func(a, b): return _jit[a][2] > _jit[b][2])
	for k in keys:
		var j: Array = _jit[k]
		print("JITTER %-12s flips=%4d / %d samples  biggest=%.4f" % [k, j[2], j[4], j[3]])

func _physics_process(dt: float) -> void:
	_snap_prev()
	var inp := _read_input()
	phys.step(dt, inp)
	ride_log.record(dt, phys, inp, _log_lift, rig.position.y if rig else 0.0, rider.J if rider else [])
	if jitter_on and not phys.crash_on:
		for kv in [["slip", phys.slip, 0.002], ["yaw_rate", phys.yaw_rate, 0.02], ["lean", phys.lean, 0.002], ["bike_lean", phys.bike_lean, 0.003],
				["counter", phys.counter, 0.003], ["steer", phys.steer, 0.003], ["hip_shift", phys.hip_shift, 0.001], ["body_x", phys.body_x, 0.001],
				["pitch", phys.pitch, 0.002], ["y", phys.y, 0.001], ["body_y", phys.body_y, 0.001], ["compress", phys.compress, 0.001], ["lat_a", phys.lat_a, 0.05], ["v", phys.v, 0.01]]:
			_jitter_sample(kv[0], kv[1], kv[2])
	if phys.crash_on:
		rider.pose_ragdoll(ragdoll.p, _ragdoll_roots())
	if not phys.is_sane():
		push_warning("physics went non-finite; restoring last good state")
		for k in _last_good: phys.set(k, _last_good[k])
		phys.v = 0; phys.vy = 0; phys.air = false; phys.w_init = false
		phys.reset_body()
	else:
		for k in ["x", "z", "y", "heading", "course", "pitch", "lean", "steer", "slip", "compress"]:
			_last_good[k] = phys.get(k)

## torn-off limbs: joint -> where its free piece's root point is now (Rider.pose_ragdoll)
func _ragdoll_roots() -> Dictionary:
	if ragdoll.cut.is_empty(): return {}
	var out := {}
	for b in ragdoll.cut:
		out[b] = ragdoll.p[ragdoll.cut[b]]
	return out

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

# tests (BMX_DAB_PROBE): per-frame shoe moves on the bike, the sole's lowest point vs the ground
var dab_probe := OS.get_environment("BMX_DAB_PROBE") != ""
var _dab_last := []
var _dab_stats := {"jump_dab": 0.0, "jump_ride": 0.0, "sole_min": 1e9, "t_print": 0.0}
func _dab_probe(st: BikePhysics) -> void:
	for i in 2:
		var lp: Vector3 = rider.shoe[i].position
		if _dab_last.size() == 2:
			var j: float = lp.distance_to(_dab_last[i]) / maxf(get_process_delta_time(), 1e-3)   # m/s on the bike
			var key := "jump_dab" if dab_k > 0.0 and dab_k < 1.0 else "jump_ride"
			if t > 0.3: _dab_stats[key] = maxf(_dab_stats[key], j)
		if dab_k > 0.99 and (dab_side < 0.0) == (i == 0):
			var sp: Vector3 = rider.shoe[i].global_position
			_dab_stats.sole_min = minf(_dab_stats.sole_min, sp.y - terrain.top_height(sp.x, sp.z))
	_dab_last = [rider.shoe[0].position, rider.shoe[1].position]
	if t >= _dab_stats.t_print:
		_dab_stats.t_print = t + 0.25
		print("DAB t=%.2f v=%.2f pedal=%.2f k=%.2f side=%d jump_dab=%.3f jump_ride=%.3f sole_gap=%.3f" % [t, st.v, st.pedal, dab_k, dab_side, _dab_stats.jump_dab, _dab_stats.jump_ride, _dab_stats.sole_min])

## Foot down at a stop: nearly stopped, not pedalling, on the ground, not crashed -> one foot leaves its
## pedal for the ground beside the bike (eased in over 0.5 s, back up over 0.4 s when riding off).
func _update_dab(dt: float, st: BikePhysics) -> void:
	if st.crash_on:
		dab_lin = 0.0; dab_k = 0.0
		return
	var want: bool = not st.air and st.pedal < 0.05 and (st.v < 1.2 and st.v > -0.7 if dab_lin > 0.0 else absf(st.v) < 0.5)   # backing up (brake held) lifts it
	if want and dab_lin <= 0.0:
		# which foot: the one on the lower pedal; level cranks -> the side the bike already leans to, else left
		var dy := 0.0
		if rig.pedal_pivots.size() == 2:
			dy = rig.pedal_pivots[0].global_position.y - rig.pedal_pivots[1].global_position.y
		if absf(dy) > 0.03: dab_side = -1.0 if dy < 0.0 else 1.0
		elif absf(st.bike_lean) > 0.02: dab_side = -signf(st.bike_lean)
		else: dab_side = -1.0
	dab_lin = move_toward(dab_lin, 1.0 if want else 0.0, dt / (0.5 if want else 0.4))
	dab_k = smoothstep(0.0, 1.0, dab_lin)

## Moves the dabbing foot's target (lean-node space) from its pedal to the ground beside the bike.
func _dab_foot(lt: Dictionary) -> void:
	var key := "footL" if dab_side < 0.0 else "footR"
	var hb := rig.global_transform.basis   # heading only: x forward, z to the rider's right
	var fwd := Vector3(hb.x.x, 0.0, hb.x.z).normalized()
	var rgt := Vector3(hb.z.x, 0.0, hb.z.z).normalized()
	var bb: Vector3 = rig.crank_n.global_position
	var g := bb + rgt * dab_side * DAB_OUT + fwd * 0.04
	g.y = terrain.top_height(g.x, g.z) + 0.012   # sole just on the drawn ground (rocks, decks too)
	var tl: Vector3 = rig.lean_g.to_local(g)
	tl.y -= 0.03   # the rider draws the shoe 3 cm above its foot point
	var pedal_p: Vector3 = lt[key]
	var f := pedal_p.lerp(tl, dab_k)
	f.y += sin(PI * dab_k) * 0.07   # lifts off the pedal on the way out / back
	lt[key] = f

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
	_update_dab(dt, st)
	var wobble := sin(t * 2.3) * 0.025 * maxf(0.0, 1 - absf(st.v) / 2) * (1.0 - dab_k)
	var dab_lean := -dab_side * DAB_LEAN * dab_k   # bike_lean > 0 tips the top to the rider's left
	rig.pose(drawn_pos.x, y_draw + (1.5 if OS.get_environment("BMX_PITCH_POSE") != "" else 0.0), drawn_pos.z, hd, p_draw, st.hop_nose, st.bike_lean + st.rock + wobble + dab_lean,
		st.steer - wobble * 1.5, st.wheel_f, st.wheel_r, st.crank)
	# the physics' tyres are soft and follow the smooth height field; the drawn ground is a triangle mesh
	# (higher in hollows) with rocks and decks on it. Lift / tilt the drawn bike so no tyre is ever inside it
	if OS.get_environment("BMX_NOUNCLIP") == "":
		rig.fit_wheels(terrain.top_height)
		var _pre_y := rig.position.y
		var _dF0 := rig.tyre_depth(rig.wheel_f, rig.wheel_rf, terrain.top_height) if st.bank_probe else 0.0
		var _dR0 := rig.tyre_depth(rig.wheel_r, rig.wheel_rr, terrain.top_height) if st.bank_probe else 0.0
		var _base_over: float = rig.global_position.y - terrain.top_height(rig.global_position.x, rig.global_position.z)
		var _axF_over_base: float = rig.wheel_f.global_position.y - rig.global_position.y
		if st.bank_probe and not st.air:   # tests: how low the physics body sits vs the ground, by lean
			var bin_k := mini(int(absf(st.bike_lean) / 0.25), 4)
			var acc: Array = _base_bins.get(bin_k, [0.0, 0, 0.0])
			acc[0] += _base_over; acc[1] += 1; acc[2] += st.n_load / BikePhysics.G
			_base_bins[bin_k] = acc
		var _axF: Vector3 = rig.wheel_f.global_position
		var _axR: Vector3 = rig.wheel_r.global_position
		var was: float = rig.unclip_tyres(terrain.top_height)
		_log_lift = maxf(was, 0.0)
		if st.bank_probe and was > 0.05 and not st.air:   # tests: the drawn bike lifted a lot (it "shoots up")
			print("BASE over ground=%.3f  axleF over base=%.3f  susp xF=%.3f xR=%.3f  y_draw-y=%.3f" % [_base_over, _axF_over_base, rig.susp.xF if rig.susp else 0.0, rig.susp.xR if rig.susp else 0.0, y_draw - st.y])
			print("LIFT %.3f m  bike_lean=%.2f lean=%.2f bank=%.2f v=%.1f  dF=%.3f dR=%.3f  axleF-ground=%.3f axleR-ground=%.3f  field-vs-mesh F=%.3f R=%.3f" % [was, st.bike_lean, st.lean, st.bank, st.v, _dF0, _dR0,
				_axF.y - terrain.top_height(_axF.x, _axF.z), _axR.y - terrain.top_height(_axR.x, _axR.z),
				terrain.top_height(_axF.x, _axF.z) - terrain.height(_axF.x, _axF.z), terrain.top_height(_axR.x, _axR.z) - terrain.height(_axR.x, _axR.z)])
		if clip_probe:
			clip_stats.frames += 1
			if was > 0.002: clip_stats.fixed += 1
			clip_stats.before = maxf(clip_stats.before, was)
			var left: float = maxf(rig.tyre_depth(rig.wheel_f, rig.wheel_rf, terrain.top_height), rig.tyre_depth(rig.wheel_r, rig.wheel_rr, terrain.top_height))
			clip_stats.after = maxf(clip_stats.after, left)
			if left > 0.0005: clip_stats.bad += 1
	elif clip_probe:
		var d: float = maxf(rig.tyre_depth(rig.wheel_f, rig.wheel_rf, terrain.top_height), rig.tyre_depth(rig.wheel_r, rig.wheel_rr, terrain.top_height))
		clip_stats.frames += 1
		clip_stats.before = maxf(clip_stats.before, d)
		if d > 0.002: clip_stats.bad += 1
	if OS.get_environment("BMX_LIP_SHOT") != "" and _lip_shots < 10:   # tests: 10 shots, 0.08 s apart, from a lip
		if _lip_shots == 0 and st.prep > 0.2 and not st.air: _lip_t = t
		if _lip_t >= 0.0 and t - _lip_t >= _lip_shots * 0.08:
			get_viewport().get_texture().get_image().save_png("%s_%d.png" % [OS.get_environment("BMX_LIP_SHOT"), _lip_shots])
			print("LIPSHOT %d prep=%.2f air=%s compress=%.2f absorb=%.2f vy=%.1f" % [_lip_shots, st.prep, st.air, st.compress, st.body_y - st.y, st.vy])
			_lip_shots += 1
	if OS.get_environment("BMX_LEAN_SHOT") != "" and not st.air and not st.crash_on:   # tests: shots in deep leans
		var ln := absf(st.bike_lean)
		_lean_max = maxf(_lean_max, ln)
		if ln > 0.7 and t - _lean_shot_t > 1.5 and _lean_shots < 4:
			_lean_shot_t = t
			get_viewport().get_texture().get_image().save_png("%s_%d.png" % [OS.get_environment("BMX_LEAN_SHOT"), _lean_shots])
			print("LEANSHOT %d bike=%.0fdeg body=%.0fdeg v=%.1f" % [_lean_shots, rad_to_deg(st.bike_lean), rad_to_deg(st.bike_lean - st.counter), st.v])
			_lean_shots += 1
	if clip_probe and OS.get_environment("BMX_CLIP_SHOT") != "":   # tests: a screenshot when a tyre was 12+ cm in
		var deep: float = clip_stats.before
		if clip_stats.get("shot", 0) == 1:
			get_viewport().get_texture().get_image().save_png(OS.get_environment("BMX_CLIP_SHOT"))
			clip_stats.shot = 2
		elif clip_stats.get("shot", 0) == 0 and deep > 0.12 and not st.crash_on and not st.air:
			clip_stats.shot = 1
	st.brake_heat *= exp(-dt / 3.5)
	rig.set_brake_heat((st.brake_heat - 0.35) / 0.9)
	if not st.crash_on:
		var lt := rig.limb_targets()
		if dab_k > 0.0: _dab_foot(lt)
		var T: Dictionary = Tune.v
		rider.update_pose(dt, {"footL": lt.footL, "footR": lt.footR, "handL": lt.handL, "handR": lt.handR,
			"dab": dab_k, "dabSide": dab_side, "dabLean": DAB_LEAN,
			"v": st.v, "lean": st.bike_lean + st.rock, "steer": st.steer, "yawRate": st.yaw_rate,
			"counter": st.counter, "rockRoll": st.rock, "headRoll": st.bike_lean * 0.85,
			"absorb": clampf(body_y - y_draw, -T.legComp, T.legExt), "pitch": p_draw, "bodyLevel": T.bodyLevel,
			"attackDrop": T.attackDrop, "pedal": st.pedal, "sprint": st.sprint * st.pedal, "crank": st.crank,
			"air": st.air_k, "compress": maxf(0.0, -st.compress), "hipShift": st.hip_shift, "bodyStick": st.body_in_s, "slope": st._g_pitch, "airTilt": st.air_tilt * float(Tune.v.get("stickBodyTilt", 0.6)) * clampf(st.air_stick.length() * 3.0 + absf(st.edge_s) * 2.0, 0.0, 1.0) if st.air else 0.0, "bodyLat": st.air_stick.x if st.air else st.flick, "wheelR": rider.to_local(rig.wheel_r.global_position), "wheelRR": rig.wheel_rr, "t": t,
			"airSpin": st.yaw_rate if st.air else 0.0, "wheelY": (rig.wheel_f.global_position.y + rig.wheel_r.global_position.y) * 0.5, "turn": 0.0 if st.air else st.yaw_rate * clampf(absf(st.v) / 3.0, 0.3, 1.0)})
		if dab_probe: _dab_probe(st)
		if st.crash_on: _jit_skip = 40
		elif _jit_skip > 0: _jit_skip -= 1
		if jitter_on and _jit_skip == 0:   # tests: the drawn joints (rider space), per frame
			var hj: Vector3 = rider.J[0]
			if _jit_head != Vector3.INF and hj.distance_to(_jit_head) > 0.08:
				print("JUMP head %.3f m  v=%.2f brake_stop=%s pivot=%.2f slip=%.2f counter=%.2f lean=%.2f pitch=%.2f slope=%.2f wheelie=%.2f air=%.2f hip=%.3f" % [hj.distance_to(_jit_head), st.v, st.brake_stop, st.pivot, st.slip, st.counter, st.lean, st.pitch, st._g_pitch, rider.sm_wheelie, st.air_k, st.hip_shift])
			_jit_head = hj
			for ji in [[0, "j_head"], [1, "j_chest"], [2, "j_pelvis"], [4, "j_elbowL"], [10, "j_kneeL"]]:
				var jp: Vector3 = rider.J[ji[0]]
				_jitter_sample(ji[1] + "x", jp.x, 0.002); _jitter_sample(ji[1] + "y", jp.y, 0.002); _jitter_sample(ji[1] + "z", jp.z, 0.002)
	var vd: float = Settings.get_v("view_distance")
	terrain.update_stream(st.x, st.z, 4.0)
	far_hills.follow(drawn_pos)
	sheep.follow(dt, drawn_pos, st.v, st.fwd())
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
	_update_light(dt)
	sun.light_energy = sun_energy * atmos.shade
	# the dust simulation around the rider (fx/smoke_sim.gd)
	if st.crash_on and ragdoll.active: blood.crash_step(ragdoll.p, ragdoll.q, ragdoll.last_h, ragdoll.rad)
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
		sun.directional_shadow_max_distance = 220.0
	else:
		env.fog_depth_begin = (cam.dist + 55) * vd
		env.fog_depth_end = (cam.dist * 1.6 + 100) * vd
		sun.directional_shadow_max_distance = clampf(cam.dist * 4.5, 80, 260) * (0.7 if int(Settings.get_v("shadows")) == 0 else 1.0)
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
