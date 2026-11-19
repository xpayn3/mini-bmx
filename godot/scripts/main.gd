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
var controls_open: Control
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
	if OS.get_environment("BMX_SEED") != "":   # tests: a fixed world behind the title screen too
		GameState.seed = int(OS.get_environment("BMX_SEED"))
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
		elif a.begins_with("--hitch"): _hitch(float(a.get_slice("=", 1)) if "=" in a else 30.0)

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
	game.set_scenic(not riding)   # title screen: golden hour over the hills
	if riding:
		game.cam.set_mode(Settings.get_v("camera"))

# ---------------------------------------------------------------- title screen
func _show_menu() -> void:
	state = MENU
	get_tree().paused = false
	if game: game.exit_photo()
	_close_controls()
	_set_riding(false)
	if menu: menu.queue_free()
	menu = Control.new()
	menu.theme = UITheme.get_theme()
	menu.set_anchors_preset(Control.PRESET_FULL_RECT)
	menu.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(menu)
	ui.move_child(menu, 0)
	# a soft dusk shade behind the menu that fades out into the view
	var grad := Gradient.new()
	grad.set_color(0, Color(0.05, 0.04, 0.07, 0.72))
	grad.set_color(1, Color(0.05, 0.04, 0.07, 0.0))
	grad.add_point(0.55, Color(0.05, 0.04, 0.07, 0.5))
	var gt := GradientTexture2D.new()
	gt.gradient = grad
	gt.width = 256; gt.height = 4
	var shade := TextureRect.new()
	shade.texture = gt
	shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	shade.stretch_mode = TextureRect.STRETCH_SCALE
	shade.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	shade.custom_minimum_size.x = 720
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
	var gar := UITheme.button("GARAGE  Â·  customise your downhill bike", _open_garage, 18)
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
	seed_row.add_child(UITheme.button("ðŸŽ² Random", func(): GameState.new_seed(); se.text = str(GameState.seed); restart_ride(), 16))
	vb.add_child(seed_row)
	var sp2 := Control.new(); sp2.custom_minimum_size.y = 12; vb.add_child(sp2)
	vb.add_child(UITheme.button("Settings", _open_settings))
	vb.add_child(UITheme.button("Controls", _show_controls))
	vb.add_child(UITheme.button("Quit", func(): get_tree().quit()))
	var foot := UITheme.label("v1.0 Â· Godot %s" % Engine.get_version_info().string, 12, UITheme.MUTED)
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
	if game: game.exit_photo()
	state = RIDING
	game.respawn(false)
	_set_riding(true)

# ---------------------------------------------------------------- pause
func _unhandled_input(e: InputEvent) -> void:
	if not e.is_action_pressed("pause") or e.is_echo(): return
	if is_instance_valid(settings_open) or garage: return
	if is_instance_valid(controls_open):   # Esc closes the controls card, back to the pause menu
		_close_controls()
		get_viewport().set_input_as_handled()
		return
	if state == RIDING: _pause()
	elif state == PAUSED: _resume()
	get_viewport().set_input_as_handled()

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and state == RIDING and Settings.get_v("pause_unfocused") and OS.get_cmdline_user_args().is_empty():
		_pause()

func _pause() -> void:
	if game: game.exit_photo()
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
	_close_controls()
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

func _close_controls() -> void:
	if is_instance_valid(controls_open):
		controls_open.queue_free()
	controls_open = null

func _show_controls() -> void:
	if is_instance_valid(controls_open): return
	var p := PanelContainer.new()
	controls_open = p
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
	vb.add_child(UITheme.label("Mouse drag: orbit Â· wheel: zoom Â· hold hop at a lip to pop higher Â· press S / W as you leave a lip to throw a back / front flip Â· carve: hold a turn at speed", 13, UITheme.MUTED))
	var close := UITheme.button("Close", _close_controls)
	vb.add_child(close)
	close.grab_focus.call_deferred()

