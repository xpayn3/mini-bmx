extends Node
## Player settings: graphics, gameplay, and rebindable controls (keyboard + gamepad).
## Saved to user://settings.cfg. Emits `changed` after every apply so the game can refresh
## its environment / camera.

signal changed

const PATH := "user://settings.cfg"

## action -> [description, default keys, default joypad buttons, default joypad axes [axis, sign]]
const ACTIONS := {
	"pedal":        ["Pedal",                    [KEY_W, KEY_UP],      [],                         [[JOY_AXIS_TRIGGER_RIGHT, 1]]],
	"brake":        ["Brake / roll back",        [KEY_S, KEY_DOWN],    [],                         [[JOY_AXIS_TRIGGER_LEFT, 1]]],
	"steer_left":   ["Steer left",               [KEY_A, KEY_LEFT],    [JOY_BUTTON_DPAD_LEFT],     [[JOY_AXIS_LEFT_X, -1]]],
	"steer_right":  ["Steer right",              [KEY_D, KEY_RIGHT],   [JOY_BUTTON_DPAD_RIGHT],    [[JOY_AXIS_LEFT_X, 1]]],
	"hop":          ["Hop / pump (hold to charge)", [KEY_SPACE],       [JOY_BUTTON_A],             []],
	"sprint":       ["Sprint",                   [KEY_SHIFT],          [JOY_BUTTON_X],             []],
	"gear_easier":  ["Shift easier",             [KEY_Q],              [JOY_BUTTON_LEFT_SHOULDER], []],
	"gear_harder":  ["Shift harder",             [KEY_E],              [JOY_BUTTON_RIGHT_SHOULDER], []],
	"bail":         ["Bail",                     [KEY_F],              [JOY_BUTTON_B],             []],
	"respawn":      ["Back to start",            [KEY_BACKSPACE],      [JOY_BUTTON_BACK],          []],
	"new_world":    ["New world",                [KEY_R],              [],                         []],
	"next_bike":    ["Next bike",                [KEY_B],              [],                         []],
	"camera_next":  ["Next camera",              [KEY_C],              [JOY_BUTTON_Y],             []],
	"body_fwd":     ["Body forward (over the bars)", [KEY_KP_8],       [],                         [[JOY_AXIS_RIGHT_Y, -1]]],
	"body_back":    ["Body back (manual)",       [KEY_KP_5],           [],                         [[JOY_AXIS_RIGHT_Y, 1]]],
	"body_left":    ["Body lean left (flick)",   [KEY_KP_4],           [],                         [[JOY_AXIS_RIGHT_X, -1]]],
	"body_right":   ["Body lean right (flick)",  [KEY_KP_6],           [],                         [[JOY_AXIS_RIGHT_X, 1]]],
	"cam_left":     ["Rotate camera left",       [KEY_Z],              [],                         []],
	"cam_right":    ["Rotate camera right",      [KEY_X],              [],                         []],
	"cam_up":       ["Tilt camera up",           [],                   [],                         []],
	"cam_down":     ["Tilt camera down",         [],                   [],                         []],
	"zoom_in":      ["Zoom in",                  [KEY_EQUAL],          [JOY_BUTTON_DPAD_UP],       []],
	"zoom_out":     ["Zoom out",                 [KEY_MINUS],          [JOY_BUTTON_DPAD_DOWN],     []],
	"records":      ["Records",                  [KEY_H],              [],                         []],
	"tune":         ["Ride tuning panel",        [KEY_P],              [],                         []],
	"pose_panel":   ["Rider position panel",     [KEY_K],              [],                         []],
	"look_panel":   ["Rider look panel",         [KEY_L],              [],                         []],
	"pause":        ["Pause",                    [KEY_ESCAPE],         [JOY_BUTTON_START],         []],
	"screenshot":   ["Screenshot",               [KEY_F12],            [],                         []],
	"toggle_hud":   ["Hide HUD",                 [KEY_F1],             [],                         []],
	"photo":        ["Photo mode",               [KEY_O],              [],                         []],
}

