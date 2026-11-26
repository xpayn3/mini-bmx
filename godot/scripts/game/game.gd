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
## Poly Haven pure-sky HDRIs (CC0, 4K), with the sun's U across each photo (measured: brightest 0.02 % of pixels).
## `el` = the sun height they were shot at; the ride crossfades between them as the sun climbs.
const HDRI_DIR := "res://assets/hdri/"
const HDRI_NIGHT := ["rogland_clear_night_4k.hdr", 0.5084]
const HDRI_LOW := [["belfast_sunset_puresky_4k.hdr", 0.5992], ["qwantani_dusk_2_puresky_4k.hdr", 0.6002]]
const HDRI_DAY := [["kloofendal_48d_partly_cloudy_puresky_4k.hdr", 0.5952], ["kloofendal_43d_clear_puresky_4k.hdr", 0.6003], ["autumn_field_puresky_4k.hdr", 0.6006]]
static var SUN_DIR := Vector3(SUN_AZ.normalized().x * cos(SUN_ELEV), sin(SUN_ELEV), SUN_AZ.normalized().y * cos(SUN_ELEV))
const SKY := Color("a9d6ea")
## ride light: a clear afternoon. A strong warm sun against a cool blue sky fill (warm light, cool shade)
const RIDE_SUN := 1.8
const RIDE_SUN_COL := Color("fff1de")
const RIDE_FAR := 2600.0   # camera far plane: the far hills (FarHills) reach the horizon
const RIDE_FOG := Color(0.74, 0.85, 0.98)
const DUST_SPLASH := Color("eef6fa")
const PUDDLE_DROP := Color(0.24, 0.21, 0.17)   # muddy water off a tyre through a road puddle
var _splash_acc := 0.0
var _pud_us := 0
var _pud_n := 0
var _dprobe_t := 0.0
const DIRT_CHUNK := Color("7a5534")
const ROCK_CHUNK := Color("8d8a84")
const GRASS_CHUNK := Color("4f8a2e")

var terrain
var fx
var ragdoll
var rider
var rig: BikeRig
var phys: BikePhysics
var rumble: PadRumble   # layered controller vibration (game/pad_rumble.gd)
var cam: CameraRig
var hud
var wasted                  # crash slow-mo + "WASTED" look (fx/wasted.gd)
var area_title              # new area banner in the WASTED type (fx/area_title.gd)
var audio
var sun: DirectionalLight3D
var env: Environment
const VOL_DENSITY := 0.0035   # haze thick enough that the sun shows as shafts past trees and fences
var cam_attr: CameraAttributesPractical
var refl_probe: ReflectionProbe   # scene reflections (trees, hills) for the bike paint / chrome / wet; follows the rider
var _probe_pos := Vector3(1e9, 0, 0)
var _probe_t := 0.0
var grade_rect: ColorRect
var lens := LensFx.new()     # water + dust on the camera lens, drawn by grade_rect (fx/lens_fx.gd)
var atmos := Atmos.new()
var grime: Grime
var contact: ContactShadow   # soft dark patches under the tyres + bike / rider (fx/contact_shadow.gd)
var blood                    # blood on the ground + torn-off limbs after a crash (fx/blood.gd; loaded by path, no class cache needed)
var dust: RideDust
var sun_energy := RIDE_SUN
# level light (tuning card › Light, LightSettings): time of day, day / night cycle
var tod := 19.33             # the clock (hours); the cycle runs it, a slider move resets it
var light_ver := -1          # LightSettings.version last applied
var _light_time := NAN       # the Light tab's time / cycle last applied (only a change of these resets the clock)
var _light_cycle := false
var light_t := 0.0
var light_note := ""
var _lab_ver := -1           # LightLab.version last applied (dev knobs)         # what the light model chose (LSWEEP / BMX_LIGHT_PROBE lines)
const GoggleLens = preload("res://scripts/rider/goggle_lens.gd")
const RIM_LAYER := 1 << 11   # render layer 12: the rider + bike (only the rim light uses it)
const AGX_CONTRAST := 1.35        # the title screen's look
## a ride (2026-11-26 realistic light): AgX at Godot's own contrast, white 12 (docs: >= 6 for real light), a neutral grade,
## the exposure one constant (SunSky puts the day's adaptation into the light itself). These are the start values; the
## dev knobs (exposure 1.2, haze sky light 0.2, bloom mix ...) are LightLab's (res://data/light_lab.json)
const AGX_CONTRAST_RIDE := 1.25
const AGX_WHITE := 12.0
const GLOW_MIX := 0.04
const MOON_COL := Color(0.72, 0.8, 1.0)   # moonlight is sunlight, but night vision (rods) sees it blue-grey
## CameraAttributesPractical turns sensitivity (ISO) into a luminance clamp as ISO x 12.5 / 100 / 100, and the
## tonemapper multiplies by auto_exposure_scale / luminance: pinned here (min = max) the factor is 1 = as if off
const AE_NEUTRAL_ISO := 0.4 / 0.00125   # = auto_exposure_scale (0.4) / 0.00125 -> 320
## directional shadow reach: the terrain only loads +-168 m and far casters are trimmed
const SHADOW_MAX := 150.0
## shadow reach by quality (Low .. Ultra): fixed, so the cascades never re-fit while riding. The streamed trees
## are drawn to DECO_FADE_OUT (124 m): High reaches past them, so every tree you see has its shadow.
const SHADOW_REACH := [100.0, 140.0, 170.0, 200.0]
var _shadow_zoom := -1.0
## the cascades sit where the picture is: the first one ends just past the rider (the follow cameras are 5-25 m
## behind), the second over the trail ahead, the third out to the trees. Fixed shares of the reach put the rider in
## a coarse middle cascade. Redone only when the zoom you set changes (not with the speed dolly).
## the sun's shadow uses 2 cascades at every quality (2026-11-24): the rider / bike / everything near the camera was drawn
## into 3-4 of the 4 cascades' maps (409 of the 889 shadow draws were the rider + bike). 2 cascades, the near one still
## ending zoom + 6 m (so the rider's own shadow stays as sharp): shadow draws 887 -> 539, render CPU -0.15 ms, GPU -0.13 ms
## at the start, the 30 s follow ride 141 -> 156 fps; mid-distance tree shadows a touch softer.
## BMX_SHADOW_SPLITS=4 = the old 4 cascades (Medium and up)
func _two_splits() -> bool:
	var forced := Env.s("BMX_SHADOW_SPLITS")
	if forced != "": return forced != "4"
	# 2026-11-25 (realism pass): only the top shadow quality pays for the 4 cascades again (sharper mid-distance tree shadows,
	# ~-8 % fps measured when it was dropped); every other preset keeps the cheap 2
	return int(Settings.get_v("shadows")) < 3

func _shadow_fit() -> void:
	var sq := int(Settings.get_v("shadows"))
	var reach: float = SHADOW_REACH[clampi(sq, 0, 3)]
	if terrain is LevelTerrain and terrain.baked: reach = LevelTerrain.RT_SHADOW   # (baked level: far shadows are baked)
	if Env.s("BMX_SHADOW_REACH") != "": reach = float(Env.s("BMX_SHADOW_REACH"))   # tests
	var zoom := roundf(cam.dist / maxf(1.0 - 0.2 * cam.speed_feel, 0.5))   # the zoom set, without the speed dolly
	if absf(sun.directional_shadow_max_distance - reach) > 0.5: sun.directional_shadow_max_distance = reach
	if zoom == _shadow_zoom: return
	_shadow_zoom = zoom
	if sq == 0 or _two_splits():
		# 2026-11-24 (user: ground / grass / shadows blurry a couple of metres ahead of the rider): the near cascade ended at
		# zoom + 6 m, i.e. ~6 m past the rider, so the ground he rides onto was in the coarse far map. Now it reaches 18 m
		# past him (Low 24: smaller map) and the two cascades are cross-faded at every quality (like racing games do)
		var s1 := 24.0 if sq == 0 else 18.0
		if Env.s("BMX_SHADOW_S1") != "": s1 = float(Env.s("BMX_SHADOW_S1"))   # tests
		sun.directional_shadow_split_1 = clampf((zoom + s1) / reach, 0.03, 0.5)
		return
	sun.directional_shadow_split_1 = clampf((zoom + 6.0) / reach, 0.04, 0.3)
	sun.directional_shadow_split_2 = clampf((zoom + 22.0) / reach, sun.directional_shadow_split_1 + 0.05, 0.5)
	sun.directional_shadow_split_3 = clampf((zoom + 55.0) / reach, sun.directional_shadow_split_2 + 0.08, 0.75)

## the band (m from the rider) the streamed trees / rocks dissolve out over and the far backdrop's trees in
## (shaders/deco_fade.gdshaderinc): inside the 144 m the loaded chunks always cover, so chunks never pop in
const DECO_FADE_IN := 100.0
const DECO_FADE_OUT := 124.0
## the ground crossfade: real chunk ground full until x, gone by y m from the rider. The loaded chunk square always covers
## >= 144 m (Terrain.RADIUS 3 x 48 m, less the rider's offset in his chunk), so the band ends there. BMX_GROUND_FADE=in,out (0,0 = off)
var _ground_band := Vector2(105.0, 144.0) if Env.s("BMX_GROUND_FADE") == "" else Vector2(float(Env.s("BMX_GROUND_FADE").split(",")[0]), float(Env.s("BMX_GROUND_FADE").split(",")[1]))
var _deco_band := Vector2(DECO_FADE_IN, DECO_FADE_OUT) if Env.s("BMX_DECO_FADE") == "" 	else Vector2(float(Env.s("BMX_DECO_FADE").split(",")[0]), float(Env.s("BMX_DECO_FADE").split(",")[1]))   # test: in,out
const MIST_DEEP := 2.0      # the mist top sits this far over the low ground round the rider's path
const MIST_CLEAR_FULL := 8.0   # the rider this far above the mist top: full mist
const MIST_CLEAR_NONE := 3.0   # ... this close above it (or in it): none, the ground round the bike is always clear
const MIST_LEFT := 8.0      # the low ground round here is this far above the pool for 3 s: a new one
const MIST_DRIFT := 0.3     # m/s the level may move in view (small changes only)
const MIST_FADE_IN := 6.0   # s a new pool takes to appear
const MIST_DENSITY := 0.3  # height fog in the dips at sunrise (Env BMX_MIST=k forces the amount)
var rim: DirectionalLight3D
var _rim_col := Color(1, 1, 1)
var _rim_e := 0.0
var _rim_dir := Vector3.ZERO   # the rim light's direction, eased (_rim_update)
var _rim_tag_t := 0.0
var _mist_y := NAN           # the mist top (world height); see _mist_update
var _mist_want := 0.0
var _mist_gy := 0.0
var _mist_pos := Vector3.ZERO
var _mist_f := 0.0
var _mist_thin := 1.0
var _mist_swap := false
var _mist_out := 1.2
var _mist_off_t := 0.0
var _mist_scan_t := 0.0
var _mist_probe_t := 0.0
var _match := 0.0   # rider light match (Grime.trim), 0..1: how much the over-bright parts of the rider + bike are rolled off
var _lens_now := ""
var night_k := 0.0           # how much night (0 day .. 1 full night), from _apply_light
var golden_k := 0.0          # how golden the low sun is (0..1), from _apply_light
var motes: AmbientMotes      # pollen by day, fireflies at dusk / night
var amb_base := 0.36        # flat ambient for the GI setting (SDFGI brings its own sky light)
var speed_k := 0.0           # 0..1 speed feel (FOV boost, edge blur)
var photo := false           # photo mode (O, game/photo_mode.gd): time frozen, free camera, lens / light / look card
var photo_mode: PhotoMode    # built on first use
var _photo_last := 0
## instant replay (I / pad L3 / pause > Replay, game/replay.gd): the last 60 s of what was drawn, played back
## with its own cameras while the ride is frozen (time_scale 0, like photo mode)
var replay: ReplayMode
var replay_on := false
# ---- Pose Lab (ui/pose_lab.gd, rider/pose_keys.gd): pause anywhere (mid-air too) and pose the rider with keys on the
# jump timeline. STYLE ONLY: pose_hold just stops the physics step like the playground's pause, nothing in the
# physics changes. pose_t = where in the jump timeline we are now (-1 = not in a jump)
var pose_lab = null
var pose_hold := false          # the physics step is held (the rider is still drawn / posed every frame)
var pose_steps := 0             # physics ticks to run while held
var pose_t := -1.0
var _pl_air := 0.0              # s since take-off (for the timeline's air part)
var style_names := PackedStringArray()   # what each float of style_row is ("pose|t", "clip|<name>|w / sig / t", "ch|<channel>", "sig|..", "drv|..")
var style_row := PackedFloat32Array()    # this frame's style numbers: the replay keeps one per sample (Style Inspector)
var _style_rev := -1
const STYLE_SIG := ["kmh", "air", "bike_lean", "air_tw", "flip_acc", "yaw_rate", "man_a", "nose_a", "pop_fx", "squash", "prep", "land_fold", "air_pull"]
const STYLE_DRV := ["preload", "extend", "popFx", "squash", "landFold", "landReach", "airPull", "bodyStick", "hipShift", "flipExt", "flipArch", "lipK", "bodyLat", "airWhip", "lean", "steer", "pitch"]
var _clip_probe := Env.s("BMX_CLIP_PROBE") != ""
var _clip_probe_k := -1
var _pk_bar := 0.0             # Pose Lab: the drawn handlebar turned by a key (rad)
var _pk_rt_on := false         # the rider node is turned about the bottom bracket by a "bike under body" key
var _landed := 0.0           # landing impact to feed the mud next step
var _cloud_t := 0.0
var susp = null
var pedal_a0 := [0.0, PI]

var bike_cfg: Dictionary
var t := 0.0
var drawn_pos := Vector3.ZERO
# tests (BMX_CLIP_PROBE): how deep the drawn tyres went into the ground before / after unclipping
var clip_probe := Env.s("BMX_CLIP_PROBE") != ""
var _lean_max := 0.0; var _lean_shot_t := -9.0; var _lean_shots := 0   # tests (BMX_LEAN_SHOT)
var _jp_v := 0.0   # tests (BMX_JUMP_PROBE): the speed it left the ground at
var _lip_t := -1.0; var _lip_shots := 0   # tests (BMX_LIP_SHOT)
var _land_t := -1.0; var _land_shots := 0   # tests (BMX_LAND_SHOT)
var clip_stats := {"frames": 0, "fixed": 0, "bad": 0, "before": 0.0, "after": 0.0}
# tests: BMX_GAP_PROBE=1 = the air left under each grounded tyre of the drawn bike, binned by bank and manual
# (GAP lines at the end): gap = how far the tyre's lowest point is above the drawn ground, mesh = drawn ground
# minus the physics ground under the axle (> 0: the drawn ground is higher), lift = the drawn bike's unclip lift
var gap_probe := Env.s("BMX_GAP_PROBE") != ""
var gap_stats := {}

func _gap_probe(st) -> void:
	var bank_b: String = "flat" if absf(st.bank) < 0.1 else ("bank" if absf(st.bank) < 0.25 else "steep")
	var man: String = "manual" if st.man_a > 0.1 else ("nose" if st.nose_a > 0.1 else "both")
	for w in [["F", rig.wheel_f, rig.wheel_rf, st.c_f], ["R", rig.wheel_r, rig.wheel_rr, st.c_r]]:
		if not w[3]: continue
		var drawn: Callable = terrain.drawn_height if terrain.has_method("drawn_height") and not (terrain is PlaygroundTerrain) and not (terrain is LevelTerrain) else terrain.top_height
		rig._ground_cache.clear()   # (it holds this frame's fit samples of top_height)
		var g: float = -rig.tyre_depth(w[1], w[2], drawn)
		rig._ground_cache.clear()
		var a: Vector3 = (w[1] as Node3D).global_position
		var mesh: float = drawn.call(a.x, a.z) - terrain.height(a.x, a.z)
		var k: String = "%s %s %s" % [bank_b, man, w[0]]
		var s: Array = gap_stats.get(k, [0, 0.0, 0.0, 0.0, 0.0, 0])
		s[0] += 1; s[1] += g; s[2] = maxf(s[2], g); s[3] += mesh; s[4] += _lift_s
		if g > 0.01: s[5] += 1
		gap_stats[k] = s
var _prev := {}
var _last_good := {}
# foot down at a stop (drawn only, the physics doesn't know): 0..1 eased, which foot (-1 left, +1 right)
var dab_lin := 0.0
var dab_k := 0.0
var dab_side := -1.0
const DAB_LEAN := 0.24       # rad (~14 deg) the bike leans onto the foot: a relaxed, stylish lean, the body stays upright
const DAB_OUT := 0.36        # m from the bike's centre line to the foot on the ground
const DAB_FWD := 0.10        # m ahead of the bottom bracket the foot goes down (a little forward, braced)
var _dab_vprev := 0.0
var _dab_dec := 0.0          # smoothed deceleration (m/s^2): slowing to a stop brings the foot out early
var _dab_gap := 0.0          # foot side's ground height minus the other side's (side slope)
var _dab_lean_s := 0.0       # the bike's lean onto the foot, eased
var _dab_hold := 0.0         # s the foot has been fully down
var _idle_tgt := Vector2.ZERO   # idle look-round target (yaw, pitch)
var _idle_next := 0.0
var msg_t := 0.0
var biome_t := 0.0
var biome_cur := "Green Hills"
var biome_next := ""
var biome_hold := 0
var takeoff := Vector3.ZERO
var air_peak := 0.0
var input_enabled := true
var sky_mat: ShaderMaterial
## The title screen's backdrop is its own hand-picked place (a fixed world and spot), not the player's world:
## main builds the title Game with title_world = true and swaps to the real world when a ride starts.
const TITLE_SEED := 37   # a desert summit with rolling hills far below, picked by hand
## the bike is turned this far from the hand-picked heading: the camera (yaw_off -1.95 from it: the bike faces three-quarters towards the camera) then looks ~0.5 rad round
## from the original view, across the valley the hill falls into, instead of into the sun
const TITLE_TURN := 2.45
## x, z, heading (rad) of the bike on that summit. The heading was 1.4399 until 2026-11-26: the land changed under it
## (2026-11-25 mountains / erosion) and the view looked into a ridge 58 m high, burying the sign. Now the camera looks
## west-south-west (260 deg) over the open plateau to the mountains (picked from a survey of every direction here)
const TITLE_SPOT := Vector3(30.0, -120.0, 4.0379)
var title_world := false
## a test level instead of the procedural world (main sets it before add_child from GameState.level): "playground" =
## the test playground (scripts/levels: PlaygroundTerrain + PlaygroundProbe, which measures every jump)
var level := ""
var level_probe: PlaygroundProbe
var lab: PlaygroundLab   # the playground's lab tools (energy / checks, pause / step / slow, record / replay), made by diag
var race: LevelRace   # a built level's race timing (levels/level_race.gd: gates, splits, best times)
var diag: RideDiag   # ride diagnostics (F4, levels/ride_diag.gd): graphs of suspension, input, tyres, body, air
var _level_light_ver := -1
## parts of an earlier Game of the same world to use instead of building them ({terrain, far_hills}; main sets it
## before add_child: the title backdrop round a garage visit). See take_world().
var reuse := {}
var _title_heading := NAN
var title_sign: TitleSign   # the hillside RUNOUT sign behind the rider on the title screen
var scenic := false          # title screen: golden hour, a lookout camera, far hills to the horizon
var far_hills: FarHills
var grass: GrassField
var sheep: Node3D   # SheepHerdCs
var tumbleweeds: Tumbleweeds
var title_life: TitleLife     # title screen only: birds, blowing dust, dust round the bushes

## ripples in the road's puddles: the lake's compute wake (world/water_wake.gd) as a second, snappier instance that the
## ground shader reads through the globals puddle_wake / puddle_wake_info
var puddle_wake: WaterWake = null
var _pw_info := Vector4.ZERO
static var _pw_owner := 0   # the Game whose wake the puddle_wake globals point at

## the road's surface baked into a camera-following texture window (world/road_detail.gd); the ground shader reads it
## through the globals road_a / road_b / road_c / road_info0..2 (info.w = 0: its old per-pixel path)
var road: RoadDetail = null
var _road_info: Array[Vector4] = [Vector4.ZERO, Vector4.ZERO, Vector4.ZERO, Vector4.ZERO]
static var _road_owner := 0

## freed (not just moved: a prebuilt ride's reparent fires _exit_tree): switch the puddle ripples off, or the title /
## garage / next ride's ground would read this Game's freed wake texture through a live window
func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and _pw_owner == get_instance_id():
		_pw_owner = 0
		RenderingServer.global_shader_parameter_set("puddle_wake_info", Vector4.ZERO)   # (z = 0: ground.gdshader never samples it)
	if what == NOTIFICATION_PREDELETE and _road_owner == get_instance_id():   # (the same for the baked road)
		_road_owner = 0
		for l in RoadDetail.CELLS.size(): RenderingServer.global_shader_parameter_set("road_info%d" % l, Vector4.ZERO)
		if road != null: road.free_gpu()

func _ready() -> void:
	if not title_world and level == "":
		puddle_wake = WaterWake.new()
		if puddle_wake.ok:
			puddle_wake.damp = 2.5
			puddle_wake.cell = 0.03   # puddles: fine ripples (3 cm cells over a 10 m window: the same texel count, a window the rider's tyres never leave)
			puddle_wake.wave_c = 0.55
			RenderingServer.global_shader_parameter_set("puddle_wake", puddle_wake.tex)
			_pw_owner = get_instance_id()
		else:
			puddle_wake = null
	if not title_world: _make_ruts.call_deferred()   # (once the terrain exists)
	if not title_world and Env.s("BMX_LIGHT_SWEEP") != "":   # test: time of day sweep with picture stats (game/light_sweep.gd)
		var sw = preload("res://scripts/game/light_sweep.gd").new()
		sw.game = self
		add_child(sw)
	if not title_world and (level == "" or level.ends_with(".tscn")) and Env.s("BMX_GHOST") != "0":   # (built levels too)   # the ghost of your best run on this world (game/ghost_rider.gd)
		ghost = preload("res://scripts/game/ghost_rider.gd").new(self)
		add_child(ghost)
		ghost.start_run.call_deferred()
	if Env.s("BMX_TRI_SCAN") != "" and not title_world:   # tests: triangles + LOD levels of every rider / bike mesh
		var RPT := preload("res://scripts/game/render_probe.gd")
		get_tree().create_timer(6.0).timeout.connect(func(): RPT.tri_scan(rig, "bike"); RPT.tri_scan(rider, "rider"))
	if Env.s("BMX_MERGE_SCAN") != "" and not title_world:   # tests: what merging rider / bike meshes could save
		var RP := preload("res://scripts/game/render_probe.gd")
		var snap_r := {}; var snap_b := {}
		get_tree().create_timer(6.0).timeout.connect(func(): RP.merge_scan(rider, "rider", snap_r, false); RP.merge_scan(rig, "bike", snap_b, false))
		get_tree().create_timer(12.0).timeout.connect(func(): RP.merge_scan(rider, "rider", snap_r, true); RP.merge_scan(rig, "bike", snap_b, true))
	if Env.s("BMX_PROF") != "" and not title_world: toggle_profiler.call_deferred(int(Env.s("BMX_PROF")))   # tests: 1 compact, 2 full
	bike_cfg = GameState.bike_config()
	if not title_world:
		CrashLog.game = weakref(self)
		CrashLog.note("ride start: seed %d, bike %s" % [GameState.seed, GameState.bike_id])
	Tune.set_ride(bike_cfg.ride)
	_build_environment()
	if reuse.has("terrain"):   # the title world's own, kept while the garage was open (it is always the same place)
		terrain = reuse.terrain
	elif level == "playground":
		terrain = PlaygroundTerrain.new(GameState.seed)
	elif level.ends_with(".tscn"):   # a level built in the editor (the level builder, res://levels/)
		terrain = LevelTerrain.new(level, GameState.seed)
	elif title_world and TitleTerrain.available() and Env.s("BMX_TITLE_PROC") == "" and Env.s("BMX_TITLE_SEED") == "":
		terrain = TitleTerrain.new(TITLE_SEED)   # the title: a small fixed place loaded from a file, nothing generated
	else:
		terrain = load("res://scripts/world/terrain.gd").new((int(Env.s("BMX_TITLE_SEED")) if Env.s("BMX_TITLE_SEED") != "" else TITLE_SEED) if title_world else GameState.seed)
	add_child(terrain)
	if terrain._tapes and not terrain._tapes.torn.is_connected(_on_tape_torn):
		terrain._tapes.torn.connect(_on_tape_torn)
	terrain.view_scale = float(Settings.get_v("view_distance"))   # before the first chunks are built
	terrain.update_stream(0, 0, INF)
	# the baked road (not on the title backdrop, not the playground: its ground has its own shader)
	if not title_world and level != "playground":
		var rq := int(Env.s("BMX_ROAD")) if Env.s("BMX_ROAD") != "" else int(Settings.get_v("road_detail"))
		if Env.s("BMX_OLD_ROAD") != "": rq = 0
		road = RoadDetail.new(rq)
		if road.ok:
			RenderingServer.global_shader_parameter_set("road_a", road.tex_a)
			RenderingServer.global_shader_parameter_set("road_b", road.tex_b)
			RenderingServer.global_shader_parameter_set("road_c", road.tex_c)
			_road_owner = get_instance_id()
		else:
			road = null
	if reuse.has("far_hills"):
		far_hills = reuse.far_hills
	elif level != "":
		far_hills = null   # a test level: flat to the horizon
	else:
		far_hills = FarHills.new()   # the distant landscape behind the streamed chunks
		if title_world: far_hills.ridge_gain = 1.4   # the title view: real mountains on the horizon
		far_hills.setup(terrain)
	if far_hills: add_child(far_hills)
	if far_hills and terrain is TitleTerrain and not (terrain as TitleTerrain).far.is_empty():
		far_hills.load_baked((terrain as TitleTerrain).far)   # the backdrop as baked, never rebuilt
	reuse = {}
	grass = GrassField.new(terrain)   # the grass carpet round the camera (Settings "grass")
	add_child(grass)
	sheep = null if terrain is TitleTerrain else CrashLog.cs_new("res://scripts/world/SheepHerdCs.cs")   # woolly flocks that graze and run from the bike (C#; none without it; none on the fixed title)
	if sheep != null:
		sheep.name = "Sheep"
		add_child(sheep)
		sheep.setup(terrain)
		if level != "": sheep.enabled = false
	if Env.s("BMX_RENDER_PROBE") != "": add_child(preload("res://scripts/game/render_probe.gd").new(self))
	if terrain is LevelTerrain:
		race = LevelRace.new()
		race.name = "LevelRace"
		add_child(race)
		race.setup(self, terrain.lf, terrain.path)
	if terrain is PlaygroundTerrain:
		level_probe = PlaygroundProbe.new()
		level_probe.name = "PlaygroundProbe"
		add_child(level_probe)
		level_probe.setup(self, terrain.course)
		diag = RideDiag.new()   # the developer view: graphs + the tuning card (only on the test playground)
		diag.name = "RideDiag"
		add_child(diag)
		diag.setup(self)
	tumbleweeds = Tumbleweeds.new()   # dry bushes that roll over the desert before the wind
	add_child(tumbleweeds)
	fx = load("res://scripts/fx/fx.gd").new()
	add_child(fx)
	if fx.has_method("setup"): fx.setup(terrain)
	rig = BikeRig.new()
	add_child(rig)
	rig.load_bike(bike_cfg, bike_cfg.get("build", {}))
	susp = rig.susp
	if susp != null and Env.s("BMX_NOUNCLIP") == "": susp.wheels_follow = true   # the wheels track the ground, the frame floats
	pedal_a0 = rig.pedal_a0
	phys = BikePhysics.new(self)
	phys.T = Tune.v
	rumble = PadRumble.new(self)
	phys.setup(rig.extras, bike_cfg)
	ragdoll = Ragdoll.new(terrain)
	rider = load("res://scripts/rider/rider.gd").new()
	rig.lean_g.add_child(rider)
	var vw: Dictionary = GameState.view   # (watching a saved replay: its rider)
	rider.set_look(vw.look if vw.get("look") is Dictionary and not (vw.look as Dictionary).is_empty() else RiderPanels.load_look())
	var pose: Dictionary = vw.pose.duplicate(true) if vw.get("pose") is Dictionary and not (vw.pose as Dictionary).is_empty() else RiderPanels.load_pose(GameState.bike_id, bike_cfg.pose)
	for kv in Env.s("BMX_POSE").split(",", false):   # tests: "bumpAbsorb=2,kneeOpen=0" (not saved)
		var pr := kv.split("=")
		if pr.size() == 2 and pose.has(pr[0]): pose[pr[0]] = float(pr[1])
	rider.set_style(pose)
	phys.bike_rock = float(rider.style.get("bikeRock", 1.0)) if rider.get("style") is Dictionary else 1.0
	if rig.seat != null: rider.seat = rig.seat
	var grip := rig.grip_mid()
	rider.fit = Vector3((grip.x - 0.4388) * 0.5, ((grip.y - 0.9646) + (rig.crank_n.position.y - 0.297)) * 0.5, 0)
	rider.use_helmet(str(rider.look.get("helmet", "glory")))
	cam = CameraRig.new()
	cam.game = self
	add_child(cam)
	cam.current = true
	cam.far = RIDE_FAR
	cam.set_mode(cam.default_mode())
	hud = load("res://scripts/ui/hud.gd").new()
	hud.game = self
	add_child(hud)
	replay = ReplayMode.new(self)
	add_child(replay)
	grime = Grime.new()
	add_child(grime)
	grime.watch(rig)
	grime.watch(rider, true)
	blood = preload("res://scripts/fx/blood.gd").new(terrain, fx)
	blood.ragdoll = ragdoll
	add_child(blood)
	if Env.s("BMX_NO_CONTACT") == "":   # tests: compare without
		contact = ContactShadow.new()
		add_child(contact)
	dust = RideDust.new()
	add_child(dust)
	dust.recorder = replay   # (the instant replay records the dust)
	if dust.sim != null: dust.sim.recorder = replay
	motes = AmbientMotes.new()
	add_child(motes)
	if dust.sim != null and dust.sim.compositor != null:   # the dust is drawn as a compositor effect
		var comp := Compositor.new()
		comp.compositor_effects = [dust.sim.compositor]
		cam.compositor = comp
	audio = load("res://scripts/game/ride_audio.gd").new()
	audio.game = self
	add_child(audio)
	wasted = preload("res://scripts/fx/wasted.gd").new(self)
	add_child(wasted)
	area_title = preload("res://scripts/fx/area_title.gd").new()
	add_child(area_title)
	Tune.changed.connect(func(): phys.T = Tune.v)
	Settings.changed.connect(_apply_settings)
	_apply_settings()
	respawn(false)
	# shader warm-up behind the opening fade (pipeline cache + ubershaders do the rest)
	grime.warm_frames = 4
	dust.warm_up(Vector3(0, phys.y + 0.5, 0))
	fx.puff(Vector3(0, phys.y + 0.4, 0), Vector3.ZERO, Color.WHITE, 0.3, 0.2, 0.0)
	fx.chunk(Vector3(0, phys.y + 0.4, 0), Vector3.ZERO, Color.WHITE, 0.01, 0.2)
	if blood: blood.warm_draw(cam)   # crash-only blood shaders + splat decals, so the first crash doesn't wait on them
	if wasted and _wasted_on(): wasted.warm()   # and the WASTED silhouette mask's pipelines
	ClipGetUp.warm()   # the get-up / dizzy clips load on a worker thread now, not at the first crash