# ---------------------------------------------------------------- unattended smoke test
var _probe := {}
func _autotest(seconds: float) -> void:
	if OS.get_environment("BMX_SEED") != "":
		GameState.seed = int(OS.get_environment("BMX_SEED"))
		await _new_game()
	_start_ride()
	if OS.get_environment("BMX_CAM") != "": game.cam.set_mode(OS.get_environment("BMX_CAM"))
	if OS.get_environment("BMX_AT") != "":   # tests: start this many metres down the course
		var cp: Array = game.terrain.field.course.at(float(OS.get_environment("BMX_AT")))
		game.phys.reset_at(cp[0], cp[1], atan2(-float(cp[3]), float(cp[2])))
		game._snap_prev()
		game.cam.snap_to(Vector3(cp[0], game.phys.y + 0.5, cp[1]))
	var pedal := OS.get_environment("BMX_IDLE") == ""
	if OS.get_environment("BMX_PANEL") != "":   # tests: open the tuning card (ride/rider/look), BMX_PANEL_CAT = category tab
		var pt: String = game.hud.SIDE_TABS.get(OS.get_environment("BMX_PANEL"), "ride")
		if OS.get_environment("BMX_PANEL_CAT") != "": TuneCard.last_cat[pt] = int(OS.get_environment("BMX_PANEL_CAT"))
		game.hud._toggle_side(OS.get_environment("BMX_PANEL"))
	if OS.get_environment("BMX_NOLOD") != "": get_viewport().mesh_lod_threshold = 0.0
	if OS.get_environment("BMX_LOD") != "": get_viewport().mesh_lod_threshold = float(OS.get_environment("BMX_LOD"))
	if OS.get_environment("BMX_NOVSYNC") != "": DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED); Engine.max_fps = 0
	var rec: AudioEffectRecord = null
	if OS.get_environment("BMX_REC") != "":   # tests: record the game's own sound to a wav
		rec = AudioEffectRecord.new()
		AudioServer.add_bus_effect(0, rec)
		rec.set_recording_active(true)
	var t0 := Time.get_ticks_msec()
	var frames := 0
	var tris := 0.0
	var draws := 0.0
	while (Time.get_ticks_msec() - t0) / 1000.0 < seconds:
		var el := (Time.get_ticks_msec() - t0) / 1000.0
		if OS.get_environment("BMX_IDLE_FOR") != "": pedal = el >= float(OS.get_environment("BMX_IDLE_FOR"))   # tests: stand still, then ride off
		var stop_at := OS.get_environment("BMX_STOP_AT")   # tests: "a,b" = pedal, brake to a stop from a s, ride off again at b s
		if stop_at != "":
			var sa := stop_at.split(",")
			var braking := el >= float(sa[0]) and (sa.size() < 2 or el < float(sa[1]))
			pedal = not braking
			if braking and game.phys.v > 0.3: Input.action_press("brake")   # off once stopped (held brake backs up)
			else: Input.action_release("brake")
		if pedal and not (OS.get_environment("BMX_COAST") != "" and int(el) % 6 >= 3): Input.action_press("pedal")   # BMX_COAST: 3 s pedal / 3 s coast
		else: Input.action_release("pedal")
		var body_t := OS.get_environment("BMX_BODY")   # tests: the body stick. manual / fwd / lean / flick (from 3 s)
		if body_t != "" and el >= 3.0:
			var ph2: BikePhysics = game.phys
			if body_t == "manual": Input.action_press("body_back", 0.9 if int(el) % 4 < 3 else 0.0)
			elif body_t == "fwd": Input.action_press("body_fwd", 1.0)
			elif body_t == "lean": Input.action_press("body_left", 1.0)
			elif body_t == "flick":
				var side := int(el * 1.5) % 2 == 0
				Input.action_press("body_left", 1.0) if side else Input.action_release("body_left")
				Input.action_press("body_right", 1.0) if not side else Input.action_release("body_right")
			if OS.get_environment("BMX_BODY_PRINT") != "" and int(el * 10) % 5 == 0:
				print("BODY t=%.1f v=%.1f in=%.2f flick=%.2f manual=%.2f pitch=%.2f g=%.2f bike_lean=%.2f lean=%.2f yaw=%.2f slip=%.2f hip=%.3f air=%s" % [el, ph2.v, ph2.body_in, ph2.flick, ph2.manual_up, ph2.pitch, ph2._g_pitch, ph2.bike_lean, ph2.lean, ph2.yaw_rate, ph2.slip, ph2.hip_shift, ph2.air])
		if OS.get_environment("BMX_MUD") != "": game.grime.mud = float(OS.get_environment("BMX_MUD"))   # tests: hold the mud level
		var straight := OS.get_environment("BMX_STRAIGHT") != ""   # tests: ride straight, no steering / hops
		if OS.get_environment("BMX_CAM_ORBIT") != "": game.cam.orbit_t = float(OS.get_environment("BMX_CAM_ORBIT")); game.cam.pan_t = 1e9   # held: no re-centre
		if OS.get_environment("BMX_CAM_DIST") != "": game.cam.dist = float(OS.get_environment("BMX_CAM_DIST"))
		if OS.get_environment("BMX_CAM_PROBE") != "":   # tests: the camera's offset from the rider, frame to frame
			var off: Vector3 = game.cam.global_position - game.drawn_pos
			if _probe.has("cam_off") and el > 1.0:
				var jump: float = (off - _probe.cam_off).length()
				_probe.cam_jump_max = maxf(_probe.get("cam_jump_max", 0.0), jump)
				_probe.cam_dist_min = minf(_probe.get("cam_dist_min", 1e9), off.length())
				_probe.cam_dist_max = maxf(_probe.get("cam_dist_max", 0.0), off.length())
			_probe.cam_off = off
		var trick := OS.get_environment("BMX_TRICK")   # tests: back / front flip lean, side = A / D lean (alternating) in every jump
		if OS.get_environment("BMX_KNEE_PROBE") != "" and game.rider != null:   # tests: biggest knee jump per frame
			var tr: float = game.rider.torso_ratio
			if el > 1.0: _probe.tmin = minf(_probe.get("tmin", 9.0), tr); _probe.tmax = maxf(_probe.get("tmax", 0.0), tr)
			for i in 3:
				var kp: Vector3 = game.rider.knee[i].position if i < 2 else game.rider.pelvis_mesh.position
				var key := "knee%d" % i
				if _probe.has(key):
					var j: float = kp.distance_to(_probe[key])
					var tag := ("air" if game.phys.air else "ground") + ("_hip" if i == 2 else "")
					if j > _probe.get("jump_" + tag, 0.0): _probe["jump_" + tag] = j
				_probe[key] = kp
		var launch := OS.get_environment("BMX_LAUNCH")   # tests: stop at 3 s, then pedal (sprint=1: sprint) away; prints 0-15 / 0-25 / 0-35 km/h times
		if launch != "" and el > 3.0:
			var ph = game.phys
			if not _probe.has("l_t0"):
				_probe.l_t0 = el; ph.v = 0.0
			var hold := float(OS.get_environment("BMX_LAUNCH_HOLD")) if OS.get_environment("BMX_LAUNCH_HOLD") != "" else 99.0   # tests: let go of sprint after this long
			if launch == "sprint" and el - float(_probe.l_t0) < hold: Input.action_press("sprint")
			else: Input.action_release("sprint")
			Input.action_press("pedal")
			var lt: float = el - float(_probe.l_t0)
			if ph.front_air: _probe.l_wh = float(_probe.get("l_wh", 0.0)) + get_process_delta_time()
			_probe.l_pmax = maxf(float(_probe.get("l_pmax", 0.0)), ph.pitch - ph._g_pitch)
			if (ph.crash_on or ph.crash_pending != "") and not _probe.has("l_crash"):
				_probe.l_crash = true
				print("LAUNCH crash %s at %.2f s v=%.1f" % [ph.crash_pending, lt, ph.v])
			if OS.get_environment("BMX_LAUNCH_DBG") != "" and lt < 2.0: print("WH t=%.2f fa=%s ra=%s up=%.2f pitch=%.2f g=%.2f nref=%s spr=%.2f thr=%s" % [lt, ph.front_air, ph.rear_air, ph.wheelie_up, ph.pitch, ph._g_pitch, ph.nose_ref, ph.sprint, Input.get_action_strength("pedal")])
			if int(lt * 2) != int(_probe.get("l_tick", -1)):
				_probe.l_tick = int(lt * 2)
				print("LAUNCH t=%.1f v=%.1f km/h nose_up=%.2f wheelie_s=%.2f max=%.2f" % [lt, ph.v * 3.6, ph.pitch - ph._g_pitch, float(_probe.get("l_wh", 0.0)), float(_probe.l_pmax)])
			for kmh in [15, 25, 35]:
				if ph.v * 3.6 >= kmh and not _probe.has("l_%d" % kmh):
					_probe["l_%d" % kmh] = lt
					print("LAUNCH %s 0-%d km/h in %.2f s (stamina %.2f)" % [launch, kmh, lt, ph.stamina])
			var ls := OS.get_environment("BMX_LAUNCH_SHOTS")
			if ls != "" and lt > 0.3 and lt - float(_probe.get("l_shot", -1.0)) > 0.4 and int(_probe.get("l_n", 0)) < 6:
				_probe.l_shot = lt; _probe.l_n = int(_probe.get("l_n", 0)) + 1
				get_viewport().get_texture().get_image().save_png("%s_%d.png" % [ls, _probe.l_n])
		if OS.get_environment("BMX_VMAX") != "" and not game.phys.air: _probe.vmax_kmh = maxf(_probe.get("vmax_kmh", 0.0), game.phys.v * 3.6)   # tests
		var airshot := OS.get_environment("BMX_AIRSHOT")   # tests: dir/prefix -> shots mid-air (up to 8)
		if airshot != "" and game.phys.air and game.phys.air_time > 0.25 and _airshots < 8 and el - _airshot_t > 0.6:
			_airshot_t = el
			get_viewport().get_texture().get_image().save_png("%s_%d.png" % [airshot, _airshots])
			_airshots += 1
		if trick != "" and game.phys.air:
			var ph = game.phys
			if ph.air_time > 0.06 and trick == "side": trick = "left" if int(el / 2.0) % 2 == 0 else "right"
			Input.action_release("pedal"); Input.action_release("brake"); Input.action_release("steer_left"); Input.action_release("steer_right")
			if OS.get_environment("BMX_BIGAIR") != "" and ph.air_time < 0.03 and ph.vy < 7.0: ph.vy = 7.0   # tests: big air for full flips
			if ph.air_time > 0.06:   # a fresh press after take-off (held keys are locked)
				if trick == "back": Input.action_press("brake")
				elif trick == "manual":   # lean back to this nose-up angle (BMX_MANUAL_PITCH, rad) and hold it
					var mp := float(OS.get_environment("BMX_MANUAL_PITCH")) if OS.get_environment("BMX_MANUAL_PITCH") != "" else 1.0
					var e: float = mp - ph.pitch - ph.pitch_v * 0.25
					if e > 0.05: Input.action_press("brake")
					elif e < -0.05: Input.action_press("pedal")
				elif trick == "front": Input.action_press("pedal")
				elif trick == "left": Input.action_press("steer_left")
				elif trick == "right": Input.action_press("steer_right")
			await get_tree().process_frame
			continue
		elif trick != "":
			Input.action_release("brake"); Input.action_release("sprint")
			var ph = game.phys
			if (trick == "back" or trick == "front") and (ph.prep > 0.25 or ph.front_air or ph.rear_air):
				# a fresh press at the lip throws the rider into the flip (a key held from before doesn't count)
				if trick == "back": Input.action_press("brake")
				elif _probe.get("lip_rel", false): Input.action_press("pedal")
				else: Input.action_release("pedal"); _probe.lip_rel = true
			else:
				_probe.lip_rel = false
		if OS.get_environment("BMX_FOLLOW") != "":   # tests: steer along the trail centreline, get up after a crash
			var ph = game.phys
			var crs = game.terrain.field.course
			var best_d := 1e9
			var s0: float = _probe.get("fs", 0.0)
			for k in range(-40, 81):   # nearest centreline point near the last one (1 m steps)
				var cp: Array = crs.at(s0 + k)
				var dd: float = Vector2(cp[0] - ph.x, cp[1] - ph.z).length_squared()
				if dd < best_d: best_d = dd; _probe.fs = s0 + k
			var tp: Array = crs.at(float(_probe.fs) + 6.0 + absf(ph.v) * 0.5)
			var err: float = BikePhysics.ang_diff(atan2(-(tp[1] - ph.z), tp[0] - ph.x), ph.heading)
			var sv := clampf(err * 2.5, -1.0, 1.0)
			Input.action_press("steer_left", sv) if sv > 0.05 else Input.action_release("steer_left")
			Input.action_press("steer_right", -sv) if sv < -0.05 else Input.action_release("steer_right")
			if ph.crash_on:
				_probe.crash_t = _probe.get("crash_t", 0.0) + get_process_delta_time()
				if _probe.crash_t > 2.0:
					_probe.crash_t = 0.0
					var cp2: Array = crs.at(float(_probe.fs) + 3.0)
					game.get_up()
					ph.reset_at(cp2[0], cp2[1], atan2(-float(cp2[3]), float(cp2[2])))
					game._snap_prev()
			if OS.get_environment("BMX_PUMP") != "" and not ph.air and ph.prep > 0.15: Input.action_press("hop")   # tests: pump into lips
			else: Input.action_release("hop")
			await get_tree().process_frame
			if OS.get_environment("BMX_DUST_SHOTS") != "":   # the timed screenshots work here too
				var t0f := float(OS.get_environment("BMX_DUST_T0")) if OS.get_environment("BMX_DUST_T0") != "" else 3.0
				var nkf := int((el - t0f) * 2.0)
				if el > t0f and nkf != _probe.get("dust_k", -1) and nkf < 8:
					_probe["dust_k"] = nkf
					get_viewport().get_texture().get_image().save_png("%s_%d.png" % [OS.get_environment("BMX_DUST_SHOTS"), nkf])
			continue
		if OS.get_environment("BMX_STEER") != "":   # tests: hold a steady turn (+ left, - right) after 2 s
			var sv := float(OS.get_environment("BMX_STEER")) if el > 2.0 else 0.0
			Input.action_press("steer_left", maxf(sv, 0.0)) if sv > 0 else Input.action_release("steer_left")
			Input.action_press("steer_right", maxf(-sv, 0.0)) if sv < 0 else Input.action_release("steer_right")
		elif pedal and not straight and int(el) % 6 == 3: Input.action_press("steer_left")
		else: Input.action_release("steer_left")
		if pedal and not straight and int(el * 2) % 7 == 0: Input.action_press("hop")
		elif OS.get_environment("BMX_AIRPULL") != "" and game.phys.air and game.phys.air_time > 0.1: Input.action_press("hop")   # tests: tuck in the air
		else: Input.action_release("hop")
		if OS.get_environment("BMX_BAIL") != "" and el > float(OS.get_environment("BMX_BAIL")) and not _probe.has("bailed"):   # tests: bail (crash) here
			_probe["bailed"] = true
			game.phys.crash_pending = "BAIL!"
		if OS.get_environment("BMX_LAND_TEST") != "" and el > float(OS.get_environment("BMX_LAND_TEST")) and not _probe.has("landed"):   # tests: fake a hard landing
			_probe["landed"] = true
			game.on_landing(1.0, 8.0)
		if OS.get_environment("BMX_SKID") != "" and el > float(OS.get_environment("BMX_SKID")):   # tests: lock the rear (skid) from this time on
			Input.action_release("pedal"); Input.action_press("brake")
		await get_tree().process_frame
		if OS.get_environment("BMX_DUST_SHOTS") != "":   # tests: dir/prefix â€” a screenshot every 0.5 s after BMX_DUST_T0 (3 s)
			var t0d := float(OS.get_environment("BMX_DUST_T0")) if OS.get_environment("BMX_DUST_T0") != "" else 3.0
			var nk := int((el - t0d) * 2.0)
			if el > t0d and nk != _probe.get("dust_k", -1) and nk < 8:
				_probe["dust_k"] = nk
				get_viewport().get_texture().get_image().save_png("%s_%d.png" % [OS.get_environment("BMX_DUST_SHOTS"), nk])
		if OS.get_environment("BMX_FENCE") != "":   # tests: ride straight into the nearest fence, shots around the hit
			_fence_test(el)
		if OS.get_environment("BMX_CACTUS_ROW") != "":   # tests: the five cactus kinds in a row in front of the camera
			_cactus_row(el)
		if OS.get_environment("BMX_BODY_PROBE") != "":   # tests: the rider's body vs the bike
			var ph = game.phys
			_probe.hs_max = maxf(_probe.get("hs_max", 0.0), ph.hip_shift)
			_probe.hs_min = minf(_probe.get("hs_min", 0.0), ph.hip_shift)
			_probe.bx_max = maxf(_probe.get("bx_max", 0.0), absf(ph.body_x))
			if ph.air:
				_probe.air_f = _probe.get("air_f", 0) + 1
				_probe.rel_min = minf(_probe.get("rel_min", 0.0), ph.body_y - ph.y)
				_probe.pull_max = maxf(_probe.get("pull_max", 0.0), ph.air_pull)
		frames += 1
		tris +=RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)
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
	if not _probe.is_empty(): print("AUTOTEST body ", _probe)
	if game.clip_probe:
		var bs: Array = game.rider.bounce_stats
		print("BOUNCE body_rms=%.1fcm body_max=%.1fcm legs_feel=%.2fg" % [sqrt(bs[0] / maxi(bs[1], 1)) * 100, bs[2] * 100, sqrt(bs[3] / maxi(bs[1], 1)) / 9.81])
		var cs: Dictionary = game.clip_stats
		print("RIDE bottom_outs=%d body=%.2fg ground=%.2fg" % [st.probe_bottom, sqrt(st.probe_acc2 / maxi(st.probe_n, 1)) / 9.81, sqrt(st.probe_g2 / maxi(st.probe_n, 1)) / 9.81])
		print("CLIP frames=%d lifted=%d deepest_before=%.1fcm deepest_after=%.2fcm frames_inside=%d" % [cs.frames, cs.fixed, cs.before * 100, cs.after * 100, cs.bad])
	if OS.get_environment("BMX_KNEE_PROBE") != "":
		for row in game.rider.knee_dbg: print("KNEE ", row)
	if game.rider.limb_probe:
		for k in game.rider.limb_stats:
			var s: Dictionary = game.rider.limb_stats[k]
			print("LIMB %s frames=%d turn_max=%.1fdeg jump_max=%.1fcm flips=%d jumps=%d" % [k, s.frames, s.turn_max, s.jump_max * 100, s.flips, s.jumps])
			for w in s.worst: print("  LIMBW %s %s" % [k, w])
	print("AUTOTEST avg triangles/frame=%dk draw calls=%d" % [tris / maxi(frames, 1) / 1000, draws / maxi(frames, 1)])
	print("AUTOTEST frames=%d fps=%.1f pos=(%.1f, %.1f, %.1f) v=%.2f crash=%s sane=%s" % [frames, frames / seconds, st.x, st.y, st.z, st.v, st.crash_on, st.is_sane()])
	if rec != null:
		rec.set_recording_active(false)
		rec.get_recording().save_to_wav(OS.get_environment("BMX_REC"))
	var shot := OS.get_environment("BMX_SHOT")
	if shot != "":
		get_viewport().get_texture().get_image().save_png(shot)
	get_tree().quit()