const DEFAULTS := {
	"window_mode": 0,        # 0 windowed, 1 borderless fullscreen, 2 exclusive fullscreen
	"vsync": true,
	"max_fps": 0,            # 0 = unlimited
	"render_scale": 1.0,     # 3D resolution scale
	"upscaler": 0,           # 0 bilinear, 1 FSR 1, 2 FSR 2
	"msaa": 2,               # 0 off, 1 2x, 2 4x, 3 8x
	"fxaa": false,
	"taa": false,
	"shadows": 2,            # 0 low .. 3 ultra
	"ssao": true,
	"bloom": true,
	"tilt_shift": true,      # the miniature-diorama depth of field
	"grade": true,           # colour grade + vignette
	"view_distance": 1.0,    # fog / streaming multiplier
	"show_fps": true,
	"units": 0,              # 0 km/h, 1 mph
	"camera": "trail",
	"cam_rev": 0,            # 1 = the Trail camera became the default (old saved "drone" moves over once)
	"mouse_sens": 1.0,
	"invert_y": false,
	"cam_shake": 1.0,
	"cam_dist": 1.0,         # × every camera's distance
	"cam_height": 0.0,       # degrees added to every camera's pitch (higher = more from above)
	"cam_side": 0.0,         # degrees the camera sits round to the side (+ = right of the rider)
	"cam_ahead": 1.0,        # × how far ahead the Trail camera looks
	"cam_follow": 1.0,       # × how quickly the camera turns / catches up after the rider
	"cam_speed_fov": 1.0,    # × the wider view at speed
	"cam_recenter": true,    # the camera swings back behind the rider a moment after you turn it
	"cam_keep": true,        # never let the rider leave the frame
	"cam_fade": true,        # trees / rocks between the camera and the rider dissolve
	"deadzone": 0.15,
	"volume": 0.8,
	# display
	"resolution": "",        # "1920x1080" (windowed / exclusive fullscreen); "" = desktop / default
	"monitor": -1,           # -1 = the current screen
	"brightness": 1.0,
	"fov": 0.0,              # degrees added to every camera preset
	# graphics extras
	"ssr": false,            # screen-space reflections (water, paint)
	"lod": 1.0,              # mesh detail: lower = more detail far away
	"fx_density": 1.0,       # dust / roost / chunk amount
	"aniso": 2,              # 0 off, 1 2x, 2 4x, 3 8x, 4 16x texture filtering
	"quality": 2,            # last preset picked: 0 low, 1 medium, 2 high, 3 ultra, 4 custom
	"gi": 1,                 # global illumination: 0 off (sky ambient only), 1 SSIL, 2 SDFGI (+ SSIL)
	"vol_fog": true,         # volumetric fog: sun shafts in the haze, dust clouds you can see light through
	"cloud_shadows": true,   # soft cloud shadows drifting over the land
	"wind": true,            # gusts rolling over the grass (and the bike parting it)
	"grime": true,           # mud build-up, wet look and drips on bike and rider
	"speed_fx": true,        # FOV boost and edge blur at speed
	"occlusion": false,      # occlusion culling (hills hide what's behind them; costs CPU)
	# audio
	"sfx_volume": 1.0,
	"mute_unfocused": true,
	# gameplay / controller
	"pause_unfocused": true,
	"rumble": true,
	"wasted": true,          # crash: slow motion + "WASTED" screen
	"steer_sens": 1.0,       # analog steering response (1 = linear)
	# interface
	"ui_scale": 1.0,
	"hud_gauge": true,
	"hud_gear": true,
	"hud_jump": true,
	"hud_quick": true,       # the Quick tune card (top right)
}

## Quality presets: every expensive feature in one place (settings menu + --quality=N on the command line).
const PRESETS := {
	0: {"render_scale": 0.75, "upscaler": 1, "msaa": 0, "fxaa": true, "taa": false, "shadows": 0, "ssao": false, "gi": 0,
		"vol_fog": false, "ssr": false, "bloom": true, "tilt_shift": false, "view_distance": 0.7, "lod": 2.0, "fx_density": 0.6,
		"aniso": 1, "cloud_shadows": true, "wind": true, "grime": true, "speed_fx": true},
	1: {"render_scale": 1.0, "upscaler": 0, "msaa": 1, "fxaa": false, "taa": false, "shadows": 1, "ssao": true, "gi": 0,
		"vol_fog": false, "ssr": false, "bloom": true, "tilt_shift": true, "view_distance": 1.0, "lod": 1.0, "fx_density": 1.0,
		"aniso": 2, "cloud_shadows": true, "wind": true, "grime": true, "speed_fx": true},
	2: {"render_scale": 1.0, "upscaler": 0, "msaa": 2, "fxaa": false, "taa": false, "shadows": 2, "ssao": true, "gi": 1,
		"vol_fog": true, "ssr": false, "bloom": true, "tilt_shift": true, "view_distance": 1.0, "lod": 1.0, "fx_density": 1.0,
		"aniso": 3, "cloud_shadows": true, "wind": true, "grime": true, "speed_fx": true},
	3: {"render_scale": 1.0, "upscaler": 0, "msaa": 2, "fxaa": false, "taa": true, "shadows": 3, "ssao": true, "gi": 2,
		"vol_fog": true, "ssr": true, "bloom": true, "tilt_shift": true, "view_distance": 1.4, "lod": 0.75, "fx_density": 1.2,
		"aniso": 4, "cloud_shadows": true, "wind": true, "grime": true, "speed_fx": true},
}
const QUALITY_NAMES := ["Low", "Medium", "High", "Ultra", "Custom"]

