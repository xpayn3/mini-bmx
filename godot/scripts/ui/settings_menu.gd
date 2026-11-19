extends PanelContainer
## Settings: Graphics / Gameplay / Audio / Controls (rebind keyboard + gamepad).

signal closed

var _wait_action := ""
var _wait_pad := false
var _wait_btn: Button
var _controls_box: VBoxContainer

func _ready() -> void:
	theme = UITheme.get_theme()
	process_mode = Node.PROCESS_MODE_ALWAYS
	custom_minimum_size = Vector2(820, 640)
	UITheme.centre.call_deferred(self)
	_build(0)

## (Re)build the contents in place. The menu node itself is never replaced: whoever opened it keeps
## its connection to `closed` (replacing the node used to lose that, leaving the pause screen dark).
func _build(tab: int) -> void:
	for c in get_children():
		remove_child(c); c.queue_free()
	_wait_action = ""
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	add_child(vb)
	var head := HBoxContainer.new()
	var title := UITheme.label("SETTINGS", 26, UITheme.ACCENT, true)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	head.add_child(UITheme.button("Done", _close, 17))
	vb.add_child(head)
	var tabs := TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_child(tabs)
	for page in [_display(), _graphics(), _audio(), _gameplay(), _interface(), _controls(), _controller()]:
		tabs.add_child(page.get_parent())   # the page's ScrollContainer
	tabs.current_tab = tab

func _close() -> void:
	closed.emit()
	queue_free()

func _page(name_: String) -> VBoxContainer:
	var sc := ScrollContainer.new()
	sc.name = name_
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var vb := VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_theme_constant_override("separation", 8)
	sc.add_child(vb)
	return vb

func _row(parent: Control, text: String, ctl: Control, tip := "") -> void:
	var hb := HBoxContainer.new()
	var l := UITheme.label(text, 16)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.tooltip_text = tip
	l.mouse_filter = Control.MOUSE_FILTER_PASS
	ctl.custom_minimum_size.x = 260
	hb.add_child(l); hb.add_child(ctl)
	parent.add_child(hb)

func _option(parent: Control, text: String, key: String, items: Array, tip := "") -> void:
	var ob := OptionButton.new()
	for it in items: ob.add_item(it)
	ob.selected = int(Settings.get_v(key))
	ob.item_selected.connect(func(i): Settings.set_v(key, i))
	_row(parent, text, ob, tip)

func _check(parent: Control, text: String, key: String, tip := "") -> void:
	var cb := CheckButton.new()
	cb.button_pressed = Settings.get_v(key)
	cb.toggled.connect(func(on): Settings.set_v(key, on))
	_row(parent, text, cb, tip)

func _slider(parent: Control, text: String, key: String, lo: float, hi: float, stepv: float, fmt := "%.2f", tip := "") -> void:
	var hb := HBoxContainer.new()
	var s := HSlider.new()
	s.min_value = lo; s.max_value = hi; s.step = stepv
	s.value = float(Settings.get_v(key))
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var vl := UITheme.label(fmt % s.value, 15, UITheme.MUTED)
	vl.custom_minimum_size.x = 56
	vl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	# while dragging only the label follows: applying a setting re-sets the window, viewport, shadows,
	# audio and bindings and writes the file, so it happens once on release (keys / wheel / reset: at once)
	var drag := [false]
	s.drag_started.connect(func(): drag[0] = true)
	s.drag_ended.connect(func(changed):
		drag[0] = false
		if changed: Settings.set_v(key, s.value))
	s.value_changed.connect(func(v):
		vl.text = fmt % v
		if not drag[0]: Settings.set_v(key, v))
	hb.add_child(s); hb.add_child(vl)
	hb.add_child(UITheme.reset_button(s, float(Settings.DEFAULTS.get(key, s.value))))
	_row(parent, text, hb, tip)