## BMX_FENCE test: at 2 s put the bike 6 m in front of the nearest fence panel, aimed at it; shots
## at the hit and after (BMX_FENCE=dir/prefix)
var _airshots := 0
var _airshot_t := -10.0
var _fence := {}
func _fence_test(el: float) -> void:
	var ph = game.phys
	if _fence.is_empty() and el > 2.0:
		var best = null
		var bd := INF
		for key in game.terrain._col_grid:
			for c in game.terrain._col_grid[key]:
				if c.has("fence") and not c["fence"]["broken"] and (OS.get_environment("BMX_FENCE_STYLE") == "" or c["fence"]["style"] == OS.get_environment("BMX_FENCE_STYLE")):
					var d := Vector2(c.x - ph.x, c.z - ph.z).length()
					if d < bd: bd = d; best = c
		if best == null: return
		var p: Dictionary = best["fence"]
		var dir := Vector2(p.cx - best.x, p.cz - best.z)
		# the panel's own direction: from its first collider to its centre; ride across it
		var along := Vector2(p.cx, p.cz) - Vector2(best.x, best.z)
		var nrm := Vector2(-along.y, along.x).normalized() if along.length() > 0.1 else Vector2(1, 0)
		var start := Vector2(p.cx, p.cz) - nrm * 6.0
		ph.reset_at(start.x, start.y, atan2(-nrm.y, nrm.x))
		ph.v = 7.0
		_fence = {"panel": p, "t": el, "shot": 0}
		print("FENCE test: panel at (%.1f, %.1f) style=%s parts=%d" % [p.cx, p.cz, p.style, p.parts.size()])
	elif not _fence.is_empty():
		var p: Dictionary = _fence.panel
		var pre := OS.get_environment("BMX_FENCE")
		if _fence.shot == 0 and el > _fence.t + 0.3:
			get_viewport().get_texture().get_image().save_png(pre + "_0before.png"); _fence.shot = 1
		if _fence.shot == 1 and p.broken:
			_fence.hit = Engine.get_process_frames(); _fence.shot = 2
			var seen := []
			for k in game.terrain._col_grid:
				for c in game.terrain._col_grid[k]:
					if c.has("fence") and c["fence"]["broken"] and not seen.any(func(q): return is_same(q, c["fence"])):
						seen.append(c["fence"])
			var n := seen.size()
			print("FENCE broken panels=%d debris=%d lying=%d" % [n, game.terrain._debris._items.size(), game.terrain._debris._wrecks.size()])
		if _fence.has("hit") and Engine.get_process_frames() > _fence.hit + 25:   # stop near the wreck (later shots)
			ph.v = move_toward(ph.v, 0.0, 0.6)
		if _fence.shot >= 2 and _fence.shot < 7 and Engine.get_process_frames() >= _fence.hit + [0, 0, 2, 12, 30, 60, 720][_fence.shot]:
			if _fence.shot == 6: print("FENCE after 12 s: moving=%d lying=%d" % [game.terrain._debris._items.size(), game.terrain._debris._wrecks.size()])
			get_viewport().get_texture().get_image().save_png(pre + "_%d.png" % _fence.shot); _fence.shot += 1