## lift the terrain + far hills out of this Game before it is freed, for a later Game of the same world
## (`reuse`); they wait out of the tree, not processing (the terrain joins its workers on leaving)
func take_world() -> Dictionary:
	var out := {"terrain": terrain, "far_hills": far_hills}
	remove_child(terrain)
	remove_child(far_hills)
	# this Game is done: it must not drive the lifted terrain (update_stream etc.) while it waits to be freed
	# (its children too: camera, HUD, grass... read game.terrain)
	set_process(false)
	set_physics_process(false)
	process_mode = Node.PROCESS_MODE_DISABLED
	terrain = null
	far_hills = null
	return out

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
	# incremental: a re-filter of the radiance (time of day changed, the day / night cycle ticking) is spread over
	# a few frames instead of all at once (AUTOMATIC re-filtered it in one frame whenever a sky uniform changed)
	sky.process_mode = Sky.PROCESS_MODE_INCREMENTAL
	sky.sky_material = sm
	sky_mat = sm
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	# the shade is lit by the sky alone (no hand-tinted fill colour): its brightness is set by the sky meter (SunSky / SkyMeter)
	env.ambient_light_sky_contribution = 1.0 if not title_world else 0.8
	env.ambient_light_color = Color(0.55, 0.68, 0.9)
	env.ambient_light_energy = 0.42
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	# AgX (filmic): bright warm light rolls off to white gracefully instead of going flat orange / clipping
	# (ACES did that at golden hour); it is a little flatter, so the exposure / grade numbers below are tuned for it
	env.tonemap_mode = Environment.TONE_MAPPER_AGX if Env.s("BMX_ACES") == "" else Environment.TONE_MAPPER_ACES
	env.tonemap_agx_contrast = AGX_CONTRAST if title_world else AGX_CONTRAST_RIDE
	env.tonemap_agx_white = AGX_WHITE
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
	env.sdfgi_energy = 1.0   # the sky's light as measured, bounced (2026-11-26: was 0.8 against a hand-set ambient)
	env.sdfgi_y_scale = Environment.SDFGI_Y_SCALE_75_PERCENT
	env.ssr_max_steps = 48
	env.ssr_fade_in = 0.15
	env.ssr_fade_out = 2.0
	if title_world:
		env.glow_intensity = 0.25
		env.glow_strength = 0.9
		env.glow_bloom = 0.02
		env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
		env.glow_hdr_threshold = 0.92
		env.set_glow_level(0, 0.0); env.set_glow_level(1, 0.6); env.set_glow_level(2, 1.0)
		env.set_glow_level(3, 0.6); env.set_glow_level(4, 0.3)
	else:
		# bloom = the lens's own scatter (veiling glare), energy-conserving: a few % of every pixel spread wide, no threshold
		# (Call of Duty AW / learnopengl "physically based bloom"). Softlight glow worked after the tonemapper: a grade, not light
		env.glow_blend_mode = Environment.GLOW_BLEND_MODE_MIX
		env.glow_mix = GLOW_MIX
		env.glow_intensity = 1.0
		env.glow_strength = 1.0
		env.glow_bloom = 0.0
		env.glow_hdr_threshold = 0.0
		for i in 7: env.set_glow_level(i, [0.0, 0.0, 0.5, 1.0, 1.0, 0.8, 0.5][i])
	# volumetric fog: a light haze the sun shines through (shafts past trees, lit dust clouds); the
	# depth fog above still does the far fade, so this stays thin
	env.volumetric_fog_density = VOL_DENSITY
	env.volumetric_fog_albedo = Color(0.86, 0.9, 0.95)
	env.volumetric_fog_anisotropy = 0.78
	env.volumetric_fog_length = 90.0
	env.volumetric_fog_detail_spread = 1.6
	env.volumetric_fog_ambient_inject = 0.12   # haze lit by the sun (shafts), not a milky veil
	env.volumetric_fog_sky_affect = 0.0
	env.volumetric_fog_temporal_reprojection_enabled = true
	env.volumetric_fog_temporal_reprojection_amount = 0.9
	env.adjustment_enabled = true
	# goggle lens (picked on the ride setup page): its tinted film = a colour LUT over the whole view; Clear = none
	_lens_now = str(GameState.goggle_lens)
	env.adjustment_color_correction = GoggleLens.lut(_lens_now)
	env.adjustment_saturation = 1.22 if title_world else 1.0   # a ride: neutral, AgX does the highlights
	env.adjustment_contrast = 1.12 if title_world else 1.0
	we.environment = env
	cam_attr = CameraAttributesPractical.new()
	cam_attr.dof_blur_amount = 0.06
	# auto exposure: the eye adapts between shade and open sun / the night; kept to a narrow range on top of the
	# time-of-day exposure so the look stays as graded (CameraAttributesPractical keeps the DoF + photo mode as is)
	# a ride takes its exposure from the light (SunSky), not from what the camera sees (bright / dark kit, the sky in view
	# fed back into it): no auto exposure, so no luminance pass either. The title keeps its old metered look.
	cam_attr.auto_exposure_enabled = title_world
	cam_attr.auto_exposure_scale = 0.4
	cam_attr.auto_exposure_speed = 0.7
	cam_attr.auto_exposure_min_sensitivity = 80.0
	cam_attr.auto_exposure_max_sensitivity = 140.0
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
	sun.directional_shadow_fade_start = 0.75   # a long fade: the end of the reach never shows as a line
	sun.directional_shadow_max_distance = SHADOW_MAX
	sun.directional_shadow_pancake_size = 30.0
	sun.shadow_bias = 0.02
	sun.shadow_normal_bias = 1.2
	sun.light_volumetric_fog_energy = 2.6 if title_world else 1.0
	add_child(sun)
	sun.look_at_from_position(SUN_DIR.normalized(), Vector3.ZERO, Vector3.UP)
	# rim light: lights only the rider + bike (RIM_LAYER) from behind them as the camera sees them, so their
	# outline catches a bright edge and never sinks into the background (backlit, at dusk, in a forest)
	rim = DirectionalLight3D.new()
	rim.name = "RimLight"
	rim.light_cull_mask = RIM_LAYER
	rim.shadow_enabled = false
	rim.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY   # not in the sky shader (LIGHT0 must stay the sun / moon)
	rim.light_volumetric_fog_energy = 0.0
	rim.light_specular = 1.2
	rim.light_energy = 0.0
	add_child(rim)
	refl_probe = ReflectionProbe.new()
	refl_probe.size = Vector3(160, 60, 160)
	refl_probe.max_distance = 260.0
	refl_probe.box_projection = false
	refl_probe.interior = false
	refl_probe.ambient_mode = ReflectionProbe.AMBIENT_DISABLED   # reflections only: the ambient stays as graded
	refl_probe.update_mode = ReflectionProbe.UPDATE_ONCE
	refl_probe.intensity = 1.0
	# only the rider + bike take its reflections (paint, chrome, visor; _rim_update tags them with RIM_LAYER). On
	# the land it lit every tree / dirt face within its 80 m box with the captured scene and nothing outside it:
	# gloss popped on as trees came near, and on / off again each time the box jumped 30 m along the trail
	refl_probe.reflection_mask = RIM_LAYER
	refl_probe.cull_mask &= ~RIM_LAYER   # and they don't reflect themselves in it
	# off (2026-11-23): it re-captured every 30 m / 6 s and the bike paint, chrome and visor then reflected a different
	# world in one frame (user: "sometimes glossy, sometimes not"); a moving probe can't be blended in Godot. The sky's
	# own reflections are the same everywhere. BMX_REFL_PROBE=1 brings it back.
	refl_probe.visible = Env.s("BMX_REFL_PROBE") != ""
	add_child(refl_probe)
	# colour grade (split tone) + vignette, drawn over the 3D view
	var cl := CanvasLayer.new(); cl.layer = -1
	grade_rect = ColorRect.new()
	grade_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	grade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_grade_sh = load("res://shaders/grade.gdshader")
	_grade_sh_mip = Shader.new()   # the same pass with a mipmapped screen read: only while the speed blur is on
	_grade_sh_mip.code = _grade_sh.code.replace(GRADE_MIP_FROM, GRADE_MIP_TO)
	var gm := ShaderMaterial.new(); gm.shader = _grade_sh_mip   # (compiled now, while the ride loads: the first switch to it
	gm.shader = _grade_sh                                         # mid-ride, at ~25 km/h, cost 8 ms; later switches ~0.1 ms)
	grade_rect.material = gm
	cl.add_child(grade_rect)
	add_child(lens)
	add_child(cl)

func _lens_aspect() -> float:
	var vs := get_viewport().get_visible_rect().size
	return vs.x / maxf(vs.y, 1.0)

## tests: BMX_LENS_RAIN=0..1 keeps that much water on the lens (rain), BMX_LENS_DUST=0..1 dusts it,
## BMX_LENS_WIND=0..1 holds the air over it (else the speed)
func _lens_test_setup() -> void:
	if Env.s("BMX_LENS_RAIN") != "": lens.rain = float(Env.s("BMX_LENS_RAIN"))
	if Env.s("BMX_LENS_SPLASH") != "": lens.splash(float(Env.s("BMX_LENS_SPLASH")))
	if Env.s("BMX_LENS_WIND") != "": lens.wind_override = float(Env.s("BMX_LENS_WIND"))
	if Env.s("BMX_LENS_DUST") != "": lens.add_dust(float(Env.s("BMX_LENS_DUST")), Color(0.62, 0.55, 0.45))

## grade.gdshader reads the screen without mips (a mipmap sampler makes Godot build the screen's mip chain every
## frame); the speed blur needs them, so while it is on the material runs a copy of the shader with them
const GRADE_MIP_FROM := "hint_screen_texture, filter_linear;"
const GRADE_MIP_TO := "hint_screen_texture, filter_linear_mipmap;"
var _grade_sh: Shader
var _grade_sh_mip: Shader
func _grade_mips(gm: ShaderMaterial, on: bool) -> void:
	var want := _grade_sh_mip if on else _grade_sh
	if gm.shader == want or want == null: return
	var _st := Time.get_ticks_usec()
	_grade_swap(gm, want)
	_perf("fx.grade_swap", _st)

func _grade_swap(gm: ShaderMaterial, want: Shader) -> void:
	var keep := {}
	for u in gm.shader.get_shader_uniform_list():   # carry every value over (photo mode's too)
		keep[u.name] = gm.get_shader_parameter(u.name)
	gm.shader = want
	for k in keep:
		if keep[k] != null: gm.set_shader_parameter(k, keep[k])

## Title screen look: golden hour from a lookout. The camera faces the best view from the spawn, the sun
## sits low ahead and to the right of it, and a coarse copy of the landscape fills the view to the
## horizon. Off = the normal ride light, as built above.
func set_scenic(on: bool) -> void:
	if on == scenic: return
	scenic = on
	if on:
		_to_hilltop()
		var best := _title_heading
		var sy := best - 1.05   # low sun ahead-right of the bike, out of the frame
		var el := deg_to_rad(10.0)
		sun.look_at_from_position(Vector3(cos(sy) * cos(el), sin(el), -sin(sy) * cos(el)), Vector3.ZERO, Vector3.UP)
		sun.light_color = Color(1.0, 0.62, 0.34)
		# a grazing sun: more bias or the ground shades itself in thin stripes (acne); softer edges so
		# the long tree shadows don't read as flat black bands
		sun.shadow_bias = 0.05
		sun.shadow_normal_bias = 2.0
		sun.shadow_blur = 1.2
		sun_energy = 2.3
		_sky_set("golden", 1.0)
		_sky_set("sun_vec", Vector3.ZERO)   # the sky's sun = the light here
		_sky_set("night", 0.0)
		_sky_set("energy", 1.0)
		_sky_set("sunny", 0.0)
		_sky_set("light_energy", 0.85)
		env.fog_light_color = Color(0.93, 0.70, 0.52)
		env.fog_aerial_perspective = 0.0
		env.fog_sun_scatter = 0.35
		env.fog_sky_affect = 0.0
		env.fog_depth_curve = 1.25
		env.fog_density = 0.7
		env.volumetric_fog_albedo = Color(1.0, 0.82, 0.62)
		env.volumetric_fog_density = VOL_DENSITY
		env.tonemap_exposure = 0.95
		env.background_energy_multiplier = 1.0   # the glare guard is off here
		env.adjustment_brightness = float(Settings.get_v("brightness"))
		if cam_attr:
			cam_attr.auto_exposure_min_sensitivity = 80.0   # a night ride left it pinned
			cam_attr.auto_exposure_max_sensitivity = 140.0
		cam.far = 3500.0
		cam.vista_yaw = best
		cam.set_mode("vista")
		_make_title_sign(best)
		# the rider sits on the bike on the hilltop, facing out over the view, not moving
		phys.heading = best
		phys.course = best   # the physics rebuilds the heading from the course, or it swings round slowly
		phys.slip = 0.0
		phys.v = 0.0
		_snap_prev()
		atmos.gain = 0.3   # a slight breeze
		_title_lights(best)
		_hair_key()
		if title_life == null:
			title_life = TitleLife.new()
			add_child(title_life)
	else:
		atmos.gain = 1.0
		if title_sign != null:
			title_sign.queue_free()
			title_sign = null
		if title_life != null:
			title_life.queue_free()
			title_life = null
		tumbleweeds.clear()
		if is_instance_valid(_studio): _studio.queue_free()
		_studio = null
		sun.look_at_from_position(SUN_DIR.normalized(), Vector3.ZERO, Vector3.UP)
		sun.light_color = RIDE_SUN_COL
		sun.shadow_bias = 0.02
		sun.shadow_normal_bias = 1.2
		sun.shadow_blur = 1.0
		sun_energy = RIDE_SUN
		_sky_set("golden", 0.0)
		_sky_set("sunny", 1.0)
		_sky_set("light_energy", 0.55)
		env.fog_light_color = RIDE_FOG
		env.fog_sun_scatter = 0.0
		_ride_fog()
		env.volumetric_fog_albedo = Color(0.86, 0.9, 0.95)
		env.volumetric_fog_density = VOL_DENSITY
		env.tonemap_exposure = 0.8
		cam.far = RIDE_FAR
		light_ver = -1   # the level light (time of day) takes over on the next frame

## the hair's sheen (shaders/hair.gdshader) comes from the light in use (sun / moon), not the studio key
var _hair_nodes: Array = []
func _hair_key() -> void:
	if sun == null: return
	var to_key := sun.global_basis.z   # toward the sun / moon
	var kc := sun.light_color * clampf(sun_energy / maxf(RIDE_SUN, 0.01), 0.1, 1.2)
	for h in _hair_nodes:
		if not is_instance_valid(h): continue
		var m := (h as GeometryInstance3D).material_override as ShaderMaterial
		if m == null: continue
		m.set_shader_parameter("key_world_on", 1.0)
		m.set_shader_parameter("key_world", to_key)
		m.set_shader_parameter("key_col", Vector3(kc.r, kc.g, kc.b))

var _rim_dirty := true
var _rim_hooked := false
var _rim_rider: Node
var _rim_rig: Node
func _rim_node_added(n: Node) -> void:
	if _rim_dirty or not (n is GeometryInstance3D): return
	if (is_instance_valid(rider) and rider.is_ancestor_of(n)) or (is_instance_valid(rig) and rig.is_ancestor_of(n)):
		_rim_dirty = true

## the rim light follows the camera: it shines from behind + above the rider as seen from the lens, a little from the
## side the sun is on (so it agrees with the light in the scene). The rider / bike meshes get RIM_LAYER (re-tagged
## when a mesh joins them: helmets, cams, a new bike or a crash add meshes).
## Rider / bike parts too small for their sun shadow to show (bolts, pedals, fingers, buckles: < SMALL_SHADOW
## across) and the stickers (they lie on the frame, which casts that shadow already) cast none: the rider + bike
## were ~60 % of the shadow pass' draw calls, each tiny part drawn again in every cascade (BMX_RENDER_PROBE).
## Decided once per mesh. BMX_ALL_SHADOWS=1 keeps every one.
const SMALL_SHADOW := 0.1
static var _ALL_SHADOWS := Env.s("BMX_ALL_SHADOWS") != ""
func _shadow_size(gi: GeometryInstance3D) -> void:
	if _ALL_SHADOWS or not (gi is MeshInstance3D) or gi.has_meta("shadow_sized"): return
	var mi := gi as MeshInstance3D
	if mi.mesh == null: return
	gi.set_meta("shadow_sized", true)
	var across := (mi.get_aabb().size * mi.global_basis.get_scale()).length()
	if across < SMALL_SHADOW or String(mi.name).begins_with("decal"):
		gi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func _rim_update(dt: float) -> void:
	if rim == null: return
	# re-tag only when a mesh joined the rider / bike (or they were swapped), not by walking both trees twice a second
	if not _rim_hooked:
		_rim_hooked = true
		get_tree().node_added.connect(_rim_node_added)
	if rider != _rim_rider or rig != _rim_rig:
		_rim_rider = rider
		_rim_rig = rig
		_rim_dirty = true
	_rim_tag_t -= dt
	if _rim_dirty and _rim_tag_t <= 0.0:
		_rim_tag_t = 0.2
		_rim_dirty = false
		_hair_nodes.clear()
		for root in [rider, rig]:
			if root == null or not is_instance_valid(root): continue
			for n in (root as Node).find_children("*", "GeometryInstance3D", true, false):
				var gi := n as GeometryInstance3D
				if gi.layers & RIM_LAYER == 0: gi.layers |= RIM_LAYER
				if gi is Hair: _hair_nodes.append(gi)
				_shadow_size(gi)
		_hair_key()
	var c3 := get_viewport().get_camera_3d()
	if c3 == null or scenic or Env.s("BMX_NO_RIM") != "":
		rim.light_energy = 0.0
		return
	var fwd := -c3.global_basis.z
	var fh := Vector3(fwd.x, 0.0, fwd.z)
	if fh.length() < 0.01: fh = Vector3(1, 0, 0)
	fh = fh.normalized()
	var side := Vector3(-fh.z, 0.0, fh.x)
	# the side the key light is on: the light in use (the moon at night), not the true sun under the horizon.
	# The light node looks from the light toward the scene (-Z), so +Z points at the sun / moon, like _gg_sun did
	var to_key := sun.global_basis.z
	# which side the sun is on, as a smooth -1..1 (it was signf(): with the sun near the view line, every bend of the
	# trail flipped the rim from one side of the rider to the other in one frame, and the glint on the helmet / frame /
	# kit jumped on and off with it)
	var sun_side := clampf(side.dot(Vector3(to_key.x, 0.0, to_key.z)) / 0.5, -1.0, 1.0)
	# the light travels toward the camera (from behind the rider), down a little, leaning in from the sun's side
	var travel := (-fh * 0.55 + Vector3.DOWN * 0.35 - side * sun_side * 0.9 * float(LightSettings.current.get("rim_side", 1.0))).normalized()   # ~60 deg off the view: lights the outline
	# and it turns at most like a slow pan (the trail camera swings round in bends)
	_rim_dir = travel if _rim_dir == Vector3.ZERO else _rim_dir.slerp(travel, minf(1.0, dt * 2.5)).normalized()
	rim.global_basis = Basis.looking_at(_rim_dir, Vector3.UP if absf(_rim_dir.y) < 0.98 else Vector3.FORWARD)
	rim.light_color = _rim_col
	rim.light_energy = _rim_e if Env.s("BMX_RIM_E") == "" else float(Env.s("BMX_RIM_E"))

## morning mist: height fog that lies in the dips at sunrise (and a little at dusk), burning off by mid-morning.
## The mist is a pool with a level fixed in the WORLD (it used to hang off the rider's height, so on a descent the
## whole fog level sank away in front of the bike and never arrived). The level comes from the land: the low ground
## round the place the rider is heading for (13 height samples every 0.3 s), a few metres deep over it.
##  - the level itself never moves in view, except a slow drift (MIST_DRIFT) for small changes
##  - the rider is never IN it: the mist is only there while the rider is above its top (full from MIST_CLEAR_FULL
##    over it, gone by MIST_CLEAR_NONE). Riding down towards a pool it burns off before the wheels reach it, so the
##    ground round the bike is always clear; mist is something you look down on in the dips
##  - a pool that no longer fits (the rider has come down to it, or has climbed well away from it) goes while
##    nothing shows, and the new pool fades in slowly in the low ground ahead
func _mist_update(dt: float) -> void:
	if scenic or phys == null: return
	var h := tod
	var morning := smoothstep(4.8, 6.2, h) * (1.0 - smoothstep(8.6, 10.6, h))
	var evening := smoothstep(19.4, 20.4, h) * (1.0 - smoothstep(21.5, 23.0, h)) * 0.45
	var nightm := (1.0 - smoothstep(0.0, 1.0, minf(absf(h - 3.0) / 2.5, 1.0))) * 0.25   # a little in the small hours
	var k := maxf(maxf(morning, evening), nightm) * float(LightSettings.current.get("haze", 1.0)) * float(LightSettings.current.get("mist", 1.0))
	if Env.s("BMX_MIST") != "": k = float(Env.s("BMX_MIST"))
	if k <= 0.001:
		env.fog_height_density = 0.0
		_mist_y = NAN
		return
	var pos := Vector3(float(phys.x), float(phys.y), float(phys.z))
	var jumped := is_nan(_mist_y) or pos.distance_to(_mist_pos) > 30.0   # a new ride / respawn / test spawn
	_mist_pos = pos
	# where the pool belongs: the low ground round the spot ~4 s ahead
	_mist_scan_t -= dt
	if jumped or _mist_scan_t <= 0.0:
		_mist_scan_t = 0.3
		var f: Vector3 = phys.fwd()
		var lead := clampf(float(phys.v) * 4.0, -80.0, 80.0)
		var cx := pos.x + f.x * lead
		var cz := pos.z + f.z * lead
		var wl := Terrain.WATER if level == "" else -INF   # (a built level has no world sea: mist lies in its own hollows)
		var lo := [maxf(float(terrain.height(pos.x, pos.z)), wl)]
		for i in 12:
			var a := float(i) * TAU / 6.0 + (0.0 if i < 6 else 0.52)
			var r := 70.0 if i < 6 else 150.0
			lo.append(maxf(float(terrain.height(cx + cos(a) * r, cz + sin(a) * r)), wl))   # lakes: mist lies on the water
		lo.sort()
		_mist_want = float(lo[1]) + MIST_DEEP   # the second lowest: one odd hole doesn't set the level
	if jumped:
		_mist_y = _mist_want
		_mist_gy = pos.y
		_mist_f = 0.0
		_mist_thin = 1.0
		_mist_swap = false
		_mist_off_t = 0.0
	_mist_gy += (pos.y - _mist_gy) * (1.0 - exp(-dt / 0.7))   # the rider's height without hops / bumps
	var d := _mist_y - _mist_gy          # how deep the rider's wheels are under the mist top
	var off := _mist_want - _mist_y      # how far the pool is from where it belongs
	# does this pool still fit?
	if not _mist_swap:
		if _mist_thin < 0.03 and off < -3.0:
			_mist_swap = true                # come down to it (burnt off by now): the next pool is further down
			_mist_out = 0.3
		else:
			_mist_off_t = _mist_off_t + dt if off > MIST_LEFT else 0.0
			if _mist_off_t > 3.0:            # climbed away: the low ground round here is well above the old pool
				_mist_swap = true
				_mist_out = 4.0
			elif absf(off) < 3.0:
				_mist_y += clampf(off, -MIST_DRIFT * dt, MIST_DRIFT * dt)
	if _mist_swap:
		_mist_f -= dt / _mist_out
		if _mist_f <= 0.0:
			_mist_f = 0.0
			_mist_y = _mist_want
			_mist_swap = false
			_mist_off_t = 0.0
			_mist_thin = 1.0
	else:
		_mist_f = minf(1.0, _mist_f + dt / MIST_FADE_IN)
	# only while the rider is above it: burns off as the rider comes down to its top
	var dens := MIST_DENSITY * k
	var want_thin := smoothstep(MIST_CLEAR_NONE, MIST_CLEAR_FULL, -d)
	_mist_thin += (want_thin - _mist_thin) * (1.0 - exp(-dt / (0.35 if want_thin < _mist_thin else 4.0)))   # goes at once, comes back slowly
	var ease_f := _mist_f * _mist_f * (3.0 - 2.0 * _mist_f)
	env.fog_height = _mist_y
	env.fog_height_density = dens * ease_f * _mist_thin
	if Env.s("BMX_MIST_PROBE") != "":
		_mist_probe_t -= dt
		if _mist_probe_t <= 0.0:
			_mist_probe_t = 0.5
			print("MIST level=%.1f want=%.1f rider=%.1f deep=%.1f fade=%.2f thin=%.2f dens=%.3f swap=%s" % [_mist_y, _mist_want, _mist_gy, d, _mist_f, _mist_thin, env.fog_height_density, _mist_swap])

## glare guard: riding (or looking) toward a low sun washed the screen out (the sunlit haze, the bloom, the bright
## sky round the sun, dust lit from behind) so the trail couldn't be seen. When the camera faces a low sun this eases
## all of those off, smoothly (like squinting / sunglasses); the light on the land stays the same.
const GG_GLOW := 1.0   # env.glow_intensity (a ride: mix bloom, Light tab › Bloom scales it)
var _gg_vol := 2.6
var _gg_scat := 0.0
var _gg_dust := 1.0
var _gg_sun := Vector3.UP
var _gg_el := 60.0
var _gg_k := 0.0
var _gg_s := 0.0
var _gg_glow := GG_GLOW   # bloom after the Light tab's Bloom slider

## sky material uniforms are only written when they really change: any write dirties the sky and
## re-filters its radiance cubemap (ambient + reflections)
var _sky_cache := {}
func _sky_set(key: String, v: Variant) -> void:
	if _sky_cache.has(key):
		var o: Variant = _sky_cache[key]
		if typeof(o) == typeof(v):
			if v is float:
				if absf(float(o) - float(v)) < 1e-4: return
			elif v is Vector3:
				if (o as Vector3).is_equal_approx(v): return
			elif o == v:
				return
	_sky_cache[key] = v
	sky_mat.set_shader_parameter(key, v)

## the HDRI textures, loaded once each
var _hdri_tex := {}
func _hdri(file: String) -> Texture2D:
	if not _hdri_tex.has(file): _hdri_tex[file] = load(HDRI_DIR + file)
	return _hdri_tex[file]

func _glare_guard(dt: float) -> void:
	if scenic or photo: return
	var c3 := get_viewport().get_camera_3d()
	if c3 == null: return
	var fwd := -c3.global_basis.z
	var face := fwd.normalized().dot(_gg_sun)                       # 1 = looking straight at the sun
	var lowsun := 1.0 - smoothstep(20.0, 40.0, _gg_el)              # a high sun is out of view anyway
	var up := smoothstep(-6.0, 0.0, _gg_el)                         # only while it's up (dusk afterglow is soft)
	var target := smoothstep(0.35, 0.92, face) * lowsun * up
	_gg_s += (target - _gg_s) * (1.0 - exp(-dt * 3.0))
	if absf(_gg_s - _gg_k) < 0.004: return
	_gg_k = _gg_s
	var k := _gg_s * float(LightSettings.current.get("glare", 1.0))
	if Env.s("BMX_GLARE_OFF") != "": k = 0.0
	sun.light_volumetric_fog_energy = _gg_vol * (1.0 - 0.8 * k)
	env.fog_sun_scatter = _gg_scat * (1.0 - k)
	env.glow_intensity = _gg_glow * (1.0 - 0.65 * k)
	# the sky's own brightness in view: through the environment, not the sky material (a material change
	# re-filtered the whole radiance cubemap every frame the guard moved)
	env.background_energy_multiplier = 1.0 - 0.38 * k
	if dust and dust.sim != null: dust.sim.sun_gain = _gg_dust * (1.0 - 0.6 * k)
	if Env.s("BMX_GLARE_PROBE") != "" and Engine.get_process_frames() % 30 == 0:
		print("GLARE face=%.2f el=%.1f k=%.2f" % [face, _gg_el, k])

## level light: time of day -> sun (or moon at night), sky mode, ambient, fog, haze, exposure.
## Applied when the Light sliders change; with the cycle on, the clock runs and it re-applies 10x / s.
func _update_light(dt: float) -> void:
	if scenic: return
	if str(GameState.goggle_lens) != _lens_now:   # picked after this ride was pre-built (intro) / changed in a menu
		_lens_now = str(GameState.goggle_lens)
		env.adjustment_color_correction = GoggleLens.lut(_lens_now)
	if rig: rig.set_lights_on(night_k > 0.35 or Env.s("BMX_BIKELIGHT_ON") != "")   # a new bike (B) gets its lamp on too
	LightSettings.ensure_loaded()
	var L: Dictionary = LightSettings.current
	if level != "" and Env.s("BMX_LIGHT_PRESET") == "" and Env.s("BMX_LIGHT") == "":
		# a test level: clear midday light (readable shots, no golden haze) until the player changes the light in it
		if _level_light_ver < 0: _level_light_ver = LightSettings.version
		if LightSettings.version == _level_light_ver:
			if terrain is LevelTerrain:   # a built level: its own time of day + sun (its light is baked for them)
				L = LightSettings.current.duplicate()
				L.time = terrain.hour; L.sun_turn = terrain.sun_turn; L.cycle = 0.0
			else:
				L = LightSettings.preset("Noon")
				L.haze = 0.3; L.mist = 0.0; L.cycle = 0.0
	var changed := light_ver != LightSettings.version or _lab_ver != LightLab.version
	if _lab_ver != LightLab.version:   # a Lab knob moved (dev): the lens grade may have changed too
		_lab_ver = LightLab.version
		env.adjustment_color_correction = GoggleLens.lut(_lens_now)
	if changed:
		light_ver = LightSettings.version
		# the clock only jumps when the time (or the cycle switch) itself changed: any other Light slider used to
		# reset a running day / night cycle back to the slider's time
		var lt := float(L.time)
		var lc := float(L.cycle) > 0.5
		if lt != _light_time or lc != _light_cycle or not lc:
			tod = lt
		_light_time = lt
		_light_cycle = lc
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


## the HDRI for this sun height: night -> low sun (two photos) -> the day photo of this world (by seed),
## crossfaded between neighbours so a day / night cycle never pops
func _pick_sky_hdri(el_deg: float, az: float) -> void:
	var day: Array = HDRI_DAY[posmod(GameState.seed, HDRI_DAY.size())]
	var low: Array = HDRI_LOW[posmod(GameState.seed, HDRI_LOW.size())]
	var a: Array
	var b: Array
	var t := 0.0
	if el_deg < -6.0:
		a = HDRI_NIGHT; b = HDRI_NIGHT
	elif el_deg < 1.0:
		a = HDRI_NIGHT; b = low; t = smoothstep(-6.0, 1.0, el_deg)
	elif el_deg < 14.0:
		a = low; b = day; t = smoothstep(4.0, 14.0, el_deg)
	else:
		a = day; b = day
	_sky_set("hdri", _hdri(String(a[0])))
	_sky_set("rotation", az - (float(a[1]) - 0.5) * TAU)
	if b == a or t <= 0.0:
		_sky_set("mix_b", 0.0)
		return
	_sky_set("hdri_b", _hdri(String(b[0])))
	_sky_set("rotation_b", az - (float(b[1]) - 0.5) * TAU)
	_sky_set("mix_b", t)