## a slider for a ride tuning value (Tune, saved in tune.cfg), range and default from Tune.DEFS
func _tune_slider(parent: Control, text: String, key: String, fmt: String, tip := "") -> void:
	var row: Array = []
	for g in Tune.DEFS:
		for r in g[1]:
			if r[0] == key: row = r
	if row.is_empty(): return
	var hb := HBoxContainer.new()
	var s := HSlider.new()
	s.min_value = row[3]; s.max_value = row[4]; s.step = row[5]
	s.value = float(Tune.base.get(key, row[2]))
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var vl := UITheme.label(fmt % s.value, 15, UITheme.MUTED)
	vl.custom_minimum_size.x = 56
	vl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var drag := [false]   # applied on release (writes tune.cfg), the label follows the drag
	s.drag_started.connect(func(): drag[0] = true)
	s.drag_ended.connect(func(changed):
		drag[0] = false
		if changed: Tune.set_value(key, s.value))
	s.value_changed.connect(func(v):
		vl.text = fmt % v
		if not drag[0]: Tune.set_value(key, v))
	hb.add_child(s); hb.add_child(vl)
	hb.add_child(UITheme.reset_button(s, float(row[2])))
	_row(parent, text, hb, tip)

func _display() -> Control:
	var p := _page("Display")
	_option(p, "Display mode", "window_mode", ["Windowed", "Borderless fullscreen", "Exclusive fullscreen"])
	var res := OptionButton.new()
	var list := [""] + Array(Settings.RESOLUTIONS)
	for r in list: res.add_item("Desktop / default" if r == "" else r.replace("x", " × "))
	res.selected = maxi(0, list.find(Settings.get_v("resolution")))
	res.item_selected.connect(func(i): Settings.set_v("resolution", list[i]))
	_row(p, "Resolution", res, "Window size, or the screen mode in exclusive fullscreen")
	var mon := OptionButton.new()
	mon.add_item("Current screen")
	for i in DisplayServer.get_screen_count():
		var sz := DisplayServer.screen_get_size(i)
		mon.add_item("Screen %d  (%d × %d)" % [i + 1, sz.x, sz.y])
	mon.selected = int(Settings.get_v("monitor")) + 1
	mon.item_selected.connect(func(i): Settings.set_v("monitor", i - 1))
	_row(p, "Monitor", mon)
	_check(p, "V-Sync", "vsync")
	var fps := OptionButton.new()
	var caps := [0, 30, 60, 75, 120, 144, 165, 240]
	for c in caps: fps.add_item("Unlimited" if c == 0 else "%d FPS" % c)
	fps.selected = maxi(0, caps.find(int(Settings.get_v("max_fps"))))
	fps.item_selected.connect(func(i): Settings.set_v("max_fps", caps[i]))
	_row(p, "Frame rate cap", fps)
	_slider(p, "Brightness", "brightness", 0.6, 1.5, 0.05, "%.2f")
	_slider(p, "3D resolution", "render_scale", 0.5, 1.0, 0.05, "%.2fx")
	_option(p, "Upscaler", "upscaler", ["Bilinear", "AMD FSR 1", "AMD FSR 2"], "Used when 3D resolution is below 100%")
	return p

