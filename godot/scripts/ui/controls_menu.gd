extends MenuBase
## Controls: every key / gamepad binding (click one to rebind) and the camera + riding feel.
## Opened from the title menu and the pause menu; it scrolls, so it always fits the screen.

var _wait_action := ""
var _wait_pad := false
var _wait_btn: Button
var _wait_token := 0          # bumped on every start / finish so an old timeout can't cancel a newer wait
var _notice := ""             # "X was on that key: swapped" line shown above the list after a conflict
const WAIT_SECS := 6.0
var _bind_box: VBoxContainer

func _title() -> String: return "CONTROLS"

func _pages() -> Array:
	return [_bindings(), _camera()]

# ---------------------------------------------------------------- bindings
func _bindings() -> Control:
	var p := _page("Controls")
	_bind_box = p
	_fill_bindings()
	return p

func _fill_bindings() -> void:
	for c in _bind_box.get_children(): _bind_box.remove_child(c); c.queue_free()
	_hint(_bind_box, "Click a binding, then press the new key / button (Esc cancels; a pad rebind also cancels on a mouse click or after %d s). A key already used elsewhere is swapped." % int(WAIT_SECS))
	if _notice != "": _hint(_bind_box, _notice)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 6)
	_bind_box.add_child(grid)
	var a := _lbl("ACTION", 12, MUTED, true); a.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(a)
	for t in ["KEYBOARD", "GAMEPAD"]:
		var h := _lbl(t, 12, MUTED, true); h.custom_minimum_size.x = _f(160)
		grid.add_child(h)
	for action in Settings.ACTIONS:
		if not Dev.on and action in Dev.ACTIONS: continue   # developer tools: not offered in release builds
		var l := _lbl(Settings.ACTIONS[action][0], 15)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		grid.add_child(l)
		for pad in [false, true]:
			var b := GlyphButton.new()
			b.action = action; b.pad = pad
			b.tooltip_text = Settings.binding_text(action, pad)
			b.custom_minimum_size = Vector2(_f(160), _f(38))
			b.add_theme_font_size_override("font_size", _f(14))
			b.pressed.connect(_start_rebind.bind(action, pad, b))
			grid.add_child(b)
	var hb := HBoxContainer.new()
	hb.add_child(UITheme.button("Reset all controls", func(): Settings.reset_bindings(); _fill_bindings.call_deferred(), _f(15)))
	_bind_box.add_child(hb)
	_section(_bind_box, "TIPS")
	if Settings.pad_active:
		_hint(_bind_box, "Right stick = your body: back = manual, held back into a lip = back flip (forward = front flip), pushed right to the side into a lip = 360, left / right = throw the bike over to turn harder, flick it to whip round. Hold A at a lip to pop higher. Settings › Controller to remap the pad.")
	else:
		_hint(_bind_box, "WASD rides the bike, the arrow keys are your body: ↓ rolling = manual (held, it sits on the balance point), held into a lip = back flip (↑ = front flip), ← / → throw the bike over to turn harder and whip it round; in the air they tilt and lay the bike over. Hold hop at a lip to pop higher · mouse drag: orbit · wheel: zoom.")
		_check(_bind_box, "Classic keys: W / S also tilt the bike in the air and throw flips", "kb_ws_air",
			"Off: only the arrow keys move the bike in the air, so braking or pedalling through a jump can't flip you")

func _start_rebind(action: String, pad: bool, b: Button) -> void:
	if _wait_btn and is_instance_valid(_wait_btn) and _wait_action != "":
		_wait_btn.text = ""; _wait_btn.queue_redraw()
	_wait_action = action; _wait_pad = pad; _wait_btn = b
	b.text = "press…"; b.queue_redraw()
	_modal(true)
	_wait_token += 1
	# real-time timer (works while paused): a pad rebind nobody answers cancels itself
	get_tree().create_timer(WAIT_SECS, true, false, true).timeout.connect(_wait_timeout.bind(_wait_token))

func _wait_timeout(token: int) -> void:
	if token == _wait_token and _wait_action != "" and _wait_pad: _cancel_rebind()

func _cancel_rebind() -> void:
	if _wait_btn and is_instance_valid(_wait_btn): _wait_btn.text = ""; _wait_btn.queue_redraw()
	_wait_action = ""; _wait_token += 1
	_modal(false)

## while waiting for a key / button nothing else may take it (menu navigation, the leaflet's B)
func _modal(on: bool) -> void:
	if is_instance_valid(nav): nav.enabled = not on
	if on: add_to_group(&"nav_modal")
	elif is_in_group(&"nav_modal"): remove_from_group(&"nav_modal")

## after the list is rebuilt: focus the binding that was just changed
func _refocus(action: String, pad: bool) -> void:
	for c in _bind_box.get_children():
		if c is GridContainer:
			for b in c.get_children():
				if b is GlyphButton and b.action == action and b.pad == pad: b.grab_focus(); return

