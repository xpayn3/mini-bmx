extends Node
## Root: owns the ride (Game) and the menus. The world keeps running behind the title screen with a
## slow orbiting camera; Esc pauses a ride.

enum { MENU, RIDING, PAUSED }

var game: Game
var state := MENU
var ui := CanvasLayer.new()
var menu: Control
var pause_menu: Control
var settings_open: Control
var fade: ColorRect

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	ui.layer = 20
	add_child(ui)
	fade = ColorRect.new()
	fade.color = Color(0.66, 0.84, 0.92)
	fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(fade)
	if "--garage" not in OS.get_cmdline_user_args():   # straight to the garage: don't build the world first
		_new_game()
		_show_menu()
	create_tween().tween_property(fade, "modulate:a", 0.0, 0.8)
	# command-line: --ride skips the title screen; --autotest=N rides N seconds unattended then quits
	for a in OS.get_cmdline_user_args():
		if a == "--ride": _start_ride()
		elif a.begins_with("--autotest"): _autotest(float(a.get_slice("=", 1)) if "=" in a else 10.0)
		elif a == "--garage": _open_garage()
		elif a.begins_with("--shot="): _shot(a.get_slice("=", 1))
		elif a.begins_with("--bench="): _bench(a.get_slice("=", 1))
		elif a.begins_with("--showcase="): _showcase(a.get_slice("=", 1))

func _new_game() -> void:
	if game:
		game.queue_free()
		await game.tree_exited
	game = Game.new()
	game.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(game)
	move_child(game, 0)

func restart_ride() -> void:
	fade.modulate.a = 1.0
	await _new_game()
	_set_riding(state != MENU)
	create_tween().tween_property(fade, "modulate:a", 0.0, 0.5)

func _set_riding(riding: bool) -> void:
	game.input_enabled = riding
	game.hud.visible = riding
	if not riding:
		game.cam.set_mode("orbitcam")
	else:
		game.cam.set_mode(Settings.get_v("camera"))

# ---------------------------------------------------------------- title screen
func _show_menu() -> void:
	state = MENU
	get_tree().paused = false
	_set_riding(false)
	if menu: menu.queue_free()
	menu = Control.new()
	menu.theme = UITheme.get_theme()
	menu.set_anchors_preset(Control.PRESET_FULL_RECT)
	menu.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(menu)
	ui.move_child(menu, 0)
	var shade := ColorRect.new()
	shade.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	shade.custom_minimum_size.x = 520
	shade.color = Color(0.04, 0.08, 0.12, 0.55)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	menu.add_child(shade)
	var vb := VBoxContainer.new()
	vb.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	vb.offset_left = 64; vb.offset_right = 460; vb.offset_top = 90; vb.offset_bottom = -40
	vb.add_theme_constant_override("separation", 12)
	menu.add_child(vb)
	vb.add_child(UITheme.label("MINI BMX", 64, UITheme.ACCENT, true))
	vb.add_child(UITheme.label("Downhill & BMX on endless procedural trails", 17, UITheme.MUTED))
	var sp := Control.new(); sp.custom_minimum_size.y = 28; vb.add_child(sp)
	var ride := UITheme.button("RIDE", _start_ride, 24)
	ride.custom_minimum_size.y = 58
	vb.add_child(ride)
	var gar := UITheme.button("GARAGE  ·  customise your downhill bike", _open_garage, 18)
	gar.custom_minimum_size.y = 50
	vb.add_child(gar)
	# bike picker
	var bikes := HBoxContainer.new()
	bikes.add_theme_constant_override("separation", 8)
	var group := ButtonGroup.new()
	for id in GameState.BIKES:
		var b := Button.new()
		b.text = GameState.BIKES[id].label
		b.toggle_mode = true
		b.button_group = group
		b.button_pressed = id == GameState.bike_id
		b.custom_minimum_size = Vector2(0, 44)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(func():
			if GameState.bike_id != id:
				GameState.bike_id = id; GameState.save(); restart_ride())
		bikes.add_child(b)
	vb.add_child(UITheme.label("BIKE", 13, UITheme.MUTED))
	vb.add_child(bikes)
	# world seed
	vb.add_child(UITheme.label("WORLD", 13, UITheme.MUTED))
	var seed_row := HBoxContainer.new()
	seed_row.add_theme_constant_override("separation", 8)
	var se := LineEdit.new()
	se.text = str(GameState.seed)
	se.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	se.custom_minimum_size.y = 44
	se.text_submitted.connect(func(t):
		if t.is_valid_int():
			GameState.seed = int(t); restart_ride())
	seed_row.add_child(se)
	seed_row.add_child(UITheme.button("🎲 Random", func(): GameState.new_seed(); se.text = str(GameState.seed); restart_ride(), 16))
	vb.add_child(seed_row)
	var sp2 := Control.new(); sp2.custom_minimum_size.y = 12; vb.add_child(sp2)
	vb.add_child(UITheme.button("Settings", _open_settings))
	vb.add_child(UITheme.button("Controls", _show_controls))
	vb.add_child(UITheme.button("Quit", func(): get_tree().quit()))
	var foot := UITheme.label("v1.0 · Godot %s" % Engine.get_version_info().string, 12, UITheme.MUTED)
	foot.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	foot.position = Vector2(64, -36)
	menu.add_child(foot)
	ride.grab_focus.call_deferred()