func _graphics() -> Control:
	var p := _page("Graphics")
	var presets := HBoxContainer.new()
	presets.add_theme_constant_override("separation", 8)
	var cur: int = Settings.get_v("quality")
	for lvl in 4:
		var b := UITheme.button(Settings.QUALITY_NAMES[lvl], _preset.bind(lvl), 15)
		b.toggle_mode = true
		b.button_pressed = lvl == cur
		presets.add_child(b)
	_row(p, "Quality preset", presets, "Low / Medium / High / Ultra. Changing any option below makes it Custom.")
	p.add_child(UITheme.label("Current: %s" % Settings.QUALITY_NAMES[cur], 13, UITheme.MUTED))
	p.add_child(UITheme.label("LIGHTING", 13, UITheme.MUTED))
	_option(p, "Shadows", "shadows", ["Low", "Medium", "High", "Ultra (soft contact-hardening)"])
	_option(p, "Global illumination", "gi", ["Off", "SSIL (bounce light)", "SDFGI + SSIL (most expensive)"], "Light bouncing off the ground and hills")
	_check(p, "Ambient occlusion", "ssao")
	_check(p, "Volumetric fog", "vol_fog", "Haze the sun shines through, real dust clouds on big skids and landings")
	_check(p, "Cloud shadows", "cloud_shadows")
	_check(p, "Screen-space reflections", "ssr", "Reflections in water and glossy paint")
	p.add_child(UITheme.label("IMAGE", 13, UITheme.MUTED))
	_option(p, "Anti-aliasing (MSAA)", "msaa", ["Off", "2x", "4x", "8x"])
	_check(p, "TAA", "taa", "Temporal anti-aliasing: no shimmering grass, slightly softer image")
	_check(p, "FXAA", "fxaa")
	_option(p, "Texture filtering", "aniso", ["Bilinear", "2x anisotropic", "4x anisotropic", "8x anisotropic", "16x anisotropic"])
	_check(p, "Bloom", "bloom")
	_check(p, "Tilt-shift (miniature look)", "tilt_shift")
	_check(p, "Colour grade + vignette", "grade")
	_check(p, "Speed effects", "speed_fx", "Wider view and blurred screen edges when you go fast")
	p.add_child(UITheme.label("WORLD & EFFECTS", 13, UITheme.MUTED))
	_slider(p, "View distance", "view_distance", 0.6, 2.0, 0.1, "%.1fx")
	_slider(p, "Model detail (LOD)", "lod", 0.25, 4.0, 0.25, "%.2f", "Lower = more detail far away")
	_check(p, "Wind in the grass", "wind")
	_check(p, "Mud & wet bike", "grime", "Mud builds up on dirt and sand, washes off in water")
	_slider(p, "Dust & dirt effects", "fx_density", 0.0, 1.5, 0.1, "%.1fx")
	_check(p, "Occlusion culling", "occlusion", "Skip what hills hide. Helps low-down cameras on slower GPUs; costs some CPU")
	return p

func _preset(level: int) -> void:
	Settings.apply_preset(level)
	_reopen(1)

func _reopen(tab: int) -> void:
	_build.call_deferred(tab)   # deferred: the button that asked is still mid-signal

func _gameplay() -> Control:
	var p := _page("Gameplay")
	_option(p, "Speed units", "units", ["km/h", "mph"])
	_slider(p, "Steering response (stick)", "steer_sens", 0.5, 2.0, 0.05, "%.2f", "Above 1: quicker off-centre; below 1: finer near centre")
	_slider(p, "Stick deadzone", "deadzone", 0.05, 0.5, 0.01)
	_check(p, "Controller vibration", "rumble")
	_check(p, "Crash slow motion (WASTED)", "wasted", "Time slows down and the screen goes grey when you fall")
	_check(p, "Blood", "blood", "Falls leave blood smears on the ground; very hard crashes can tear off an arm or a leg")
	_check(p, "Pause when the window loses focus", "pause_unfocused")
	var rb := UITheme.button("Reset ride tuning to defaults", func(): Tune.reset_defaults(), 15)
	_row(p, "Ride tuning (P in game)", rb)
	return p

func _audio() -> Control:
	var p := _page("Audio")
	_slider(p, "Master volume", "volume", 0.0, 1.0, 0.05)
	_slider(p, "Ride sounds", "sfx_volume", 0.0, 1.0, 0.05)
	_check(p, "Mute when the window loses focus", "mute_unfocused")
	return p