## BMX_CACTUS_ROW=1: at 1.5 s the five cactus kinds stand in a row in front of the camera (BMX_CACTUS_DIST m,
## default 7); BMX_CACTUS_SMASH=secs smashes them all then (as if hit at bike height, 7 m/s across the view)
var _cacti := []
func _cactus_row(el: float) -> void:
	var tr = game.terrain
	if _cacti.is_empty() and el > 1.5:
		var cam: Camera3D = get_viewport().get_camera_3d()
		var fw := -cam.global_basis.z; fw.y = 0; fw = fw.normalized()
		var rt := fw.cross(Vector3.UP)
		var dist := float(OS.get_environment("BMX_CACTUS_DIST")) if OS.get_environment("BMX_CACTUS_DIST") != "" else 7.0
		for k in CactusGeo.KINDS:
			var side := float(OS.get_environment("BMX_CACTUS_SIDE")) if OS.get_environment("BMX_CACTUS_SIDE") != "" else 0.0
			var p: Vector3 = cam.global_position + fw * dist + rt * ((k - 2) * 1.45 + side)
			p.y = tr.height(p.x, p.z) - 0.03
			var col := TerrainField.lin([0x4f8a3c, 0x5c9a45, 0x6b9e4a][k % 3])
			var xf := Transform3D(Basis(Vector3.UP, k * 1.3), p)
			var mi := MeshInstance3D.new()
			mi.mesh = CactusGeo.MESHES[k]
			mi.material_override = tr._debris._cactus_material(col)
			tr.add_child(mi)
			mi.global_transform = xf
			_cacti.append({"mi": mi, "rec": {"xform": xf, "col": col, "kind": k}, "rt": rt})
		print("CACTUS row placed")
	if not _cacti.is_empty() and OS.get_environment("BMX_CACTUS_SMASH") != "" and el > float(OS.get_environment("BMX_CACTUS_SMASH")) and _cacti[0]["mi"].visible:
		var t0 := Time.get_ticks_usec()
		for c in _cacti:
			c["mi"].visible = false
			var o: Vector3 = c["rec"]["xform"].origin
			tr._debris.smash_cactus(c["rec"], c["rt"] * 7.0, o + Vector3(0, 0.45, 0) - c["rt"] * 0.25)
		print("CACTUS smashed %d in %.1f ms, debris moving=%d" % [_cacti.size(), (Time.get_ticks_usec() - t0) / 1000.0, tr._debris._items.size()])


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


