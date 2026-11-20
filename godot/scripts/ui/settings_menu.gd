extends "res://scripts/ui/controls_menu.gd"
## Settings: Display / Graphics / Audio / Gameplay / Interface / Controller, then the Controls (key / pad
## bindings) and Camera pages from controls_menu.gd (one window for all of it).

func _title() -> String: return "SETTINGS"

func _pages() -> Array:
	return [_display(), _graphics(), _audio(), _gameplay(), _interface(), _controller(), _bindings(), _camera()]

func _display() -> Control:
	var p := _page("Display")
	_option(p, "Display mode", "window_mode", ["Windowed", "Borderless fullscreen", "Exclusive fullscreen"])
	var res := OptionButton.new()
	var list := [""] + Settings.resolutions_for_screen()
	for r in list: res.add_item("Desktop / default" if r == "" else r.replace("x", " × "))
	res.selected = maxi(0, list.find(Settings.get_v("resolution")))
	res.item_selected.connect(func(i): Settings.set_v("resolution", list[i]))
	_row(p, "Resolution", res, "Window size, or the screen mode in exclusive fullscreen")
	var mon := OptionButton.new()
	mon.add_item("Current screen")
	for i in DisplayServer.get_screen_count():
		var sz := DisplayServer.screen_get_size(i)
		mon.add_item("Screen %d  (%d × %d)" % [i + 1, sz.x, sz.y])
	mon.selected = clampi(int(Settings.get_v("monitor")) + 1, 0, mon.item_count - 1)   # a saved screen that is gone now
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
		var b := UITheme.button(Settings.QUALITY_NAMES[lvl], _preset.bind(lvl), _f(15))
		b.toggle_mode = true
		b.button_pressed = lvl == cur
		presets.add_child(b)
	_row(p, "Quality preset", presets, "Low / Medium / High / Ultra. Changing any option below makes it Custom.")
	_hint(p, "Current: %s" % Settings.QUALITY_NAMES[cur])
	_section(p, "LIGHTING")
	_option(p, "Shadows", "shadows", ["Low", "Medium", "High", "Ultra (soft contact-hardening)"])
	_option(p, "Global illumination", "gi", ["Off", "SSIL (bounce light)", "SDFGI + SSIL (most expensive)"], "Light bouncing off the ground and hills")
	_check(p, "Ambient occlusion", "ssao")
	_check(p, "Volumetric fog", "vol_fog", "Haze the sun shines through, real dust clouds on big skids and landings")
	_check(p, "Cloud shadows", "cloud_shadows")
	_check(p, "Screen-space reflections", "ssr", "Reflections in water and glossy paint")
	_section(p, "IMAGE")
	_option(p, "Anti-aliasing (MSAA)", "msaa", ["Off", "2x", "4x", "8x"])
	_check(p, "TAA", "taa", "Temporal anti-aliasing: no shimmering grass, slightly softer image")
	_check(p, "FXAA", "fxaa")
	_option(p, "Texture filtering", "aniso", ["Bilinear", "2x anisotropic", "4x anisotropic", "8x anisotropic", "16x anisotropic"])
	_check(p, "Bloom", "bloom")
	_check(p, "Tilt-shift (miniature look)", "tilt_shift")
	_check(p, "Colour grade + vignette", "grade")
	_check(p, "Speed effects", "speed_fx", "Wider view and blurred screen edges when you go fast")
	_section(p, "WORLD & EFFECTS")
	_slider(p, "View distance", "view_distance", 0.6, 2.0, 0.1, "%.1fx")
	_slider(p, "Model detail (LOD)", "lod", 0.25, 4.0, 0.25, "%.2f", "Lower = more detail far away")
	_option(p, "Grass", "grass", ["Off", "Low", "Medium", "High"], "A grass carpet round you, out to 40 / 52 / 60 m")
	_check(p, "Wind in the grass", "wind")
	_check(p, "Mud & wet bike", "grime", "Mud builds up on dirt and sand, washes off in water")
	_slider(p, "Dust & dirt effects", "fx_density", 0.0, 1.5, 0.1, "%.1fx")
	_check(p, "Occlusion culling", "occlusion", "Skip what hills hide. Helps low-down cameras on slower GPUs; costs some CPU")
	return p

func _preset(level: int) -> void:
	Settings.apply_preset(level)
	_reopen(1)

func _gameplay() -> Control:
	var p := _page("Gameplay")
	_option(p, "Speed units", "units", ["km/h", "mph"])
	_check(p, "Crash slow motion (WASTED)", "wasted", "Time slows down and the screen goes grey when you fall")
	_check(p, "Blood", "blood", "Falls leave blood smears on the ground; very hard crashes can tear off an arm or a leg")
	_check(p, "Pause when the window loses focus", "pause_unfocused")
	_check(p, "Intro at start (CRT TV)", "boot_intro", "Off: a still frame of the TV while the game loads, then straight to the menu")
	var rb := UITheme.button("Reset ride tuning to defaults", func(): Tune.reset_defaults(), _f(15))
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
	_check(p, "Bike computer (speed / slope)", "hud_gauge")
	_check(p, "Gear shifter", "hud_gear")
	_check(p, "Jump card", "hud_jump")
	_check(p, "Quick tune card", "hud_quick", "The pinned ride sliders, top right (its ✕ hides it)")
	return p