func _apply_light(h: float, L: Dictionary) -> void:
	var el_deg := sun_elev_deg(h)
	var x := fposmod(h - 6.0, 24.0)
	# the sun swings ~200 deg across the day; 16:00 = the old afternoon sun (SUN_AZ)
	var yaw := deg_to_rad(rad_to_deg(atan2(SUN_AZ.y, SUN_AZ.x)) + float(L.sun_turn) + (x - 10.0) * (100.0 / 7.0))
	# the sky's look (which photo / procedural sky): golden low, twilight, night
	var g := 1.0 - smoothstep(8.0, 30.0, el_deg)        # how low the sun is (shadow softness / bias, fog thinning)
	var n := 1.0 - smoothstep(-11.0, -3.5, el_deg)      # how much night (after the afterglow has faded)
	var day := 1.0 - n
	# the painted sunset sky only round sunset itself: above ~10 deg a real sky is still blue overhead (the low-sun photos
	# show it); painted from 9 deg up it tinted all the shade pink and the scene went milky
	var gw := clampf((1.0 - smoothstep(0.0, LightLab.v("golden_below"), el_deg)) * day, 0.0, 1.0)
	var tw := smoothstep(1.0, -4.0, el_deg) * day        # twilight: the sun just under the horizon, the sky still glowing
	# the light itself: physics (scripts/world/sun_sky.gd). Only what a real clear day gives, the sun dimmer + redder low down
	var S := SunSky.state(el_deg, L)
	_sun_state = S
	var dirv: Vector3
	if S.sun_on:
		var e := deg_to_rad(maxf(el_deg, 1.0))   # never light from below the ground
		dirv = Vector3(cos(yaw) * cos(e), sin(e), sin(yaw) * cos(e))
		sun.light_color = S.sun_color
		sun_energy = S.sun_energy
	else:
		var e := deg_to_rad(SunSky.MOON_EL)   # the moon, opposite the sun (low enough to show in the sky ahead)
		dirv = Vector3(cos(yaw + PI) * cos(e), sin(e), sin(yaw + PI) * cos(e))
		sun.light_color = MOON_COL
		sun_energy = S.moon_energy
	sun.look_at_from_position(dirv, Vector3.ZERO, Vector3.UP)
	if Env.s("BMX_MOON_PROBE") != "": print("MOON dir=%s az=%.2f" % [dirv, atan2(dirv.z, dirv.x)])
	# grazing light needs more bias (acne) and softer edges on the long shadows
	sun.shadow_bias = lerpf(0.02, 0.05, g)
	sun.shadow_normal_bias = lerpf(1.2, 2.0, g)
	sun.shadow_blur = lerpf(lerpf(0.8, 1.2, g), 2.6, n) * float(L.shadow_soft)
	# the haze scatters the light it is lit by: 1 = what the light really is (it was 2.6-3x: a white veil into a low sun)
	sun.light_volumetric_fog_energy = LightLab.v("sun_haze")
	_gg_vol = sun.light_volumetric_fog_energy
	# sky: blue + white clouds by day, golden low, stars at night; its photographed sun follows ours
	_pick_sky_hdri(el_deg, atan2(dirv.x, -dirv.z))
	_sky_set("golden", gw)
	var se := deg_to_rad(el_deg)   # the true sun for the sky (also under the horizon: dusk / dawn glow)
	_sky_set("sun_vec", Vector3(cos(yaw) * cos(se), sin(se), sin(yaw) * cos(se)))
	_sky_set("sunny", day * (1.0 - gw))
	_sky_set("night", n)
	_gg_sun = Vector3(cos(yaw) * cos(deg_to_rad(el_deg)), sin(deg_to_rad(el_deg)), sin(yaw) * cos(deg_to_rad(el_deg)))
	_gg_el = el_deg
	# the sky's brightness = what the sky meter says it must be to give SunSky's sky light (the same for the view, the
	# ambient, the reflections and the fog: one sky)
	_sky_level()
	_sky_meter_ask()
	# ambient = the sky alone (sky contribution 1, set up in _build_environment: ambient_light_energy no longer counts)
	# fog / haze: distance fog takes its colour from the sky itself (aerial perspective); a thin aerosol haze in the air
	_ride_fog()
	env.fog_density *= float(L.haze) * lerpf(1.0, 1.35, n) * lerpf(1.0, 0.6, gw)   # golden: clear air, not milk
	env.fog_light_color = RIDE_FOG.lerp(Color(0.95, 0.64, 0.46), g * day).lerp(Color(0.4, 0.3, 0.46), tw).lerp(Color(0.012, 0.016, 0.03), n)
	env.fog_sun_scatter = LightLab.v("sun_scatter") * day   # (scales with the sun's energy: 0.06 lit a white veil round a low sun)
	_gg_scat = env.fog_sun_scatter
	_gg_k = -1.0   # re-apply the guard on top of the new values
	env.volumetric_fog_anisotropy = 0.7   # aerosol (Mie) forward scattering
	env.volumetric_fog_albedo = Color(0.9, 0.9, 0.9)   # grey: its colour comes from the light it scatters
	# less aerosol low in the sky's light (a low sun lit a thick haze into a white veil); the night's own thin mist
	env.volumetric_fog_density = VOL_DENSITY * LightLab.v("vol_density") * float(L.haze) * lerpf(1.0, 0.4, gw) * lerpf(1.0, 1.5, n)
	env.volumetric_fog_ambient_inject = LightLab.v("vol_ambient")
	env.fog_aerial_perspective = LightLab.v("fog_aerial")
	env.tonemap_agx_contrast = LightLab.v("agx_contrast")
	env.tonemap_agx_white = LightLab.v("agx_white")
	env.glow_mix = LightLab.v("bloom_mix")   # the haze is lit by the sky too (0 left it black between the rays)
	# one exposure all day (the day's adaptation is in the light: SunSky); the Light tab's Exposure on top
	env.tonemap_exposure = LightLab.v("expo") * float(L.exposure)
	# night vision: colour fades (rods)
	env.adjustment_saturation = float(L.saturation) * lerpf(1.0, LightLab.v("night_sat"), n)
	env.adjustment_contrast = float(L.contrast)
	env.adjustment_brightness = float(Settings.get_v("brightness"))   # Settings › Brightness on top
	if cam_attr and cam_attr.auto_exposure_enabled:   # (a title Game turned into a ride: pinned = as if off)
		cam_attr.auto_exposure_min_sensitivity = AE_NEUTRAL_ISO
		cam_attr.auto_exposure_max_sensitivity = AE_NEUTRAL_ISO
		cam_attr.auto_exposure_scale = 0.4
	night_k = n
	golden_k = gw
	# rim (off by default: a fake light): warm low sun, cold moonlight
	_rim_col = Color(1.0, 0.97, 0.92).lerp(Color(1.0, 0.7, 0.45), gw).lerp(Color(0.85, 0.6, 0.75), tw).lerp(Color(0.6, 0.72, 1.0), n)
	_rim_e = lerpf(lerpf(0.5, 1.3, gw), 1.0, tw * (1.0 - n))
	_rim_e = lerpf(_rim_e, 0.8, n) * float(L.get("rim", 0.0))   # Light tab › Rim light
	if rim != null: rim.light_specular = 1.2 * float(L.get("rim_spec", 1.0))
	# light match (off by default since the low sun is physical: it no longer burns the kit out)
	_match = 0.0
	if el_deg > -3.0:
		_match = clampf((1.0 - smoothstep(8.0, 35.0, el_deg)) * smoothstep(-3.0, 5.0, el_deg) * float(L.get("rider_match", 0.0)), 0.0, 1.0)
	_gg_glow = float(L.get("bloom", 1.0))
	env.glow_intensity = _gg_glow
	if dust and dust.sim != null:   # the dust's sky light: dim and cold at night (it glowed white in the dark)
		dust.sim.sun_gain = lerpf(1.0, 0.5, g * day)
		_gg_dust = dust.sim.sun_gain
		dust.sim.amb_col = Color(0.5, 0.6, 0.78).lerp(Color(0.62, 0.5, 0.52), gw).lerp(Color(0.025, 0.032, 0.05), n)
	# water: reflect this sky and glint where this sun is
	if terrain and terrain.has_method("water_light"):
		var hz := Color(0.784, 0.933, 0.969).lerp(Color(1.0, 0.78, 0.6), gw).lerp(Color(0.07, 0.09, 0.15), n)
		var zn := Color(0.424, 0.765, 0.925).lerp(Color(0.62, 0.62, 0.72), gw).lerp(Color(0.02, 0.03, 0.07), n)
		terrain.water_light(dirv, sun.light_color * clampf(sun_energy / 2.0, 0.0, 1.5), hz, zn)
	light_note = "ev=%.1f adapt=%.2f sun_lux=%.0f sky_lux=%.0f sun_e=%.3f sky_irr=%.3f f=%.3f le=%.3f" % [S.ev, S.stops, S.lux_sun, S.lux_sky, sun_energy, S.sky_irr, _sky_f, _sky_le]
	_hair_key()


## ---- the sky's brightness, measured (world/sky_meter.gd): f = what one unit of the sky shader's light_energy gives a white
## card in the shade; light_energy = SunSky's sky light / f. The meter re-measures after every light change (the sky's
## photo / procedural mode / clouds change f), so any HDRI or sky look gives the real sun : sky ratio.
const SKY_F0 := 1.0             # f before the first reading (no RenderingDevice: stays this)
var _sun_state := {}
var _sky_f := SKY_F0
var _sky_le := 0.3
var _sky_meter: SkyMeter
var _sky_meter_due := false
var _sky_meter_t := 0.0

func _sky_level() -> void:
	if _sun_state.is_empty(): return
	_sky_le = clampf(float(_sun_state.sky_irr) / maxf(_sky_f, 1e-4), 0.002, 20.0)
	_sky_set("light_energy", _sky_le)
	_sky_set("energy", _sky_le)

func _sky_meter_ask() -> void:
	if scenic or RenderingServer.get_rendering_device() == null: return
	if _sky_meter == null:
		_sky_meter = SkyMeter.new(sky_mat)
		add_child(_sky_meter)
	_sky_meter_due = true

## each frame (from _process): a due measurement waits for the last one and 0.15 s, then runs
func _sky_meter_step(dt: float) -> void:
	_sky_meter_t -= dt
	if not _sky_meter_due or _sky_meter == null or _sky_meter.busy() or _sky_meter_t > 0.0: return
	_sky_meter_due = false
	# a slider / time change: answered at once; the day / night cycle drifts slowly, so it is measured every 2 s (each read
	# renders a 2 x 1 view a few frames and reads 2 pixels back)
	_sky_meter_t = 2.0 if float(LightSettings.current.get("cycle", 0.0)) > 0.5 else 0.15
	var le := _sky_le
	_sky_meter.measure(sun.global_basis.z, func(sky_c: Color) -> void: _sky_meter_got(sky_c, le))

func _sky_meter_got(sky_c: Color, le: float) -> void:
	var a := 0.2126 * sky_c.r + 0.7152 * sky_c.g + 0.0722 * sky_c.b
	if le <= 1e-5 or a <= 0.0 or is_nan(a): return
	var f := a / le
	if f < 1e-3 or f > 1e3: return   # a broken read: keep the last
	if Env.s("BMX_LIGHT_PROBE") != "":
		print("SKYMETER le=%.3f card=%.4f f=%.3f (was %.3f) want=%.4f rgb=%s" % [le, a, f, _sky_f, float(_sun_state.get("sky_irr", 0.0)), sky_c])
	if absf(f - _sky_f) > 0.02 * _sky_f:
		_sky_f = f
		_sky_level()
		_sky_meter_due = true   # check again once the sky has the new level (converges in 1-2 reads)


var _studio: Node3D
var _look_yaw := 0.0
var _look_pitch := 0.0
const LOOK_DEPTH := 0.75       # how far from the camera to the head the looked-at point sits
const LOOK_YAW_MAX := 1.9      # ~110 deg: neck + shoulders turned back
const LOOK_PITCH_BIAS := 0.15  # the pose already tips the head down a little

## title screen: the rider's head looks straight at the mouse, all the time, wherever it is on the screen
## (on a pad: at the focused button).
func _update_look(dt: float) -> void:
	var yaw_t := 0.0
	var pitch_t := 0.0
	if scenic and cam and rider and rider.head:
		var vp := get_viewport()
		var m: Vector2 = vp.get_mouse_position()
		# on a pad: look at the menu button that has the cursor (focus) instead of the mouse
		if Settings.pad_active:
			var f: Control = vp.gui_get_focus_owner()
			if f and f.is_visible_in_tree():
				m = f.get_global_transform_with_canvas() * (f.size * 0.5)
		if Env.s("BMX_TITLE_MOUSE") != "":   # tests: a fixed mouse position (fractions of the screen)
			var q := Env.s("BMX_TITLE_MOUSE").split_floats(",")
			m = Vector2(q[0], q[1]) * vp.get_visible_rect().size
		# a real point under the mouse, between the camera and the head (= "at the screen"): the mouse over the
		# helmet = looking into the camera, ahead of him = looking forward, behind him = turning back over the
		# shoulder. Worked out in the head's parent space, where +x = forward, +y = up.
		var c3: Camera3D = vp.get_camera_3d()
		if c3:
			var hw: Vector3 = rider.head.global_position
			var o: Vector3 = c3.project_ray_origin(m)
			var tgt: Vector3 = o + c3.project_ray_normal(m) * (o.distance_to(hw) * LOOK_DEPTH)
			var par: Node3D = rider.head.get_parent_node_3d()
			var d: Vector3 = par.global_transform.affine_inverse() * tgt - rider.head.position
			yaw_t = clampf(atan2(-d.z, d.x), -LOOK_YAW_MAX, LOOK_YAW_MAX)
			pitch_t = clampf(atan2(d.y, Vector2(d.x, d.z).length()) + LOOK_PITCH_BIAS, -0.6, 0.7)
			# past straight behind the yaw wraps: keep turning the way he already is instead of snapping round
			if absf(yaw_t - _look_yaw) > PI: yaw_t = signf(_look_yaw) * LOOK_YAW_MAX
	var k := 1.0 - exp(-dt * 9.0)
	if not scenic:   # riding: the calm look-round with a foot down (slow, unhurried head turns)
		_idle_look(dt)
		yaw_t = _idle_tgt.x * dab_k
		pitch_t = _idle_tgt.y * dab_k
		k = 1.0 - exp(-dt * 3.2)
	_look_yaw += (yaw_t - _look_yaw) * k
	_look_pitch += (pitch_t - _look_pitch) * k
	if scenic and Env.s("BMX_LOOK_PROBE") != "" and Engine.get_process_frames() % 30 == 0:
		var fo: Control = get_viewport().gui_get_focus_owner()
		print("LOOK yaw=%.2f pitch=%.2f focus=%s" % [_look_yaw, _look_pitch, (fo.get_class() + " '" + str(fo.get("text")) + "'") if fo else "-"])


## title screen: photo-shoot lighting round the bike - a warm key spot from the camera side to bring out the
## frame (welds, tube shapes, paint), a rim light from behind to cut it out of the backdrop, a soft fill
func _title_lights(heading: float) -> void:
	if is_instance_valid(_studio): _studio.queue_free()
	_studio = Node3D.new()
	add_child(_studio)
	var d := Vector3(cos(heading), 0.0, -sin(heading))        # the way the bike points
	var f := Vector3(-d.z, 0.0, d.x)                          # the camera looks along this (side-on)
	var c := Vector3(phys.x, phys.y + 0.7, phys.z)            # the middle of bike + rider
	# a magazine shoot: a big soft key (softbox, soft-edged shadows, gentle on skin and the glossy
	# helmet), a low cool fill (about 3:1, the shadow side keeps its shape), and a warm hard rim from
	# behind like the low sun, which outlines the rider + bike against the bright sky. The sun is
	# already strong, so the studio lights only shape: nothing on the rider may clip to white.
	var key := SpotLight3D.new()
	key.light_color = Color(1.0, 0.96, 0.92)
	key.light_energy = 2.8
	key.light_size = 1.2                 # a softbox: wide soft shadow edges, soft highlights
	key.light_specular = 0.35            # no hot white spot on the helmet / skin
	key.spot_range = 30.0
	key.spot_angle = 30.0
	key.spot_angle_attenuation = 1.8     # a broad even pool, no hard spotlight circle on the ground
	key.shadow_enabled = true
	key.shadow_bias = 0.05
	key.shadow_blur = 2.0
	_studio.add_child(key)
	key.look_at_from_position(c - f * 5.5 + d * 6.0 + Vector3(0, 3.4, 0), c, Vector3.UP)
	var rim := SpotLight3D.new()
	rim.light_color = Color(1.0, 0.68, 0.42)
	rim.light_energy = 9.0
	rim.light_size = 0.15
	rim.light_specular = 1.2             # a bright edge glint on the helmet, frame tubes, tyres
	rim.spot_range = 30.0
	rim.spot_angle = 18.0
	rim.spot_angle_attenuation = 1.2
	rim.shadow_enabled = false
	_studio.add_child(rim)
	rim.look_at_from_position(c + f * 4.0 - d * 5.5 + Vector3(0, 2.6, 0), c, Vector3.UP)
	var fill := OmniLight3D.new()
	fill.light_color = Color(0.72, 0.8, 1.0)
	fill.light_energy = 0.35
	fill.light_specular = 0.0
	fill.omni_range = 12.0
	fill.shadow_enabled = false
	_studio.add_child(fill)
	fill.global_position = c - f * 5.0 - d * 2.5 + Vector3(0, 0.4, 0)

## how far rocks / logs rise above the bare ground under and round (x, z), over the bike's footprint
func _rock_rise(x: float, z: float) -> float:
	var worst: float = terrain.top_height(x, z) - terrain.deck_height(x, z)
	for i in 8:
		var a := i * TAU / 8.0
		var px := x + cos(a) * 1.7
		var pz := z + sin(a) * 1.7
		worst = maxf(worst, terrain.top_height(px, pz) - terrain.deck_height(px, pz))
	return worst

## every rock drawn near (x, z): [x, z, radius] from the rock MultiMeshes of the loaded chunks (the visible meshes,
## which can stick out past the ground's dome that height() knows about)
func _rocks_near(x: float, z: float, reach: float) -> Array:
	var out: Array = []
	if not TerrainGeo.MESH.has("rock"):
		return out
	var rock: Mesh = TerrainGeo.MESH["rock"]
	var rr := maxf(rock.get_aabb().size.x, rock.get_aabb().size.z) * 0.5
	var cacti: Array = []   # cacti too: one standing right behind the bike spoils the picture
	for c in 5:
		if TerrainGeo.MESH.has("cactus%d" % c):
			cacti.append(TerrainGeo.MESH["cactus%d" % c])
	for k in terrain.chunks:
		var n = terrain.chunks[k].get("node")
		if not is_instance_valid(n):
			continue
		for mi in (n as Node).get_children():
			if not (mi is MultiMeshInstance3D):
				continue
			var mm: MultiMesh = (mi as MultiMeshInstance3D).multimesh
			if mm == null:
				continue
			var is_cactus := mm.mesh in cacti
			if mm.mesh != rock and not is_cactus and not mi.has_meta("rock"):
				continue
			for i in mm.instance_count:
				var xf: Transform3D = mm.get_instance_transform(i)
				var s := xf.basis.get_scale()
				var r := 1.5 if is_cactus else rr * maxf(s.x, s.z)
				if Vector2(xf.origin.x - x, xf.origin.z - z).length() < reach + r:
					out.append([xf.origin.x, xf.origin.z, r])
	return out

## the spot nearest to (x, z) with no rock under or beside the bike (a spiral out to ~22 m; the spot itself if bare)
func _clear_spot(x: float, z: float, head: float) -> Vector2:
	var rocks := _rocks_near(x, z, 30.0)
	var V: Dictionary = CameraRig.VISTA   # where the title camera will stand: the view of the bike must be clear too
	var cyaw := head + float(V.yaw_off)
	var cdir := Vector2(cos(cyaw), -sin(cyaw))
	var cright := Vector2(-cdir.y, cdir.x)
	var free := func(px: float, pz: float) -> bool:
		if _rock_rise(px, pz) >= 0.04:
			return false
		var cam2 := Vector2(px, pz) - cdir * float(V.back) + cright * float(V.side)
		for r in rocks:
			var rp := Vector2(r[0], r[1])
			if rp.distance_to(Vector2(px, pz)) < r[2] + 2.6:   # the bike is ~2 m long: keep it well clear
				return false
			for k in 7:   # nothing in the line from the camera to the bike (a low lens sees every rock)
				if rp.distance_to(cam2.lerp(Vector2(px, pz), k / 6.0)) < r[2] + 1.2:
					return false
		return true
	if free.call(x, z):
		return Vector2(x, z)
	for ring in range(1, 30):
		var rad := ring * 0.75
		var n := maxi(8, ring * 6)
		for i in n:
			var a := i * TAU / n
			var px := x + cos(a) * rad
			var pz := z + sin(a) * rad
			if free.call(px, pz):
				return Vector2(px, pz)
	return Vector2(x, z)

## title screen: stand the bike on the hand-picked summit of the title world
func _to_hilltop() -> void:
	_end_crash()   # the main menu straight from a crash
	if blood: blood.clear()
	var sp := TITLE_SPOT
	if Env.s("BMX_TITLE_SPOT") != "":   # tests / picking a new spot: x,z,heading
		var q := Env.s("BMX_TITLE_SPOT").split_floats(",")
		sp = Vector3(q[0], q[1], q[2])
	terrain.update_stream(sp.x, sp.y, INF)   # (a ride's own world, far from here: every chunk built now. main parks the title world to avoid it)
	var clear := _clear_spot(sp.x, sp.y, sp.z + TITLE_TURN)   # never on a rock: the nearest bare ground to the picked spot
	sp = Vector3(clear.x, clear.y, sp.z)
	phys.reset_at(sp.x, sp.y, 0.0)
	_snap_prev()
	cam.snap_to(Vector3(sp.x, phys.y + 0.5, sp.y))
	_title_heading = sp.z + TITLE_TURN   # the bike turned so the camera looks out over the long drop, away from the sun

## title screen: the game's name as a Hollywood-style sign close behind the rider, in the camera's view. The hill falls away
## in front of the summit, so the letters stand on a gantry (beam + posts down to the hillside) at about the rider's height
## Placed by eye on the fixed title land (2026-11-26): the letters clear above the helmet, the beam behind it, the word
## between the menu card and the top-right buttons; close enough (80 m) that the haze doesn't wash it out
const SIGN_D := 80.0        # metres from the rider along the camera's view axis
const SIGN_SIDE := 0.06     # sideways as a share of the distance (+ = right on screen)
const SIGN_H := 0.058       # letter height as a share of the distance (the lookout lens is narrow: the whole word fits)
const SIGN_UP := 8.2        # the letters' feet above the camera's eye
func _make_title_sign(best: float) -> void:
	if title_sign != null: title_sign.queue_free()
	if Env.s("BMX_NO_SIGN") != "": return
	var d := SIGN_D; var side_k := SIGN_SIDE; var h_k := SIGN_H; var up := SIGN_UP
	if Env.s("BMX_SIGN") != "":   # tests: distance, side share, height share, feet above the eye
		var q := Env.s("BMX_SIGN").split_floats(",")
		d = q[0]; side_k = q[1]; h_k = q[2]; up = q[3]
	var yaw := best + float(CameraRig.VISTA.get("yaw_off", 0.0))
	var dir := Vector3(cos(yaw), 0.0, -sin(yaw))
	var right := Vector3(-dir.z, 0.0, dir.x)
	var t: Terrain = terrain
	var c := Vector2(phys.x, phys.z) + Vector2(dir.x, dir.z) * d + Vector2(right.x, right.z) * side_k * d
	var ground := func(x: float, z: float) -> float: return t.height(x, z)
	title_sign = TitleSign.new()
	add_child(title_sign)
	title_sign.build(ground, c, -dir, h_k * d, phys.y + 1.2 + up)
	if Env.s("BMX_SIGN_PROBE") != "":   # tests: the land between the camera and the sign (it was buried in a hill once)
		var eye := Vector2(phys.x, phys.z) - Vector2(dir.x, dir.z) * 10.5
		var s := ""
		for i in 13:
			var q := eye.lerp(c, i / 12.0)
			s += " %.0fm:%.1f" % [eye.distance_to(q), t.height(q.x, q.y)]
		print("SIGNPROBE rider_y=%.1f eye~%.1f feet=%.1f top=%.1f | ground along the view:%s" % [phys.y, phys.y + 1.0, phys.y + 1.2 + up, phys.y + 1.2 + up + h_k * d, s])

func _apply_settings() -> void:
	terrain.set_view_scale(float(Settings.get_v("view_distance")))
	if ghost: ghost.enabled = bool(Settings.get_v("ghost"))
	if grass:
		grass.set_quality(int(Env.s("BMX_GRASS")) if Env.s("BMX_GRASS") != "" else int(Settings.get_v("grass")))
	var sq: int = Settings.get_v("shadows")
	# shadows: Low = 2 cascades, hard-ish; Ultra = 4 blended cascades + contact-hardening soft shadows
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS if (sq == 0 or _two_splits()) else DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	# 2 splits: the first one covers ~a fifth of the reach (0.06 left the second cascade stretched over the rest)
	_shadow_zoom = -1.0   # _shadow_fit places the splits
	sun.directional_shadow_blend_splits = true
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
	refl_probe.visible = gi >= 1 and Env.s("BMX_REFL_PROBE") != ""   # off: see where it is made (it popped)
	_probe_pos = Vector3(1e9, 0, 0)
	env.adjustment_brightness = float(Settings.get_v("brightness"))
	env.glow_enabled = Settings.get_v("bloom")
	(grade_rect.material as ShaderMaterial).set_shader_parameter("grade_amt", 1.0 if Settings.get_v("grade") else 0.0)
	grade_rect.visible = Settings.get_v("grade") or Settings.get_v("speed_fx") or Settings.get_v("lens_fx")
	cam_attr.dof_blur_far_enabled = Settings.get_v("tilt_shift")
	cam_attr.dof_blur_near_enabled = Settings.get_v("tilt_shift")
	if hud: hud.apply_settings()

# ---------------------------------------------------------------- host API used by BikePhysics
func flash(text: String) -> void:
	msg_t = 1.4
	if Env.s("BMX_MAN_PROBE") != "": print("FLASH ", text, " v=%.1f" % phys.v)   # tests
	var _ft := Time.get_ticks_usec()
	if hud: hud.flash(text)
	_perf("msg.flash", _ft)

var _tape_front := {}   # what holds a caught tape: the drawn front axle, heading, steering axis, wheel radius (TapeSim.push_at)

## a caught race tape tore (TapeSim.torn): the pop comes now, not when the tyre first touched it
func _on_tape_torn(speed: float) -> void:
	if speed > 3.0 and not phys.crash_on: flash("SNAP!")

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
		# the road's own colour, a little DARKER: the sim lights the cloud with the full sun + sky (no ground AO, no
		# worn-line darkening, the trail's baked colour is darker than the plain biome colour read here), and the
		# old +16 % towards white on top made the cloud read paler than the track it comes from
		return c * 0.82
	return c.lerp(Color.WHITE, 0.42 if s == 0 else 0.28)

## the point is on a rope bridge's deck (planks: no dust, dirt or tracks)
func _on_rope_deck(x: float, z: float, y: float) -> bool:
	return terrain != null and not terrain.ropes.is_empty() and terrain.rope_under(x, z, y) != null

func burst(pos: Vector3, n: int, s: int, power: float, with_dust := true) -> void:
	if s == 2 or _on_rope_deck(pos.x, pos.z, pos.y): return
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
	if c.get("tape", false): return true   # tape stretches first (TapeSim.grab): no bits fly off
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
	if level_probe: level_probe.on_crash(reason)
	if diag: diag.on_crash(reason)
	if rope_probe: print("ROPE CRASH ", reason, " at ", Vector3(phys.x, phys.y, phys.z))
	_rd_air.resize(0)   # crash dust: per-part "was in the air" flags start fresh
	# a fast crash on dirt / sand throws a couple of splats of it at the lens
	if not phys.air and absf(phys.v) > 7.0 and (phys.surf == 1 or phys.surf == 3):
		lens.add_dust(clampf((absf(phys.v) - 7.0) / 25.0, 0.05, 0.35), ground_dust(phys.x, phys.z, phys.surf))
	if Env.s("BMX_TRICK") != "" or Env.s("BMX_MAN_PROBE") != "": print("CRASH ", reason, " v=%.1f air=%s pitch=%.2f gp=%.2f man=%.2f lean=%.2f slip=%.2f" % [phys.v, phys.air, phys.pitch, phys._g_pitch, phys.man_a, phys.lean, phys.slip])   # tests
	elif Env.s("BMX_CRASH_LOG") != "":   # tests: every crash with the ground sim's state at that moment
		print("CRASH %s | v=%.1f air=%s since_land=%.2f slip=%.2f lean=%.2f lean_err=%.2f front_use=%.2f rear_lock=%.2f front_lock=%.2f bank=%.2f pitch_err=%.2f" % [
			reason, phys.v, phys.air, phys.since_land, phys.slip, phys.lean, phys.lean_err, phys.front_use, phys.rear_lock, phys.front_lock, phys.bank,
			wrapf(phys.pitch - phys._g_pitch, -PI, PI)])
	var pts: Array = rider.joints_world()
	var f := phys.fwd()
	# the body carries on with the bike's own motion (no extra pop up: it used to throw the body into the air)
	var body_vel := f * phys.v + Vector3(0, minf(maxf(phys.vy, 0), 6.0 if phys.air else 0.3) + 0.2, 0)
	var spin_v := f * (1.0 + absf(phys.v) * 0.08)   # the top of the body keeps going a little as the bike stops
	var crash_v := body_vel.length()
	phys.begin_crash()
	_break_action_cam(body_vel)
	# detach the rider into world space
	rider.get_parent().remove_child(rider)
	add_child(rider)
	rider.transform = Transform3D.IDENTITY
	ragdoll.start(pts, body_vel, spin_v, 1.0 / 60)
	var flat_v := Vector2(body_vel.x, body_vel.z).length()
	crash_fatal = flat_v > Blood_FATAL_SPEED or Env.s("BMX_FATAL") != ""
	if blood: blood.crash_start(flat_v)
	grime.add_blood(clampf((crash_v - 8.0) * 0.035, 0.0, 0.5))   # only a severe crash (> ~8 m/s) stains; the rider + bike stay bloody until a death + revive
	rider.pose_ragdoll(ragdoll.p)
	# (no dust right where the crash starts with the smoke sim: only where the body / bike hit and slide)
	burst(Vector3(phys.x, phys.y + 0.05, phys.z), 30 if dust.sim == null else 2, terrain.surface(phys.x, phys.z), 1.5, dust.sim == null)
	var cs: int = terrain.surface(phys.x, phys.z)
	# (with the smoke sim the ragdoll's own impacts throw the dust: _crash_dust)
	if cs != 2 and dust.sim == null: dust.cloud(Vector3(phys.x, phys.y, phys.z), f * phys.v * 0.3, ground_dust(phys.x, phys.z, cs), 3.2, 1.2)
	if _wasted_on(): wasted.start(reason)
	else: flash(reason)
	if hud: hud.on_crash(crash_v)
	if audio: audio.crash()

## the helmet action cam snaps off its hinge and tumbles away (FlyingCam); a new one is on the helmet
## after getting up. The old one lies where it landed until a respawn or FlyingCam.LIFE.
var flying_cam: FlyingCam = null
func _break_action_cam(body_vel: Vector3) -> void:
	var r: Dictionary = rider.break_action_cam()
	if r.is_empty(): return
	if flying_cam and is_instance_valid(flying_cam): flying_cam.queue_free()
	var xf: Transform3D = r.xform
	var side := xf.basis.z.normalized()
	var vel := body_vel * 1.05 + Vector3(0, 2.0 + randf() * 2.5, 0) + side * (randf() - 0.5) * 3.0
	var spin := Vector3(randf() - 0.5, randf() - 0.5, randf() - 0.5).normalized() * (12.0 + randf() * 14.0)
	flying_cam = FlyingCam.launch(self, r.body, xf, terrain, vel, spin)
	if Env.s("BMX_CAM_PROBE") != "" or Env.s("BMX_GOPRO_PROBE") != "":
		print("GOPRO off at %s v=%s" % [str(xf.origin), str(vel)])

## the crash slow-mo is on (Settings › Gameplay; autotests keep normal time unless BMX_WASTED=1)
func _wasted_on() -> bool:
	return false   # removed (user, 2026-11-23): no crash slow motion, no grey WASTED screen; a crash just flashes its reason
	if Env.s("BMX_WASTED") != "": return true
	if level != "": return false   # the test playground: no slow motion / WASTED screen (the lab has its own slow motion)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--autotest"): return false
	return bool(Settings.get_v("wasted"))

## the hold to get up is done: the rider climbs to their feet, then get_up() puts them on the bike.
## With clips in ClipGetUp.GETUP_DIR: the clip matching how the body lies, then standing dizzy until hop is pressed
## again (or Backspace). Without them: the procedural GetUpAnim straight onto the bike.
## A fatal crash (crash_fatal), a torn-off limb (or BMX_GETUP_ANIM=0) gets straight back on as before:
## the climb to the feet is only for crashes the rider walks away from.
var getup_anim = null              # ClipGetUp / GetUpAnim
var _hop_armed := false            # dizzy: hop let go since standing up (a fresh press gets back on)
var crash_fatal := false
const Blood_FATAL_SPEED := 12.0   # = Blood.FATAL_SPEED (fx/blood.gd), kept here: blood may be off
var _stand_world: Array = []   # the standing pose it ended in (world), blended into the riding pose
var _stand_blend := 1.0
const STAND_BLEND := 0.35      # s from standing to on the bike
func begin_getup() -> void:
	if getup_anim != null: return
	if not ragdoll.active or not ragdoll.cut.is_empty() or crash_fatal or Env.s("BMX_GETUP_ANIM") == "0":
		get_up(); return
	if ClipGetUp.available() and Env.s("BMX_GETUP_ANIM") != "proc":
		var g := ClipGetUp.new(rider, terrain, ragdoll.p)
		if g.ok():
			getup_anim = g
			g.target = rig.global_position   # the fallen bike: where the limp ends
			g.has_target = true
			if Env.s("BMX_WALK_FAR") != "":   # tests: walk to a point this many metres down the trail from the bike
				g.target += float(Env.s("BMX_WALK_FAR")) * rig.global_transform.basis.x
	if getup_anim == null: getup_anim = GetUpAnim.new(rider, terrain, ragdoll.p)
	_hop_armed = false
	ragdoll.active = false
	phys.crash_hold = 0.0; phys.crash_armed = false
	if wasted: wasted.finish()
	if Env.s("BMX_GETUP_PROBE") != "": print("GETUP start at ", (ragdoll.p[Ragdoll.PELVIS] as Vector3).snapped(Vector3.ONE * 0.01))

## one physics step of the get-up: draw it, keep the ragdoll's points on it (camera, photo mode follow them)
func _getup_step(dt: float, hop: bool) -> void:
	if getup_anim is ClipGetUp and getup_anim.dizzy():
		# standing dizzy: a fresh hop press gets back on the bike (tests: BMX_DIZZY_SECS)
		if not hop: _hop_armed = true
		elif _hop_armed: getup_anim.release(); _hop_armed = false
		var ds := Env.s("BMX_DIZZY_SECS")
		if ds != "" and getup_anim.t > float(ds): getup_anim.release(); _hop_armed = false
	elif getup_anim is ClipGetUp and getup_anim.walking():
		# limping to the bike: a fresh hop press gets on now
		if not hop: _hop_armed = true
		elif _hop_armed: getup_anim.skip()
	var going: bool = getup_anim.step(dt)
	var P: Array = getup_anim.last_world
	for i in mini(P.size(), ragdoll.p.size()):
		ragdoll.p[i] = P[i]; ragdoll.q[i] = P[i]
	if not going:
		_stand_world = P.duplicate()
		if Env.s("BMX_GETUP_PROBE") != "": print("GETUP stood up, pelvis ", (P[2] as Vector3).snapped(Vector3.ONE * 0.01), " head ", (P[0] as Vector3).snapped(Vector3.ONE * 0.01))
		get_up()
		_stand_blend = 0.0

