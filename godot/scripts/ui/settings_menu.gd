extends MenuBase
## Settings: Display / Graphics / Audio / Gameplay / Interface / Controller. Key + camera settings live in
## the separate Controls window (controls_menu.gd).

func _title() -> String: return "SETTINGS"

func _pages() -> Array:
	return [_display(), _graphics(), _audio(), _gameplay(), _interface(), _controller()]

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
	_section(p, "XBOX CONTROLLER")
	_check(p, "Vibration", "rumble", "Rumble on landings and crashes")
	_slider(p, "Vibration strength", "rumble_strength", 0.0, 1.5, 0.05, "%.2fx")
	_hint(p, "Click a button, trigger or stick to change what it does. Buttons light up as you press them.")
	var m := PadMap.new()
	m.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	p.add_child(m)
	_section(p, "RIGHT STICK: RIDER BODY")
	_hint(p, "Up / down: weight forward over the bars / back (pull it well back rolling = manual; yank it at a lip = flip)." +
		"  Left / right: throw the bike over under you to turn harder; a quick flick whips the bike round.  In the air: tilt and lean the bike.")
	_slider(p, "Steering response (stick)", "steer_sens", 0.5, 2.0, 0.05, "%.2f", "Above 1: quicker off-centre; below 1: finer near centre")
	_slider(p, "Stick deadzone", "deadzone", 0.05, 0.5, 0.01)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 10)
	hb.add_child(UITheme.button("Reset controller buttons", func(): Settings.reset_pad_bindings(); m.queue_redraw(), 15))
	p.add_child(hb)
	return p