var garage: Garage

func _open_garage() -> void:
	if menu: menu.queue_free(); menu = null
	fade.modulate.a = 1.0
	if game:
		game.queue_free()
		await game.tree_exited
		game = null
	GameState.bike_id = "dh"
	garage = Garage.new()
	add_child(garage)
	garage.closed.connect(_close_garage)
	create_tween().tween_property(fade, "modulate:a", 0.0, 0.5)

func _close_garage(ride: bool) -> void:
	fade.modulate.a = 1.0
	garage.queue_free()
	await garage.tree_exited
	garage = null
	await _new_game()
	if ride: _start_ride()
	else: _show_menu()
	create_tween().tween_property(fade, "modulate:a", 0.0, 0.5)

func _start_ride() -> void:
	if menu: menu.queue_free(); menu = null
	state = RIDING
	game.respawn(false)
	_set_riding(true)

# ---------------------------------------------------------------- pause
func _unhandled_input(e: InputEvent) -> void:
	if not e.is_action_pressed("pause") or e.is_echo(): return
	if is_instance_valid(settings_open) or garage: return
	if state == RIDING: _pause()
	elif state == PAUSED: _resume()
	get_viewport().set_input_as_handled()

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and state == RIDING and Settings.get_v("pause_unfocused") and OS.get_cmdline_user_args().is_empty():
		_pause()

func _pause() -> void:
	state = PAUSED
	get_tree().paused = true
	pause_menu = PanelContainer.new()
	pause_menu.theme = UITheme.get_theme()
	pause_menu.custom_minimum_size = Vector2(360, 0)
	ui.add_child(pause_menu)
	UITheme.centre(pause_menu)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	pause_menu.add_child(vb)
	vb.add_child(UITheme.label("PAUSED", 30, UITheme.ACCENT, true))
	var resume := UITheme.button("Resume", _resume)
	vb.add_child(resume)
	vb.add_child(UITheme.button("Back to start", func(): _resume(); game.respawn(false)))
	vb.add_child(UITheme.button("New world", func(): _resume(); game.respawn(true)))
	vb.add_child(UITheme.button("Settings", _open_settings))
	vb.add_child(UITheme.button("Controls", _show_controls))
	vb.add_child(UITheme.button("Main menu", func(): _close_pause(); GameState.save(); _show_menu()))
	vb.add_child(UITheme.button("Quit to desktop", func(): GameState.save(); get_tree().quit()))
	resume.grab_focus.call_deferred()

func _close_pause() -> void:
	if pause_menu: pause_menu.queue_free(); pause_menu = null

func _resume() -> void:
	_close_pause()
	state = RIDING
	get_tree().paused = false

func _open_settings() -> void:
	if is_instance_valid(settings_open): return
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.35)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui.add_child(dim)
	settings_open = load("res://scripts/ui/settings_menu.gd").new()
	if pause_menu: pause_menu.visible = false
	# clean up when the menu actually leaves the tree, however it was closed: a missed `closed`
	# signal used to leave this dim up (dark screen, every click swallowed) and Esc blocked
	settings_open.tree_exiting.connect(func():
		if is_instance_valid(dim): dim.queue_free()
		settings_open = null
		if is_instance_valid(pause_menu): pause_menu.visible = true)
	ui.add_child(settings_open)

