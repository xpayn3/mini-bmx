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
	set_anchors_preset(Control.PRESET_CENTER)
	custom_minimum_size = Vector2(760, 600)
	position = -custom_minimum_size / 2
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
	tabs.add_child(_graphics())
	tabs.add_child(_gameplay())
	tabs.add_child(_audio())
	tabs.add_child(_controls())

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

func _slider(parent: Control, text: String, key: String, lo: float, hi: float, stepv: float, fmt := "%.2f") -> void:
	var hb := HBoxContainer.new()
	var s := HSlider.new()
	s.min_value = lo; s.max_value = hi; s.step = stepv
	s.value = float(Settings.get_v(key))
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var vl := UITheme.label(fmt % s.value, 15, UITheme.MUTED)
	vl.custom_minimum_size.x = 56
	vl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	s.value_changed.connect(func(v): vl.text = fmt % v; Settings.set_v(key, v))
	hb.add_child(s); hb.add_child(vl)
	_row(parent, text, hb)

func _graphics() -> Control:
	var p := _page("Graphics")
	_option(p, "Display", "window_mode", ["Windowed", "Borderless fullscreen", "Exclusive fullscreen"])
	_check(p, "V-Sync", "vsync")
	var fps := OptionButton.new()
	var caps := [0, 30, 60, 120, 144, 165, 240]
	for c in caps: fps.add_item("Unlimited" if c == 0 else "%d FPS" % c)
	fps.selected = maxi(0, caps.find(int(Settings.get_v("max_fps"))))
	fps.item_selected.connect(func(i): Settings.set_v("max_fps", caps[i]))
	_row(p, "Frame rate cap", fps)
	_slider(p, "3D resolution", "render_scale", 0.5, 1.0, 0.05, "%.2fx")
	_option(p, "Upscaler", "upscaler", ["Bilinear", "AMD FSR 1", "AMD FSR 2"], "Used when 3D resolution is below 100%")
	_option(p, "MSAA", "msaa", ["Off", "2x", "4x", "8x"])
	_check(p, "FXAA", "fxaa")
	_check(p, "TAA", "taa")
	_option(p, "Shadows", "shadows", ["Low", "Medium", "High", "Ultra"])
	_check(p, "Ambient occlusion", "ssao")
	_check(p, "Bloom", "bloom")
	_check(p, "Tilt-shift (miniature look)", "tilt_shift")
	_check(p, "Colour grade + vignette", "grade")
	_slider(p, "View distance", "view_distance", 0.6, 2.0, 0.1, "%.1fx")
	var presets := HBoxContainer.new()
	presets.add_theme_constant_override("separation", 8)
	for pr in [["Low", 0], ["Medium", 1], ["High", 2], ["Ultra", 3]]:
		presets.add_child(UITheme.button(pr[0], _preset.bind(pr[1]), 15))
	_row(p, "Quick preset", presets)
	return p

func _preset(level: int) -> void:
	var v: Dictionary = {
		0: {"render_scale": 0.75, "upscaler": 1, "msaa": 0, "fxaa": true, "shadows": 0, "ssao": false, "bloom": false, "tilt_shift": false, "view_distance": 0.7},
		1: {"render_scale": 1.0, "upscaler": 0, "msaa": 1, "fxaa": false, "shadows": 1, "ssao": false, "bloom": true, "tilt_shift": true, "view_distance": 1.0},
		2: {"render_scale": 1.0, "upscaler": 0, "msaa": 2, "fxaa": false, "shadows": 2, "ssao": true, "bloom": true, "tilt_shift": true, "view_distance": 1.0},
		3: {"render_scale": 1.0, "upscaler": 0, "msaa": 3, "fxaa": false, "shadows": 3, "ssao": true, "bloom": true, "tilt_shift": true, "view_distance": 1.5},
	}[level]
	for k in v: Settings.data[k] = v[k]
	Settings.apply(); Settings.save()
	_reopen(0)

func _reopen(tab: int) -> void:
	var p := get_parent()
	var m = load("res://scripts/ui/settings_menu.gd").new()
	m.closed.connect(func(): closed.emit())
	p.add_child(m)
	m.get_child(0).get_child(1).current_tab = tab
	queue_free()

func _gameplay() -> Control:
	var p := _page("Gameplay")
	_option(p, "Speed units", "units", ["km/h", "mph"])
	var cams := OptionButton.new()
	var keys := CameraRig.PRESETS.keys()
	for k in keys: cams.add_item(CameraRig.PRESETS[k].label)
	cams.selected = maxi(0, keys.find(Settings.get_v("camera")))
	cams.item_selected.connect(func(i): Settings.set_v("camera", keys[i]))
	_row(p, "Default camera", cams)
	_slider(p, "Mouse sensitivity", "mouse_sens", 0.2, 3.0, 0.1, "%.1f")
	_check(p, "Invert camera Y", "invert_y")
	_slider(p, "Camera shake", "cam_shake", 0.0, 1.5, 0.05)
	_slider(p, "Stick deadzone", "deadzone", 0.05, 0.5, 0.01)
	_check(p, "Show FPS", "show_fps")
	var rb := UITheme.button("Reset ride tuning to defaults", func(): Tune.reset_defaults(), 15)
	_row(p, "Tuning (P in game)", rb)
	return p

func _audio() -> Control:
	var p := _page("Audio")
	_slider(p, "Master volume", "volume", 0.0, 1.0, 0.05)
	return p

func _controls() -> Control:
	var p := _page("Controls")
	_controls_box = p
	_fill_controls()
	return p

func _fill_controls() -> void:
	for c in _controls_box.get_children(): c.queue_free()
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