func apply_preset(level: int) -> void:
	for k in PRESETS[level]: data[k] = PRESETS[level][k]
	data["quality"] = level
	apply()
	save()

## a graphics option changed by hand: the preset label becomes "Custom" unless it still matches one
func _sync_quality() -> void:
	for lvl in PRESETS:
		var same := true
		for k in PRESETS[lvl]:
			var a = data.get(k)
			var b = PRESETS[lvl][k]
			if (typeof(b) == TYPE_FLOAT and not is_equal_approx(float(a), b)) or (typeof(b) != TYPE_FLOAT and a != b):
				same = false; break
		if same:
			data["quality"] = lvl
			return
	data["quality"] = 4

const RESOLUTIONS := ["1280x720", "1366x768", "1600x900", "1920x1080", "2560x1440", "3440x1440", "3840x2160"]

var data := DEFAULTS.duplicate()
var bindings := {}   # action -> Array[InputEvent]
var _had_quality := false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	load_settings()
	if not FileAccess.file_exists(PATH) or not _had_quality: _sync_quality()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--set="):   # --set=key=value (testing / benchmarks), not saved
			var kv := a.trim_prefix("--set=")
			data[kv.get_slice("=", 0)] = str_to_var(kv.get_slice("=", 1))
		if a.begins_with("--quality="):
			var lvl := int(a.get_slice("=", 1))
			for k in PRESETS[lvl]: data[k] = PRESETS[lvl][k]
			data["quality"] = lvl
	apply()

func get_v(k: String):
	return data.get(k, DEFAULTS.get(k))

func set_v(k: String, val) -> void:
	data[k] = val
	if PRESETS[0].has(k): _sync_quality()
	apply()
	save()

# ---------------- input ----------------
func default_events(action: String) -> Array:
	var d = ACTIONS[action]
	var out := []
	for k in d[1]:
		var e := InputEventKey.new(); e.physical_keycode = k; out.append(e)
	for b in d[2]:
		var e := InputEventJoypadButton.new(); e.button_index = b; out.append(e)
	for a in d[3]:
		var e := InputEventJoypadMotion.new(); e.axis = a[0]; e.axis_value = a[1]; out.append(e)
	return out

func _install_bindings() -> void:
	var dz: float = get_v("deadzone")
	for action in ACTIONS:
		if InputMap.has_action(action):
			InputMap.action_erase_events(action)
		else:
			InputMap.add_action(action)
		InputMap.action_set_deadzone(action, dz)
		for e in bindings.get(action, default_events(action)):
			InputMap.action_add_event(action, e)

func rebind(action: String, ev: InputEvent, slot: int) -> void:
	## Replace the keyboard (slot 0) or gamepad (slot 1) binding of an action.
	var list: Array = bindings.get(action, default_events(action)).duplicate()
	var is_pad := ev is InputEventJoypadButton or ev is InputEventJoypadMotion
	# drop the existing primary binding of the same kind
	for i in list.size():
		var e = list[i]
		var e_pad: bool = e is InputEventJoypadButton or e is InputEventJoypadMotion
		if e_pad == is_pad:
			list.remove_at(i)
			break
	list.insert(0, ev)
	bindings[action] = list
	_install_bindings()
	save()

func reset_bindings() -> void:
	bindings.clear()
	_install_bindings()
	save()

static func event_text(e: InputEvent) -> String:
	if e is InputEventKey:
		var k: int = e.physical_keycode if e.physical_keycode else e.keycode
		return OS.get_keycode_string(DisplayServer.keyboard_get_keycode_from_physical(k)) if k else "?"
	if e is InputEventJoypadButton:
		return ["A", "B", "X", "Y", "Back", "Guide", "Start", "L3", "R3", "LB", "RB", "D-Up", "D-Down", "D-Left", "D-Right"][e.button_index] if e.button_index < 15 else "Pad %d" % e.button_index
	if e is InputEventJoypadMotion:
		var names := ["Left stick X", "Left stick Y", "Right stick X", "Right stick Y", "LT", "RT"]
		var n: String = names[e.axis] if e.axis < names.size() else "Axis %d" % e.axis
		if e.axis >= 4:
			return n
		return n + (" +" if e.axis_value > 0 else " -")
	if e is InputEventMouseButton:
		return "Mouse %d" % e.button_index
	return "?"

func binding_text(action: String, pad: bool) -> String:
	for e in InputMap.action_get_events(action):
		var e_pad: bool = e is InputEventJoypadButton or e is InputEventJoypadMotion
		if e_pad == pad:
			return event_text(e)
	return "—"