func _show_controls() -> void:
	var p := PanelContainer.new()
	p.theme = UITheme.get_theme()
	ui.add_child(p)
	UITheme.centre(p)
	var vb := VBoxContainer.new()
	p.add_child(vb)
	vb.add_child(UITheme.label("CONTROLS", 24, UITheme.ACCENT, true))
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 22)
	for a in Settings.ACTIONS:
		grid.add_child(UITheme.label(Settings.binding_text(a, false), 15, UITheme.ACCENT, true))
		grid.add_child(UITheme.label(Settings.binding_text(a, true), 15, UITheme.MUTED))
		grid.add_child(UITheme.label(Settings.ACTIONS[a][0], 15))
	vb.add_child(grid)
	vb.add_child(UITheme.label("Mouse drag: orbit · wheel: zoom · hold hop at a lip to pop higher · carve: hold a turn at speed", 13, UITheme.MUTED))
	var close := UITheme.button("Close", func(): p.queue_free())
	vb.add_child(close)
	close.grab_focus.call_deferred()

# ---------------------------------------------------------------- unattended smoke test
func _autotest(seconds: float) -> void:
	if OS.get_environment("BMX_SEED") != "":
		GameState.seed = int(OS.get_environment("BMX_SEED"))
		await _new_game()
	_start_ride()
	if OS.get_environment("BMX_CAM") != "": game.cam.set_mode(OS.get_environment("BMX_CAM"))
	var pedal := OS.get_environment("BMX_IDLE") == ""
	if OS.get_environment("BMX_PANEL") != "": game.hud._toggle_side(OS.get_environment("BMX_PANEL"))
	if OS.get_environment("BMX_NOLOD") != "": get_viewport().mesh_lod_threshold = 0.0
	if OS.get_environment("BMX_LOD") != "": get_viewport().mesh_lod_threshold = float(OS.get_environment("BMX_LOD"))
	if OS.get_environment("BMX_NOVSYNC") != "": DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED); Engine.max_fps = 0
	var t0 := Time.get_ticks_msec()
	var frames := 0
	var tris := 0.0
	var draws := 0.0
	while (Time.get_ticks_msec() - t0) / 1000.0 < seconds:
		var el := (Time.get_ticks_msec() - t0) / 1000.0
		if pedal: Input.action_press("pedal")
		if pedal and int(el) % 6 == 3: Input.action_press("steer_left")
		else: Input.action_release("steer_left")
		if pedal and int(el * 2) % 7 == 0: Input.action_press("hop")
		else: Input.action_release("hop")
		await get_tree().process_frame
		frames += 1
		tris += RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)
		draws += RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
	if OS.get_environment("BMX_PAUSE") != "":
		_pause()
		if OS.get_environment("BMX_PAUSE") == "settings":
			_open_settings()
			if OS.get_environment("BMX_TAB") != "": settings_open.get_child(0).get_child(1).current_tab = int(OS.get_environment("BMX_TAB"))
		for i in 10: await get_tree().process_frame
		if OS.get_environment("BMX_PAUSE") == "preset":   # pause > settings > a quality preset > Done > resume
			_open_settings()
			await get_tree().process_frame
			settings_open._preset(2)
			for i in 5: await get_tree().process_frame
			settings_open._close()
			for i in 3: await get_tree().process_frame
			var dims := ui.get_children().filter(func(c): return c is ColorRect and c != fade).size()
			print("AUTOTEST pause/settings: settings_open=%s dim_left=%d pause_menu_visible=%s" % [is_instance_valid(settings_open), dims, pause_menu.visible if is_instance_valid(pause_menu) else "gone"])
			_resume()
			await get_tree().process_frame
			print("AUTOTEST resumed: paused=%s state_riding=%s" % [get_tree().paused, state == RIDING])
	var st := game.phys
	print("AUTOTEST avg triangles/frame=%dk draw calls=%d" % [tris / maxi(frames, 1) / 1000, draws / maxi(frames, 1)])
	print("AUTOTEST frames=%d fps=%.1f pos=(%.1f, %.1f, %.1f) v=%.2f crash=%s sane=%s" % [frames, frames / seconds, st.x, st.y, st.z, st.v, st.crash_on, st.is_sane()])
	var shot := OS.get_environment("BMX_SHOT")
	if shot != "":
		get_viewport().get_texture().get_image().save_png(shot)
	get_tree().quit()

