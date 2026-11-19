extends MenuBase
## Controls: every key / gamepad binding (click one to rebind) and the camera + riding feel.
## Opened from the title menu and the pause menu; it scrolls, so it always fits the screen.

var _wait_action := ""
var _wait_pad := false
var _wait_btn: Button
var _bind_box: VBoxContainer

func _title() -> String: return "CONTROLS"

func _pages() -> Array:
	return [_bindings(), _camera()]

# ---------------------------------------------------------------- bindings
func _bindings() -> Control:
	var p := _page("Bindings")
	_bind_box = p
	_fill_bindings()
	return p

func _fill_bindings() -> void:
	for c in _bind_box.get_children(): c.queue_free()
	_hint(_bind_box, "Click a binding, then press the new key / button (Esc cancels).")
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 6)
	_bind_box.add_child(grid)
	var a := _lbl("ACTION", 12, MUTED, true); a.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(a)
	for t in ["KEYBOARD", "GAMEPAD"]:
		var h := _lbl(t, 12, MUTED, true); h.custom_minimum_size.x = 160
		grid.add_child(h)
	for action in Settings.ACTIONS:
		var l := _lbl(Settings.ACTIONS[action][0], 15)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		grid.add_child(l)
		for pad in [false, true]:
			var b := Button.new()
			b.text = Settings.binding_text(action, pad)
			b.custom_minimum_size = Vector2(160, 34)
			b.add_theme_font_size_override("font_size", 14)
			b.pressed.connect(_start_rebind.bind(action, pad, b))
			grid.add_child(b)
	var hb := HBoxContainer.new()
	hb.add_child(UITheme.button("Reset all controls", func(): Settings.reset_bindings(); _fill_bindings.call_deferred(), 15))
	_bind_box.add_child(hb)
	_section(_bind_box, "TIPS")
	if Settings.pad_active:
		_hint(_bind_box, "Right stick = your body: back = manual, yank it at a lip = flip, left / right = throw the bike over to turn harder, flick it to whip round. Hold A at a lip to pop higher. Settings › Controller to remap the pad.")
	else:
		_hint(_bind_box, "Mouse drag: orbit · wheel: zoom · hold hop at a lip to pop higher · press S / W as you leave a lip to throw a back / front flip · carve: hold a turn at speed.")

func _start_rebind(action: String, pad: bool, b: Button) -> void:
	if _wait_btn and is_instance_valid(_wait_btn) and _wait_action != "":
		_wait_btn.text = Settings.binding_text(_wait_action, _wait_pad)
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
		_fill_bindings.call_deferred()

# ---------------------------------------------------------------- camera + riding
func _camera() -> Control:
	var p := _page("Camera")
	_section(p, "CAMERA")
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
	var hb := HBoxContainer.new()
	hb.add_child(UITheme.button("Reset camera", _reset_camera, 15))
	p.add_child(hb)
	_section(p, "RIDING")
	_tune_slider(p, "Top speed", "topSpeed", "×%.2f",
		"How fast the rider can pedal the bike: top speed, the power to reach it and less drag (also in the tuning card, Ride › Speed)")
	return p

func _reset_camera() -> void:
	for k in ["fov", "cam_speed_fov", "cam_dist", "cam_height", "cam_side", "cam_ahead", "cam_follow", "cam_shake",
			"mouse_sens", "invert_y", "cam_recenter", "cam_keep", "cam_fade"]:
		Settings.data[k] = Settings.DEFAULTS[k]
	Settings.apply()
	Settings.save()
	_reopen(1)   # rebuilt so the sliders show the defaults