## Controller: the Xbox pad drawn with what every button does; click one to change it
func _controller() -> Control:
	var p := _page("Controller")
	_section(p, "CONTROLLER")
	_hint(p, "Click a button, trigger or stick to change what it does. Buttons light up as you press them.")
	var m := PadMap.new()
	m.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	p.add_child(m)
	_section(p, "RIGHT STICK: RIDER BODY")
	_hint(p, "Up / down: weight forward over the bars / back (pull it well back rolling = manual; yank it at a lip = flip)." +
		"  Left / right: throw the bike over under you to turn harder; a quick flick whips the bike round.  In the air: tilt and lean the bike.")
	_slider(p, "Steering response (stick)", "steer_sens", 0.5, 2.0, 0.05, "%.2f", "Above 1: quicker off-centre; below 1: finer near centre")
	_slider(p, "Stick deadzone", "deadzone", 0.05, 0.5, 0.01)
	_slider(p, "Steering curve (stick)", "pad_expo", 1.0, 3.0, 0.05, "%.2f", "Higher = the first bit of stick leans the bike in more gently; full lock stays at the edge")
	_vibration(p)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 10)
	hb.add_child(UITheme.button("Reset controller buttons", func(): Settings.reset_pad_bindings(); m.queue_redraw(), _f(15)))
	hb.add_child(UITheme.button("Reset vibration", _reset_vibration, _f(15)))
	p.add_child(hb)
	return p

func _reset_vibration() -> void:
	for k in Settings.DEFAULTS:
		if String(k).begins_with("rumble"): Settings.set_v(k, Settings.DEFAULTS[k])
	var tc := find_children("*", "TabContainer", true, false)
	_build.call_deferred(tc[0].current_tab if tc.size() > 0 else 0)

## VIBRATION: on / off, the motors, then one strength per effect (game/pad_rumble.gd). Changing any of
## them plays that effect on the pad so you feel what you set.
func _vibration(p: Control) -> void:
	_section(p, "VIBRATION")
	if Env.s("BMX_VIB_SCROLL") != "":   # tests: scroll the page to this section and play one effect's preview
		var sec: Control = p.get_child(p.get_child_count() - 1)
		var sc := p.get_parent() as ScrollContainer
		get_tree().create_timer(0.8, true, false, true).timeout.connect(func():
			if is_instance_valid(sc) and is_instance_valid(sec): sc.scroll_vertical = int(sec.position.y) - 10 + int(Env.s("BMX_VIB_DY") if Env.s("BMX_VIB_DY") != "" else "0")
			PadRumble.preview(get_tree(), Env.s("BMX_VIB_SCROLL")))
	var cb := CheckButton.new()
	cb.button_pressed = Settings.get_v("rumble")
	cb.toggled.connect(func(on):
		Settings.set_v("rumble", on)
		PadRumble.preview(get_tree(), "rumble"))
	_row(p, "Vibration", cb, "Feel the ground, bumps, sliding tyres, landings and crashes through the pad")
	_rumble_slider(p, "Overall strength", "rumble_strength", 0.0, 1.5, "Every effect at once")
	_rumble_slider(p, "Heavy motor (left grip)", "rumble_heavy", 0.0, 1.5, "The low thump: landings, rear wheel, crashes")
	_rumble_slider(p, "Light motor (right grip)", "rumble_light", 0.0, 1.5, "The fast buzz: ground, front wheel, tyre chatter")
	_rumble_slider(p, "Faintest feel", "rumble_floor", 0.0, 0.2, "The lowest speed a motor runs at: raise it if light effects don't come through, lower it for silence on smooth ground", "%.2f")
	_rumble_slider(p, "Slip chatter speed", "rumble_chatter", 0.5, 2.0, "How fast the sliding-tyre chatter pulses")
	var last := ""
	for e in PadRumble.EFFECTS:
		if e[3] != last:
			last = e[3]
			_section(p, "VIBRATION: " + PadRumble.GROUPS[last])
		_rumble_slider(p, e[1], e[0], 0.0, 2.0, e[2])

func _rumble_slider(p: Control, text: String, key: String, lo: float, hi: float, tip: String, fmt := "%.2fx") -> void:
	_slider_row(p, text, lo, hi, 0.05 if hi > 0.5 else 0.01, float(Settings.get_v(key)), float(Settings.DEFAULTS.get(key, 1.0)), fmt, tip,
		func(v):
			Settings.set_v(key, v)
			PadRumble.preview(get_tree(), key))