func _input(e: InputEvent) -> void:
	if _wait_action == "": return
	# Esc cancels a key rebind; B cancels a key rebind too (a pad user can't type), Esc cancels a pad rebind
	# Esc cancels either kind; a pad rebind can also be cancelled with a mouse click or by waiting
	# (WAIT_SECS), since every pad button is a valid binding and a pad user can't type Esc
	var cancel: bool = (e is InputEventKey and e.pressed and e.physical_keycode == KEY_ESCAPE) 		or (not _wait_pad and e is InputEventJoypadButton and e.pressed and e.button_index == JOY_BUTTON_B) 		or (_wait_pad and e is InputEventMouseButton and e.pressed)
	if cancel:
		_cancel_rebind()
		get_viewport().set_input_as_handled(); return
	var ok := false
	var moved := []
	if not _wait_pad and e is InputEventKey and e.pressed:
		var ek := InputEventKey.new(); ek.physical_keycode = e.physical_keycode
		moved = Settings.rebind(_wait_action, ek, 0); ok = true
	elif _wait_pad and e is InputEventJoypadButton and e.pressed:
		var eb := InputEventJoypadButton.new(); eb.button_index = e.button_index
		moved = Settings.rebind(_wait_action, eb, 1); ok = true
	elif _wait_pad and e is InputEventJoypadMotion and absf(e.axis_value) > 0.6:
		var em := InputEventJoypadMotion.new(); em.axis = e.axis; em.axis_value = signf(e.axis_value)
		moved = Settings.rebind(_wait_action, em, 1); ok = true
	if ok:
		var was := [_wait_action, _wait_pad]
		_wait_action = ""
		_wait_token += 1
		_notice = ""
		if not moved.is_empty():
			_notice = "%s was on that %s: swapped to %s." % [", ".join(moved), "button" if was[1] else "key", "its old binding of " + Settings.ACTIONS[was[0]][0]]
		get_viewport().set_input_as_handled()
		_fill_bindings.call_deferred()
		_refocus.call_deferred(was[0], was[1])
		get_tree().create_timer(0.25, true, false, true).timeout.connect(_modal.bind(false))   # the button's release isn't a menu press

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
	hb.add_child(UITheme.button("Reset camera", _reset_camera, _f(15)))
	p.add_child(hb)
	_section(p, "SPEED EFFECTS")
	_check(p, "Speed effects", "speed_fx", "Master switch: wider view, blur, lines and vignette when you go fast")
	_slider(p, "Starts at", "sfx_start", 5.0, 60.0, 1.0, "%.0f km/h", "Speed where the effects begin: none below it, growing smoothly to full about 60 km/h above it")
	_slider(p, "Wider view", "cam_speed_fov", 0.0, 2.0, 0.1, "%.1fx", "How much the view widens when you go fast")
	_slider(p, "Camera pull-in", "sfx_pull", 0.0, 2.0, 0.1, "%.1fx", "How much closer the camera moves to the rider at speed")
	_slider(p, "Edge blur", "sfx_blur", 0.0, 2.0, 0.1, "%.1fx", "Smeared left / right sides of the screen")
	_slider(p, "Speed lines", "sfx_lines", 0.0, 2.0, 0.1, "%.1fx", "Streaks rushing out from the middle")
	_slider(p, "Colour fringing", "sfx_fringe", 0.0, 2.0, 0.1, "%.1fx", "Red / blue split toward the corners")
	_slider(p, "Vignette", "sfx_vignette", 0.0, 2.0, 0.1, "%.1fx", "The frame darkens and closes in at speed")
	_check(p, "Turn warnings", "pacenotes", "A small card for the next bend: an arrow, the distance, and BRAKE when you are too fast for it")
	var hs := HBoxContainer.new()
	hs.add_child(UITheme.button("Reset speed effects", _reset_speed_fx, _f(15)))
	p.add_child(hs)
	_section(p, "RIDING")
	_tune_slider(p, "Top speed", "topSpeed", "×%.2f",
		"How fast the rider can pedal the bike: top speed, the power to reach it and less drag (also in the tuning card, Ride › Speed)")
	return p

func _reset_speed_fx() -> void:
	for k in ["speed_fx", "cam_speed_fov", "sfx_blur", "sfx_lines", "sfx_fringe", "sfx_vignette", "sfx_pull", "sfx_start", "pacenotes"]:
		Settings.data[k] = Settings.DEFAULTS[k]
	Settings.apply()
	Settings.save()
	_reopen(1)

func _reset_camera() -> void:
	for k in ["fov", "cam_speed_fov", "cam_dist", "cam_height", "cam_side", "cam_ahead", "cam_follow", "cam_shake",
			"mouse_sens", "invert_y", "cam_recenter", "cam_keep", "cam_fade"]:
		Settings.data[k] = Settings.DEFAULTS[k]
	Settings.apply()
	Settings.save()
	_reopen(1)   # rebuilt so the sliders show the defaults


## a binding button: shows the key / pad button as its icon (PadGlyph); "press…" while waiting for a new one
class GlyphButton extends Button:
	var action := ""
	var pad := false
	func _draw() -> void:
		if text != "": return
		var g := PadGlyph.glyph_for(action, pad)
		if g == "?":
			var f := get_theme_font("font")
			draw_string(f, Vector2(0, size.y * 0.5 + 5), "—", HORIZONTAL_ALIGNMENT_CENTER, size.x, 14, Color(0, 0, 0, 0.4))
			return
		PadGlyph.draw(self, g, size * 0.5, minf(36.0, size.y - 14.0))