func _interface() -> Control:
	var p := _page("Interface")
	_slider(p, "UI scale", "ui_scale", 0.75, 1.5, 0.05, "%.2fx")
	_check(p, "Show FPS", "show_fps")
	_check(p, "Bike computer (speed / slope)", "hud_gauge")
	_check(p, "Gear shifter", "hud_gear")
	_check(p, "Jump card", "hud_jump")
	_check(p, "Quick tune card", "hud_quick", "The pinned ride sliders, top right (its ✕ hides it)")
	return p

## Controller: the Xbox pad drawn with what every button does; click one to change it
func _controller() -> Control:
	var p := _page("Controller")
	p.add_child(UITheme.label("XBOX CONTROLLER", 13, UITheme.MUTED))
	_check(p, "Vibration", "rumble", "Rumble on landings and crashes")
	_slider(p, "Vibration strength", "rumble_strength", 0.0, 1.5, 0.05, "%.2fx")
	p.add_child(UITheme.label("Click a button, trigger or stick to change what it does. Buttons light up as you press them.", 13, UITheme.MUTED))
	var m := PadMap.new()
	m.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	p.add_child(m)
	p.add_child(UITheme.label("RIGHT STICK: RIDER BODY", 13, UITheme.MUTED))
	p.add_child(UITheme.label("Up / down: weight forward over the bars / back (pull it well back rolling = manual; yank it at a lip = flip)." +
		"  Left / right: throw the bike over under you to turn harder; a quick flick whips the bike round.  In the air: tilt and lean the bike.", 13))
	p.get_child(p.get_child_count() - 1).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_slider(p, "Steering response (stick)", "steer_sens", 0.5, 2.0, 0.05, "%.2f", "Above 1: quicker off-centre; below 1: finer near centre")
	_slider(p, "Stick deadzone", "deadzone", 0.05, 0.5, 0.01)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 10)
	hb.add_child(UITheme.button("Reset controller buttons", func(): Settings.reset_pad_bindings(); m.queue_redraw(), 15))
	p.add_child(hb)
	return p

func _controls() -> Control:
	var p := _page("Controls")
	_controls_box = p
	_fill_controls()
	return p

func _fill_controls() -> void:
	for c in _controls_box.get_children(): c.queue_free()
	_camera_section(_controls_box)
	_controls_box.add_child(UITheme.label("RIDING", 13, UITheme.MUTED))
	_tune_slider(_controls_box, "Top speed", "topSpeed", "×%.2f",
		"How fast the rider can pedal the bike: top speed, the power to reach it and less drag (also in the tuning card, Ride › Speed)")
	var head := HBoxContainer.new()
	var a := UITheme.label("Action", 13, UITheme.MUTED); a.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(a)
	var k := UITheme.label("Keyboard", 13, UITheme.MUTED); k.custom_minimum_size.x = 150; head.add_child(k)
	var g := UITheme.label("Gamepad", 13, UITheme.MUTED); g.custom_minimum_size.x = 150; head.add_child(g)
	_controls_box.add_child(head)
	for action in Settings.ACTIONS:
		var hb := HBoxContainer.new()
		var l := UITheme.label(Settings.ACTIONS[action][0], 15)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hb.add_child(l)
		for pad in [false, true]:
			var b := Button.new()
			b.text = Settings.binding_text(action, pad)
			b.custom_minimum_size = Vector2(150, 34)
			b.add_theme_font_size_override("font_size", 14)
			b.pressed.connect(_start_rebind.bind(action, pad, b))
			hb.add_child(b)
		_controls_box.add_child(hb)
	_controls_box.add_child(UITheme.button("Reset all controls", func(): Settings.reset_bindings(); _fill_controls(), 15))
	_controls_box.add_child(UITheme.label("Click a binding, then press the new key / button (Esc cancels).", 13, UITheme.MUTED))