## just back on the bike: the standing body eases into the riding pose (after update_pose)
func _stand_to_bike(dt: float) -> void:
	_stand_blend = minf(_stand_blend + dt / STAND_BLEND, 1.0)
	var w := smoothstep(0.0, 1.0, _stand_blend)
	var inv: Transform3D = rider.global_transform.affine_inverse()
	var P := []
	for i in 15: P.append((inv * (_stand_world[i] as Vector3)).lerp(rider.J[i], w))
	rider.pose_points(P)

## the drawn-only smoothing (motion caps, pose smoothers, the stand-to-bike blend) starts fresh: after a respawn / a
## reset onto the trail it kept the old spot's values (a spawn drawn ~50 deg leaned, swinging upright; Backspace while
## climbing back on stretched the body from the old spot)
func _reset_draw_state() -> void:
	_mc.clear(); _stand_blend = 1.0
	_yaw_s = 0.0; _turn_s = 0.0; _aspin_s = 0.0; _atilt_s = 0.0; _blat_s = 0.0; _awhip_s = 0.0

## a crash (or its get-up / dizzy clip) is dropped at once: back on the bike, no slow motion, no WASTED.
## Respawn / the title hilltop: phys.reset_at clears crash_on without a get-up, which left the ragdoll, the
## WASTED slow motion and the blood running and the rider detached from the bike for the next ride
func _end_crash() -> void:
	if phys == null: return
	var detached: bool = rider != null and rig != null and rig.lean_g != null and rider.get_parent() != null and rider.get_parent() != rig.lean_g
	if phys.crash_on or getup_anim != null or detached:
		get_up()
	if wasted: wasted.stop()

func get_up() -> void:
	_jw_prev = Vector2(INF, INF)
	var _gt := Time.get_ticks_usec()   # (its parts are "getup.*" in the frame profiler, F10)
	if getup_anim is ClipGetUp: getup_anim.free_clips()   # (Backspace while standing dizzy)
	getup_anim = null
	_reset_draw_state()
	phys.get_up()
	_out_of_crevasse()
	if wasted: wasted.finish()
	_gt = _perf("getup.phys_wasted", _gt)
	ragdoll.active = false
	if blood: blood.crash_end()
	_gt = _perf("getup.blood", _gt)
	if rider.get_parent() != rig.lean_g:
		rider.get_parent().remove_child(rider)
		rig.lean_g.add_child(rider)
	_gt = _perf("getup.reparent", _gt)
	rider.transform = Transform3D.IDENTITY
	rider.reset_pose()
	_gt = _perf("getup.reset_pose", _gt)
	rider.remount_action_cam()
	_gt = _perf("getup.action_cam", _gt)
	if Env.s("BMX_GOPRO_PROBE") != "": print("GOPRO remounted: ", rider.action_cam.get_node_or_null("Body") != null)
	_snap_prev()
	if hud: hud.on_get_up()

## tests (BMX_SKIP_PROBE=1): every time the wheels leave the ground, sorted by why. A flight (both wheels off) is
## "jump" off a built jump (TerrainField.fo_m at take-off), "hop" when the rider hopped / popped just before
## (hop button, stick hop, a pop: pop_fx or kick_t), "crash", else "skip" = the ground threw the bike off by itself.
## One-wheel lifts on the ground are counted too (front / rear off > 0.05 s, no flight). SKIP lines per event of
## a skip (speed, air, height, ground slope / curve under the bike), SKIPSUM every 10 s (counts per km, air time)
var _SKIP := OS.get_environment("BMX_SKIP_PROBE") != ""
var _SKIP_TR: PackedFloat64Array = PackedFloat64Array(Array(OS.get_environment("BMX_SKIP_TRACE").split(",", false)).map(func(q): return float(q)))   # (tests: x0,x1 = every step between)
var _sk := {"t": 0.0, "dist": 0.0, "jump": 0, "hop": 0, "skip": 0, "skip_air": 0.0, "skip_big": 0, "jump_air": 0.0, "lift_f": 0, "lift_r": 0, "lift_t": 0.0, "fast_t": 0.0, "fast_skip": 0, "fo_long": 0, "fo_max": 0.0, "fo_t": 0.0}
var _sk_air := false; var _sk_why := ""; var _sk_v := 0.0; var _sk_y0 := 0.0; var _sk_peak := 0.0; var _sk_kap := 0.0; var _sk_sl := 0.0
var _sk_fr1 := 0.0; var _sk_fo := 0.0; var _sk_fr := 0.0; var _sk_next := 10.0; var _sk_x := 0.0
func _skip_probe(dt: float, inp: Dictionary) -> void:
	_sk.t += dt
	if _SKIP_TR.size() == 2 and phys.x > _SKIP_TR[0] and phys.x < _SKIP_TR[1]:
		var f0: Vector3 = phys.fwd()
		print("SKTR x=%.2f y=%.3f vy=%+.2f v=%.1f pitch=%+.3f pv=%+.2f gp=%+.3f air=%s fa=%s ra=%s cf=%s cr=%s xF=%.3f xR=%.3f vF=%+.2f vR=%+.2f fF=%.1f fR=%.1f tyF=%.1f tyR=%.1f sqF=%.3f sqR=%.3f leg=%+.3f legf=%+.1f body_v=%+.2f cg=%.1f gy=%.3f" % [phys.x, phys.y, phys.vy, phys.v, phys.pitch, phys.pitch_v, phys._g_pitch, phys.air, phys.front_air, phys.rear_air, phys.c_f, phys.c_r,
			phys.dg_xF, phys.dg_xR, phys.dg_vF, phys.dg_vR, phys.dg_fF, phys.dg_fR, phys.dg_tyF, phys.dg_tyR, phys.dg_sqF, phys.dg_sqR, phys.dg_leg, phys.dg_leg_f, phys.body_v, phys.corner_g, terrain.deck_height(phys.x, phys.z)])
	if phys.crash_on: _sk_air = false; return
	_sk.dist += absf(phys.v) * dt
	if phys.v > 11.0: _sk.fast_t += dt
	var both: bool = phys.air
	if both and not _sk_air:
		_sk_air = true; _sk_v = phys.v; _sk_y0 = phys.y; _sk_peak = phys.y; _sk_x = phys.x
		var fm := 0.0
		if terrain.field != null:
			terrain.field.jump_eval(phys.x, phys.z); fm = terrain.field.fo_m
		_sk_why = "jump" if fm > 0.05 else ("hop" if (phys.pop_fx > 0.3 or phys.kick_t > 0.0 or phys.hop_t > 0.0) else "skip")
		var f: Vector3 = phys.fwd()
		var h0: float = terrain.deck_height(phys.x, phys.z)
		_sk_kap = (terrain.deck_height(phys.x + f.x * 0.6, phys.z + f.z * 0.6) + terrain.deck_height(phys.x - f.x * 0.6, phys.z - f.z * 0.6) - 2.0 * h0) / 0.36
		_sk_sl = phys._g_pitch
	if both: _sk_peak = maxf(_sk_peak, phys.y)
	if not both and _sk_air:
		_sk_air = false
		var at: float = phys.air_time
		if at >= 0.05:
			_sk[_sk_why] += 1
			if _sk_why == "skip":
				_sk.skip_air += at
				if at > 0.25: _sk.skip_big += 1
				if _sk_v > 11.0: _sk.fast_skip += 1
				print("SKIP v=%.0f km/h air=%.2f s up=%.2f m dist=%.1f m slope=%.0fdeg curve=%.3f /m (v^2 x curve = %.2f g) x=%.0f" % [_sk_v * 3.6, at, _sk_peak - _sk_y0, absf(phys.x - _sk_x), rad_to_deg(_sk_sl), _sk_kap, _sk_v * _sk_v * _sk_kap / 9.81, phys.x])
			elif _sk_why == "jump": _sk.jump_air += at
	if not both:
		# (riding on the front wheel alone, the rear up, not a nose manual: how long at a time)
		if not phys.c_r and phys.nose_a < 0.05 and phys.man_a < 0.05 and (phys.c_f or _sk_fr1 > 0.0):
			_sk_fr1 += dt; _sk.fo_t += dt
		else:
			if _sk_fr1 > 0.3: _sk.fo_long += 1
			_sk.fo_max = maxf(_sk.fo_max, _sk_fr1); _sk_fr1 = 0.0
		_sk_fo = _sk_fo + dt if phys.front_air else 0.0
		_sk_fr = _sk_fr + dt if phys.rear_air else 0.0
		if phys.front_air or phys.rear_air: _sk.lift_t += dt
		if absf(_sk_fo - 0.05) < dt * 0.5 and phys.man_a < 0.05: _sk.lift_f += 1
		if absf(_sk_fr - 0.05) < dt * 0.5 and phys.nose_a < 0.05: _sk.lift_r += 1
	if _sk.t >= _sk_next:
		_sk_next += 10.0
		var km: float = maxf(0.001, _sk.dist / 1000.0)
		print("SKIPSUM t=%.0fs dist=%.0fm | skips=%d (%.1f/km, %d over 0.25 s, %d above 40 km/h, %.1f s in the air) jumps=%d (%.1f s) hops=%d | wheel lifts front=%d rear=%d (%.1f/km, one wheel off %.1f %% of the time) | front wheel alone %.1f s, %d runs over 0.3 s, longest %.2f s | above 40 km/h %.0f %% of the time" % [
			_sk.t, _sk.dist, _sk.skip, _sk.skip / km, _sk.skip_big, _sk.fast_skip, _sk.skip_air, _sk.jump, _sk.jump_air, _sk.hop,
			_sk.lift_f, _sk.lift_r, (_sk.lift_f + _sk.lift_r) / km, 100.0 * _sk.lift_t / maxf(0.01, _sk.t), _sk.fo_t, _sk.fo_long, _sk.fo_max, 100.0 * _sk.fast_t / maxf(0.01, _sk.t)])

func on_trick(trick: String) -> void:
	if hud: hud.on_trick(trick)

func on_style(points: int, label: String) -> void:
	if hud: hud.on_style(points, label)
	if Env.s("BMX_TRICK") != "": print("STYLE +%d %s" % [points, label])   # tests

func on_takeoff() -> void:
	takeoff = Vector3(phys.x, phys.y, phys.z)
	_jp_v = sqrt(phys.v * phys.v + phys.vy * phys.vy)
	air_peak = phys.y
	if hud: hud.on_takeoff()

## a landing that went badly (HEAVY / SLAM verdict): the slam's second bounce + clatter
func on_bad_landing(sev: float) -> void:
	var _lt := Time.get_ticks_usec()
	if audio: audio.landing_bad(sev)
	_perf("p_step.land_bad_audio", _lt)

func on_landing(air_time: float, impact: float) -> void:
	var dist := Vector2(phys.x - takeoff.x, phys.z - takeoff.z).length()
	var height := air_peak - maxf(takeoff.y, phys.y)
	if Env.s("BMX_JUMP_PROBE") != "" and air_time > 0.45 and terrain.field != null:   # tests: where on a trail jump it came down
		# SHORT = on the stretch riders are meant to fly over (the table top, the gap), LANDING = on the jump past
		# that, LONG = clear of the whole jump (flat ground), NATURAL = not off a built jump at all
		terrain.field.jump_eval(takeoff.x, takeoff.z)
		var m0: float = terrain.field.fo_m
		terrain.field.jump_eval(phys.x, phys.z)
		var m1: float = terrain.field.fo_m
		var a1: float = terrain.field.fo_air
		var where := "NATURAL" if m0 < 0.05 and m1 < 0.05 else ("SHORT" if a1 > 0.3 else ("LANDING" if m1 > 0.05 else "LONG"))
		print("JUMPLAND %s v_off=%.0f km/h air=%.2f dist=%.1f height=%.1f impact=%.1f slope=%.0fdeg pitch_err=%.0fdeg x=%.0f" % [where, _jp_v * 3.6, air_time, dist, maxf(0.0, height), impact,
			rad_to_deg(phys._g_pitch), rad_to_deg(wrapf(phys.pitch - phys._g_pitch, -PI, PI)), phys.x])
	var _lt := Time.get_ticks_usec()
	if hud: hud.on_landing(air_time, dist, maxf(0.0, height), impact)
	_lt = _perf("p_step.land_hud", _lt)   # (the frame profiler's landing breakdown: F10)
	_landed = clampf(impact / 6.0, 0.0, 1.0) if air_time > 0.25 else 0.0
	var ls: int = terrain.surface(phys.x, phys.z)
	if ls == 2 and air_time > 0.15:   # a landing in the water: a ring of ripples off both tyres
		var wf := phys.fwd()
		var wk := clampf(0.1 + impact / 24.0, 0.1, 0.4)
		terrain.water_splash(Vector3(phys.x - wf.x * phys.BB_REAR, phys.y, phys.z - wf.z * phys.BB_REAR), wk, 0.5)
		terrain.water_splash(Vector3(phys.x + wf.x * (phys.L - phys.BB_REAR), phys.y, phys.z + wf.z * (phys.L - phys.BB_REAR)), wk, 0.5)
	if dust.sim != null and air_time > 0.3 and ls != 2:   # real smoke sim: a ring of dust blasted outward
		var lf := phys.fwd()
		var lbb: float = phys.BB_REAR
		var tyres := [Vector3(phys.x - lf.x * lbb, phys.y, phys.z - lf.z * lbb),
			Vector3(phys.x + lf.x * (phys.L - lbb), phys.y, phys.z + lf.z * (phys.L - lbb))]
		dust.landing_dust(tyres, lf * phys.v, impact, ground_dust(phys.x, phys.z, ls),
			(1.0 if ls == 1 else 0.85 if ls == 3 else 0.3) * clampf(air_time / 0.8, 0.4, 1.3))
	elif air_time > 0.45 and (ls == 1 or ls == 3):
		dust.cloud(Vector3(phys.x, phys.y, phys.z), phys.fwd() * phys.v * 0.3, ground_dust(phys.x, phys.z, ls), 2.6 + impact * 0.15, 1.1)
	_lt = _perf("p_step.land_dust", _lt)
	if rumble: rumble.landing(air_time, impact)
	if audio and air_time > 0.15: audio.landing(impact, phys.land_yaw)
	_perf("p_step.land_audio", _lt)

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
		{p = rear, v = vel, r = rr * 1.05, spin = -axle * (st.v / rr), solid = false, blend = 6.0},   # spokes: they stir the air (gently: the tyre's spray wins), they don't fill it
		{p = front, v = vel, r = rf * 1.05, spin = -axle * (st.v / rf), solid = false, blend = 6.0},
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
		if g < Terrain.WATER - 0.02 and absf(pp.y - Terrain.WATER) < 0.6:   # a body part in the water pushes it about
			var wsp := ((pp - (prv[i] as Vector3)) / h).length()
			if wsp > 1.5 and i % 2 == 0: terrain.water_splash(pp, minf(wsp, 10.0) * 0.1, 0.35)
		if above > 0.3:
			_rd_air[i] = 1   # off the ground: the next touch-down is an impact
			continue
		if above > 0.2: continue
		if grass and i % 2 == 0:   # the body flattens the grass it lies / slides in
			var pq: Vector3 = prv[i] if i < prv.size() else pp
			grass.trample(100 + i, pp, pp - pq, 0.28)
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
				if Env.s("BMX_SMOKE_PROBE") != "": print("CRASHDUST impact i=%d t=%.2f hit=%.1f" % [i, phys.crash_t, hit])
				dust.sim.burst(at, Vector3(v.x * 0.25, 0.6 + k * 0.8, v.z * 0.25), 0.3 + k * 0.25, (50.0 + 110.0 * k) * amt * CRASH_DUST_BODY,
					1.2 + k * 2.2, 0.08 + k * 0.05, ground_dust(pp.x, pp.z, s), 20.0)
				if Env.s("BMX_NOGRIT") == "": dust.grit_burst(at, Vector3(v.x * 0.3, 0.8 + k * 1.6, v.z * 0.3), 1.0 + k * 2.5, 600.0 * k * amt * 0.2 * CRASH_DEBRIS, 0.06, ground_dust(pp.x, pp.z, s))
				made += 1
		elif hs > 1.2 and made < 10:
			# sliding / rolling along the ground
			if Env.s("BMX_SMOKE_PROBE") != "": print("CRASHDUST slide i=%d t=%.2f hs=%.1f" % [i, phys.crash_t, hs])
			dust.sim.add_source(at, Vector3(v.x * 0.3, 0.4, v.z * 0.3), 0.25, minf(hs, 6.0) * 4.0 * amt * CRASH_DUST_BODY, 6.0, 0.3, ground_dust(pp.x, pp.z, s))
			made += 1
	# the bike sliding / tumbling along the ground
	var bs: int = terrain.surface(phys.x, phys.z)
	if absf(phys.v) > 0.6 and bs != 2 and phys.crash_t > 0.25:
		var g2: float = terrain.height(phys.x, phys.z)
		var ba := 1.0 if bs == 1 else (0.85 if bs == 3 else 0.3)
		var f := phys.fwd()
		if Env.s("BMX_SMOKE_PROBE") != "": print("CRASHDUST bike t=%.2f v=%.1f" % [phys.crash_t, phys.v])
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
	# on a rope bridge's planks: no dirt to throw, and no tyre tracks (they're drawn fixed in the world: on a deck
	# that swings and sags they hung in the air / sank into the planks)
	var bare := in_water or _on_rope_deck(st.x, st.z, st.y)
	if not st.air and va > 0.6 and not bare:
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
		# puddles on the road (drawn by ground.gdshader, world/trail_puddle.gd): wet soil gives no dust, standing
		# water none at all; looked up only where dust would come off the trail anyway
		var wet_r := Vector2.ZERO
		var wet_f := Vector2.ZERO
		if dirt and rate > 0.0:
			var pt0 := Time.get_ticks_usec()
			wet_r = terrain.puddle_at(rear.x, rear.y - 0.03, rear.z)
			wet_f = terrain.puddle_at(front.x, front.y - 0.03, front.z)
			if Env.s("BMX_PUDDLE_PROBE") != "":
				_pud_us += Time.get_ticks_usec() - pt0
				_pud_n += 1
				if _pud_n % 1200 == 0: print("PUDDLECOST calls=%d avg_us=%.1f (both tyres)" % [_pud_n, float(_pud_us) / _pud_n])
		var dry_r := 1.0 - maxf(wet_r.y, wet_r.x * 0.75)
		var dry_f := 1.0 - maxf(wet_f.y, wet_f.x * 0.75)
		if Env.s("BMX_PUDDLE_PROBE") != "" and (wet_r != Vector2.ZERO or wet_f != Vector2.ZERO):
			print("PUDDLE at=(%.1f,%.1f,%.1f) t=%.2f rear damp=%.2f water=%.2f front damp=%.2f water=%.2f dust=%.0f->%.0f" % [rear.x, rear.y, rear.z, Time.get_ticks_msec() / 1000.0, wet_r.x, wet_r.y, wet_f.x, wet_f.y, rate, rate * dry_r])
		# the dust trail: a GPU particle emitter at the rear tyre (fx/ride_dust.gd), thrown back and up,
		# flung outward in a carve
		# the tread's real state: sideways slide (slip angle x speed) and wheelspin throw the spray harder / further out
		var g_long0 := 0.0
		if skid_fx: g_long0 = -va
		elif st.a_drive > 6.0: g_long0 = clampf((st.a_drive - 6.0) * 0.8, 0.0, 7.0)
		var slide_k := clampf(absf(va * sin(clampf(st.slip_w, -1.2, 1.2))) / 4.0, 0.0, 1.0)
		var spin_k := clampf(g_long0 / 7.0, 0.0, 1.0)
		var load_k := clampf(0.55 + 0.45 * st.n_rear / 9.81, 0.4, 1.2)   # a light rear (bouncing, unloaded) kicks up less
		rate *= load_k * (1.0 + slide_k * 0.5 + spin_k * 0.4)
		# the dust starts where each tyre really meets the ground (swung out by the lean, on the drawn ground), not under the frame
		var rear_d := _dust_patch(rear, rig.wheel_r if rig != null else null, rig.wheel_rr if rig != null else 0.0)
		var front_d := _dust_patch(front, rig.wheel_f if rig != null else null, rig.wheel_rf if rig != null else 0.0)
		var d_out := turn_dir * (carve_k * 3.5 + slide_k * 2.5)
		var d_back := va * 0.3 * (1 - carve_k * 0.55) + spin_k * 2.2
		var d_ev := Vector3(-f.x * d_back + side.x * d_out, 0.7 + carve_k * 0.4 + dust_k * 1.4, -f.z * d_back + side.z * d_out)
		var d_fan := rad_to_deg(atan2((1.6 + va * 0.18) * (1 - carve_k * 0.6) * 0.5, maxf(d_back, 0.6))) + dust_k * 25.0
		var d_a := (0.62 if skid_fx else 0.45) if dirt else ((0.55 if skid_fx else 0.4) if sand else 0.26)
		# what the tyre really does to the ground, for the grit spray (fx/GritSprayCs.cs): the rear tread's speed over
		# the bike's (wheelspin from the drive force past what the ground holds, locked = it stops turning), the sideways
		# slide of the tread (slip angle x speed), the rear's load, and how loose the ground is
		var g_long := 0.0
		if skid_fx: g_long = -va
		elif st.a_drive > 6.0: g_long = clampf((st.a_drive - 6.0) * 0.8, 0.0, 7.0)
		var g_lat := va * sin(clampf(st.slip_w, -1.2, 1.2))
		var g_loose := (1.5 if sand else (1.0 if dirt else 0.35)) * (0.75 + 0.5 * clampf(st.loose, 0.0, 1.0))
		dust.set_grit_state(f * st.v, f, g_long, g_lat, clampf(st.n_rear / 9.81, 0.0, 2.0), g_loose, clampf((absf(st.vw_r) - 2.5) / 3.5, 0.0, 1.0))
		dust.feed(rear_d, d_ev, rate * fxd * dry_r, dcol, d_a, clampf(d_fan, 12.0, 70.0))
		if Env.s("BMX_DUST_PROBE") != "":
			_dprobe_t += dt
			if _dprobe_t >= 2.0:
				_dprobe_t = 0.0
				print("DUSTFEED t=%.0f x=%.0f z=%.0f surf=%d va=%.1f rate=%.0f fxd=%.2f dry=%.2f a=%.2f feed=%.0f sim_n=%d idle=%.1f stopped=%s" % [
					Time.get_ticks_msec() / 1000.0, rear.x, rear.z, s, va, rate, fxd, dry_r, d_a, dust._feed_rate,
					dust.sim._n if dust.sim else -1, dust.sim._idle if dust.sim else -1.0, str(dust.sim._stopped) if dust.sim else "-"])
		# the front tyre dusts too, less: it rolls (no drive / little skid), so it mostly lifts dust
		# sideways and up as it carves
		var f_ev := Vector3(-f.x * d_back * 0.4 + side.x * d_out * 0.6, 0.5 + carve_k * 0.3, -f.z * d_back * 0.4 + side.z * d_out * 0.6)
		dust.feed_front(front_d, f_ev, 0.0 if st.front_air else rate * fxd * 0.35 * dry_f, d_a)   # none with the front up (wheelie)
		# through standing water: muddy drops thrown off both tyres instead of dust
		if puddle_wake != null and va > 0.8:   # the tyres push the puddle (ripples: ground.gdshader)
			var pk := clampf(va / 10.0, 0.0, 1.4) * 24.0 * dt
			if wet_r.y > 0.05: puddle_wake.splash(rear, pk * wet_r.y, 0.06)
			if wet_f.y > 0.05 and not st.front_air: puddle_wake.splash(front, pk * wet_f.y * 0.8, 0.055)
		var pud := wet_r.y + (0.0 if st.front_air else wet_f.y * 0.6)
		if pud > 0.05 and va > 1.5 and fx:
			_splash_acc += dt * pud * minf(va, 14.0) * 5.0 * fxd
			while _splash_acc > 1.0:
				_splash_acc -= 1.0
				var at := rear if randf() * pud < wet_r.y else front
				var sp := (randf() - 0.5) * 2.2
				var ev := Vector3(-f.x * va * 0.25 + side.x * sp, 0.8 + randf() * 1.6, -f.z * va * 0.25 + side.z * sp)
				fx.chunk(at, ev, PUDDLE_DROP, 0.008 + randf() * 0.008, 0.9)
				if randf() < 0.25: lens.splash(0.03 + 0.04 * pud)   # some of it reaches the lens
		# a hard skid on loose ground kicks up a real cloud now and then (volumetric fog)
		_cloud_t -= dt
		if (dirt or sand) and skid_fx and va > 5 and _cloud_t <= 0 and dry_r > 0.5:
			_cloud_t = 0.45
			dust.cloud(rear, d_ev * 0.5, dcol, 2.2 + va * 0.08, 0.9)
		if not in_water:
			var cr := 0.0
			if dirt: cr = (30.0 if skid_fx else 0.0) + carve_k * 28 + st.pedal * (9.0 if va < 8 else 2.0)
			elif sand: cr = (18.0 if skid_fx else 0.0) + carve_k * 16 + st.pedal * (4.0 if va < 8 else 1.0)
			elif skid_fx: cr = 6.0
			st.chunk_acc += dt * cr * fxd * dry_r   # wet soil sticks: no dry clods out of a puddle
			while st.chunk_acc > 1:
				st.chunk_acc -= 1
				var out := turn_dir * carve_k * (2.5 + randf() * 3.5) if carve_k > 0.05 else (randf() - .5) * 1.2
				var back := (1.5 + va * 0.35) * (1 - carve_k * 0.6)
				var ev := Vector3(-f.x * back + side.x * out, 1 + randf() * 2.2, -f.z * back + side.z * out)
				var cc: Color = (DIRT_CHUNK if randf() < 0.7 else ROCK_CHUNK) if dirt else (dcol * 0.8 if sand else GRASS_CHUNK)
				fx.chunk(rear, ev, cc, 0.022)
	if st.air or va <= 0.6 or bare:
		dust.feed(rear, Vector3.ZERO, 0.0, dcol, 0.0, 20.0)
		dust.feed_front(front, Vector3.ZERO, 0.0, 0.0)
	# riding through a lake / stream: the spray soaks the lens
	if in_water and not st.air and va > 2.0: lens.splash(dt * minf(va, 12.0) * 0.06)
	# ... and both tyres push the surface: the wake runs out behind (WaterWake, compute shader)
	if in_water and va > 0.7:
		var wpush := clampf(va / 10.0, 0.0, 1.4) * 14.0 * dt
		if not st.air: terrain.water_splash(rear, wpush, 0.3)
		if not st.air and not st.front_air: terrain.water_splash(front, wpush * 0.8, 0.28)
	# riding fast through dry dust (dirt / sand) slowly dusts the lens: full in ~1.5 min flat out, a skid's
	# cloud more; damp ground (wet bike) none
	if not st.air and not bare and (s == 1 or s == 3) and va > 5.0:
		lens.add_dust(dt * smoothstep(5.0, 16.0, va) * (0.006 + (0.012 if skid_fx else 0.0)) * (1.0 - clampf(grime.wet * 2.0, 0.0, 1.0)), dcol)
	grime.feed(dt, 2 if in_water else s, va, skid_fx, st.air, _landed, terrain.ground_color(rear.x, rear.z), Vector2(st.vw_f, st.vw_r))
	_landed = 0.0
	# dry mud knocked off the bike flies off as chunks (low on the bike, carried along with it)
	var shed := mini(grime.take_shed(), 12)
	if shed > 0 and fx:
		var bt := rig.global_transform
		var dc := grime.dry_color()
		for i in shed:
			var lp := Vector3(randf_range(-0.45, 0.75), randf_range(0.15, 0.75), randf_range(-0.12, 0.12))
			var ev := f * va * 0.85 + Vector3((randf() - 0.5) * 1.6, randf() * 1.4, (randf() - 0.5) * 1.6)
			fx.chunk(bt * lp, ev, dc, randf_range(0.008, 0.02), 1.6)
	var on_ground := not st.air and not bare and va > 0.2
	# tyre prints, pressed into the ground (world/ruts.gd; the ground shaders draw them in the ground's own colour):
	# how dark per surface, a skid's smear darker and wider; a tyre that rolled through blood prints red for a few metres
	var ta := 0.85 if s == 1 else (0.75 if sand else 0.45)
	var bl_f := 0.0
	var bl_r := 0.0
	if blood and on_ground:
		blood.tyre_color(0, front, Color.BLACK); blood.tyre_color(1, rear, Color.BLACK)   # (updates how bloody each tyre is)
		bl_f = blood.tyre_blood(0); bl_r = blood.tyre_blood(1)
	if ruts != null:
		ruts.track(0, front, ta if on_ground else 0.0, 0.085, false, bl_f)
		ruts.track(1, rear, ((minf(1.0, ta + 0.2) if skid_fx else ta) if on_ground else 0.0), 0.12 if skid_fx else 0.095, skid_fx, bl_r)
	# the bike lays the grass down behind it (wheels + the frame / pedals sweeping over); it stands up again slowly
	if grass and on_ground:
		grass.trample(0, front, f, 0.26)
		grass.trample(1, rear, f, 0.34 if skid_fx else 0.3)

# ---------------------------------------------------------------- ride control
var ruts = null    # world/ruts.gd: ruts + tyre prints in the ground
## ruts + prints: rides, built levels and the test playground. Settings › Gameplay › Ruts switches only the digging
## (BMX_RUTS=0 off, =1 on whatever the setting); the prints are always there (BMX_NO_TRACKS=1 hides them)
func _make_ruts() -> void:
	ruts = preload("res://scripts/world/ruts.gd").new(self)
	ruts.dig = Env.s("BMX_RUTS") != "0" and (Env.s("BMX_RUTS") == "1" or bool(Settings.get_v("ruts")))
	add_child(ruts)
	if not ruts.active(): ruts.queue_free(); ruts = null
var ghost = null   # game/ghost_rider.gd (rides of this world only, not the title / levels)

func respawn(new_world: bool) -> void:
	_jw_prev = Vector2(INF, INF)   # (a respawn moves the bike on purpose: not a jump)
	exit_replay()
	if replay: replay.clear()
	_line_reset()
	_end_crash()
	_reset_draw_state()
	if hud: hud.on_respawn()
	if new_world and level != "":
		new_world = false   # a test level has no other world
	if new_world:
		GameState.new_seed()
		terrain.clear_dynamic()
		terrain.set_seed(GameState.seed)
		terrain.update_stream(0, 0, INF)
		far_hills.queue_free()   # the new world's distant landscape
		far_hills = FarHills.new()
		far_hills.setup(terrain)
		add_child(far_hills)
		if sheep: sheep.reset()
		if ruts: ruts.clear()
		tumbleweeds.clear()
		flash("New world #%d" % GameState.seed)
	if grass: grass.clear_trample()
	if new_world: grime.clean()
	if blood: blood.clear()
	lens.wipe()
	_lens_test_setup()
	if flying_cam and is_instance_valid(flying_cam): flying_cam.queue_free()
	flying_cam = null
	var sp := _water_spawn() if Env.s("BMX_WATER_SPAWN") != "" else Vector3.ZERO
	if Env.s("BMX_TRAIL_FEAT") != "":
		sp = _feature_spawn(Env.s("BMX_TRAIL_FEAT"))
	if terrain.has_method("level_spawn"):
		sp = terrain.level_spawn()
	if race: race.reset()
	phys.reset_at(sp.x, sp.z, sp.y)
	if Env.s("BMX_PACK_SPAWN") != "":   # tests: "x,z" of a health pack -> start 9 m before it, facing +x
		var pxz := Env.s("BMX_PACK_SPAWN").split(",")
		sp = Vector3(float(pxz[0]) - 9.0, 0.0, float(pxz[1]))
		phys.reset_at(sp.x, sp.z, sp.y)
	if Env.s("BMX_SPAWN_AT") != "":   # tests: "x,z,heading" (e.g. read off an F8 ride log) -> start there; Backspace comes back here
		var sxz := Env.s("BMX_SPAWN_AT").split(",")
		sp = Vector3(float(sxz[0]), float(sxz[2]) if sxz.size() > 2 else 0.0, float(sxz[1]))
		phys.reset_at(sp.x, sp.z, sp.y)
	if sp != Vector3.ZERO: terrain.update_stream(sp.x, sp.z, INF)
	if Env.s("BMX_START_V") != "": phys.v = float(Env.s("BMX_START_V"))   # tests: roll in at this speed
	rider.reset_pose()
	_snap_prev()
	cam.snap_to(Vector3(phys.x, phys.y + 0.5, phys.z))
	if level == "": place_start_tv()
	# the area you start in: its banner once the screen has faded in
	biome_cur = terrain.biome_name(phys.x, phys.z)
	biome_next = ""; biome_hold = 0
	if area_title: area_title.show_area(biome_cur, 1.6)
	if ghost: ghost.start_run()   # a new run from the start: the last one saved if it was the best, this world's ghost loaded