# ---------------- persistence ----------------
func load_settings() -> void:
	var cf := ConfigFile.new()
	if cf.load(PATH) == OK:
		_had_quality = cf.has_section_key("settings", "quality")
		for k in DEFAULTS:
			if cf.has_section_key("settings", k):
				var val = cf.get_value("settings", k)
				if typeof(val) == typeof(DEFAULTS[k]) or (typeof(DEFAULTS[k]) == TYPE_FLOAT and typeof(val) == TYPE_INT):
					data[k] = val
		if cf.has_section("bindings"):
			for a in cf.get_section_keys("bindings"):
				if ACTIONS.has(a):
					var list = cf.get_value("bindings", a)
					if list is Array:
						var clean := []
						for e in list:
							if e is InputEvent:
								clean.append(e)
						bindings[a] = clean
	if int(data.cam_rev) < 1:
		if data.camera == "drone": data.camera = "trail"
		data.cam_rev = 1
	_install_bindings()

func save() -> void:
	var cf := ConfigFile.new()
	for k in data:
		cf.set_value("settings", k, data[k])
	for a in bindings:
		cf.set_value("bindings", a, bindings[a])
	cf.save(PATH)

# ---------------- apply (window / renderer); the game applies the environment on `changed` ----------------
func apply() -> void:
	var headless := DisplayServer.get_name() == "headless"
	var mon: int = get_v("monitor")
	if not headless and mon >= 0 and mon < DisplayServer.get_screen_count() and DisplayServer.window_get_current_screen() != mon:
		DisplayServer.window_set_current_screen(mon)
	var mode: int = get_v("window_mode")
	var want := DisplayServer.WINDOW_MODE_WINDOWED
	if mode == 1: want = DisplayServer.WINDOW_MODE_FULLSCREEN
	elif mode == 2: want = DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN
	if DisplayServer.get_name() != "headless" and DisplayServer.window_get_mode() != want:
		DisplayServer.window_set_mode(want)
	var res: String = get_v("resolution")
	if not headless and res != "" and mode != 1 and "x" in res:
		var sz := Vector2i(int(res.get_slice("x", 0)), int(res.get_slice("x", 1)))
		if DisplayServer.window_get_size() != sz:
			DisplayServer.window_set_size(sz)
			if mode == 0:
				var scr := DisplayServer.screen_get_usable_rect(DisplayServer.window_get_current_screen())
				DisplayServer.window_set_position(scr.position + (scr.size - sz) / 2)
	if not headless:
		get_window().content_scale_factor = float(get_v("ui_scale"))
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if get_v("vsync") else DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = int(get_v("max_fps"))
	var vp := get_viewport()
	if vp:
		vp.scaling_3d_scale = float(get_v("render_scale"))
		vp.scaling_3d_mode = [Viewport.SCALING_3D_MODE_BILINEAR, Viewport.SCALING_3D_MODE_FSR, Viewport.SCALING_3D_MODE_FSR2][int(get_v("upscaler"))]
		vp.msaa_3d = [Viewport.MSAA_DISABLED, Viewport.MSAA_2X, Viewport.MSAA_4X, Viewport.MSAA_8X][int(get_v("msaa"))]
		vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if get_v("fxaa") else Viewport.SCREEN_SPACE_AA_DISABLED
		vp.use_taa = get_v("taa")
		vp.mesh_lod_threshold = float(get_v("lod"))
		vp.anisotropic_filtering_level = int(get_v("aniso")) as Viewport.AnisotropicFiltering
		var sq: int = get_v("shadows")
		RenderingServer.directional_shadow_atlas_set_size([2048, 4096, 4096, 8192][sq], true)
		vp.use_occlusion_culling = get_v("occlusion")
		RenderingServer.directional_soft_shadow_filter_set_quality([RenderingServer.SHADOW_QUALITY_HARD, RenderingServer.SHADOW_QUALITY_SOFT_LOW, RenderingServer.SHADOW_QUALITY_SOFT_HIGH, RenderingServer.SHADOW_QUALITY_SOFT_ULTRA][sq])
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(0.0001, float(get_v("volume")))))
	var sfx := AudioServer.get_bus_index("SFX")
	if sfx < 0:
		AudioServer.add_bus(); sfx = AudioServer.bus_count - 1
		AudioServer.set_bus_name(sfx, "SFX"); AudioServer.set_bus_send(sfx, "Master")
	AudioServer.set_bus_volume_db(sfx, linear_to_db(maxf(0.0001, float(get_v("sfx_volume")))))
	_install_bindings()
	changed.emit()


## focus lost: mute (if asked); the game pauses itself (main.gd)
func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and get_v("mute_unfocused"):
		AudioServer.set_bus_mute(0, true)
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN:
		AudioServer.set_bus_mute(0, false)

## controller rumble (weak / strong 0..1, seconds)
func rumble(weak: float, strong: float, secs: float) -> void:
	if not get_v("rumble"): return
	for j in Input.get_connected_joypads():
		Input.start_joy_vibration(j, clampf(weak, 0, 1), clampf(strong, 0, 1), secs)