## camera: which one, field of view, where it sits, how it follows (all live while riding)
func _camera_section(p: Control) -> void:
	p.add_child(UITheme.label("CAMERA", 13, UITheme.MUTED))
	var cams := OptionButton.new()
	var keys := CameraRig.PRESETS.keys()
	for k in keys: cams.add_item(CameraRig.PRESETS[k].label)
	cams.selected = maxi(0, keys.find(Settings.get_v("camera")))
	cams.item_selected.connect(func(i): Settings.set_v("camera", keys[i]))
	_row(p, "Default camera", cams, "C cycles the cameras while riding")
	_slider(p, "Field of view", "fov", -15.0, 30.0, 1.0, "%+.0f°", "Degrees added to every camera: higher = wider view")
	_slider(p, "Wider view at speed", "cam_speed_fov", 0.0, 2.0, 0.1, "%.1fx", "How much the view widens when you go fast")
	_slider(p, "Distance", "cam_dist", 0.5, 2.5, 0.05, "%.2fx", "How far the camera sits from the rider (the mouse wheel zooms too)")
	_slider(p, "Height", "cam_height", -15.0, 40.0, 1.0, "%+.0f°", "Higher = looking down more from above")
	_slider(p, "Side offset", "cam_side", -90.0, 90.0, 1.0, "%+.0f°", "Swing the camera round to the side of the rider")
	_slider(p, "Look ahead", "cam_ahead", 0.0, 2.0, 0.1, "%.1fx", "How far up the trail the Trail camera looks (the rider sits lower in the frame)")
	_slider(p, "Follow speed", "cam_follow", 0.3, 2.5, 0.05, "%.2fx", "How quickly the camera turns after the rider: lower = smoother, higher = tighter")
	_slider(p, "Camera shake", "cam_shake", 0.0, 1.5, 0.05)
	_slider(p, "Mouse sensitivity", "mouse_sens", 0.2, 3.0, 0.1, "%.1f")
	_check(p, "Invert camera Y", "invert_y")
	_check(p, "Re-centre after turning it", "cam_recenter", "After a drag / Z / X the camera swings back behind the rider")
	_check(p, "Always keep the rider in view", "cam_keep")
	_check(p, "Fade things at the lens", "cam_fade", "Trees and rocks right in front of the camera dissolve")
	p.add_child(UITheme.button("Reset camera", _reset_camera, 15))

func _reset_camera() -> void:
	for k in ["fov", "cam_speed_fov", "cam_dist", "cam_height", "cam_side", "cam_ahead", "cam_follow", "cam_shake",
			"mouse_sens", "invert_y", "cam_recenter", "cam_keep", "cam_fade"]:
		Settings.data[k] = Settings.DEFAULTS[k]
	Settings.apply()
	Settings.save()
	_fill_controls.call_deferred()   # the button that asked is still mid-signal

func _start_rebind(action: String, pad: bool, b: Button) -> void:
	_wait_action = action; _wait_pad = pad; _wait_btn = b
	b.text = "press…"

func _input(e: InputEvent) -> void:
	if _wait_action == "": return
	if e is InputEventKey and e.pressed and e.physical_keycode == KEY_ESCAPE and not _wait_pad:
		_wait_btn.text = Settings.binding_text(_wait_action, _wait_pad); _wait_action = ""
		get_viewport().set_input_as_handled(); return
	var ok := false
	if not _wait_pad and e is InputEventKey and e.pressed:
		var ek := InputEventKey.new(); ek.physical_keycode = e.physical_keycode
		Settings.rebind(_wait_action, ek, 0); ok = true
	elif _wait_pad and e is InputEventJoypadButton and e.pressed:
		var eb := InputEventJoypadButton.new(); eb.button_index = e.button_index
		Settings.rebind(_wait_action, eb, 1); ok = true
	elif _wait_pad and e is InputEventJoypadMotion and absf(e.axis_value) > 0.6:
		var em := InputEventJoypadMotion.new(); em.axis = e.axis; em.axis_value = signf(e.axis_value)
		Settings.rebind(_wait_action, em, 1); ok = true
	if ok:
		_wait_action = ""
		get_viewport().set_input_as_handled()
		_fill_controls.call_deferred()