## --hitch=<secs>: scripted ride (chase camera, vsync off) that looks for frame-time spikes and what
## the main thread was doing in them: terrain streaming (chunks turned into nodes, split into ground /
## occluder / collider / decorations / grids), physics, the rest. Prints one summary.
func _hitch(secs: float) -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	GameState.seed = int(OS.get_environment("BMX_SEED")) if OS.get_environment("BMX_SEED") != "" else 7
	await _new_game()
	_start_ride()
	game.cam.set_mode("chase")
	var vp := get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(vp, true)
	for i in 90: await get_tree().process_frame
	var tr: Terrain = game.terrain
	var ft := PackedFloat32Array()     # frame ms
	var sm := PackedFloat32Array()     # update_stream ms
	var nf := PackedInt32Array()       # chunks finalized
	var gp := PackedFloat32Array()     # GPU ms
	var ph := PackedFloat32Array()     # physics process ms
	var parts := PackedFloat64Array([0, 0, 0, 0, 0])
	var fin_ms := PackedFloat32Array()
	var t0 := Time.get_ticks_msec()
	var last := Time.get_ticks_usec()
	var p0 := Vector2(game.phys.x, game.phys.z)
	var dist := 0.0
	var csv := FileAccess.open(OS.get_environment("BMX_HITCH_CSV"), FileAccess.WRITE) if OS.get_environment("BMX_HITCH_CSV") != "" else null
	if csv: csv.store_line("t,frame,gpu,cpu_render,stream,fin,phys,draws,prims,speed,crash,puffs,air")
	while Time.get_ticks_msec() - t0 < secs * 1000.0:
		var el := (Time.get_ticks_msec() - t0) / 1000.0
		Input.action_press("pedal")
		if int(el * 0.7) % 3 == 1: Input.action_press("steer_left")
		else: Input.action_release("steer_left")
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		ft.append((now - last) / 1000.0)
		last = now
		sm.append(tr.last_stream_ms)
		nf.append(tr.last_finalized)
		if tr.last_finalized > 0:
			fin_ms.append(tr.last_stream_ms / tr.last_finalized)
			for i in 5: parts[i] += tr.fin_parts[i]
		gp.append(RenderingServer.viewport_get_measured_render_time_gpu(vp))
		ph.append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)
		if csv:
			var puffs := 0
			for i in game.dust._puff_age.size():
				if game.dust._puff_age[i] < game.dust._puff_life[i]: puffs += 1
			csv.store_line("%.3f,%.3f,%.3f,%.3f,%.3f,%d,%.3f,%d,%d,%.2f,%d,%d,%.2f" % [el, ft[-1], gp[-1],
				RenderingServer.viewport_get_measured_render_time_cpu(vp), sm[-1], nf[-1], ph[-1],
				RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
				RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME),
				game.phys.v, int(game.phys.crash_on), puffs, game.phys.air_k])
		var p1 := Vector2(game.phys.x, game.phys.z)
		dist += p1.distance_to(p0)
		p0 = p1
	Input.action_release("pedal"); Input.action_release("steer_left")
	var sorted := ft.duplicate(); sorted.sort()
	var n := ft.size()
	var med: float = sorted[n / 2]
	var spike := maxf(med * 2.0, med + 4.0)
	var spikes := 0; var sp_fin := 0; var sp_after := 0; var sp_sm := 0.0; var sp_gpu := 0.0
	var gpu_after := 0.0; var n_after := 0; var gpu_norm := 0.0; var n_norm := 0
	for i in n:
		var after := i > 0 and nf[i - 1] > 0
		if after: gpu_after += gp[i]; n_after += 1
		elif nf[i] == 0: gpu_norm += gp[i]; n_norm += 1
		if ft[i] > spike:
			spikes += 1
			sp_sm += sm[i]
			sp_gpu += gp[i]
			if nf[i] > 0: sp_fin += 1
			elif after: sp_after += 1
	var chunks := 0
	for v in nf: chunks += v
	var fsorted := fin_ms.duplicate(); fsorted.sort()
	print("HITCH %d frames, %.0f m ridden, %d chunks finalized | frame median %.2f ms, 1%% low %.2f, 0.1%% low %.2f, max %.2f" % [
		n, dist, chunks, med, sorted[int(n * 0.99)], sorted[int(n * 0.999)], sorted[n - 1]])
	print("HITCH spikes (> %.2f ms): %d | with a chunk finalize %d, frame right after one %d | avg stream %.2f ms, avg GPU %.2f ms in spikes" % [
		spike, spikes, sp_fin, sp_after, sp_sm / maxi(spikes, 1), sp_gpu / maxi(spikes, 1)])
	if fsorted.size() > 0:
		var c := float(maxi(chunks, 1))
		print("HITCH per chunk: avg %.2f ms, max %.2f | ground+tex %.2f, occluder %.2f, collider %.2f, decorations %.2f, grids+tape %.2f" % [
			Array(fsorted).reduce(func(a, b): return a + b, 0.0) / fsorted.size(), fsorted[fsorted.size() - 1],
			parts[0] / c, parts[1] / c, parts[2] / c, parts[3] / c, parts[4] / c])
	print("HITCH GPU: normal frames %.2f ms, frame after a finalize %.2f ms | physics avg %.2f ms" % [
		gpu_norm / maxi(n_norm, 1), gpu_after / maxi(n_after, 1), Array(ph).reduce(func(a, b): return a + b, 0.0) / n])
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