## --shot=<png path>@<seconds>: save a screenshot after that long, then quit (testing / store shots)
func _shot(arg: String) -> void:
	var path := arg.get_slice("@", 0)
	var secs := float(arg.get_slice("@", 1)) if "@" in arg else 4.0
	await get_tree().create_timer(secs, true, false, true).timeout
	get_viewport().get_texture().get_image().save_png(path)
	print("SHOT ", path)
	get_tree().quit()


## --bench=<dir>: fixed world (BMX_SEED, default 7), scripted ride through three cameras; prints frame
## time (avg / 1% low), GPU time, triangles and draw calls per camera and saves a screenshot of each.
## Combine with --quality=0..3. Vsync off, no frame cap.
func _bench(dir: String) -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	GameState.seed = int(OS.get_environment("BMX_SEED")) if OS.get_environment("BMX_SEED") != "" else 7
	await _new_game()
	_start_ride()
	game.hud.visible = false
	var vp := get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(vp, true)
	for i in 90: await get_tree().process_frame   # let the world stream in, shaders compile
	var q: int = Settings.get_v("quality")
	var line := "BENCH quality=%s" % Settings.QUALITY_NAMES[q]
	for cam in ["drone", "chase", "diorama"]:
		game.cam.set_mode(cam)
		var ft := PackedFloat32Array()
		var gpu := 0.0
		var tris := 0.0
		var draws := 0.0
		var t0 := Time.get_ticks_msec()
		var last := Time.get_ticks_usec()
		var n := 0
		while Time.get_ticks_msec() - t0 < 7000:
			var el := (Time.get_ticks_msec() - t0) / 1000.0
			Input.action_press("pedal")
			if int(el * 0.7) % 3 == 1: Input.action_press("steer_left")
			else: Input.action_release("steer_left")
			await get_tree().process_frame
			var now := Time.get_ticks_usec()
			if el > 1.0:   # skip the camera cut
				ft.append((now - last) / 1000.0)
				gpu += RenderingServer.viewport_get_measured_render_time_gpu(vp)
				tris += RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)
				draws += RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
				n += 1
			last = now
		Input.action_release("pedal"); Input.action_release("steer_left")
		var sorted := ft.duplicate(); sorted.sort()
		var avg := 0.0
		for v in ft: avg += v
		avg /= maxi(n, 1)
		var p99 := sorted[int(sorted.size() * 0.99)] if sorted.size() > 0 else 0.0
		line += "  | %s: %.2f ms avg (%.0f fps), 1%% low %.2f ms, GPU %.2f ms, %dk tris, %d draws" % [cam, avg, 1000.0 / avg, p99, gpu / maxi(n, 1), tris / maxi(n, 1) / 1000, draws / maxi(n, 1)]
		get_viewport().get_texture().get_image().save_png("%s/%s_q%d.png" % [dir, cam, q])
	print(line)
	get_tree().quit()


## --showcase=<dir>: screenshots of each effect forced on (mud, wet, dust cloud, speed blur, photo DoF)
func _showcase(dir: String) -> void:
	GameState.seed = int(OS.get_environment("BMX_SEED")) if OS.get_environment("BMX_SEED") != "" else 7
	await _new_game()
	_start_ride()
	game.cam.set_mode("chase")
	var ride := func(secs: float):
		var t0 := Time.get_ticks_msec()
		while Time.get_ticks_msec() - t0 < secs * 1000:
			Input.action_press("pedal")
			await get_tree().process_frame
		Input.action_release("pedal")
	var shot := func(n: String):
		await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png("%s/show_%s.png" % [dir, n])
	await ride.call(5.0)
	await shot.call("plain")
	game.grime.mud = 0.75
	await ride.call(1.0)
	await shot.call("mud")
	game.grime.wet = 1.0
	await ride.call(0.6)
	await shot.call("wet")
	game.grime.clean()
	game.cam.set_mode("close")
	for i in 3:
		game.dust.cloud(game.drawn_pos, Vector3.ZERO, game.ground_dust(game.phys.x, game.phys.z, 1), 3.0, 1.2)
		await ride.call(0.25)
	await shot.call("dustcloud")
	game.speed_k = 1.0
	Settings.data["speed_fx"] = true
	game.cam.set_mode("chase")
	await ride.call(0.15)
	(game.grade_rect.material as ShaderMaterial).set_shader_parameter("blur", 1.0)
	await shot.call("speedblur")
	game.cam.set_mode("dolly")
	await ride.call(1.5)
	game.toggle_photo()
	for i in 20: await get_tree().process_frame
	await shot.call("photo")
	game.toggle_photo()
	get_tree().quit()