var start_tv: CrtTv
const START_TV_SCALE := 2.5   # oversized: ~0.95 m wide
const START_TV_AHEAD := 10.0
const START_TV_SIDE := 5.5

## the old CRT TV from the boot intro, dumped on the ground beside the start of every world, facing the rider:
## it switches on to the RUNOUT card a moment after the ride starts and stays on
func place_start_tv() -> void:
	if OS.get_environment("BMX_NO_TV") != "" or not CrtTv.assets_ok(): return
	if start_tv == null:
		start_tv = CrtTv.new()
		start_tv.light_energy = 3.0
		start_tv.light_range = 7.0
		start_tv.mat.set_shader_parameter("gain", 5.0)
		add_child(start_tv)
	var fwd := Vector3(cos(phys.heading), 0.0, -sin(phys.heading))
	var side := Vector3(-fwd.z, 0.0, fwd.x)
	var at := Vector3(phys.x, 0.0, phys.z) + fwd * START_TV_AHEAD + side * START_TV_SIDE
	var to_cam := (Vector3(phys.x, 0.0, phys.z) - fwd * 4.0 - at).normalized()   # where the ride camera starts
	var yaw := atan2(to_cam.x, to_cam.z) + deg_to_rad(8.0)   # glass (+Z) towards it, a little askew
	var b := Basis(Vector3.UP, yaw)
	# sit it on the ground: lowest of its four feet on the drawn ground, tilted to the slope
	var hx := CrtTv.SIZE.x * 0.5 * START_TV_SCALE; var hz := CrtTv.SIZE.z * 0.5 * START_TV_SCALE
	var hs := []
	for c in [Vector2(-hx, -hz), Vector2(hx, -hz), Vector2(-hx, hz), Vector2(hx, hz)]:
		var p: Vector3 = at + b * Vector3(c.x, 0.0, c.y)
		hs.append(terrain.top_height(p.x, p.z))
	var pitch := atan2(((hs[0] + hs[1]) - (hs[2] + hs[3])) * 0.5, hz * 2.0)   # back higher -> tips forward
	var roll := atan2(((hs[0] + hs[2]) - (hs[1] + hs[3])) * 0.5, hx * 2.0)
	b = b * Basis(Vector3.RIGHT, pitch) * Basis(Vector3.BACK, -roll) * Basis.from_scale(Vector3.ONE * START_TV_SCALE)
	at.y = (hs[0] + hs[1] + hs[2] + hs[3]) * 0.25 - 0.04
	start_tv.transform = Transform3D(b, at)
	_start_tv_on(true)
	start_tv.power_on(1.4)

## the start TV (shadowed glow light, live screen, 6 static voices) cost ~1.5 ms of GPU a frame for the whole
## ride; ridden past START_TV_CULL it is hidden and frozen, and comes back on if the rider returns
const START_TV_CULL := 80.0
func _start_tv_on(on: bool) -> void:
	if start_tv == null or start_tv.visible == on: return
	start_tv.visible = on
	start_tv.process_mode = Node.PROCESS_MODE_INHERIT if on else Node.PROCESS_MODE_DISABLED

func _cull_start_tv(at: Vector3) -> void:
	if start_tv == null: return
	var p := start_tv.global_position
	_start_tv_on(Vector2(at.x - p.x, at.z - p.z).length() < START_TV_CULL)

const BAIL_HOLD_MS := 350   # holding bail this long throws the rider off; a shorter tap resets to the trail
var _bail_down := -1        # tick (ms) the bail key went down, -1 = not held

## fallen off a rope bridge into its crevasse (no way out down there): stand up again on the nearer rim,
## facing the bridge
func _out_of_crevasse() -> void:
	for rb in terrain.ropes:
		var l: Vector2 = rb.local(phys.x, phys.z)
		if l.x < 0.0 or l.x > rb.length or absf(l.y) > 8.0:
			continue
		# got up on (or right beside, at its height) the deck: back in the middle of the planks, lined up with the
		# bridge whichever way is nearer the bike's heading. Stood up as it fell, crosswise on a 1.1 m deck, the
		# first pedal stroke rode off the side
		var mid: float = rb.sim.Height(l.x, 0.0, 0.0)
		if l.x > rb._u0 and l.x < rb._u1 and not is_nan(mid) and absf(mid - phys.y) < 1.0:
			var c: Vector2 = rb.world(l.x, 0.0)
			var fwd_h := atan2(-rb._dz, rb._dx)
			var hd := fwd_h if absf(BikePhysics.ang_diff(fwd_h, phys.heading)) < PI / 2 else fwd_h + PI
			terrain.rope_ref_y = mid
			phys.reset_at(c.x, c.y, hd)
			_snap_prev()
			return
		var near_start: bool = l.x < rb.length * 0.5
		var rim: Vector2 = rb.world(-2.5 if near_start else rb.length + 2.5, 0.0)
		if phys.y > terrain.height(rim.x, rim.y) - 3.0:
			continue
		terrain.rope_ref_y = INF
		phys.reset_at(rim.x, rim.y, atan2(-rb._dz, rb._dx) if near_start else atan2(rb._dz, -rb._dx))
		_snap_prev()
		cam.snap_to(Vector3(phys.x, phys.y + 0.5, phys.z))
		flash("Back on the rim")
		return

## a tap on bail: stand the rider back up on the nearest point of the trail, facing along it (not a new ride:
## the computer, trip and world stay)
func reset_to_trail() -> void:
	if terrain.has_method("level_reset"):   # a test level: back before the feature you were on
		level_reset_to(terrain.level_reset(phys.x, phys.z))
		flash("Again")
		return
	var tc: TrailCourse = terrain.field.course if terrain and terrain.field else null
	if tc == null or tc.n < 2: return
	_reset_draw_state()
	var best := 0
	var bd := INF
	for i in tc.n:
		var d: float = (tc.X[i] - phys.x) * (tc.X[i] - phys.x) + (tc.Z[i] - phys.z) * (tc.Z[i] - phys.z)
		if d < bd: bd = d; best = i
	var tx: float = tc.X[best]
	var tz: float = tc.Z[best]
	if phys.crash_on: get_up()
	if flying_cam and is_instance_valid(flying_cam): flying_cam.queue_free()
	flying_cam = null
	if blood: blood.clear()
	if bd > 40.0 * 40.0: terrain.update_stream(tx, tz, INF)   # a long way: load it first
	phys.reset_at(tx, tz, atan2(-tc.TZ[best], tc.TX[best]))
	_out_of_crevasse()
	rider.reset_pose()
	_snap_prev()
	cam.snap_to(Vector3(tx, phys.y + 0.5, tz))
	if hud: hud.trail_i = -1
	flash("Back on the trail")
## a test level: stand at sp = (x, heading, z), at rest (tries / the bail tap)
func level_reset_to(sp: Vector3) -> void:
	_reset_draw_state()
	if phys.crash_on: get_up()
	if flying_cam and is_instance_valid(flying_cam): flying_cam.queue_free()
	flying_cam = null
	if blood: blood.clear()
	phys.reset_at(sp.x, sp.z, sp.y)
	rider.reset_pose()
	_snap_prev()
	cam.snap_to(Vector3(sp.x, phys.y + 0.5, sp.z))
	if lab: lab.on_reset()
## tests (BMX_TRAIL_FEAT=drop|arch|N|x<metres>|tech): 70 m up the trail from the Nth drop / the first rock arch -> (x, heading, z)
func _feature_spawn(what: String) -> Vector3:
	var C: TrailCourse = terrain.field.course
	var idx := -1
	if what in ["gorge", "rope", "woodDrop", "skinny", "woodKicker", "bridge"]:
		for rf in terrain.field.route_feats:
			if rf.type == what:
				var gi := int(rf.s / TrailCourse.STEP)
				print("FEATSPAWN ", what, " s=", rf.s, " at=%.2f,%.2f dir=%.4f,%.4f" % [rf.x, rf.z, rf.dx, rf.dz])
				if what == "rope" and Env.s("BMX_FEAT_BACK") == "":   # rope: 6 m before the trees, on its axis
					return Vector3(rf.x - rf.dx * 6.0, -atan2(rf.dz, rf.dx), rf.z - rf.dz * 6.0)
				var gj := maxi(2, gi - (int(Env.s("BMX_FEAT_BACK")) if Env.s("BMX_FEAT_BACK") != "" else 30))
				return Vector3(C.X[gj], -atan2(C.TZ[gj], C.TX[gj]), C.Z[gj])
		return Vector3.ZERO
	if what == "flowtrail":   # 30 m before the first flow jump trail
		if C.flow_starts.size() > 0:
			var j4 := maxi(2, C.flow_starts[0] - 15)
			print("FEATSPAWN flowtrail idx=%d at %.0f,%.0f" % [C.flow_starts[0], C.X[j4], C.Z[j4]])
			return Vector3(C.X[j4], -atan2(C.TZ[j4], C.TX[j4]), C.Z[j4])
		print("FEATSPAWN flowtrail none")
		return Vector3.ZERO
	if what == "forest":   # 30 m before the first forest singletrack (TrailCourse.FOREST)
		for i in C.n:
			if C.KD[i] == TrailCourse.FOREST:
				var j3 := maxi(2, i - 15)
				print("FEATSPAWN forest idx=%d at %.0f,%.0f" % [i, C.X[j3], C.Z[j3]])
				return Vector3(C.X[j3], -atan2(C.TZ[j3], C.TX[j3]), C.Z[j3])
		print("FEATSPAWN forest none")
		return Vector3.ZERO
	if what.begins_with("x") or what.begins_with("s") or what == "tech":   # s<metres> (or the old x<metres>): that far along the trail; tech: the first tight hairpin stack past the first mountain
		var x0 := float(what.substr(1)) if what != "tech" else 1500.0
		for i in C.n:
			if i * TrailCourse.STEP >= x0 and (what != "tech" or absf(C.KAP[i]) > 0.1):
				var j2 := maxi(2, i - (20 if what == "tech" else 0))
				print("FEATSPAWN %s idx=%d at %.0f,%.0f" % [what, i, C.X[j2], C.Z[j2]])
				return Vector3(C.X[j2], -atan2(C.TZ[j2], C.TX[j2]), C.Z[j2])
		return Vector3.ZERO
	if what == "arch":
		var best := 1 << 30
		for kk in C.chunk_arches:
			for code in C.chunk_arches[kk]:
				best = mini(best, code >> 1)
		idx = best if best < (1 << 30) else -1
	elif not C.drops.is_empty():
		idx = C.drops[mini(int(what) if what.is_valid_int() else 0, C.drops.size() - 1)][1] - 6
		idx += int(what.get_slice(":", 1)) if what.contains(":") else 0
	if idx < 0:
		return Vector3.ZERO
	var j := maxi(2, idx - 35)
	print("FEATSPAWN %s idx=%d at %.0f,%.0f" % [what, idx, C.X[j], C.Z[j]])
	return Vector3(C.X[j], -atan2(C.TZ[j], C.TX[j]), C.Z[j])


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
	if e.is_action_pressed("photo") and not e.is_echo() and (photo or replay_on): toggle_photo(); return   # (also a replay frame)
	if replay_on: return   # (the replay takes its own keys in its _input)
	if e is InputEventKey and e.pressed and not e.echo and e.keycode == KEY_INSERT and not photo:   # Pose Lab
		toggle_pose_lab(); return
	if e.is_action_pressed("replay") and not e.is_echo() and not photo:
		if not open_replay(): flash("NO REPLAY YET")
		return
	if e.is_action_pressed("photo") and not e.is_echo(): toggle_photo(); return
	if e.is_action_pressed("save_log") and not e.is_echo():   # the last 60 s of physics + inputs to a CSV
		var lp := CrashLog.report("manual", "saved with the save-log button")   # report + ride log + recent log lines
		# all caps = the loud pop (the quiet info line went unnoticed), with the folder it went to
		flash(("LOG SAVED · CRASHLOGS/" + lp.replace("\\", "/").get_file().to_upper()) if lp != "" else "LOG NOT SAVED")
		return
	if e.is_action_pressed("profiler") and not e.is_echo() and not (e is InputEventKey and (e.ctrl_pressed or e.shift_pressed)):
		toggle_profiler()
		return
	if e.is_action_pressed("debug_draw") and not e.is_echo():
		if DebugOverlay.available(): flash("Physics overlay " + ("on" if DebugOverlay.toggle() else "off"))
		else: flash("Debug Draw 3D addon not loaded")
		return
	if photo: return
	# pad B with a side card up (P / K / L, demo tuning) closes it, like a console back, instead of a bail tap
	if e is InputEventJoypadButton and e.is_action_pressed("ui_cancel") and hud and hud.card and hud.card.visible:
		hud.close_sides()
		_bail_down = -1
		get_viewport().set_input_as_handled()
		return
	if e.is_action_pressed("demo") and not e.is_echo(): set_demo(demo == null); return
	if e.is_action_pressed("map") and not e.is_echo(): open_map(); return
	if e.is_action_pressed("new_world") and not e.is_echo(): respawn(true)
	elif e.is_action_pressed("respawn") and not e.is_echo(): respawn(false)
	elif e.is_action_pressed("bail") and not e.is_echo():   # tap = back on the nearest trail, hold = bail
		_bail_down = Time.get_ticks_msec()
	elif e.is_action_released("bail") and _bail_down >= 0:
		_bail_down = -1
		reset_to_trail()
	elif e.is_action_pressed("gear_easier") and not e.is_echo(): _shift(1)
	elif e.is_action_pressed("gear_harder") and not e.is_echo(): _shift(-1)
	elif e.is_action_pressed("camera_next") and not e.is_echo():
		flash(cam.next_mode())
		if level == "": Settings.data["camera"] = cam.mode; Settings.save()   # (a level's own views aren't saved)
	elif e.is_action_pressed("next_bike") and not e.is_echo():
		var ids := GameState.BIKES.keys()
		GameState.bike_id = ids[(ids.find(GameState.bike_id) + 1) % ids.size()]
		GameState.save()
		get_parent().restart_ride.call_deferred()
	elif e.is_action_pressed("hop") and phys.crash_on:
		phys.crash_armed = true

func _shift(d: int) -> void:
	if not phys.geared:
		flash("Single speed"); hud.gear_blocked(); return
	if phys.shift(d):
		hud.gear_changed(phys.gear == 0 or phys.gear == phys.cogs.size() - 1)
		if audio: audio.shift(d)
	else:
		hud.gear_blocked()

## demo mode: an AI rider (game/demo_pilot.gd) supplies the input instead of the keys / pad, F2 hands it back
var demo: DemoPilot = null

func set_demo(on: bool) -> void:
	if on == (demo != null): return
	if on and terrain is PlaygroundTerrain:   # the test playground: its test rider repeats one feature / lane
		demo = PlaygroundPilot.new(terrain.course)
	else:
		demo = DemoPilot.new() if on else null
	phys.test_rider = demo is PlaygroundPilot   # (its stronger landing help: test runs only)
	if not on:
		for a in ["pedal", "brake", "steer_left", "steer_right", "hop", "sprint"]: Input.action_release(a)
	if demo is PlaygroundPilot:
		flash("TEST RIDER on  -  STOP / F2: ride yourself")
		if diag: diag.pilot_changed()
	else:
		flash("DEMO RIDER on  -  P: tune it live  ·  F2: ride yourself" if on else "You ride")
		if diag: diag.pilot_changed()

func _read_input() -> Dictionary:
	if not input_enabled:
		return {"throttle": 0.0, "brake": 0.0, "steer": 0.0, "hop": false, "sprint": false, "body_fwd": 0.0, "body_lean": 0.0}
	if lab:   # the playground replaying a recorded run
		var rp = lab.replay_input()
		if rp != null: return rp
	if not line_play.is_empty():   # re-riding a recorded line (replay: L)
		var lp = line_input()
		if lp != null: return lp
	if demo != null and not photo:
		var dout: Dictionary = demo.tick(self, get_physics_process_delta_time())
		if Env.s("BMX_BODY") != "":   # tests: a scripted body stick (BMX_BODY=...) rides along with the test / demo rider
			dout.body_lean = Input.get_action_strength("body_left") - Input.get_action_strength("body_right")
			dout.body_fwd = Input.get_action_strength("body_fwd") - Input.get_action_strength("body_back")
		return dout
	var steer := Input.get_action_strength("steer_left") - Input.get_action_strength("steer_right")
	# a thumbstick needs a curve: fine near the centre (the first bit of stick only tips the bike in a little),
	# full lock at the edge. Keys (all or nothing) are unaffected. Steering response (Settings) scales it
	var expo: float = float(Settings.get_v("pad_expo")) if Settings.pad_active else 1.0
	steer = signf(steer) * pow(absf(steer), expo / maxf(0.3, float(Settings.get_v("steer_sens"))))
	# the rider's body (gamepad right stick, numpad on keys): round stick gate -> square, so diagonals reach full
	var bf := Input.get_action_strength("body_fwd") - Input.get_action_strength("body_back")
	var bl := Input.get_action_strength("body_left") - Input.get_action_strength("body_right")
	# a thumb is never exactly on an axis: a side lean always carries a little fore / aft and the other way
	# round. Near an axis the other one is faded out (side lean within ~15 deg of sideways = no fore / aft,
	# full again by ~35 deg), so leaning into a turn can't pull a manual or a tuck by accident; plus a small
	# round deadzone for a worn stick
	# (in the air the stick is a 360 deg attitude control: no axis fade there. Rolling the stick round in the air it
	# snapped the off axis from 0 to full over 20 deg of stick: the bike jerked, worst with both sticks working,
	# 2026-11-23. BMX_OLD_AIRFADE=1 = as before)
	var mag := Vector2(bf, bl).length()
	if mag < 0.1:
		bf = 0.0; bl = 0.0
	else:
		var ang := atan2(absf(bf), absf(bl))   # 0 = pure side, PI/2 = pure fore / aft
		var k := (mag - 0.1) / 0.9 / mag
		var fade := 0.0 if (phys != null and phys.air and not _OLD_AIRFADE) else 1.0
		bf *= k * lerpf(1.0, BikePhysics.smooth01((ang - deg_to_rad(15.0)) / deg_to_rad(20.0)), fade)
		bl *= k * lerpf(1.0, BikePhysics.smooth01((PI / 2 - ang - deg_to_rad(15.0)) / deg_to_rad(20.0)), fade)
	var bm := maxf(absf(bf), absf(bl))
	if bm > 0.01:
		var sq := minf(Vector2(bf, bl).length() / bm, 1.4142)
		bf = clampf(bf * sq, -1, 1); bl = clampf(bl * sq, -1, 1)
	# the arrow keys as the rider's body (2026-11-24): a key is all or nothing, where a thumb would hold part way.
	# ↓ held rolling sits on the manual's balance point (full back is past its edge: you'd fall off the back), full at
	# a lip (the back flip) and in the air; ← / → lean to KB_SIDE, a whip / tabletop (the stick's spin edge stays
	# the pad's: a key held into a lip mustn't spin you off every jump you carve into)
	if not Settings.pad_active and phys != null:
		if bf < 0.0 and not phys.air and phys.lip_state != 2: bf = maxf(bf, -BikePhysics.kb_back_cap())
		bl = clampf(bl, -KB_SIDE, KB_SIDE)
	# the left stick pulled back (it only steers; "both sticks back" can be asked for to start a manual, manBothSticks)
	var l_back := 0.0
	if Settings.pad_active and not Settings._test_run:
		var pads := Input.get_connected_joypads()
		if not pads.is_empty(): l_back = maxf(0.0, Input.get_joy_axis(pads[0], JOY_AXIS_LEFT_Y))
	if Env.s("BMX_LEFT_BACK") != "": l_back = float(Env.s("BMX_LEFT_BACK"))   # tests
	return {
		"pad": Settings.pad_active,
		"ws_air": bool(Settings.get_v("kb_ws_air")),   # classic keys: W / S tilt in the air / throw flips too
		"left_back": l_back,
		"body_fwd": bf,
		"body_lean": bl,
		"throttle": Input.get_action_strength("pedal"),
		"brake": Input.get_action_strength("brake"),
		"brake_front": Input.get_action_strength("brake_front"),
		"brake_rear": Input.get_action_strength("brake_rear"),
		"steer": clampf(steer, -1, 1),
		"hop": _held_ok("hop"),
		"sprint": _held_ok("sprint"),
	}

## a menu button that is also a ride action (A = sprint, X = hop) and was still held when the ride went on
## (resume, RACE, a closed menu) does nothing until it is let go
var _swallowed := {}
func swallow_held() -> void:
	for a in ["sprint", "hop"]:
		if Input.is_action_pressed(a): _swallowed[a] = true

func _held_ok(a: String) -> bool:
	var down := Input.is_action_pressed(a)
	if _swallowed.has(a):
		if down: return false
		_swallowed.erase(a)
	return down

## tests (BMX_BRAKETURN): which values vibrate - per value, how often its step-to-step change flips sign
## with a real size (a vibration), and the biggest such flip
var _base_bins := {}
var _v_prev_fx := 0.0; var _acc_fx := 0.0; var _surge := 0.0   # speed feel: last speed, its acceleration (per physics step), surge
var ride_log := RideLog.new()   # the last 60 s, saved with R3 / F8 (save_log)
var _log_lift := 0.0
const LIFT_UP := 2.4     # m/s the drawn bike may rise to clear its tyres off the ground (4 cm a frame at 60 fps)
const LIFT_DOWN := 0.6   # m/s it settles back
var _lift_s := 0.0       # the eased tyre-unclip lift
const AIR_SHARE_EASE := 0.08   # s: back on the ground the air offset eases out (it popped the bike up in one frame)
var _air_dlt := Vector3.ZERO
static var _OLD_AIRSHARE_SNAP := OS.get_environment("BMX_OLD_AIRSHARE_SNAP") != ""
const AIR_SHARE := 0.8   # in the air the drawn bike moves this share of the rider's hip moves against it (the bike is ~1/6 of the weight)
static var _OLD_AIRSHARE := OS.get_environment("BMX_OLD_AIRSHARE") != ""
var _frame_y := NAN      # where the physics put the frame this frame (before the lift): what the rider's legs feel
var jitter_on := Env.s("BMX_JITTER_ALL") != ""
var _jit_skip := 0
var _berm_hold := 0.0
var _yaw_s := 0.0; var _turn_s := 0.0; var _aspin_s := 0.0; var _atilt_s := 0.0; var _blat_s := 0.0; var _awhip_s := 0.0
var _jit_head := Vector3.INF
var _jit := {}

## Motion cap (drawn only): every drawn part of rider + bike that the physics drives follows it on a stiff, critically
## damped spring with a top speed and acceleration a real body / bike can reach (MCAP: key -> [rad or m per s,
## per s²]). Normal riding it tracks within ~0.03 s; a single bad step (a grip limit snapping, a bump spike, a
## clamp letting go) can no longer jolt the torso, the head or the bike. The physics and the ride feel are untouched
const MCAP := {
	"bike_lean": [10.0, 160.0], "steer": [9.0, 200.0], "counter": [7.0, 110.0], "head_roll": [8.0, 120.0],
	"lat_g": [6.0, 80.0], "hip_shift": [1.6, 30.0], "absorb": [5.0, 220.0], "body_stick": [6.0, 80.0],
}
var _mc := {}
var _lean_c := 0.0; var _steer_c := 0.0   # this frame's capped bike lean / bars (the bike and the rider's pose share them)
## the bars as drawn (2026-11-23, research review #5; drawing only, the physics' steer is unchanged). The physics' steer is
## the turn on the ground; the bars turn about the tilted head tube and a leaned wheel turns more on the ground than the
## bars (Meijaard 2007 App. A: tan(ground) = tan(bars) cos(head tilt) / cos(lean)). On top: the countersteer a real bike
## shows as it rolls into / out of a lean (Limebeer & Sharp 2006 figs. 16-17: the bars flick the other way for a moment),
## a short damped kick when the front is knocked by rocks / roots (~7 Hz, a DH front doesn't shimmy by itself), and the
## bars flopping into the lean with a foot down. BMX_OLD_BARS=1 = the physics' steer as before
const HEAD_TILT := 0.47       # rad, the head tube from vertical (63 deg head angle)
const BAR_CS_K := 0.03        # countersteer: rad of bars per rad/s of roll
const BAR_CS_MAX := 0.07
const BAR_KICK_HZ := 7.0
const BAR_KICK_Z := 0.25
const BAR_KICK_K := 0.07      # rad of bars per rad/s of knock
const BAR_FLOP := 0.6         # bars turned into the dab lean, x the lean
const BAR_HIT_FROM := 1.0     # m/s: smaller changes of the front wheel's upward speed don't kick the bars
const BAR_HIT_K := 0.6        # rad/s of bar swing per m/s of hit past that
var _vwf_prev := 0.0
var _bar_kick := 0.0; var _bar_kick_v := 0.0
var _OLD_BARS := Env.s("BMX_OLD_BARS") != ""
func _bar_draw(st: BikePhysics, dt: float, dab_lean: float) -> float:
	if _OLD_BARS or st.crash_on:
		_bar_kick = 0.0; _bar_kick_v = 0.0
		return st.steer
	var ln := clampf(st.bike_lean, -1.3, 1.3)
	var sd: float = atan(tan(clampf(st.steer, -1.2, 1.2)) * cos(ln) / cos(HEAD_TILT))
	var va := absf(st.v)
	if not st.air:
		sd -= clampf(st.lean_v * BAR_CS_K, -BAR_CS_MAX, BAR_CS_MAX) * smoothstep(3.0, 7.0, va)
	# the kick: a damped spring pushed by the knock (in sub-steps: 7 Hz at 30 fps is past what one Euler step holds)
	var w := TAU * BAR_KICK_HZ
	var steps := maxi(1, ceili(dt * 240.0))
	var h := dt / steps
	var push := 0.0 if st.air else st.knock * BAR_KICK_K
	# a hit on the front wheel (its upward speed jumping: a rock, a root, a landing) knocks the bars one way or the
	# other (the side the wheel was hit on: the knock's side, else a fixed hash of where it happened)
	var dvw: float = st.vw_f - _vwf_prev
	_vwf_prev = st.vw_f
	if not st.air and absf(dvw) > BAR_HIT_FROM:
		var side: float = signf(st.knock) if absf(st.knock) > 0.02 else (1.0 if sin(st.x * 7.3 + st.z * 3.1) > 0.0 else -1.0)
		_bar_kick_v += side * (absf(dvw) - BAR_HIT_FROM) * BAR_HIT_K * smoothstep(2.0, 6.0, va)
	for i in steps:
		_bar_kick_v += (-w * w * (_bar_kick - push) - 2.0 * BAR_KICK_Z * w * _bar_kick_v) * h
		_bar_kick += _bar_kick_v * h
	_bar_kick = clampf(_bar_kick, -0.08, 0.08)
	sd += _bar_kick
	sd += BAR_FLOP * dab_lean
	# (air step 3) a tabletop: the bike laid over in the air with the bars turned AGAINST the lay-over (the rider pushes the
	# low-side grip forward) - drawing only. BMX_OLD_TABLETOP=1 = straight bars
	if st.air and Env.s("BMX_OLD_TABLETOP") == "":
		sd -= clampf(st.bike_lean * BAR_TABLE, -0.5, 0.5) * st.air_k
	# steer in the air / the landing carve (drawing only; Ride > Jumps > Steer in the air > barCarve, 0 = straight bars as before):
	# in the air the bars turn a little into the steered / aimed turn, and the carve at touch-down bites them in and lets go
	var bc: float = float(Tune.v.get("barCarve", 0.5))
	if bc > 0.0 and Env.s("BMX_OLD_AIRSTEER") == "":
		if st.carve_now != _carve_seen:
			_carve_seen = st.carve_now
			_bar_carve = st.carve_now
		_bar_carve -= _bar_carve * minf(1.0, dt * 4.5)
		var inair: float = (st._air_steer_s + st._air_aim_s) * 0.4 if st.air else 0.0
		sd += (inair + _bar_carve * 0.8) * bc
	else:
		_bar_carve = 0.0
	if _bar_probe:   # tests: BMX_BAR_PROBE (BARS lines once a second: biggest kick, biggest countersteer, bars vs physics)
		_bp_k = maxf(_bp_k, absf(_bar_kick)); _bp_n = maxf(_bp_n, absf(st.knock)); _bp_c = maxf(_bp_c, absf(st.lean_v * BAR_CS_K)); _bp_d = maxf(_bp_d, absf(sd - st.steer))
		if int(t) != int(t - dt):
			print("BARS t=%.0f knock_max=%.2f x=%.0f v=%.1f kick_max=%.1fdeg countersteer_max=%.1fdeg bars_vs_physics_max=%.1fdeg" % [t, _bp_n, st.x, st.v * 3.6, rad_to_deg(_bp_k), rad_to_deg(minf(_bp_c, BAR_CS_MAX)), rad_to_deg(_bp_d)])
			_bp_k = 0.0; _bp_c = 0.0; _bp_d = 0.0; _bp_n = 0.0
	return sd
## Next-bend aim (Ride > Jumps > Steer in the air > airAim): while the bike is in the air, work out how far the trail's direction at
## the predicted touch-down (+ a few metres on, so the next bend counts) is turned from the travel direction, and hand it to the
## physics (`aim_off`, same sign as `slip`). Off the trail, backwards on it, or no airAim: 0. The nearest trail point is kept up to
## date every quarter second on the ground (a window round the last one), searched afresh when lost.
func _aim_update() -> void:
	var ph := phys
	ph.aim_off = 0.0
	if float(Tune.v.get("airAim", 0.6)) <= 0.0 or Env.s("BMX_OLD_AIRSTEER") != "": return
	var t = terrain
	if t == null or t.field == null or t.field.course == null: return
	var tc: TrailCourse = t.field.course
	if tc.n < 8: return
	if not ph.air:
		_aim_t -= 1.0 / 120.0
		if _aim_t > 0.0 and _aim_i >= 0: return
		_aim_t = 0.25
		var p0 := Vector2(ph.x, ph.z)
		if _aim_i < 0 or _aim_i >= tc.n: _aim_i = _aim_nearest(tc, p0, 0, tc.n)
		else: _aim_i = _aim_nearest(tc, p0, maxi(0, _aim_i - 60), mini(tc.n, _aim_i + 60))
		return
	if _aim_i < 0 or _aim_i >= tc.n: return
	var tl: float = clampf(ph._land_t if ph._land_t > 0.05 else 0.4, 0.15, 1.2)
	var ahead: float = absf(ph.v) * tl
	var cx: float = ph.x + cos(ph.course) * ahead
	var cz: float = ph.z - sin(ph.course) * ahead
	var j := _aim_nearest(tc, Vector2(cx, cz), maxi(0, _aim_i - 10), mini(tc.n, _aim_i + 40))
	if Vector2(tc.X[j], tc.Z[j]).distance_to(Vector2(cx, cz)) > 12.0: return
	var k := mini(tc.n - 1, j + 3)   # ~6 m past the landing: the line the rider will be turning onto
	var ang := atan2(-tc.TZ[k], tc.TX[k])
	var d := wrapf(ang - ph.course, -PI, PI)
	if absf(d) > 1.2: return         # the trail doesn't run the way he travels: riding across it / backwards, no aim
	ph.aim_off = d * smoothstep(0.06, 0.18, absf(d))

func _aim_nearest(tc: TrailCourse, p: Vector2, a: int, b: int) -> int:
	var best := a
	var bd := INF
	for i in range(a, b):
		var dx: float = tc.X[i] - p.x
		var dz: float = tc.Z[i] - p.y
		var d := dx * dx + dz * dz
		if d < bd: bd = d; best = i
	return best

var _bar_probe := Env.s("BMX_BAR_PROBE") != ""
var _bar_carve := 0.0; var _carve_seen := 0.0   # the landing carve's bar turn (decays) and the last carve seen
var _aim_i := -1; var _aim_t := 0.0              # next-bend aim: the trail index nearest the bike, its throttle clock
const BAR_TABLE := 0.4  # rad of bar turn per rad of lay-over in the air (a tabletop's bars against the lean)
var _bp_k := 0.0; var _bp_c := 0.0; var _bp_d := 0.0; var _bp_n := 0.0
func _mcap(key: String, target: float, dt: float) -> float:
	var mc: float = maxf(0.2, float(Tune.v.get("motionCap", 1.0)))   # (Ride › Smoothing: higher = looser caps)
	var lim: Array = [float(MCAP[key][0]) * mc, float(MCAP[key][1]) * mc]
	var s = _mc.get(key)
	if not is_finite(target):   # (stored, a NaN stayed in this channel until the next crash)
		return float(s[0]) if s != null else 0.0
	if s == null or not is_finite(float(s[0])) or not is_finite(float(s[1])):
		_mc[key] = [target, 0.0]
		return target
	# integrated in steps of at most 1/240 s: one step per drawn frame was unstable at 60 fps (w x dt = 1, the
	# damping overshot every frame and the legs buzzed up to 14 cm standing still, on a vsynced 60 Hz screen)
	var w := 60.0
	var n := maxi(1, ceili(dt * 240.0))
	var h := dt / n
	for _i in n:
		var acc := clampf((target - float(s[0])) * w * w - 2.0 * w * float(s[1]), -lim[1], lim[1])
		s[1] = clampf(float(s[1]) + acc * h, -lim[0], lim[0])
		s[0] = float(s[0]) + float(s[1]) * h
	# never further behind than a real lag would leave it (a long hitch / a respawn mid-move)
	if absf(target - float(s[0])) > lim[0] * 0.1: s[0] = target - signf(target - float(s[0])) * lim[0] * 0.1
	return float(s[0])
func _jitter_sample(key: String, val: float, thr: float) -> void:
	var j: Array = _jit.get(key, [NAN, 0.0, 0, 0.0, 0])   # last value, last delta, flips, biggest flip, samples
	if not is_nan(j[0]):
		var d: float = val - j[0]
		if absf(d) > thr and absf(j[1]) > thr and signf(d) != signf(j[1]):
			j[2] += 1; j[3] = maxf(j[3], absf(d - j[1]))
		j[1] = d
	j[0] = val; j[4] += 1
	_jit[key] = j

func head_rot_probe() -> float:   # tests: the drawn head's roll + yaw (rider space)
	var e: Vector3 = rider.head.transform.basis.get_euler()
	return e.x + e.y

var _jdump := PackedStringArray()   # tests (BMX_JDUMP=file.csv): every drawn frame's rider joints (rider space) + state
func jitter_report() -> void:
	if Env.s("BMX_JDUMP") != "":
		var fj := FileAccess.open(Env.s("BMX_JDUMP"), FileAccess.WRITE)
		if fj != null: fj.store_string("
".join(_jdump)); fj.close()
	var keys := _jit.keys()
	keys.sort_custom(func(a, b): return _jit[a][2] > _jit[b][2])
	for k in keys:
		var j: Array = _jit[k]
		print("JITTER %-12s flips=%4d / %d samples  biggest=%.4f" % [k, j[2], j[4], j[3]])

## tests (BMX_PERF=1): main-thread microseconds per section, averaged per drawn frame, printed every 5 s
var perf_on := Env.s("BMX_PERF") != ""
var _perf_acc := {}
var _perf_frames := 0
var _perf_print := 5.0
var _perf_last := 0
func _perf(key: String, t0: int) -> int:
	var now := Time.get_ticks_usec()
	if perf_on: _perf_acc[key] = _perf_acc.get(key, 0) + (now - t0)
	if _prof_rec: profiler.acc[key] = profiler.acc.get(key, 0) + (now - t0)
	return now

## F10: the live frame profiler (game/frame_profiler.gd), made on first use; it reads the same sections as BMX_PERF
var profiler = null   # FrameProfiler (loaded by path below: works before Godot's class cache knows the name)
var _prof_rec := false
func toggle_profiler(m: int = -1) -> void:
	if profiler == null:
		profiler = preload("res://scripts/game/frame_profiler.gd").new(self)
		add_child(profiler)
	if m < 0: profiler.cycle()
	else: profiler.set_mode(m)
	_prof_rec = profiler.recording()
	phys.prof = profiler.acc if _prof_rec else null   # (the physics' own stages, "p_step.*")
	if hud: hud.prof = profiler.acc if _prof_rec else null   # ("hud.*")
	if grime: grime.prof = profiler.acc if _prof_rec else null   # ("grime.*")
	if ragdoll: ragdoll.prof = profiler.acc if _prof_rec else null   # ("rag.*")

func _perf_report() -> void:
	var keys := _perf_acc.keys()
	keys.sort_custom(func(a, b): return _perf_acc[a] > _perf_acc[b])
	var line := "PERF t=%.0f frames=%d (ms per frame):" % [t, _perf_frames]
	for k in keys: line += " %s=%.3f" % [k, _perf_acc[k] / 1000.0 / maxi(_perf_frames, 1)]
	print(line)
	_perf_acc.clear(); _perf_frames = 0

# ---- the line: every physics step's input (and where the bike was) is kept, so a recorded line can be RIDDEN AGAIN
# (replay: L, or the Pose Lab's RESTART LINE): the snapshot of that moment is put back and the recorded inputs are fed in,
# live, so the rider rides the same line with whatever style (clips, keys, Anim Studio) is set NOW. The physics isn't
# changed by any of it: only what is drawn differs. Drift (how far the re-ride ends up from the recorded line) is measured
const LINE_MAX := 43200         # steps kept (6 min at 120 Hz)
var _line_buf := PackedFloat32Array()   # per step: the input values (_line_keys order), then x, z
var _line_keys: Array = []
var _line_bool := {}
var _line_base := 0             # absolute step index of the first kept step
var _line_n := 0                # absolute index of the next step to record
var line_play := {}             # the re-ride in progress: {keys, bools, buf, stride, i, n, snap, drift, drift_max}
var line_last := {}             # the last re-ride's start (RESTART LINE)


func _line_reset() -> void:
	_line_buf = PackedFloat32Array()
	_line_base = 0
	_line_n = 0
	line_play = {}
	line_last = {}


func _line_record(inp: Dictionary) -> void:
	if _line_keys.is_empty():
		for k in inp:
			_line_keys.append(k)
			_line_bool[k] = typeof(inp[k]) == TYPE_BOOL
	for k in _line_keys:
		var v = inp.get(k, 0.0)
		_line_buf.append((1.0 if v else 0.0) if typeof(v) == TYPE_BOOL else float(v))
	_line_buf.append(phys.x); _line_buf.append(phys.z)
	_line_n += 1
	if _line_n - _line_base > LINE_MAX:
		var drop := 3000
		var stride := _line_keys.size() + 2
		_line_buf = _line_buf.slice(drop * stride)
		_line_base += drop


func line_has(idx: int) -> bool:
	return not _line_keys.is_empty() and idx >= _line_base and idx < _line_n


## a copy of the recorded inputs from step idx to the end (what a re-ride feeds in)
func line_extract(idx: int) -> Dictionary:
	var stride := _line_keys.size() + 2
	return {"keys": _line_keys.duplicate(), "bools": _line_bool.duplicate(), "stride": stride, "i": 0, "n": _line_n - idx,
		"buf": _line_buf.slice((idx - _line_base) * stride), "idx": idx, "drift": 0.0, "drift_max": 0.0}


## the recording carries on from step idx (what came after is dropped: the ride writes it again)
func line_truncate(idx: int) -> void:
	if idx < _line_base or idx > _line_n: return
	_line_buf.resize((idx - _line_base) * (_line_keys.size() + 2))
	_line_n = idx


func line_start(line: Dictionary, snap: Array) -> void:
	line["snap"] = snap
	line_last = line.duplicate()
	line_last["i"] = 0
	line_play = line
	if Env.s("BMX_LINE_PROBE") != "": print("LINE start steps=%d from idx=%d" % [int(line.n), int(line.idx)])
	flash("RIDING THE LINE AGAIN  ·  %.0f s" % (float(line.n) / 120.0))


func line_stop(msg: String = "") -> void:
	if not line_play.is_empty():
		line_play = {}
		if msg != "": flash(msg)


## the next recorded input (null = the line is over: the player has the bike again)
func line_input():
	var lp: Dictionary = line_play
	var i: int = lp.i
	if i >= int(lp.n):
		var dm: float = lp.drift_max
		line_play = {}
		if Env.s("BMX_LINE_PROBE") != "": print("LINE finished steps=%d drift_max=%.3f drift_end=%.3f" % [int(lp.n), dm, float(lp.drift)])
		flash("LINE FINISHED  ·  drift max %.2f m, at the end %.2f m" % [dm, float(lp.drift)])
		return null
	var stride: int = lp.stride
	var b := i * stride
	var buf: PackedFloat32Array = lp.buf
	var keys: Array = lp.keys
	var inp := {}
	for ki in keys.size():
		var v := buf[b + ki]
		inp[keys[ki]] = (v > 0.5) if bool(lp.bools.get(keys[ki], false)) else v
	var d := Vector2(phys.x - buf[b + keys.size()], phys.z - buf[b + keys.size() + 1]).length()
	lp.drift = d
	lp.drift_max = maxf(float(lp.drift_max), d)
	lp.i = i + 1
	return inp


## RESTART LINE: back to where the re-ride started, the recorded inputs again from there
func line_restart() -> bool:
	if line_last.is_empty() or replay == null: return false
	var ln: Dictionary = line_last.duplicate()
	ln["i"] = 0
	ln["drift"] = 0.0; ln["drift_max"] = 0.0
	var snap: Array = ln.snap
	replay.ride_from_snap(snap)   # (puts the snapshot back, the recording carries on from it)
	line_truncate(int(ln.idx))
	line_start(ln, snap)
	pose_hold = false
	return true


## where we are on the Pose Lab's jump timeline (0..1; -1 = not in a jump): approach + load by how far the preload
## crouch is, the pop just off the lip, the flight by the share of it flown (time since take-off over that + what is
## left, `_land_t`), reaching for the landing, then the landing fold coming back up. Read only: no physics change
func _pose_phase(dt: float, st, pi: Dictionary) -> float:
	if st.air:
		if not pose_hold: _pl_air += dt
		var left: float = maxf(st._land_t, 0.0)
		var t: float = 0.40 + 0.40 * clampf(_pl_air / maxf(_pl_air + left, 0.05), 0.0, 1.0)
		var rc: float = st.land_prep * st.land_reach
		if rc > 0.05: t = maxf(t, 0.80 + 0.10 * clampf(rc, 0.0, 1.0))
		return t
	_pl_air = 0.0
	var fold: float = float(pi.get("landFold", 0.0))
	if fold > 0.03: return 0.90 + 0.10 * (1.0 - clampf(fold, 0.0, 1.0))
	var pre: float = float(pi.get("preload", 0.0))
	var pfx: float = float(pi.get("popFx", 0.0))
	if pfx > 0.05: return 0.30 + 0.10 * (1.0 - clampf(pfx, 0.0, 1.0))
	if pre > 0.03: return 0.12 + 0.18 * clampf(pre, 0.0, 1.0)
	if st.prep > 0.05: return 0.12 * clampf(st.prep, 0.0, 1.0)
	return -1.0


## what a clip's trigger says right now, read from the physics state (read only): x = how much (0..1), y = which side
## (+1 / -1, for mirroring a clip). The Pose Lab clips (PoseKeys.TRIGGERS) are driven by these
func _clip_signal(trig: String, st) -> Vector2:
	match trig:
		"jump": return Vector2(1.0 if pose_t >= 0.0 else 0.0, 1.0)
		"whip": return Vector2(clampf(absf(_awhip_s) / 0.9, 0.0, 1.0), signf(_awhip_s) if _awhip_s != 0.0 else 1.0)
		"tabletop": return Vector2(clampf((absf(_blat_s) - 0.25) / 0.55, 0.0, 1.0) if st.air else 0.0, signf(_blat_s) if _blat_s != 0.0 else 1.0)
		"scrub": return Vector2(clampf(maxf(maxf(st.squash_fx, st.auto_absorb) * st.prep, st.squash * st.prep), 0.0, 1.0), 1.0)
		"backflip": return Vector2(clampf(st.flip_acc / 1.2, 0.0, 1.0) if st.air else 0.0, 1.0)
		"frontflip": return Vector2(clampf(-st.flip_acc / 1.2, 0.0, 1.0) if st.air else 0.0, 1.0)
		"spin": return Vector2(clampf(absf(st.yaw_rate) / 3.0, 0.0, 1.0) if st.air else 0.0, signf(st.yaw_rate) if st.yaw_rate != 0.0 else 1.0)
		"manual": return Vector2(clampf(float(st.man_a) / 0.5, 0.0, 1.0), 1.0)
		"stoppie": return Vector2(clampf(float(st.nose_a) / 0.4, 0.0, 1.0), 1.0)
		"corner": return Vector2(clampf(absf(st.bike_lean) / 0.6, 0.0, 1.0) if not st.air else 0.0, signf(st.bike_lean) if st.bike_lean != 0.0 else 1.0)
		"sprint": return Vector2(clampf(st.sprint * st.pedal, 0.0, 1.0), 1.0)
		"air": return Vector2(1.0 if st.air else 0.0, 1.0)
		"ground": return Vector2(0.0 if st.air else 1.0, 1.0)
		"always": return Vector2(1.0, 1.0)
	return Vector2(0.0, 1.0)


## all the clips of the library mixed into one set of pose offsets: each clip fades in / out by its trigger (a ramp over
## its fade times), reads its own timeline (the jump timeline, or seconds since it fired), is mirrored by the side it fired
## on, and the weighted offsets are summed. In the Pose Lab with SOLO on only the clip being edited plays, at full weight,
## at the playhead (so what you edit is what you see); SOLO off shows the whole library as in a ride
func _clips_mix(dt: float, st, pi: Dictionary) -> Dictionary:
	PoseKeys.live_t = -1.0
	if PoseKeys.clips.is_empty(): return {}
	var open: bool = pose_lab != null and pose_lab.is_open()
	var solo: bool = open and pose_lab.solo
	var out := {}
	if not solo and (not PoseKeys.enabled or dab_k >= 0.01): return out
	var step: float = clampf(dt, 0.0, 0.1)
	for ci in PoseKeys.clips.size():
		var c: Dictionary = PoseKeys.clips[ci]
		var is_cur: bool = ci == PoseKeys.cur
		if solo and not is_cur: continue
		if not solo and not bool(c.enabled): continue
		var sg: Vector2 = _clip_signal(str(c.trigger), st)
		var rt: Dictionary = PoseKeys.rt(c)
		var target: float = 1.0 if solo else sg.x
		var fade: float = float(c.fade_in) if target > float(rt.w) else float(c.fade_out)
		rt.w = move_toward(float(rt.w), target, step / maxf(fade, 0.01))
		if target > 0.02:
			rt.age = float(rt.age) + step
			rt.side = sg.y
		elif float(rt.w) < 0.01:
			rt.age = 0.0
		# where this clip is on its own timeline now
		var t_live: float = pose_t if str(c.time) == "jump" else clampf(float(rt.age) / maxf(float(c.length), 0.05), 0.0, 1.0)
		if is_cur: PoseKeys.live_t = t_live
		rt["t"] = t_live
		var t: float = t_live
		if solo: t = pose_lab.t_for_pose(t_live)
		if t < 0.0 or float(rt.w) < 0.002: continue
		var v: Dictionary = PoseKeys.eval_keys(c.ks, t, 1.0)
		if v.is_empty(): continue
		var wk: float = smoothstep(0.0, 1.0, float(rt.w)) * (1.0 if solo else float(c.strength))
		var flip: float = -1.0 if (bool(c.mirror) and float(rt.side) < 0.0 and not solo) else 1.0
		for id in v:
			var val: float = float(v[id]) * wk
			if flip < 0.0 and id in PoseKeys.MIRROR: val = -val
			out[id] = float(out.get(id, 0.0)) + val
	var tk: int = Time.get_ticks_msec() / 250
	if _clip_probe and tk != _clip_probe_k:   # tests: BMX_CLIP_PROBE=1, the clips with a weight, 4x a second
		_clip_probe_k = tk
		var act := []
		for c2 in PoseKeys.clips:
			if float(PoseKeys.rt(c2).w) > 0.01: act.append("%s=%.2f" % [c2.name, float(PoseKeys.rt(c2).w)])
		if not act.is_empty(): print("CLIPS air=%s active: %s" % [st.air, ", ".join(act)])
	if out.is_empty(): return out
	for id in out:
		var inf: Array = PoseKeys.ch_info(id)
		out[id] = clampf(float(out[id]) * PoseKeys.amount, float(inf[3]) * 1.5, float(inf[4]) * 1.5)
	return out


## the keys of the moment (PoseKeys) go into the pose inputs; a "bike under body" key turns the rider about the bottom
## bracket, and the limb targets (grips, pedals) are given in his turned space so the arms and legs follow the bike
func _pose_keys_apply(dt: float, st, pi: Dictionary, lt: Dictionary) -> void:
	PoseKeys.ensure_loaded()
	pose_t = _pose_phase(dt, st, pi)
	var pk: Dictionary = _clips_mix(dt, st, pi)
	pi["pk"] = pk
	_style_fill(st, pi, pk)
	_pk_bar = -float(pk.get("bar_steer", 0.0))   # (drawn bars turn, + = right (the rig's steer is + = left): used when the rig is posed, next frame)
	var rp: float = float(pk.get("rel_pitch", 0.0))
	var rr: float = float(pk.get("rel_roll", 0.0))
	if absf(rp) > 1e-4 or absf(rr) > 1e-4:
		var piv: Vector3 = rig.lean_g.to_local(rig.crank_n.global_position)
		var rb := Basis(Vector3(1, 0, 0), -rr) * Basis(Vector3(0, 0, 1), -rp)
		var rt := Transform3D(rb, piv - rb * piv)
		rider.transform = rt
		var inv := rt.affine_inverse()
		for k in ["handL", "handR", "footL", "footR"]: lt[k] = inv * (lt[k] as Vector3)
		for k in ["gripX_L", "gripX_R", "gripZ"]: lt[k] = inv.basis * (lt[k] as Vector3)
		pi["handL"] = lt.handL; pi["handR"] = lt.handR; pi["footL"] = lt.footL; pi["footR"] = lt.footR
		pi["gripX_L"] = lt.gripX_L; pi["gripX_R"] = lt.gripX_R; pi["gripZ"] = lt.gripZ
		_pk_rt_on = true
	elif _pk_rt_on:
		rider.transform = Transform3D.IDENTITY
		_pk_rt_on = false
	if _pk_rt_on:
		pi["wheelR"] = rider.to_local(rig.wheel_r.global_position)
		pi["wheelF"] = rider.to_local(rig.wheel_f.global_position)


## this frame's style numbers (names in style_names): the jump timeline, every clip's weight / trigger signal / own time,
## the channels the clips added, the physics signals the triggers read, the procedural pose inputs. The replay keeps one row
## per sample so the Style Inspector can show what the rider's style did (rebuilt names when the clip library changes)
func _style_fill(st, pi: Dictionary, pk: Dictionary) -> void:
	if _style_rev != PoseKeys.rev or style_names.is_empty():
		_style_rev = PoseKeys.rev
		var nm := PackedStringArray(["pose|t"])
		for c in PoseKeys.clips:
			nm.append("clip|%s|w" % c.name); nm.append("clip|%s|sig" % c.name); nm.append("clip|%s|t" % c.name)
		for id in PoseKeys.ch_ids(): nm.append("ch|" + id)
		for k in STYLE_SIG: nm.append("sig|" + k)
		for k in STYLE_DRV: nm.append("drv|" + k)
		style_names = nm
		style_row.resize(nm.size())
	var row := style_row
	var i := 0
	row[i] = pose_t; i += 1
	for c in PoseKeys.clips:
		var rt: Dictionary = PoseKeys.rt(c)
		row[i] = float(rt.w); row[i + 1] = _clip_signal(str(c.trigger), st).x; row[i + 2] = float(rt.get("t", -1.0))
		i += 3
	for id in PoseKeys.ch_ids():
		row[i] = float(pk.get(id, 0.0)); i += 1
	var sv := [absf(st.v) * 3.6, 1.0 if st.air else 0.0, st.bike_lean, st.air_tw, st.flip_acc, st.yaw_rate, float(st.man_a), float(st.nose_a), st.pop_fx, st.squash, st.prep, st.land_fold, st.air_pull]
	for v in sv:
		row[i] = float(v); i += 1
	for k in STYLE_DRV:
		row[i] = float(pi.get(k, 0.0)); i += 1


func toggle_pose_lab() -> void:
	if pose_lab == null:
		pose_lab = PoseLab.new()
		pose_lab.game = self
		add_child(pose_lab)
	pose_lab.toggle()


func _physics_process(dt: float) -> void:
	# photo mode / the trail map set time_scale 0, but physics ticks still come, with dt = 0: stepping the ride then
	# divided by zero (air yaw, pivot, wheel ground speed) and left NaNs in yaw_rate / spin_acc, and live keys fed it
	if dt <= 0.0:
		if rumble: rumble.stop()
		return
	if lab and lab.hold_physics():   # the playground's pause (N steps one tick): hold the drawn bike still
		_snap_prev()
		return
	if pose_hold:   # the Pose Lab's pause (its STEP runs ticks): the same, in any ride
		if pose_steps > 0: pose_steps -= 1
		else:
			_snap_prev()
			return
	var _pk := Time.get_ticks_usec()
	if _prof_rec: profiler.ticks += 1
	_snap_prev()
	var inp := _read_input()
	if _rope_hold > 0.0:   # tests (BMX_ROPE_STOP): brake to a stop on the bridge and stand there
		_rope_hold -= dt
		inp.throttle = 0.0; inp.sprint = false
		inp.brake = 1.0 if phys.v > 0.3 else 0.0
	_pk = _perf("p_input", _pk)
	terrain.rope_ref_y = phys.y
	if level_probe: level_probe.pre_step(dt, inp)
	if lab: lab.pre_step(inp)
	_line_record(inp)
	_aim_update()
	phys.step(dt, inp)
	if ruts: ruts.step(phys)
	if _SKIP: _skip_probe(dt, inp)
	if level_probe: level_probe.post_step(dt)
	if diag: diag.record(dt, inp)
	if _AIRJERK: _air_jerk_probe(inp)
	if lab: lab.post_step(dt, inp)
	_pk = _perf("p_bike_step", _pk)
	_rope_tick(dt)
	_pk = _perf("p_rope", _pk)
	if replay and input_enabled and not scenic and not title_world: replay.phys_snap()   # (rewind: "ride from here")
	# (crashed: the ragdoll's head / chest / pelvis relative to the bike's point, world axes: rider.J holds the last
	# riding pose while the ragdoll draws the body, so an F8 after a crash showed nothing of it)
	var log_j: Array = rider.J if rider else []
	if phys.crash_on and ragdoll and ragdoll.active and ragdoll.p.size() > 2:
		var bk := Vector3(phys.x, phys.y, phys.z)
		log_j = [(ragdoll.p[0] as Vector3) - bk, (ragdoll.p[1] as Vector3) - bk, (ragdoll.p[2] as Vector3) - bk]
	ride_log.record(dt, phys, inp, _log_lift, rig.position.y if rig else 0.0, log_j)
	_pk = _perf("p_ride_log", _pk)
	if jitter_on and not phys.crash_on:
		for kv in [["slip", phys.slip, 0.002], ["yaw_rate", phys.yaw_rate, 0.02], ["lean", phys.lean, 0.002], ["bike_lean", phys.bike_lean, 0.003],
				["counter", phys.counter, 0.003], ["steer", phys.steer, 0.003], ["hip_shift", phys.hip_shift, 0.001], ["body_x", phys.body_x, 0.001],
				["pitch", phys.pitch, 0.002], ["y", phys.y, 0.001], ["body_y", phys.body_y, 0.001], ["compress", phys.compress, 0.001], ["lat_a", phys.lat_a, 0.05], ["v", phys.v, 0.01],
				["heading", phys.heading, 0.001], ["knock", phys.knock, 0.02], ["bank", phys.bank, 0.002], ["bank_lean", phys.bank_lean, 0.002],
				["gx_lean", phys._gx_lean, 0.002], ["berm_k", phys.berm_k, 0.01], ["corner_g", phys.corner_g, 0.05], ["front_use", phys.front_use, 0.02],
				["lean_v", phys.lean_v, 0.05], ["slip_w", phys.slip_w, 0.02]]:
			_jitter_sample(kv[0], kv[1], kv[2])
	if phys.crash_on and getup_anim != null:
		_getup_step(dt, inp.hop)
	elif phys.crash_on:
		rider.pose_ragdoll(ragdoll.p, _ragdoll_roots())
		if Env.s("BMX_RAGSTART_DUMP") != "" and phys.crash_t < 0.25:   # tests: the ragdoll's first steps (world, relative to the bike)
			var bk := Vector3(phys.x, phys.y, phys.z)
			print("RAGSTART t=%.3f head=%s chest=%s pelvis=%s bike_v=%.2f" % [phys.crash_t, str(((ragdoll.p[0] as Vector3) - bk).snapped(Vector3.ONE * 0.01)), str(((ragdoll.p[1] as Vector3) - bk).snapped(Vector3.ONE * 0.01)), str(((ragdoll.p[2] as Vector3) - bk).snapped(Vector3.ONE * 0.01)), phys.v])
	_pk = _perf("p_ragdoll_pose", _pk)
	_jump_watch(dt)
	if not phys.is_sane():
		push_warning("physics went non-finite; restoring last good state")
		for k in _last_good: phys.set(k, _last_good[k])
		phys.v = 0; phys.vy = 0; phys.air = false; phys.w_init = false
		phys.reset_body()
	else:
		for k in ["x", "z", "y", "heading", "course", "pitch", "lean", "steer", "slip", "compress"]:
			_last_good[k] = phys.get(k)
	# (after the sanity check: a step that went non-finite must not reach the motors or the rumble's smoothing)
	if rumble:
		if input_enabled and not photo and not (paper_map and paper_map.busy()): rumble.update(dt, inp)
		else: rumble.stop()
	_pk = _perf("p_rumble", _pk)
	# speed feel's surge: the bike's acceleration per physics step (per drawn frame it came out 3-4x weaker at 400 fps)
	_acc_fx = (absf(phys.v) - _v_prev_fx) / dt
	_v_prev_fx = absf(phys.v)

## Hitch / jump watch (2026-11-25, user: "every couple of times the level lags and the rider gets teleported a couple
## of metres in one frame"): always on in rides, writes into the session log (crashlogs/run_*.log, F8 reports) so a
## real ride tells which it is. HITCH = a drawn frame longer than HITCH_MS (wall clock, with the physics ticks it ran:
## the physics runs at most 12 ticks a frame, so a 150 ms freeze shows as the rider jumping ~1.5-2 m); JUMP = the
## bike moved further in ONE physics step than its speed explains (something set its position).
const HITCH_MS := 80.0
var _hw_last := 0
var _hw_ticks := 0
var _jw_prev := Vector2(INF, INF)
var _jw_crash := false
func _hitch_watch() -> void:
	var now := Time.get_ticks_usec()
	var ms := (now - _hw_last) / 1000.0
	if _hw_last > 0 and ms > HITCH_MS and Engine.get_process_frames() > 300 and input_enabled and not scenic and not title_world and not photo and not get_tree().paused:
		CrashLog.note("HITCH frame_ms=%.0f phys_ticks=%d pos=(%.1f, %.1f) v=%.1f crashed=%s fps=%d" % [ms, _hw_ticks, phys.x, phys.z, phys.v, phys.crash_on, Engine.get_frames_per_second()])
	_hw_last = now
	_hw_ticks = 0

func _jump_watch(dt: float) -> void:
	_hw_ticks += 1
	var p := Vector2(phys.x, phys.z)
	if is_finite(_jw_prev.x) and phys.crash_on == _jw_crash:
		var d := p.distance_to(_jw_prev)
		var expect := absf(phys.v) * dt
		if d > expect * 2.0 + 0.25 and input_enabled and not scenic:
			CrashLog.note("JUMP %.2f m in one step (speed allows %.2f) from (%.1f, %.1f) to (%.1f, %.1f) v=%.1f air=%s crashed=%s" % [d, expect, _jw_prev.x, _jw_prev.y, p.x, p.y, phys.v, phys.air, phys.crash_on])
	_jw_prev = p
	_jw_crash = phys.crash_on

## rope bridges: the rider's weight (with every bump / landing: the ground's push n_load) and sideways push
## (the turn's reaction) go into the deck, the decks step, then the deck's sideways swing carries the bike
const RIDER_KG := 95.0
const ROPE_STROKE := 4.0   # m/s² sideways per pedal stroke
## turning on the bridge (user: "the bridge sway messes with our riding"): the turn's whole reaction went into the
## deck, the deck swung, and its swing carried the bike sideways under the rider: every turn fought itself. The
## rider's legs soak most of both
const ROPE_TURN_PUSH := 0.3   # share of the turn's sideways reaction that shoves the deck
const ROPE_CARRY := 0.4       # share of the deck's sideways swing that moves the bike with it
var rope_probe := Env.s("BMX_ROPE_PROBE") != ""
var _rope_pt := 0.0
var _rope_shot := Env.s("BMX_ROPE_SHOT")
var _rope_shot_i := 0
var _rope_hold := 0.0
var _rope_test_done := {}
const ROPE_SHOT_U := [3.0, 5.0, 8.0, 15.0, 23.0, 32.0, 40.0, 42.5, 45.0]
func _save_rope_shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
	print("ROPESHOT ", path)
## the hangers + hand ropes along both sides fence the deck in (user: "drive to the rope left or right, we crash
## at once": the bike used to ride straight off the plank edge = OFF THE BRIDGE!). A tyre reaching the fence is
## held inside it, the travel is turned along the bridge (a graze scrapes along the rope, speed scrubbed by how
## hard it went in) and the rope takes the push. Only ridden square into it fast is it a crash
const ROPE_RAIL := 0.15        # the tyres stay this far inside the deck ropes
const ROPE_RAIL_CRASH := 1.05  # rad into the rope ...
const ROPE_RAIL_CRASH_V := 7.0 # ... at more than this (m/s) = thrown over the hand rope
func _rope_rail() -> void:
	for b in terrain.ropes:
		if not b.fenced(phys.x, phys.z, phys.y):
			continue
		var fw := phys.fwd()
		var over := 0.0
		for d in [phys.L - phys.BB_REAR, -phys.BB_REAR, 0.0]:
			var l: Vector2 = b.local(phys.x + fw.x * d, phys.z + fw.z * d)
			# the deck ropes where they are now (the deck swings sideways under the rider, up to ~0.4 m)
			var e: Vector2 = b.sim.Edges(clampf(l.x, b._u0 + 0.05, b._u1 - 0.05))
			if is_nan(e.x):
				continue
			var o := 0.0
			if l.y > e.y - ROPE_RAIL: o = l.y - (e.y - ROPE_RAIL)
			elif l.y < e.x + ROPE_RAIL: o = l.y - (e.x + ROPE_RAIL)
			if absf(o) > absf(over):
				over = o
		if over == 0.0:
			return
		# back inside, across the bridge (its +w direction in world = (-dz, dx), from RopeBridge.world)
		var n: Vector2 = b.world(0.0, 1.0) - b.world(0.0, 0.0)
		phys.x -= n.x * over
		phys.z -= n.y * over
		if absf(phys.v) < 0.3:
			return
		var mv := Vector2(cos(phys.course), -sin(phys.course)) * signf(phys.v)
		var ax: Vector2 = b.world(1.0, 0.0) - b.world(0.0, 0.0)
		var along := mv.dot(ax)
		var across := mv.dot(n)
		if across * over <= 0.0:
			return   # already heading back in
		var ang := atan2(absf(across), absf(along))
		if ang > ROPE_RAIL_CRASH and absf(phys.v) > ROPE_RAIL_CRASH_V:
			phys.crash_pending = "INTO THE ROPES!"
			if rope_probe: print("ROPE rail crash ang=%.2f v=%.2f" % [ang, phys.v])
			return
		# turn the travel (and the bike with it) along the bridge, the way it was going
		var tgt: float = b.axis_angle() + (0.0 if along * signf(phys.v) >= 0.0 else PI)
		var dc := wrapf(tgt - phys.course, -PI, PI)
		phys.course += dc
		phys.heading += dc
		phys.v *= 1.0 - 0.55 * sin(ang)
		# the rope takes the push: it swings out and back
		var push := RIDER_KG * clampf(absf(phys.v) * sin(ang) * 30.0, 0.0, 40.0)
		b.push(phys.x, phys.z, 0.0, Vector3(n.x, 0, n.y) * signf(over) * push)
		if rope_probe: print("ROPE rail over=%.2f ang=%.2f v=%.2f" % [over, ang, phys.v])
		return


func _rope_tick(dt: float) -> void:
	if terrain.ropes.is_empty():
		return
	var rb = null
	if not phys.crash_on:
		if not phys.air:
			_rope_rail()
		rb = terrain.rope_under(phys.x, phys.z, phys.y)
		if not phys.air:
			# a wheel rolled off the side of a deck: down you go. Left to the ride physics, the bike hung on the plank
			# edge with one axle on the deck and one over the drop: an ~85 deg "slope" it sped up on without moving,
			# sunk into the planks, until it washed out a second later
			var fw := phys.fwd()
			for d in [0.0, phys.L - phys.BB_REAR, -phys.BB_REAR]:
				var px: float = phys.x + fw.x * d
				var pz: float = phys.z + fw.z * d
				var hit := false
				for b in terrain.ropes:
					if b.off_side(px, pz, phys.y) and terrain._height0(px, pz) < phys.y - 1.5:
						hit = true
						break
				if hit:
					phys.crash_pending = "OFF THE BRIDGE!"
					if rope_probe: print("ROPE off the side at d=%.2f" % d)
					break
	if rb != null and not phys.air:
		var h := phys.heading
		# sideways: the turn's reaction + each pedal stroke shoving the deck (like footsteps set a rope bridge swinging)
		var side := phys.lat_a * ROPE_TURN_PUSH + ROPE_STROKE * phys.pedal * sin(phys.crank)
		# the weight goes down through the two tyres (split as the physics loads them), not one point under the
		# cranks: one point folded the deck into a V the bike pitched about in. A wheel still on the rim or off
		# the end pushes on nothing (AddLoad ignores points off the deck), as it should
		var nf: float = phys.n_f if is_finite(phys.n_f) else 0.4
		var nr: float = phys.n_r if is_finite(phys.n_r) else 0.6
		var kf := clampf(nf / maxf(nf + nr, 1e-3), 0.0, 1.0)
		if phys.front_air: kf = 0.0
		elif phys.rear_air: kf = 1.0
		var fy := -RIDER_KG * clampf(phys.n_load, 0.0, 40.0)
		var fs := Vector3(sin(h), 0, cos(h)) * RIDER_KG * side
		var fw := phys.fwd()
		var df: float = phys.L - phys.BB_REAR
		var dr: float = -phys.BB_REAR
		rb.push(phys.x + fw.x * df, phys.z + fw.z * df, fy * kf, fs * kf)
		rb.push(phys.x + fw.x * dr, phys.z + fw.z * dr, fy * (1.0 - kf), fs * (1.0 - kf))
	terrain.ropes_step(dt)
	if rb != null and not phys.air:
		var c: Vector2 = rb.carry(phys.x, phys.z) * ROPE_CARRY
		phys.x += c.x
		phys.z += c.y
	if _rope_shot != "":   # tests: a screenshot as the rider passes each mark on a bridge (by place, not time)
		for b in terrain.ropes:
			var u: float = b.local(phys.x, phys.z).x
			while _rope_shot_i < ROPE_SHOT_U.size() and u > ROPE_SHOT_U[_rope_shot_i] and u < b.length + 8.0:
				_save_rope_shot.call_deferred("%s_u%02d.png" % [_rope_shot, int(ROPE_SHOT_U[_rope_shot_i])])
				_rope_shot_i += 1
	# tests by place on the first bridge: BMX_ROPE_STOP=u,secs brakes to a stop at u and stands secs (game time);
	# BMX_ROPE_BAIL=u bails at u (wall-clock test timers fire in the wrong place when the frame rate drops)
	if (Env.s("BMX_ROPE_STOP") != "" or Env.s("BMX_ROPE_BAIL") != "") and not phys.crash_on:
		var u0: float = terrain.ropes[0].local(phys.x, phys.z).x
		var st := Env.s("BMX_ROPE_STOP").split(",")
		if Env.s("BMX_ROPE_STOP") != "" and not _rope_test_done.has("stop") and u0 > float(st[0]) and u0 < terrain.ropes[0].length:
			_rope_test_done["stop"] = true
			_rope_hold = float(st[1]) if st.size() > 1 else 3.0
			print("ROPETEST stop at u=%.2f" % u0)
		if Env.s("BMX_ROPE_BAIL") != "" and not _rope_test_done.has("bail") and u0 > float(Env.s("BMX_ROPE_BAIL")) and u0 < terrain.ropes[0].length:
			_rope_test_done["bail"] = true
			phys.crash_pending = "BAIL!"
			print("ROPETEST bail at u=%.2f" % u0)
	if _rope_test_done.has("bail") and not _rope_test_done.has("getup") and phys.crash_on and getup_anim == null:
		_rope_test_done["bail_t"] = float(_rope_test_done.get("bail_t", 0.0)) + dt
		if _rope_test_done["bail_t"] > 2.5:   # the real get-up (animated), as a held hop does
			_rope_test_done["getup"] = true
			begin_getup()
			print("ROPETEST getup from (%.2f, %.2f, %.2f)" % [phys.x, phys.y, phys.z])
	if _rope_test_done.has("getup") and not _rope_test_done.has("upped") and not phys.crash_on:
		_rope_test_done["upped"] = true
		var lb: Vector2 = terrain.ropes[0].local(phys.x, phys.z)
		print("ROPETEST up at u=%.2f w=%.2f y=%.2f heading_off_axis=%.2f" % [lb.x, lb.y, phys.y,
			absf(BikePhysics.ang_diff(phys.heading, atan2(-terrain.ropes[0]._dz, terrain.ropes[0]._dx)))])
	if rope_probe and Env.s("BMX_ROPE_PROBE") == "tick":
		for b in terrain.ropes:
			var l: Vector2 = b.local(phys.x, phys.z)
			if l.x < -2.0 or l.x > b.length + 2.0: continue
			var f := Vector3(sin(phys.heading), 0, cos(phys.heading))
			print("RTICK t=%.3f u=%.2f w=%.2f on=%s g=%.3f y=%.3f vy=%.2f deck=%.3f wf=%.3f wr=%.3f n=%.1f cmp=%.3f p=%.3f air=%s fa=%s ra=%s v=%.1f" % [
				t, l.x, l.y, rb != null, terrain._height0(phys.x, phys.z), phys.y, phys.vy, b.deck_at(phys.x, phys.z), phys.w_f, phys.w_r, phys.n_load, phys.compress, phys.pitch,
				phys.air, phys.front_air, phys.rear_air, phys.v])
	elif rope_probe:
		_rope_pt -= dt
		if _rope_pt <= 0.0:
			_rope_pt = 0.25
			for b in terrain.ropes:
				var l: Vector2 = b.local(phys.x, phys.z)
				var mid: Vector3 = b.sim.Centre(0.5)
				print("ROPE u=%.1f w=%.2f on=%s y=%.2f deck=%.2f mid=(%.2f %.2f) v=%.1f air=%s crash=%s n_load=%.1f" % [
					l.x, l.y, rb != null, phys.y, b.deck_at(phys.x, phys.z), mid.y, mid.z, phys.v, phys.air, phys.crash_on, phys.n_load])


## torn-off limbs: joint -> where its free piece's root point is now (Rider.pose_ragdoll)
func _ragdoll_roots() -> Dictionary:
	if ragdoll.cut.is_empty(): return {}
	var out := {}
	for b in ragdoll.cut:
		out[b] = ragdoll.p[ragdoll.cut[b]]
	return out

func toggle_photo() -> void:
	if not photo and (phys == null or (paper_map and paper_map.busy())): return
	photo = not photo
	if photo and replay_on: replay.photo_begin()   # (a replay frame: the ride camera where the replay's camera is)
	Engine.time_scale = 0.0 if (photo or replay_on) else 1.0
	# the crash slow motion pitched the sound down (Wasted._set_speed leaves photo mode alone): normal pitch while the
	# world is frozen; leaving, WASTED sets its own speed again on its next frame
	AudioServer.playback_speed_scale = 1.0
	hud.visible = input_enabled and not photo and not replay_on
	_photo_last = Time.get_ticks_usec()
	if photo_mode == null:
		photo_mode = PhotoMode.new()
		photo_mode.game = self
		add_child(photo_mode)
	if photo:
		photo_mode.open()
	else:
		photo_mode.close()
		cam_attr.dof_blur_amount = 0.06
		_apply_settings()   # also re-applies the level light (photo mode may have changed it)
		if replay_on: replay.photo_end()

## leave photo mode if it is on (pausing, the menu or a new ride must never inherit a frozen world)
func exit_photo() -> void:
	exit_replay()
	if photo:
		toggle_photo()
	exit_map()

## open the instant replay (needs ~1 s recorded; not over photo mode / the map)
func open_replay() -> bool:
	if replay_on or photo or replay == null or not replay.ready_to_play() or (paper_map and paper_map.busy()): return false
	replay_on = true
	Engine.time_scale = 0.0
	AudioServer.playback_speed_scale = 1.0
	if rumble: rumble.stop()
	hud.visible = false
	_photo_last = Time.get_ticks_usec()
	replay.open()
	return true

func exit_replay() -> void:
	if not replay_on: return
	replay.close()
	replay_on = false
	Engine.time_scale = 1.0
	if replay.viewer:   # a saved replay: back to the title menu (main rebuilds the player's own world)
		get_parent()._replay_view_done.call_deferred()
		return
	Engine.time_scale = 1.0   # (in a crash's slow motion WASTED sets its own speed again next frame)
	hud.visible = input_enabled and not photo
	_snap_prev()
	swallow_held()   # (the A / Space that left it is no sprint / hop)

## the paper trail map (M, ui/paper_map.gd): the ride freezes, a folded map comes up and unfolds. Built on
## first use. It takes all input while it's up; M / Esc / bail fold it away again.
var paper_map: PaperMap
func open_map() -> void:
	if photo or phys.crash_on or (paper_map and paper_map.busy()): return
	if paper_map == null:
		paper_map = PaperMap.new()
		paper_map.game = self
		paper_map.close_actions = [&"map", &"pause", &"bail", &"ui_cancel"]   # B folds it away too (console back)
		add_child(paper_map)
		paper_map.closed.connect(_map_closed)
	Engine.time_scale = 0.0
	hud.visible = false
	paper_map.show_map()

func _map_closed() -> void:
	Engine.time_scale = 1.0
	hud.visible = input_enabled and not photo

## put the map away at once (pause, menus, a new ride)
func exit_map() -> void:
	if paper_map and paper_map.busy():
		paper_map.close(true)

func _exit_tree() -> void:
	if ghost: ghost.end_run()   # (the run so far may be the new best)
	Engine.time_scale = 1.0
	RenderingServer.global_shader_parameter_set("deco_fade", Vector4.ZERO)   # no ride: decorations unfaded (garage)
	RenderingServer.global_shader_parameter_set("ground_fade", Vector4.ZERO)
	FarHills.ground_crossfade = false
	if rumble: rumble.stop()

# tests (BMX_DAB_PROBE): per-frame shoe moves on the bike, the sole's lowest point vs the ground
var dab_probe := Env.s("BMX_DAB_PROBE") != ""
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
		dab_lin = 0.0; dab_k = 0.0; st.foot_down = false
		return
	# slowing down to a stop: the foot comes off the pedal a moment before the bike stands (like a real rider
	# reaching for the ground), not only once it's already stopped
	var decel := (_dab_vprev - st.v) / maxf(dt, 1e-3)
	_dab_vprev = st.v
	_dab_dec += (decel - _dab_dec) * (1.0 - exp(-dt * 6.0))
	var coming := st.v < 1.8 and st.v > 0.0 and _dab_dec > 0.8
	var want: bool = not st.air and st.pedal < 0.05 and (st.v < 1.2 and st.v > -0.7 if dab_lin > 0.0 else (absf(st.v) < 0.5 or coming))   # backing up (brake held) lifts it
	if want and dab_lin <= 0.0:
		_pick_dab_side(st)
	dab_lin = move_toward(dab_lin, 1.0 if want else 0.0, dt / (0.45 if want else 0.4))
	dab_k = smoothstep(0.0, 1.0, dab_lin)
	st.foot_down = want and dab_lin >= 0.6
	# the bike settles onto the foot: a cool, deliberate lean (more when the foot's ground is lower than the
	# other side's: the bike has to go further over to reach it), with a slow small breathing sway once settled
	var lean_t := DAB_LEAN + clampf(-_dab_gap * 0.9, -0.08, 0.1) + 0.02 * sin(t * 0.8) * clampf(_dab_hold - 0.5, 0.0, 1.0)
	_dab_lean_s += (lean_t - _dab_lean_s) * (1.0 - exp(-dt * 3.0))
	_dab_hold = _dab_hold + dt if dab_k > 0.99 else 0.0

## Which foot goes down: the one on the uphill side of a side slope (the ground is closer: a short, easy
## reach), never onto a rock / bank much higher than the other side (that's a wall, step to the open side);
## on flat ground the foot on the lower pedal, level cranks -> the side the bike leans to, else left.
func _pick_dab_side(st: BikePhysics) -> void:
	var hb := rig.global_transform.basis
	var fwd := Vector3(hb.x.x, 0.0, hb.x.z).normalized()
	var rgt := Vector3(hb.z.x, 0.0, hb.z.z).normalized()
	var bb: Vector3 = rig.crank_n.global_position + fwd * DAB_FWD
	var gl: float = terrain.top_height((bb - rgt * DAB_OUT).x, (bb - rgt * DAB_OUT).z)
	var gr: float = terrain.top_height((bb + rgt * DAB_OUT).x, (bb + rgt * DAB_OUT).z)
	var dg: float = gr - gl   # > 0: the ground on the right is higher
	var dy := 0.0
	if rig.pedal_pivots.size() == 2:
		dy = rig.pedal_pivots[0].global_position.y - rig.pedal_pivots[1].global_position.y
	if absf(dg) > 0.35: dab_side = -signf(dg)            # a rock / bank right beside: step to the open side
	elif absf(dg) > 0.04: dab_side = signf(dg)           # side slope: the uphill foot
	elif absf(dy) > 0.03: dab_side = -1.0 if dy < 0.0 else 1.0
	elif absf(st.bike_lean) > 0.02: dab_side = -signf(st.bike_lean)
	else: dab_side = -1.0
	_dab_gap = (gr - gl) * dab_side   # > 0: the foot's ground is higher than the other side's

## tests (BMX_PEDAL_PROBE=1): where each shoe's sole meets its pedal - the gap between the sole under the ball of the
## foot and the pedal's top (along the pedal's up, + = floating), how far the ball is from over the axle (along the
## pedal), the angle between sole and pedal. Worst values printed every 2 s
var _pp := {t = 0.0, gap = 0.0, gap_min = 1.0, along = 0.0, ang = 0.0, n = 0}
func _pedal_probe() -> void:
	for fi in 2:
		var pv: Node3D = rig.pedal_pivots[fi]
		var pt: Transform3D = pv.global_transform
		var up := pt.basis.y.normalized()
		var top: Vector3 = pt.origin + up * rig.pedal_top * pt.basis.get_scale().y
		var st: Transform3D = rider.shoe[fi].global_transform
		var ball: Vector3 = st * Vector3(Rider.BALL_X, 0.0, 0.0)
		var d := ball - top
		var gap := d.dot(up)
		_pp.gap = maxf(_pp.gap, gap); _pp.gap_min = minf(_pp.gap_min, gap)
		_pp.along = maxf(_pp.along, absf(d.dot(pt.basis.x.normalized())))
		_pp.ang = maxf(_pp.ang, st.basis.y.normalized().angle_to(up))
		_pp.n += 1
	_pp.t += get_process_delta_time()
	if _pp.t >= 2.0:
		_pp.t = 0.0
		print("PEDALPROBE n=%d gap max=%.1f min=%.1f mm  ball off axle max=%.1f mm  sole vs pedal max=%.1f deg" % [_pp.n, _pp.gap * 1000.0, _pp.gap_min * 1000.0, _pp.along * 1000.0, rad_to_deg(_pp.ang)])

## Stopped with a foot down the rider is calm: now and then he looks round (off to the side, back up the
## trail over a shoulder, down at the foot, out ahead), holding each glance a while. Feeds lookYaw / lookPitch.
func _idle_look(dt: float) -> void:
	if dab_k < 0.5 or _dab_hold < 0.6:
		_idle_tgt = Vector2.ZERO
		_idle_next = 0.0
		return
	_idle_next -= dt
	if _idle_next <= 0.0:
		var r := randf()
		if r < 0.25: _idle_tgt = Vector2(0.0, 0.0)                                       # ahead, down the trail
		elif r < 0.55: _idle_tgt = Vector2(randf_range(0.6, 1.25) * (1.0 if randf() < 0.5 else -1.0), randf_range(-0.05, 0.2))   # off to a side
		elif r < 0.75: _idle_tgt = Vector2(dab_side * randf_range(1.4, 1.8), 0.1)        # back up the trail, over the shoulder away from the foot (yaw > 0 = left)
		elif r < 0.88: _idle_tgt = Vector2(-dab_side * 0.35, -0.45)                       # down at the foot
		else: _idle_tgt = Vector2(randf_range(-0.4, 0.4), randf_range(0.25, 0.4))          # up at the sky / the hills
		_idle_next = randf_range(1.4, 3.6)

## Moves the dabbing foot's target (lean-node space) from its pedal to the ground beside the bike.
var _pose_in := {}   # the rider's pose inputs, reused (see _process)

func _dab_foot(lt: Dictionary) -> void:
	var key := "footL" if dab_side < 0.0 else "footR"
	var hb := rig.global_transform.basis   # heading only: x forward, z to the rider's right
	var fwd := Vector3(hb.x.x, 0.0, hb.x.z).normalized()
	var rgt := Vector3(hb.z.x, 0.0, hb.z.z).normalized()
	var bb: Vector3 = rig.crank_n.global_position
	var g := bb + rgt * dab_side * DAB_OUT + fwd * DAB_FWD
	g.y = terrain.top_height(g.x, g.z) + 0.012   # sole just on the drawn ground (rocks, decks too)
	var tl: Vector3 = rig.lean_g.to_local(g)
	tl.y -= 0.03   # the rider draws the shoe 3 cm above its foot point
	var pedal_p: Vector3 = lt[key]
	var f := pedal_p.lerp(tl, dab_k)
	f.y += sin(PI * dab_k) * 0.07   # lifts off the pedal on the way out / back
	lt[key] = f

## the drawn value of a physics state key, between the last two steps (`_lerp_a` = the fraction, set per frame)
var _lerp_a := 1.0
func _lerp_k(k: String) -> float:
	return lerpf(_prev[k], phys.get(k), _lerp_a)

func _process(dt: float) -> void:
	_hitch_watch()
	if photo:
		# time stands still; the camera moves on real time
		var now := Time.get_ticks_usec()
		var rdt := minf((now - _photo_last) / 1e6, 0.1)
		_photo_last = now
		photo_mode.update(rdt)
		if area_title: area_title.view.visible = false
		return
	if replay_on:
		var rnow := Time.get_ticks_usec()
		var rrdt := minf((rnow - _photo_last) / 1e6, 0.1)
		_photo_last = rnow
		replay.update(rrdt)
		if audio: audio.update_audio(rrdt)   # (frozen: the tyres / wind fade out, as in photo mode)
		return
	if area_title: area_title.view.visible = hud.visible and level == ""   # (the test playground: no big banners)
	var _pk := Time.get_ticks_usec()
	if perf_on:
		if _perf_last > 0: _perf_acc["FRAME_wall"] = _perf_acc.get("FRAME_wall", 0) + (_pk - _perf_last)
		_perf_last = _pk
		_perf_frames += 1
		_perf_print -= dt
		if _perf_print <= 0.0:
			_perf_print = 5.0
			_perf_report()
	if _bail_down >= 0 and not Input.is_action_pressed("bail"):   # let go while photo mode / pause ate the release
		_bail_down = -1
	if _bail_down >= 0 and Time.get_ticks_msec() - _bail_down >= BAIL_HOLD_MS:   # held: the real bail
		_bail_down = -1
		if not phys.crash_on: phys.crash_pending = "BAIL!"
	dt = minf(dt, 0.1)
	t += dt
	var st := phys
	var a := Engine.get_physics_interpolation_fraction()
	if Vector2(st.x - _prev.x, st.z - _prev.z).length() > 2: a = 1.0
	_lerp_a = a
	var y_draw: float = _lerp_k("y") if st.crash_on else _lerp_k("y_draw")
	# wrapped interpolation: mid-flip the pitch jumps +PI -> -PI between two steps
	var pk := "pitch" if st.crash_on else "pitch_draw"
	var p_draw: float = wrapf(_prev[pk] + BikePhysics.ang_diff(st.get(pk), _prev[pk]) * a, -PI, PI)
	if Env.s("BMX_PITCH_POSE") != "": p_draw = wrapf(t * 4.0, -PI, PI) if Env.s("BMX_PITCH_POSE") == "sweep" else float(Env.s("BMX_PITCH_POSE"))   # tests: draw at a fixed pitch (flip poses)
	var hd: float = _prev.heading + BikePhysics.ang_diff(st.heading, _prev.heading) * a
	drawn_pos = Vector3(_lerp_k("x"), _lerp_k("y"), _lerp_k("z"))
	var body_y: float = _lerp_k("body_y")
	_update_dab(dt, st)
	_update_look(dt)
	var wobble := sin(t * 2.3) * 0.025 * maxf(0.0, 1 - absf(st.v) / 2) * (1.0 - dab_k)
	var dab_lean := -dab_side * _dab_lean_s * dab_k   # bike_lean > 0 tips the top to the rider's left
	if rig.chain and phys.geared and phys.gear >= 0: rig.chain.set_gear(phys.gear, phys.cogs)
	if st.crash_on: _mc.clear()   # (the motion cap starts fresh after a crash / get-up)
	var mdt := minf(get_process_delta_time(), 0.05)
	_lean_c = _mcap("bike_lean", st.bike_lean, mdt)
	_steer_c = _mcap("steer", _bar_draw(st, mdt, dab_lean) + st.bar_catch, mdt)
	rig.pose(drawn_pos.x, y_draw + (1.5 if Env.s("BMX_PITCH_POSE") != "" else 0.0), drawn_pos.z, hd, p_draw, st.hop_nose,
		_lean_c + st.rock + wobble + dab_lean, _steer_c - wobble * 1.5 + _pk_bar, st.wheel_f, st.wheel_r, st.crank)
	_pk = _perf("bike_pose", _pk)
	DebugOverlay.draw(self, st, drawn_pos, hd)
	# the physics' tyres are soft and follow the smooth height field; the drawn ground is a triangle mesh
	# (higher in hollows) with rocks and decks on it. Lift / tilt the drawn bike so no tyre is ever inside it
	if Env.s("BMX_NOUNCLIP") == "":
		rig.fit_wheels(terrain.top_height)
		if Env.s("BMX_STEERFIT_PROBE") != "" and Engine.get_process_frames() % 30 == 0:
			print("STEERFIT steer=%.3f xF=%.4f v=%.2f" % [_steer_c, rig.susp.xF, st.v])
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
		# the lift is eased: up at most LIFT_UP (a tyre may dip into a rock for a frame or two), back down at
		# LIFT_DOWN. Taken at once it popped the whole bike and rider 5-20 cm in one frame and dropped them the
		# next, over any rock the suspension's drawn travel couldn't take
		var need: float = rig.position.y - _pre_y
		if st.air or st.crash_on or absf(need - _lift_s) > 0.5: _lift_s = need
		elif need > _lift_s: _lift_s = minf(need, _lift_s + LIFT_UP * mdt)
		else: _lift_s = maxf(need, _lift_s - LIFT_DOWN * mdt)
		rig.position.y = _pre_y + _lift_s
		# in the air the rider's hip moves against the bike move the BIKE (it is ~1/6 of the weight; the pair's centre of
		# mass flies the arc): AIR_SHARE of Rider.body_off the other way (last frame's: the rider is posed after the bike).
		# Back on the ground it eases out, never pushing the bike down into the ground. BMX_OLD_AIRSHARE=1 = off
		# (2026-11-25, user: "weird frame jump before landing": on the touch-down frame the clamp dropped the offset's
		# downward part at once and the bike popped up 7-8 cm against its fall. On the ground it now eases to the clamped
		# value over ~AIR_SHARE_EASE s. BMX_OLD_AIRSHARE_SNAP=1 = the old clamp)
		var dlt := Vector3.ZERO
		if not st.crash_on and rider != null and not _OLD_AIRSHARE and rider.body_off.length_squared() > 1e-8:
			var bo: Vector2 = rider.body_off
			dlt = -AIR_SHARE * (1.0 - st.land_prep) * (rig.global_transform.basis * Vector3(bo.x, bo.y, 0.0))
			if not st.air: dlt.y = maxf(0.0, dlt.y)
		if st.air or st.crash_on or _OLD_AIRSHARE_SNAP: _air_dlt = dlt
		else: _air_dlt = dlt + (_air_dlt - dlt) * exp(-mdt / AIR_SHARE_EASE)
		if _air_dlt.length_squared() > 1e-10: rig.global_position += _air_dlt
		_frame_y = _pre_y
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
		if gap_probe and not st.air and not st.crash_on: _gap_probe(st)
	elif clip_probe:
		var d: float = maxf(rig.tyre_depth(rig.wheel_f, rig.wheel_rf, terrain.top_height), rig.tyre_depth(rig.wheel_r, rig.wheel_rr, terrain.top_height))
		clip_stats.frames += 1
		clip_stats.before = maxf(clip_stats.before, d)
		if d > 0.002: clip_stats.bad += 1
	if Env.s("BMX_LIP_SHOT") != "" and _lip_shots < (int(Env.s("BMX_LIP_N")) if Env.s("BMX_LIP_N") != "" else 10):   # tests: 10 shots (BMX_LIP_N), 0.08 s apart, from a lip
		if _lip_shots == 0 and st.prep > float(Env.s("BMX_LIP_PREP") if Env.s("BMX_LIP_PREP") != "" else "0.2") and not st.air: _lip_t = t
		if _lip_t >= 0.0 and t - _lip_t >= _lip_shots * float(Env.s("BMX_LIP_STEP") if Env.s("BMX_LIP_STEP") != "" else "0.08"):
			get_viewport().get_texture().get_image().save_png("%s_%d.png" % [Env.s("BMX_LIP_SHOT"), _lip_shots])
			print("LIPSHOT %d pitch=%.0f prep=%.2f air=%s compress=%.2f absorb=%.2f vy=%.1f crouch=%.2f wait=%.2f pop_fx=%.2f squash=%.2f pull=%.2f" % [_lip_shots, rad_to_deg(st.pitch), st.prep, st.air, st.compress, st.body_y - st.y, st.vy, st.crouch, st.pop_wait, st.pop_fx, st.squash, st.air_pull])
			_lip_shots += 1
	if Env.s("BMX_LANDBODY") != "": _landbody_probe(st)
	if _BODYUP and int(t * 4.0) != int((t - get_process_delta_time()) * 4.0) and rider and rider.skeleton:   # tests: the drawn torso's tilt in the world
		var gt: Transform3D = rider.global_transform
		var hp: Vector3 = gt * rider.skeleton.bone_rider("Hips").origin
		var ch: Vector3 = gt * rider.skeleton.bone_rider("UpperChest").origin
		var hd_w: Vector3 = gt * rider.skeleton.bone_rider("Head").origin
		var up := (ch - hp).normalized()
		var fw := Vector3(cos(st.course if not is_nan(st.course) else st.heading), 0, -sin(st.course if not is_nan(st.course) else st.heading))
		var sd := fw.cross(Vector3.UP).normalized()
		var hz := Vector2(up.dot(fw), up.dot(sd))
		print("BODYUP air=%s bike_lean=%.0f whip_yaw=%.0f | torso tilt from vertical=%.0f, faces %.0f deg off the flight | head %.2f m to the side" % [st.air, rad_to_deg(st.bike_lean), rad_to_deg(st.slip), rad_to_deg(acos(clampf(up.y, -1, 1))), rad_to_deg(atan2(hz.y, hz.x)), (hd_w - rig.global_position).dot(sd)])
	if Env.s("BMX_LAND_SHOT") != "" and _land_shots < 12:   # tests: 12 shots, 0.06 s apart, from just before a touch-down
		if _land_shots == 0 and st.air and st.air_time > 0.5 and st.land_prep > 0.6: _land_t = t
		if _land_t >= 0.0 and t - _land_t >= _land_shots * 0.06:
			get_viewport().get_texture().get_image().save_png("%s_%d.png" % [Env.s("BMX_LAND_SHOT"), _land_shots])
			print("LANDSHOT %d air=%s since=%.2f fold=%.2f heavy=%.2f absorb=%.2f prep=%.2f" % [_land_shots, st.air, st.since_land, st.land_fold, st.land_heavy, st.body_y - st.y, st.land_prep])
			_land_shots += 1
	if Env.s("BMX_LEAN_SHOT") != "" and not st.air and not st.crash_on:   # tests: shots in deep leans
		var ln := absf(st.bike_lean)
		_lean_max = maxf(_lean_max, ln)
		if ln > 0.7 and t - _lean_shot_t > 1.5 and _lean_shots < 4:
			_lean_shot_t = t
			get_viewport().get_texture().get_image().save_png("%s_%d.png" % [Env.s("BMX_LEAN_SHOT"), _lean_shots])
			print("LEANSHOT %d bike=%.0fdeg body=%.0fdeg v=%.1f" % [_lean_shots, rad_to_deg(st.bike_lean), rad_to_deg(st.bike_lean - st.counter), st.v])
			_lean_shots += 1
	if Env.s("BMX_TSHOTS") != "":   # tests: "prefix@t1,t2,..." = a screenshot at each ride time (s)
		var spec := Env.s("BMX_TSHOTS").split("@")
		var times := spec[1].split(",") if spec.size() > 1 else PackedStringArray()
		if _lean_shots < times.size() and t >= float(times[_lean_shots]):
			get_viewport().get_texture().get_image().save_png("%s_%02d.png" % [spec[0], _lean_shots])
			print("TSHOT %d t=%.2f bike=%+.0fdeg body=%+.0fdeg roll_p=%+.2f roll_c=%+.2f v=%.1f" % [_lean_shots, t, rad_to_deg(st.bike_lean),
				rad_to_deg(st.bike_lean - st.counter), rider.roll_p, rider.roll_c, st.v])
			_lean_shots += 1
	if Env.s("BMX_BERM_SHOT") != "" and not st.air and not st.crash_on:   # tests: shots + numbers on real berms
		var bmin := float(Env.s("BMX_BERM_MIN")) if Env.s("BMX_BERM_MIN") != "" else 0.15
		# (BMX_BERM_STICK=1: only with the body stick leaned into the bank; body_flat = the body without bank_sq)
		var stick_ok: bool = Env.s("BMX_BERM_STICK") == "" or (st.flick * signf(st.bank) > 0.4 and st.lean * st.bank > 0.0)
		_berm_hold = _berm_hold + dt if (absf(st.bank) > bmin and stick_ok) else 0.0   # (settled in the bank, not just entering it)
		if _berm_hold > (0.5 if Env.s("BMX_BERM_STICK") != "" else 0.0) and t - _lean_shot_t > 1.2 and _lean_shots < 6:
			_lean_shot_t = t
			var c_flat: float = maxf((st.bike_lean - (st.lean + st.bank_lean) * float(Tune.v.bodyLean)) * signf(st.bike_lean), absf(st.bike_lean) * 0.2) * signf(st.bike_lean)
			print("BERMBODY %d flick=%+.2f bank_sq=%.2f body_flat=%+.0fdeg body_drawn=%+.1fdeg hips=%+.1fdeg chest=%+.1fdeg" % [_lean_shots, st.flick, st.bank_sq,
				rad_to_deg(st.bike_lean - c_flat), rad_to_deg(st.bike_lean - st.counter), rad_to_deg(rider.roll_p), rad_to_deg(rider.roll_c)])
			get_viewport().get_texture().get_image().save_png("%s_%d.png" % [Env.s("BMX_BERM_SHOT"), _lean_shots])
			print("BERMSHOT %d bank=%+.0fdeg lean=%+.0fdeg bike=%+.0fdeg body=%+.0fdeg steer_in=%+.2f lat=%+.1f berm_k=%.2f v=%.1f" % [_lean_shots,
				rad_to_deg(st.bank), rad_to_deg(st.lean), rad_to_deg(st.bike_lean), rad_to_deg(st.bike_lean - st.counter), st.steer_in, st.lat_a, st.berm_k, st.v])
			_lean_shots += 1
	if clip_probe and Env.s("BMX_CLIP_SHOT") != "":   # tests: a screenshot when a tyre was 12+ cm in
		var deep: float = clip_stats.before
		if clip_stats.get("shot", 0) == 1:
			get_viewport().get_texture().get_image().save_png(Env.s("BMX_CLIP_SHOT"))
			clip_stats.shot = 2
		elif clip_stats.get("shot", 0) == 0 and deep > 0.12 and not st.crash_on and not st.air:
			clip_stats.shot = 1
	_pk = _perf("tyre_unclip", _pk)
	rig.set_brake_heat((st.brake_heat - 0.35) / 0.9)
	if not st.crash_on:
		var lt := rig.limb_targets()
		if dab_k > 0.0: _dab_foot(lt)
		var T: Dictionary = Tune.v
		# the pose inputs that switch on / off with the bike leaving / touching the ground are eased, never stepped
		# (a corner's turn pose used to snap to zero on the first air frame, a stick tilt off on landing)
		var ek := 1.0 - exp(-dt * 8.0)
		_yaw_s += (st.yaw_rate - _yaw_s) * (1.0 - exp(-dt * 14.0))   # (the tyre sim's bump nudges are not the rider's business)
		_turn_s += ((0.0 if st.air else st.yaw_rate * clampf(absf(st.v) / 3.0, 0.3, 1.0)) - _turn_s) * (1.0 - exp(-dt * 5.0))
		_aspin_s += ((st.yaw_rate if st.air else 0.0) - _aspin_s) * ek
		_atilt_s += ((st.air_tilt * float(T.get("stickBodyTilt", 0.6)) * clampf(st.air_stick.length() * 3.0 + absf(st.edge_s) * 2.0, 0.0, 1.0) if st.air else 0.0) - _atilt_s) * ek
		# (on a bank the stick leans the body with the bike: no hips to the outside there, see bank_sq)
		# (since 2026-11-26 the stick leans the body itself, also on banks: no fade. BMX_OLD_STICKBIKE=1 = before)
		_blat_s += ((st.air_stick.x if st.air else st.flick * (1.0 - (st.bank_sq if BikePhysics._OLD_STICKBIKE else 0.0))) - _blat_s) * ek
		# the bike's twist against the body in the air (an air whip): the body turns back against it
		_awhip_s += ((st.air_tw if st.air else 0.0) - _awhip_s) * (1.0 - exp(-dt * 16.0))
		var pi := _pose_in   # one dictionary filled in place every frame (update_pose doesn't keep it)
		pi["footL"] = lt.footL
		pi["footR"] = lt.footR
		pi["handL"] = lt.handL
		pi["handR"] = lt.handR
		pi["gripX_L"] = lt.gripX_L; pi["gripX_R"] = lt.gripX_R; pi["gripZ"] = lt.gripZ
		pi["dab"] = dab_k
		pi["dabSide"] = dab_side
		pi["dabLean"] = _dab_lean_s
		pi["v"] = st.v
		# (through the motion cap, MCAP: the torso, head and hips can't move faster than a body can)
		var pdt := minf(dt, 0.05)
		pi["lean"] = _lean_c + st.rock
		pi["steer"] = _steer_c
		pi["yawRate"] = _yaw_s
		pi["counter"] = _mcap("counter", st.counter, pdt)
		pi["rockRoll"] = st.rock
		pi["frameY"] = _frame_y
		pi["headRoll"] = _mcap("head_roll", st.bike_lean * 0.85, pdt)
		pi["absorb"] = _mcap("absorb", clampf(body_y - y_draw, -T.legComp, T.legExt), pdt)
		pi["pitch"] = p_draw
		pi["bodyLevel"] = T.bodyLevel
		pi["attackDrop"] = T.attackDrop
		pi["pedal"] = st.pedal
		pi["sprint"] = st.sprint * st.pedal
		pi["stamina"] = st.stamina
		pi["hr"] = hud.hr if hud else 72.0   # the bike computer's heart rate (made up from effort, slow to recover): drives the breathing
		pi["crank"] = st.crank
		pi["air"] = st.air_k
		pi["compress"] = maxf(0.0, -st.compress)
		# the jump: the preload crouch, the legs driving straight through the lip / a hop (extend), the pop just gone
		# (the tuck after it), a lip being squashed, and how close a lip is (he rides it centred, not like a climb)
		pi["extend"] = maxf(0.0, st.compress)
		# (hands off he winds up into the lip himself: autoPump = his skill, see BikePhysics._step_lip)
		var auto_pre: float = 0.0 if (st.pop_wait > 0.0 or st.squash > 0.2) else st.prep * float(phys.T.autoPump) * (1.0 - st.auto_absorb)
		pi["preload"] = maxf(st.crouch, auto_pre) * (0.0 if st.air else 1.0)
		# (the stand-tall + pull-up of a pro: only after the player's own pump; hands off he rides it plainly)
		pi["popFx"] = st.pop_fx * minf(1.0, st.pop_q) * (1.0 if st.pro_flight else 0.35)
		pi["airPull"] = st.air_pull if (st.air and st.pro_flight) else 0.0   # the bike pulled up into the body after the pop (the tuck)
		pi["squash"] = maxf(maxf(st.squash, st.auto_absorb) * st.prep, st.squash_fx)   # (hands off he soaks small / fast lips: auto_absorb)
		pi["lipK"] = maxf(st.prep, 1.0 if (st.pop_wait > 0.0 or st.hop_t > 0.0) else 0.0)
		pi["landFold"] = 0.0 if st.air else st.land_fold   # folded up by a landing, gathering himself again
		pi["landReach"] = st.land_prep * st.land_reach     # legs reaching down for the ground (as far as this landing needs)
		pi["inAir"] = 1.0 if st.air else 0.0
		pi["brakeF"] = st.brake_f; pi["brakeR"] = st.brake_r   # the levers (the index + middle fingers pull them)
		pi["hipShift"] = _mcap("hip_shift", st.hip_shift, pdt)
		pi["bodyStick"] = -0.55 if scenic else _mcap("body_stick", st.body_in_s, pdt)
		pi["speedTuck"] = 0.0 if scenic else st.speed_tuck   # (the speed record tuck: hips back, back flat, head low)
		pi["relax"] = 1.0 if scenic else 0.85 * dab_k   # foot down = calm: sat up, back straight, chin up
		pi["tall"] = 1.0 if scenic else 0.0
		pi["lookYaw"] = _look_yaw
		pi["lookPitch"] = _look_pitch
		# the LAND's slope under the two wheels (deck_height: no rock / log domes). With the domes in it the slope
		# flipped +-6 deg as each wheel crossed a stone, and the rider read every rock as a climb / a wheelie
		var sf: Vector3 = phys.fwd()
		pi["slope"] = atan2(terrain.deck_height(phys.x + sf.x * (phys.L - phys.BB_REAR), phys.z + sf.z * (phys.L - phys.BB_REAR))
			- terrain.deck_height(phys.x - sf.x * phys.BB_REAR, phys.z - sf.z * phys.BB_REAR), phys.L)
		pi["frontUp"] = st.wheelie_up   # the balance manual's angle: only a held front counts as a wheelie pose
		pi["airTilt"] = _atilt_s
		pi["bodyLat"] = _blat_s
		pi["airWhip"] = _awhip_s
		pi["torsoVmax"] = float(T.get("torsoMaxSpeed", 2.5))
		pi["latG"] = 0.0 if scenic else _mcap("lat_g", st.lat_a / BikePhysics.G, pdt)
		pi["wheelR"] = rider.to_local(rig.wheel_r.global_position)
		pi["wheelRR"] = rig.wheel_rr
		pi["wheelF"] = rider.to_local(rig.wheel_f.global_position)
		pi["wheelRF"] = rig.wheel_rf
		pi["t"] = t
		pi["airSpin"] = _aspin_s
		# (2026-11-24, back flips from research/jump: GMBN "How to backflip" side views + Hardline 97 ft) the body leads a
		# flip: thrown at the lip he drives the legs straight and throws the HEAD back; then tucks tight; half way round he
		# turns head and shoulders to spot the landing over his shoulder; the last quarter he opens up and pushes the bike
		# down under him (that also slows the turn). Drawn from how far round the flip is (flip_acc). BMX_OLD_FLIPPOSE=1
		pi["flipTwist"] = 0.0
		pi["flipArch"] = 0.0
		pi["flipExt"] = 0.0
		if Env.s("BMX_OLD_FLIPPOSE") == "":
			if not st.air and st.throw_v > 0.5:
				var thr: float = clampf(st.throw_v / maxf(float(T.flipRate), 0.1), 0.0, 1.0)
				pi["preload"] = float(pi["preload"]) * (1.0 - thr)
				pi["extend"] = maxf(float(pi["extend"]), 0.1 * thr)
				pi["lookPitch"] = float(pi["lookPitch"]) + 0.45 * thr
				if st.throw_v > 0.0: pi["flipArch"] = thr   # (a back flip: the back arches as he throws it - video 2026-11-24)
			elif st.air and absf(st.flip_acc) > 0.25:
				var fon: float = smoothstep(1.0, 2.2, absf(st.air_w))
				var ph: float = clampf(absf(st.flip_acc) / TAU, 0.0, 1.0)
				var f_head: float = fon * (1.0 - smoothstep(0.15, 0.35, ph))
				var f_look: float = fon * smoothstep(0.35, 0.55, ph) * (1.0 - smoothstep(0.85, 1.0, ph))
				var f_open: float = maxf(fon, smoothstep(0.6, 0.75, ph)) * smoothstep(0.7, 0.9, ph)
				var side: float = 1.0   # (spotting over the right shoulder)
				pi["lookPitch"] = float(pi["lookPitch"]) + (0.5 * f_head - 0.35 * f_look) * signf(st.flip_acc)
				pi["lookYaw"] = float(pi["lookYaw"]) + 0.75 * f_look * side
				pi["flipTwist"] = 0.4 * f_look * side
				# (the back arches as the flip starts - chest out, head and shoulders thrown back - then folds into the tuck)
				if st.flip_acc > 0.0: pi["flipArch"] = fon * (1.0 - smoothstep(0.2, 0.4, ph))
				# (the user, from the side view: upside down his body is LONG - legs nearly straight, arms straight, hanging off
				# the bike - not balled up. So no tuck through the middle: he extends, and stays long to the landing)
				var f_ext: float = fon * smoothstep(0.1, 0.3, ph)
				pi["flipExt"] = maxf(f_ext, f_open)
				pi["landReach"] = maxf(float(pi["landReach"]), maxf(f_ext, f_open))
		pi["wheelY"] = (rig.wheel_f.global_position.y + rig.wheel_r.global_position.y) * 0.5
		pi["turn"] = _turn_s
		pi["pedalTop"] = rig.pedal_top_in(rider)
		_pose_keys_apply(dt, st, pi, lt)
		rider.update_pose(dt, pi)
		# the pedals turn with the feet (ankling): flat pedals tip under the shoe, about their axle (the foot's place
		# doesn't move, so this frame's pose stays right)
		if rig.pedal_pivots.size() == 2:
			for fi in 2: rig.pedal_pivots[fi].rotation.z = st.crank + rider.foot_pitch[fi]
			if Env.s("BMX_PEDAL_PROBE") != "": _pedal_probe()
		if _stand_blend < 1.0 and _stand_world.size() >= 15: _stand_to_bike(dt)
		if dab_probe: _dab_probe(st)
		elif _jit_skip > 0: _jit_skip -= 1
		if jitter_on and _jit_skip == 0:   # tests: the drawn joints (rider space), per frame
			var hj: Vector3 = rider.J[0]
			if _jit_head != Vector3.INF and hj.distance_to(_jit_head) > 0.08:
				print("JUMP head %.3f m  v=%.2f brake_stop=%s pivot=%.2f slip=%.2f counter=%.2f lean=%.2f pitch=%.2f slope=%.2f wheelie=%.2f air=%.2f hip=%.3f" % [hj.distance_to(_jit_head), st.v, st.brake_stop, st.pivot, st.slip, st.counter, st.lean, st.pitch, st._g_pitch, rider.sm_wheelie, st.air_k, st.hip_shift])
			_jit_head = hj
			var jthr := 0.0003 if Env.s("BMX_JITTER_FINE") != "" else 0.002   # (fine: sub-millimetre buzz)
			for ji in [[0, "j_head"], [1, "j_chest"], [2, "j_pelvis"], [4, "j_elbowL"], [10, "j_kneeL"]]:
				var jp: Vector3 = rider.J[ji[0]]
				_jitter_sample(ji[1] + "x", jp.x, jthr); _jitter_sample(ji[1] + "y", jp.y, jthr); _jitter_sample(ji[1] + "z", jp.z, jthr)
			_jitter_sample("d_bike_lean", _lean_c, jthr * 2.0); _jitter_sample("d_steer", _steer_c, jthr * 2.0)
			_jitter_sample("d_counter", pi["counter"], jthr * 2.0); _jitter_sample("d_absorb", pi["absorb"], jthr)
			_jitter_sample("d_rider_y", rider.global_position.y, jthr); _jitter_sample("d_head_rot", head_rot_probe(), jthr * 2.0)
			if Env.s("BMX_JDUMP") != "":
				var row := "%.4f,%.3f,%.4f,%.3f,%.3f,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f" % [t, st.v, st.lean, float(pi.get("brake", 0.0)), st.air_k, _lean_c, _steer_c, float(pi["counter"]), float(pi["absorb"]), float(pi["latG"]), st.hip_shift]
				for jq in rider.J.size():
					var jv: Vector3 = rider.J[jq]
					row += ",%.5f,%.5f,%.5f" % [jv.x, jv.y, jv.z]
				# + the drawn bike in the world (frame jumps through take-offs / landings) and the physics' air / pitch
				var rgt: Transform3D = rig.global_transform
				var wh: Vector3 = rider.to_global(rider.J[0]); var wp: Vector3 = rider.to_global(rider.J[2])
				row += ",%.4f,%.4f,%.4f,%.4f,%d,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f,%d" % [rgt.origin.x, rgt.origin.y, rgt.origin.z, asin(clampf(rgt.basis.x.normalized().y, -1.0, 1.0)), int(st.air), st.pitch, st.y, Engine.get_physics_frames(), float(pi["pitch"]), st.pitch_draw, wh.x, wh.y, wh.z, wp.x, wp.y, wp.z, int(st.crash_on)]
				_jdump.append(row)
	_pk = _perf("rider_pose", _pk)
	if replay and input_enabled and not scenic and not title_world: replay.capture(t)   # (real rides only, not the title backdrop)
	_pk = _perf("replay_rec", _pk)
	var vd: float = Settings.get_v("view_distance")
	# which chunks' trees cast shadows depends on where the shadow map is and where the sun is (Terrain._update_far_shadows)
	var scam := get_viewport().get_camera_3d()
	terrain.shadow_eye = scam.global_position if scam != null else Vector3(st.x, st.y, st.z)
	terrain.shadow_sun = sun.global_transform.basis.z.normalized()
	terrain.shadow_reach = sun.directional_shadow_max_distance
	# streamed decorations dissolve out / the far backdrop's trees in over this band round the rider (no pop-in)
	RenderingServer.global_shader_parameter_set("deco_fade", Vector4(st.x, st.z, _deco_band.x, _deco_band.y))
	# the real ground dissolves out / the far backdrop's ground in over this band (shaders/ground + far_hills.gd): no hard edge
	RenderingServer.global_shader_parameter_set("ground_fade", Vector4(st.x, st.z, _ground_band.x, _ground_band.y) if _ground_band.y > 0.0 else Vector4.ZERO)
	FarHills.ground_crossfade = _ground_band.y > 0.0
	terrain.update_stream(st.x, st.z, 4.0)
	_pk = _perf("terrain_stream", _pk)
	if not phys.crash_on and hud and hud.life < 1.0:   # a full-health rider rolls past a pack and leaves it
		if terrain.take_pack(st.x, st.y, st.z) != null:
			hud.on_health_pack(HealthPack.HEAL)
	# what a caught tape stretches over: the drawn bike's front (the tyre, or the fork above it; the drawn bike,
	# not the physics state a step ahead of it, so the tape sits on the bike you see)
	if phys.crash_on:
		terrain.tape_push(null)
	else:
		_tape_front["axle"] = rig.wheel_f.global_position
		_tape_front["fwd"] = Vector3(cos(hd), 0.0, -sin(hd))
		_tape_front["axis"] = ((rig.steer_n.get_parent() as Node3D).global_basis * rig.steer_axis).normalized()
		_tape_front["r"] = rig.wheel_rf
		terrain.tape_push(_tape_front)
	if contact != null:   # contact shadows on the drawn bike (and the body in a crash)
		# under each tyre's lowest point in its own (leaned) plane, not under the axle: laid over, the
		# contact patch swings out to the side by r x sin(lean)
		var wf: Vector3 = _tyre_bottom(rig.wheel_f, rig.wheel_rf)
		var wr: Vector3 = _tyre_bottom(rig.wheel_r, rig.wheel_rr)
		var mid := (rig.wheel_f.global_position + rig.wheel_r.global_position) * 0.5
		var bh := ContactShadow.RIDE_H
		if phys.crash_on and ragdoll != null and not ragdoll.p.is_empty():
			mid = ragdoll.p[Ragdoll.PELVIS]; bh = 0.15
		contact.visible = not photo or rig.visible
		contact.update(wf, wr, 0.0, 0.0, hd, mid, bh, terrain.top_height)
	_pk = _perf("packs_tape", _pk)
	if far_hills: far_hills.follow(drawn_pos)
	_pk = _perf("far_hills", _pk)
	if sheep: sheep.follow(dt, drawn_pos, st.v, st.fwd())
	_pk = _perf("sheep", _pk)
	_cull_start_tv(drawn_pos)
	biome_t -= dt
	if biome_t <= 0:
		biome_t = 0.5
		var b: String = terrain.biome_name(st.x, st.z)
		if b != biome_cur:
			biome_hold = biome_hold + 1 if b == biome_next else 0
			biome_next = b
			if biome_hold >= 3:
				biome_cur = b
				area_title.show_area(b)
				Steam.presence("Riding · " + b)
	_pk = _perf("biome", _pk)
	# weather: wind, the bike parting the grass, cloud shadows (the sun dims with the shade at the rider)
	atmos.update(t, dt, drawn_pos, 0.0 if st.air or st.crash_on else clampf(absf(st.v) / 2.0, 0.0, 1.0))
	var vcam := get_viewport().get_camera_3d()
	tumbleweeds.update(dt, terrain, vcam, atmos.wind, drawn_pos, st.v, float(Settings.get_v("fx_density")))
	if title_life != null:
		title_life.update(dt, vcam, atmos.wind, drawn_pos, terrain)
	_update_light(dt)
	_sky_meter_step(dt)
	_glare_guard(dt)
	_rim_update(dt)
	_mist_update(dt)
	var se_now := sun_energy * atmos.shade
	if absf(se_now - sun.light_energy) > 0.005 * maxf(sun.light_energy, 0.01): sun.light_energy = se_now   # only a real change (each set re-uploads the light)
	_update_probe(dt, drawn_pos)
	_pk = _perf("atmos_light_probe", _pk)
	# the dust simulation around the rider (fx/smoke_sim.gd)
	if st.crash_on and ragdoll.active: blood.crash_step(ragdoll.p, ragdoll.q, ragdoll.last_h, ragdoll.rad)
	_pk = _perf("blood", _pk)
	if st.crash_on and dust.sim != null: _crash_dust()
	elif dust.sim != null: dust.sim.set_body(_body_parts(st))
	elif _rd_air.size() > 0: _rd_air.resize(0)
	dust.attach(terrain, sun)
	if dust.sim != null:
		dust.sim.cloud = Vector4(atmos.cloud_off.x, atmos.cloud_off.y, Atmos.CLOUD_DEPTH if atmos.clouds_on else 0.0, atmos.shade)
	dust.sim_step(dt, drawn_pos, st.fwd(), atmos.wind)
	if motes: motes.update(drawn_pos, night_k, golden_k)
	_pk = _perf("dust_sim", _pk)
	grime.trim = 0.0 if scenic or Env.s("BMX_NO_MATCH") != "" else _match
	grime.update(dt, rig)
	_pk = _perf("grime", _pk)
	# speed feel: wider FOV and streaky screen edges when fast
	# from ~25 km/h, full by ~75 km/h: wider FOV with the camera pulled in (dolly zoom), a surge of extra FOV
	# while accelerating hard, rumble, bank, streaks and speed lines at the edges, tighter vignette
	var fx_on: bool = Settings.get_v("speed_fx") and not st.crash_on
	var sfx0 := float(Settings.get_v("sfx_start")) / 3.6   # m/s where it begins
	var sk := smoothstep(sfx0, sfx0 + 17.0, absf(st.v)) if fx_on else 0.0  # 2026-11-24 (user: misjudged speed into corners): starts earlier, much stronger below
	speed_k += (sk - speed_k) * minf(1.0, dt * (2.5 if sk > speed_k else 1.2))
	_surge += ((clampf(_acc_fx / 5.0, 0.0, 1.0) * smoothstep(4.0, 12.0, absf(st.v)) if fx_on else 0.0) - _surge) * minf(1.0, dt * 2.0)
	cam.fov_boost = speed_k * 22.0 + _surge * 8.0
	cam.speed_feel = speed_k
	var gm := grade_rect.material as ShaderMaterial
	var blur_k: float = speed_k * (0.4 + 0.6 * speed_k) * float(Settings.get_v("sfx_blur"))
	gm.set_shader_parameter("blur", blur_k)
	gm.set_shader_parameter("fx_lines", float(Settings.get_v("sfx_lines")))
	gm.set_shader_parameter("fx_fringe", float(Settings.get_v("sfx_fringe")))
	gm.set_shader_parameter("fx_vig", float(Settings.get_v("sfx_vignette")))
	gm.set_shader_parameter("speed", speed_k)
	# sun flare (grade.gdshader): where the sun is on screen; the shader only shows it while the pixels there are bright sky
	var fl_k := 0.0
	var fl_uv := Vector2(-1.0, -1.0)
	var fl_cam := get_viewport().get_camera_3d()
	if fl_cam != null and not scenic and not photo and not st.crash_on and Settings.get_v("grade") and sun != null and sun.visible:
		var to_sun: Vector3 = sun.global_transform.basis.z
		if to_sun.y > 0.03 and night_k < 0.6:
			var far_p := fl_cam.global_position + to_sun * 1000.0
			if not fl_cam.is_position_behind(far_p):
				fl_uv = fl_cam.unproject_position(far_p) / get_viewport().get_visible_rect().size
				fl_k = (1.0 - night_k) * smoothstep(0.03, 0.12, to_sun.y)
	gm.set_shader_parameter("sun_uv", fl_uv)
	gm.set_shader_parameter("flare", fl_k)
	# water / dust on the lens: only on the default trail camera (user, 2026-11-24); on other views it is
	# hidden and waits as it was
	var lens_on: bool = Settings.get_v("lens_fx") and not scenic and cam.mode == "trail"
	if lens_on:
		# the air over the lens comes from the camera's own motion (grade.gdshader's focus = the view's middle)
		lens.update(dt, get_viewport().get_camera_3d(), get_viewport().get_visible_rect().size, Vector2(0.5, 0.52))
	lens.apply(gm, lens_on)
	var lens_mips := lens_on and lens.active()   # the drops / dust read the screen out of focus
	_grade_mips(gm, lens_mips or blur_k > (0.0008 if gm.shader == _grade_sh_mip else 0.001))   # (the shader blurs from 0.001)
	_pk = _perf("speed_fx", _pk)
	cam.update_cam(dt)
	_pk = _perf("camera", _pk)
	# fog + shadows sized to the zoom level, sun follows the rider
	if scenic:
		env.fog_depth_begin = 250.0
		env.fog_depth_end = 3100.0
		sun.directional_shadow_max_distance = 220.0
	else:
		# 2026-11-24 (user: "a little more fog to hide pop-ups, subtle"): starts 20 m earlier and ends 10 m sooner (was +55 / +130)
		env.fog_depth_begin = (cam.dist + 35) * vd   # (+75: too thin over the 100-124 m hand-over, pop-in showed)
		env.fog_depth_end = (cam.dist * 1.6 + 120) * vd
		_shadow_fit()
	if cam_attr.dof_blur_far_enabled and scenic:   # lookout: keep the view sharp, soften only the horizon
		cam_attr.dof_blur_far_distance = 9.0     # the cyclist sharp, the landscape behind softly out of focus
		cam_attr.dof_blur_far_transition = 140.0
		cam_attr.dof_blur_near_distance = 2.0
		cam_attr.dof_blur_near_transition = 1.0
	elif cam_attr.dof_blur_far_enabled:
		# riding: nothing you need to see is blurred (user 2026-11-23: "it blurs stuff in front of our view"; the
		# diorama focus ended ~17 m past the camera, i.e. the trail ahead). Only the far haze softens; no near blur.
		# The sense of speed is the side blur in grade.gdshader.
		# (then "pop-in from far, a little more blur on far stuff": the decorations hand over to the far backdrop at
		# 100-124 m, so the soft blur starts at 60 m and is full by ~150 m; the trail just ahead stays sharp)
		cam_attr.dof_blur_far_distance = 60.0
		cam_attr.dof_blur_far_transition = 90.0
	cam_attr.dof_blur_near_enabled = bool(Settings.get_v("tilt_shift")) and scenic
	_pk = _perf("fog_dof", _pk)
	if terrain.has_method("update_water"): terrain.update_water(st.x, st.z, t)
	if puddle_wake != null:
		puddle_wake.step(dt, Vector3(st.x, 0.0, st.z))
		# (no window while the wake isn't running: its compute shader may have failed on the render thread after _ready)
		var pwi := Vector4(puddle_wake.centre.x, puddle_wake.centre.y, WaterWake.N * puddle_wake.cell, puddle_wake.cell) if puddle_wake.ok else Vector4.ZERO
		if pwi != _pw_info:   # (a global set re-uploads them all: only when the window moved a cell)
			_pw_info = pwi
			RenderingServer.global_shader_parameter_set("puddle_wake_info", pwi)
	_pk = _perf("water", _pk)
	if road != null and _road_owner == get_instance_id():
		var cf := -cam.global_basis.z
		road.update(dt, Vector2(st.x, st.z), Vector2(cf.x, cf.z), terrain)
		for l in RoadDetail.CELLS.size():
			if road.info[l] != _road_info[l]:   # (a global set re-uploads them all: only when a window moved a tile)
				_road_info[l] = road.info[l]
				RenderingServer.global_shader_parameter_set("road_info%d" % l, road.info[l])
	_pk = _perf("road", _pk)
	if fx.has_method("update"): fx.update(dt, cam)
	_pk = _perf("fx_tracks", _pk)
	if msg_t > 0: msg_t -= dt
	hud.update_hud(dt)
	_pk = _perf("hud", _pk)
	if audio: audio.update_audio(dt)
	_pk = _perf("audio", _pk)
	if absf(st.v) * 3.6 > float(GameState.records.top_speed) + 0.5 and not st.crash_on:
		GameState.records.top_speed = absf(st.v) * 3.6
		GameState.touch_records()


## reflection probe: sits above the rider and re-captures the surroundings (UPDATE_ONCE, re-armed) after
## 30 m of travel or 6 s, so it costs a single cube render now and then instead of one every frame
func _update_probe(dt: float, at: Vector3) -> void:
	if refl_probe == null or not refl_probe.visible: return
	_probe_t += dt
	if _probe_t > 6.0 or at.distance_to(_probe_pos) > 30.0:
		_probe_t = 0.0
		_probe_pos = at
		refl_probe.global_position = at + Vector3(0, 4.0, 0)   # moved only when it re-captures: moving an UPDATE_ONCE probe re-captures it, so it did every frame
		refl_probe.update_mode = ReflectionProbe.UPDATE_ONCE

## ride fog: a light, sunny distance haze that takes the sky's own colour (no grey wall at the horizon)
## and leaves the sky itself clear
func _ride_fog() -> void:
	env.fog_density = 0.7
	env.fog_sky_affect = 0.0
	env.fog_depth_curve = 1.6
	env.fog_aerial_perspective = 1.0   # the distance takes the sky's own colour (one sky: SkyMeter)

# tests (BMX_LANDBODY=1): how far the drawn body drops into a landing. From touch-down for 1.2 s: lowest pelvis /
# chest height over the bike (rider space) vs where they settle at the end, peak fold, the physics legs' deepest
var _lb := {}
func _landbody_probe(st) -> void:
	if rider == null or rider.pelvis_mesh == null or rider.torso == null: return
	var py: float = rider.pelvis_mesh.position.y
	var cy: float = rider.torso.position.y
	if st.air:
		if st.air_time > 0.3: _lb = {"air": st.air_time, "on": false}
		return
	if _lb.is_empty(): return
	if not _lb.on:
		_lb.merge({"on": true, "t": 0.0, "p0": py, "c0": cy, "pmin": py, "cmin": cy, "tmin": 0.0, "fold": 0.0, "leg": 0.0, "v": st.v})
	_lb.t += get_process_delta_time()
	if py < _lb.pmin: _lb.pmin = py; _lb.tmin = _lb.t
	_lb.cmin = minf(_lb.cmin, cy)
	_lb.fold = maxf(_lb.fold, st.land_fold)
	_lb.leg = minf(_lb.leg, st.body_y - st.y)
	if _lb.t > 1.2:
		print("LANDBODY air=%.2f v=%.1f hit=%.1f heavy=%.2f fold=%.2f leg_min=%.0fcm | pelvis touch=%.0f low=%.0f (-%.0f cm at %.2fs) end=%.0f | chest low -%.0f cm" % [_lb.air, _lb.v, st._land_hit, st.land_heavy, _lb.fold, _lb.leg * 100, _lb.p0 * 100, _lb.pmin * 100, (py - _lb.pmin) * 100, _lb.tmin, py * 100, (cy - _lb.cmin) * 100])
		_lb = {}


## tests (BMX_AIRJERK=1): how smooth the bike's attitude is in the air: per flight, the worst step-to-step change of
## its pitch / lean / yaw rate (rad/s per physics step: a jerk shows as a spike) and of the stick values the physics got
static var _AIRJERK := OS.get_environment("BMX_AIRJERK") != ""
static var _BODYUP := OS.get_environment("BMX_BODYUP") != ""
static var _OLD_AIRFADE := OS.get_environment("BMX_OLD_AIRFADE") != ""
const KB_SIDE := 0.75   # the arrow keys' side lean: short of the stick's spin edge (BikePhysics.SPIN_EDGE 0.85), past the whip's 0.7
var _aj := {}
func _air_jerk_probe(inp: Dictionary) -> void:
	var st = phys
	var yaw: float = st.heading
	var cur := {"p": st.pitch, "l": st.bike_lean, "y": yaw, "sx": float(inp.get("body_lean", 0.0)), "sy": float(inp.get("body_fwd", 0.0)), "st": float(inp.get("steer", 0.0))}
	if st.air and st.air_time > 0.1:
		if _aj.has("prev") and _aj.has("prev2"):
			var a: Dictionary = _aj.prev; var b: Dictionary = _aj.prev2
			for k in ["p", "l", "y"]:
				var d2 := absf(wrapf(cur[k] - a[k], -PI, PI) - wrapf(a[k] - b[k], -PI, PI)) * 120.0
				_aj["m_" + k] = maxf(float(_aj.get("m_" + k, 0.0)), d2)
				_aj["s_" + k] = float(_aj.get("s_" + k, 0.0)) + d2 * d2
			for k in ["sx", "sy", "st"]:
				_aj["m_" + k] = maxf(float(_aj.get("m_" + k, 0.0)), absf(cur[k] - a[k]))
			_aj.n = int(_aj.get("n", 0)) + 1
		_aj.prev2 = _aj.get("prev", cur); _aj.prev = cur
	elif _aj.has("n") and int(_aj.n) > 10:
		var n := float(_aj.n)
		print("AIRJERK steps=%d pitch max=%.2f rms=%.2f | lean max=%.2f rms=%.2f | yaw max=%.2f rms=%.2f | input step max lean=%.2f fwd=%.2f steer=%.2f" % [
			_aj.n, _aj.m_p, sqrt(_aj.s_p / n), _aj.m_l, sqrt(_aj.s_l / n), _aj.m_y, sqrt(_aj.s_y / n), _aj.m_sx, _aj.m_sy, _aj.m_st])
		_aj = {}
	else:
		_aj = {}

## the lowest point of a drawn tyre: the axle + its radius straight down within the wheel's plane
## (laid over, that is out to the side of the axle, where the tyre really touches the ground)
## a tyre's dust patch: the physics contact point moved sideways by how far the drawn tyre's lowest point sits out
## from its axle (the lean), at the drawn ground's height there (rocks, ruts' lips and all)
func _dust_patch(p: Vector3, wheel: Node3D, r: float) -> Vector3:
	if wheel == null or not wheel.is_inside_tree(): return p
	var b := _tyre_bottom(wheel, r)
	# sideways only: where the drawn tyre's lowest point really is across the bike (the bike leans about the
	# contact, so the axle's own offset must not be added again); along the travel the physics point stays (no lag)
	var side := Vector3(-phys.fwd().z, 0.0, phys.fwd().x)
	var lat := clampf((b.x - p.x) * side.x + (b.z - p.z) * side.z, -0.3, 0.3)
	var q := Vector3(p.x + side.x * lat, 0.0, p.z + side.z * lat)
	q.y = maxf(terrain.top_height(q.x, q.z), p.y - 0.03) + 0.03
	return q

static func _tyre_bottom(wheel: Node3D, r: float) -> Vector3:
	var xf := wheel.global_transform
	var ax := xf.basis.z.normalized()
	var down := Vector3.DOWN - ax * ax.dot(Vector3.DOWN)
	var dl := down.length()
	if dl < 1e-3: return xf.origin + Vector3.DOWN * r
	return xf.origin + down / dl * r
