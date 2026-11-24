extends Node
## Root: owns the ride (Game) and the menus. The world keeps running behind the title screen with a
## slow orbiting camera; Esc pauses a ride.

enum { MENU, RIDING, PAUSED }

var game: Game
var state := MENU
var ui := CanvasLayer.new()
var menu: Control
var pause_menu                 # the pause leaflet (ui/pause_pamphlet.gd), a CanvasLayer
var settings_open: Control
var controls_open: Control
var fade: ColorRect

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	ui.layer = 20
	add_child(ui)
	Input.joy_connection_changed.connect(_on_pad_connection)
	add_child(load("res://scripts/ui/fullscreen_button.gd").new())   # bottom-right fullscreen toggle (F11)
	fade = ColorRect.new()
	fade.color = Color(0.66, 0.84, 0.92)
	fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(fade)
	if Env.s("BMX_SEED") != "":   # tests: a fixed world behind the title screen too
		GameState.seed = int(Env.s("BMX_SEED"))
	if Env.s("BMX_LEVEL") != "": GameState.level = Env.s("BMX_LEVEL")   # tests: a test level (playground)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--level="): GameState.level = a.get_slice("=", 1)
	if "--garage" not in OS.get_cmdline_user_args() and "--rider" not in OS.get_cmdline_user_args() and "--shop" not in OS.get_cmdline_user_args():   # straight to the garage: don't build the world first
		var plain := true   # only a plain launch (or a title screenshot) gets the title backdrop; tests ride the real world
		for a in OS.get_cmdline_user_args():
			if not a.begins_with("--shot="): plain = false
		_new_game(plain)
		_show_menu()
	create_tween().set_ignore_time_scale().tween_property(fade, "modulate:a", 0.0, 0.8)
	# boot intro (the CRT TV): a plain launch only, or BMX_INTRO=1
	if (OS.get_cmdline_user_args().is_empty() or OS.get_environment("BMX_INTRO") != "") and CrtTv.assets_ok():   # (no TV files: no intro, straight to the menu)
		var intro := CrtIntro.new()
		intro.hold = true
		intro.still = (not Settings.get_v("boot_intro") and OS.get_environment("BMX_INTRO") != "1") or OS.get_environment("BMX_INTRO") == "still"
		add_child(intro)
		_prebuild_behind(intro)
		intro.finished.connect(func() -> void:
			var tw := create_tween().set_ignore_time_scale()
			tw.tween_property(intro.root, "modulate:a", 0.0, 4.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)   # the menu fades in slowly
			tw.tween_callback(intro.queue_free)
			if OS.get_environment("BMX_INTRO_SHOTS") != "":   # tests: a frame of the menu after it, then quit
				await get_tree().create_timer(2.5, true, false, true).timeout
				get_viewport().get_texture().get_image().save_png(OS.get_environment("BMX_INTRO_SHOTS") + "_menu.png")
				if OS.get_environment("BMX_INTRO_RIDE") != "":   # ... then RIDE: the pre-built world goes straight in
					var r0 := Time.get_ticks_msec()
					await _start_ride()
					print("INTRO ride start ms=", Time.get_ticks_msec() - r0, " prebuilt_used=", _prebuilt_taken)
					await get_tree().create_timer(4.0, true, false, true).timeout
					get_viewport().get_texture().get_image().save_png(OS.get_environment("BMX_INTRO_SHOTS") + "_ride.png")
				GameState.quit())
	# command-line: --ride skips the title screen; --autotest=N rides N seconds unattended then quits
	for a in OS.get_cmdline_user_args():
		if a == "--ride" or a.begins_with("--level="): _start_ride()
		elif a == "--demo": _start_demo()
		elif a.begins_with("--autotest"): _autotest(float(a.get_slice("=", 1)) if "=" in a else 10.0)
		elif a == "--garage": _open_garage()
		elif a == "--rider": _open_garage("rider")
		elif a == "--shop": _open_garage("shop")
		elif a.begins_with("--shot="): _shot(a.get_slice("=", 1))
		elif a.begins_with("--bench="): _bench(a.get_slice("=", 1))
		elif a.begins_with("--showcase="): _showcase(a.get_slice("=", 1))
		elif a.begins_with("--hitch"): _hitch(float(a.get_slice("=", 1)) if "=" in a else 30.0)
	if Env.s("BMX_PADSEQ") != "": _pad_seq(Env.s("BMX_PADSEQ"))

## tests: drive the menus with a synthetic Xbox pad (use with BMX_PAD=1), then quit. Comma-separated steps:
## u d l r (D-pad) a b x y lb rb start, `D700` = hold D-pad down 700 ms (U / L / R too), `lsd` / `lsr` = a flick
## of the left stick, esc / enter = keys, w500 = wait 500 ms, shot:<file.png>, at:<secs> = wait until then, mw:x:y:n = n mouse-wheel notches at x, y (n < 0 = up).
## Prints PADSEQ <step> focus=<the focused control> after each.
func _pad_seq(seq: String) -> void:
	var t0 := Time.get_ticks_msec()
	await get_tree().create_timer(2.0, true, false, true).timeout
	var btn := {"u": JOY_BUTTON_DPAD_UP, "d": JOY_BUTTON_DPAD_DOWN, "l": JOY_BUTTON_DPAD_LEFT, "r": JOY_BUTTON_DPAD_RIGHT,
		"a": JOY_BUTTON_A, "b": JOY_BUTTON_B, "x": JOY_BUTTON_X, "y": JOY_BUTTON_Y, "lb": JOY_BUTTON_LEFT_SHOULDER,
		"rb": JOY_BUTTON_RIGHT_SHOULDER, "start": JOY_BUTTON_START}
	var wait := func(ms: float) -> void: await get_tree().create_timer(ms / 1000.0, true, false, true).timeout
	for step in seq.split(","):
		step = step.strip_edges()
		if step.begins_with("shot:"):
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(step.substr(5))
			print("PADSEQ shot ", step.substr(5)); continue
		if step.begins_with("at:"):
			var until := float(step.substr(3)) * 1000.0
			while Time.get_ticks_msec() - t0 < until: await get_tree().process_frame
			continue
		if step.begins_with("w"): await wait.call(float(step.substr(1))); continue
		if step.begins_with("k:"):   # any key: k:O, k:M ...
			for down in [true, false]:
				var k := InputEventKey.new(); k.keycode = OS.find_keycode_from_string(step.substr(2))
				k.physical_keycode = k.keycode; k.pressed = down
				Input.parse_input_event(k); await wait.call(60)
		elif step.begins_with("mw:"):   # mw:x:y:n = n mouse-wheel notches at screen x, y (n < 0 = up), 40 ms apart
			var pr := step.substr(3).split(":")
			var at := Vector2(float(pr[0]), float(pr[1]))
			Input.warp_mouse(at)
			for i in absi(int(pr[2])):
				for down in [true, false]:
					var mb := InputEventMouseButton.new(); mb.position = at; mb.global_position = at
					mb.button_index = MOUSE_BUTTON_WHEEL_UP if int(pr[2]) < 0 else MOUSE_BUTTON_WHEEL_DOWN
					mb.pressed = down; mb.factor = 1.0
					Input.parse_input_event(mb)
				await wait.call(40)
		elif step.begins_with("click:"):   # click:x:y = a left mouse click at screen x, y
			var cp := step.substr(6).split(":")
			var at := Vector2(float(cp[0]), float(cp[1]))
			Input.warp_mouse(at)
			var mm := InputEventMouseMotion.new(); mm.position = at; mm.global_position = at
			Input.parse_input_event(mm); await wait.call(60)
			for down in [true, false]:
				var mb := InputEventMouseButton.new(); mb.position = at; mb.global_position = at
				mb.button_index = MOUSE_BUTTON_LEFT; mb.pressed = down
				mb.button_mask = MOUSE_BUTTON_MASK_LEFT if down else 0
				Input.parse_input_event(mb); await wait.call(60)
		elif step in ["esc", "enter"]:
			for down in [true, false]:
				var k := InputEventKey.new(); k.keycode = KEY_ESCAPE if step == "esc" else KEY_ENTER
				k.physical_keycode = k.keycode; k.pressed = down
				Input.parse_input_event(k); await wait.call(60)
		elif step.begins_with("ls"):
			var m := InputEventJoypadMotion.new()
			m.axis = JOY_AXIS_LEFT_Y if step[2] in "ud" else JOY_AXIS_LEFT_X
			m.axis_value = -1.0 if step[2] in "ul" else 1.0
			Input.parse_input_event(m); await wait.call(90)
			m = m.duplicate(); m.axis_value = 0.0
			Input.parse_input_event(m); await wait.call(60)
		elif step.length() > 1 and step[0] in "UDLR" and step.substr(1).is_valid_int():
			var jb := InputEventJoypadButton.new(); jb.button_index = btn[step[0].to_lower()]; jb.pressed = true
			Input.parse_input_event(jb)
			await wait.call(float(step.substr(1)))
			jb = jb.duplicate(); jb.pressed = false
			Input.parse_input_event(jb); await wait.call(60)
		elif btn.has(step):
			for down in [true, false]:
				var jb := InputEventJoypadButton.new(); jb.button_index = btn[step]; jb.pressed = down
				Input.parse_input_event(jb); await wait.call(70)
		else:
			print("PADSEQ unknown step ", step); continue
		await wait.call(120)
		print("PADSEQ ", step, " focus=", _focus_desc())
	await wait.call(200)
	GameState.quit()

func _focus_desc() -> String:
	var vps: Array = []
	if is_instance_valid(pause_menu) and pause_menu.get("page"): vps.append(pause_menu.page)
	for n in get_tree().get_nodes_in_group(&"pad_nav_vp"): vps.append(n)
	vps.append(get_viewport())
	for vp in vps:
		var f: Control = vp.gui_get_focus_owner()
		if f:
			var t = f.get("text")
			var extra := ""
			if f is Range: extra = " v=%s" % (f as Range).value
			if f is OptionButton: extra = " sel=%d" % (f as OptionButton).selected
			if f is TabBar: extra = " tab=%d" % (f as TabBar).current_tab
			var row := f.get_parent()
			var lbl := ""
			if row and row.get_child_count() > 0 and row.get_child(0) is Label: lbl = " row='%s'" % row.get_child(0).text
			if lbl == "" and row and row.get_parent() and row.get_parent().get_child_count() > 0 and row.get_parent().get_child(0) is Label: lbl = " row='%s'" % row.get_parent().get_child(0).text
			return "%s '%s'%s%s" % [f.get_class(), t if t != null else "", extra, lbl]
	return "-"

var _rebuilding := false   # _new_game is between freeing the old Game and adding the new one
func _new_game(title := false) -> void:
	while _rebuilding: await get_tree().process_frame   # two quick restarts: one after the other, never two Games
	_rebuilding = true
	if game:
		game.queue_free()
		await game.tree_exited
	game = Game.new()
	game.title_world = title   # the title screen's own backdrop world; a ride swaps it for the real one
	game.level = "" if title else GameState.level
	if title and not _title_keep.is_empty():   # the title world's terrain kept from before the garage
		game.reuse = _title_keep
		_title_keep = {}
	game.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(game)
	move_child(game, 0)
	_rebuilding = false

## the title world's terrain + far hills, out of the tree while the garage is open (Game.take_world)
var _title_keep := {}

func _free_title_keep() -> void:
	for n in _title_keep.values():
		if is_instance_valid(n): (n as Node).free()   # out of the tree: its workers were joined when it left
	_title_keep = {}

func _exit_tree() -> void:
	LensScene.join()
	_free_title_keep()
	Garage.free_kept(true)   # the garage's world out of the door, kept between visits

func restart_ride() -> void:
	fade.modulate.a = 1.0
	await _new_game(game != null and game.title_world and state == MENU)
	_set_riding(state != MENU)
	create_tween().set_ignore_time_scale().tween_property(fade, "modulate:a", 0.0, 0.5)

## a new world seed: the title backdrop stays as it is, only a real ride world is rebuilt
func _seed_changed() -> void:
	if not (game and game.title_world): restart_ride()

func _set_riding(riding: bool) -> void:
	game.input_enabled = riding
	game.hud.visible = riding
	game.set_scenic(not riding)   # title screen: golden hour over the hills
	if riding:
		game.cam.set_mode(game.cam.default_mode())

# ---------------------------------------------------------------- the ride, built during the boot intro
var ride_ready: Game            # the player's own world, built off-screen while the intro holds on black
var _ride_park: SubViewport     # its own World3D, never drawn
var _prebuilt_taken := false     # tests: RIDE used the pre-built world
var _ride_sig := ""             # what it was built from (seed, bike, garage build, rider): stale if that changed

func _ride_sig_now() -> String:
	var cfg: Dictionary = GameState.bike_config()
	return JSON.stringify([GameState.seed, GameState.bike_id, cfg, RiderPanels.load_look(),
		RiderPanels.load_pose(GameState.bike_id, cfg.get("pose", {}))])

## while the intro shows black (only the TV's standby LED), build the ride world (the main-thread hitch is hidden
## there), then let the intro play. RIDE then just moves it in (_take_prebuilt).
func _prebuild_behind(intro: CrtIntro) -> void:
	for i in 3: await get_tree().process_frame   # the black frame is up first
	if OS.get_environment("BMX_NO_PREBUILD") != "":   # tests: the old way (RIDE builds the world)
		intro.hold = false
		return
	var t0 := Time.get_ticks_msec()
	_ride_park = SubViewport.new()
	_ride_park.own_world_3d = true
	_ride_park.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_ride_park.size = Vector2i(get_viewport().get_visible_rect().size)
	add_child(_ride_park)
	var g := Game.new()
	g.title_world = false
	_ride_park.add_child(g)   # its _ready builds the terrain, bike, rider... here
	g.process_mode = Node.PROCESS_MODE_DISABLED
	ride_ready = g
	_ride_sig = _ride_sig_now()
	print("PREBUILD ride world ms=", Time.get_ticks_msec() - t0)
	# the ride setup page's turntable with this bike on it, parked hidden (~0.2 s that RIDE no longer waits for)
	t0 = Time.get_ticks_msec()
	hero_view = BikeTurntable.new()
	hero_view.visible = false
	add_child(hero_view)
	hero_view.show_rider(RiderPanels.load_look())   # the Character step's standing rider too
	hero_view.set_bike(GameState.bike_id)
	print("PREBUILD turntable ms=", Time.get_ticks_msec() - t0)
	LensScene.prewarm()   # the RACE step's trail preview: its land is worked out on a worker meanwhile
	if is_instance_valid(intro): intro.hold = false

func _take_prebuilt() -> bool:
	if ride_ready == null or not is_instance_valid(ride_ready): return false
	if GameState.level != "": return false   # a test level: the pre-built world is the normal one (kept for later)
	var g := ride_ready
	ride_ready = null
	if _ride_sig_now() != _ride_sig:   # changed in the menus since: build it the normal way
		_ride_park.queue_free()
		_ride_park = null
		return false
	if game: game.queue_free()
	g.reparent(self, false)
	move_child(g, 0)
	g.process_mode = Node.PROCESS_MODE_PAUSABLE
	g.cam.current = true
	if g.hud and g.hud.has_method("set_computer"): g.hud.set_computer()
	game = g
	_ride_park.queue_free()
	_ride_park = null
	_prebuilt_taken = true
	return true

# ---------------------------------------------------------------- title screen
func _show_menu() -> void:
	state = MENU
	_held_time_scale = -1.0   # (paused in a crash's slow motion, then Main menu: the menu runs at normal speed)
	_held_audio_speed = -1.0
	GameState.end_ride()
	Steam.presence("In the menus")
	get_tree().paused = false
	if game: game.exit_photo()
	_close_controls()
	_set_riding(false)
	if menu: menu.queue_free()
	menu = Control.new()
	menu.theme = UITheme.paper_theme()
	menu.set_anchors_preset(Control.PRESET_FULL_RECT)
	menu.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(menu)
	ui.move_child(menu, 0)
	# B on the ride setup = one step back (step 1 -> the main page); LB / RB = previous / next step
	PadNav.attach(menu, {"back": _menu_back, "tabs": _menu_tabs, "first": func(): return menu_focus if is_instance_valid(menu_focus) else null})
	# one flat white card down the left (the garage and settings use the same cards), the view beside it
	# the menu card fills the screen height, the small stats card sits under it at the bottom
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", Tokens.S3)
	stack.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	stack.offset_left = MENU_EDGE; stack.offset_right = MENU_EDGE + MENU_W
	stack.offset_top = MENU_EDGE; stack.offset_bottom = -MENU_EDGE
	menu.add_child(stack)
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", UITheme.card_style(Tokens.PAPER, Tokens.R_XL, Tokens.S6))
	card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stack.add_child(card)
	CrashLog.notice(menu)   # "the game closed unexpectedly last time" once per launch
	menu_stats = _stats_card()
	stack.add_child(menu_stats)
	var outer := VBoxContainer.new()
	card.add_child(outer)
	var vb := VBoxContainer.new()
	vb.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_theme_constant_override("separation", Tokens.S3)
	outer.add_child(vb)
	# title: the game's logo, the same one the TV shows (ui/game_logo.gd)
	var head := VBoxContainer.new()
	var logo := GameLogo.new()
	logo.custom_minimum_size = Vector2(0, 130)
	head.add_child(logo)
	vb.add_child(head)
	menu_col = vb
	# QUIT, top right of the screen (asks first)
	menu_quit = UITheme.make_button("QUIT", _confirm_quit, "secondary", Tokens.T_LG)
	menu_quit.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	menu_quit.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	menu_quit.offset_right = -MENU_EDGE; menu_quit.offset_top = MENU_EDGE
	menu_quit.offset_left = -MENU_EDGE - 140; menu_quit.offset_bottom = MENU_EDGE + Tokens.H_CHIP + Tokens.S2
	menu.add_child(menu_quit)
	# SETTINGS: a gear button just left of QUIT (controls are a tab in it)
	var bh := Tokens.H_CHIP + Tokens.S2
	menu_settings = UITheme.make_button("", _open_settings, "secondary", Tokens.T_LG)
	menu_settings.tooltip_text = "Settings"
	menu_settings.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	menu_settings.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	menu_settings.offset_right = -MENU_EDGE - 140 - Tokens.S3; menu_settings.offset_top = MENU_EDGE
	menu_settings.offset_left = menu_settings.offset_right - bh; menu_settings.offset_bottom = MENU_EDGE + bh
	var gear := GearIcon.new()
	gear.set_anchors_preset(Control.PRESET_FULL_RECT)
	gear.offset_left = Tokens.S3; gear.offset_top = Tokens.S3; gear.offset_right = -Tokens.S3; gear.offset_bottom = -Tokens.S3
	menu_settings.add_child(gear)
	menu.add_child(menu_settings)
	# version: small, bottom right of the screen, just left of the fullscreen button and centred on it
	menu_version = UITheme.text("v%s  ·  Godot %s" % [ProjectSettings.get_setting("application/config/version", "1.0.0"), Engine.get_version_info().string], Color(1, 1, 1, 0.8), Tokens.T_XS)
	menu_version.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	menu_version.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	menu_version.grow_vertical = Control.GROW_DIRECTION_BEGIN
	menu_version.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	menu_version.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	menu_version.offset_right = -FSB.MARGIN - FSB.SIZE - Tokens.S3
	menu_version.offset_bottom = -FSB.MARGIN
	menu_version.offset_top = -FSB.MARGIN - FSB.SIZE
	menu_version.mouse_filter = Control.MOUSE_FILTER_IGNORE
	menu.add_child(menu_version)
	if _menu_after == "replays": _menu_page_replays()
	else: _menu_page_main()
	_menu_after = ""
	if Env.s("BMX_MENU_PAGE") == "setup": _menu_page_setup(int(Env.s("BMX_SETUP_STEP")))   # tests: the ride setup page (BMX_SETUP_STEP=0..3)
	if Env.s("BMX_MENU_PAGE") == "credits": _show_credits()   # tests: the credits window
	if PartThumbs.BAKE != "" and not _baking:
		_baking = true
		_bake_menu_thumbs.call_deferred()

## The release bake's menu pass (tools/bake_thumbs.ps1): every ride setup step for every bike, with each
## of their tabs (bike colours / wheels, character kit / helmet / plate), so every picture a fresh install
## shows there ships with the game. Then quits. (The garage and rider room have their own pass.)
var _baking := false
func _bake_menu_thumbs() -> void:
	var settle := func() -> void:
		var quiet := 0
		while quiet < 4:
			await get_tree().process_frame
			quiet = quiet + 1 if (not is_instance_valid(bike_thumbs) or bike_thumbs.idle()) else 0
	await get_tree().create_timer(2.0).timeout
	for id in GameState.BIKES:
		GameState.bike_id = id
		for step in SETUP_STEPS.size():
			var tabs := [""]
			if step == 1: tabs = ["colour", "wheels"]
			if step == 2: tabs = ["kit", "hair", "plate"]
			for tb in tabs:
				if step == 1: tune_cat = tb
				if step == 2: char_tab = tb
				_menu_page_setup(step)
				await settle.call()
		print("BAKE menu bike=%s pictures=%d" % [id, PartThumbs.baked_count()])
	print("BAKE done mode=menu pictures=%d" % PartThumbs.baked_count())
	GameState.quit()

var menu_quit: Button
var menu_settings: Button
var menu_version: Label
var menu_stats: Control

## the small card under the title menu: this week (distance, rides), the weekly streak and the lifetime total
func _stats_card() -> Control:
	var card := PanelContainer.new()
	var st := UITheme.card_style(Tokens.PAPER, Tokens.R_XL, Tokens.S5)
	st.content_margin_left = Tokens.S6; st.content_margin_right = Tokens.S6   # text lines up with the menu card's
	card.add_theme_stylebox_override("panel", st)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", Tokens.S4)
	card.add_child(row)
	var mi: bool = Settings.get_v("units") == 1
	var unit := 1609.344 if mi else 1000.0
	var wk := GameState.week_totals()
	var streak := GameState.week_streak()
	var stat := func(cap: String, val: String) -> void:
		var col := VBoxContainer.new()
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.add_theme_constant_override("separation", 0)
		col.add_child(UITheme.caption(cap))
		col.add_child(UITheme.display(val, Tokens.T_XL, Tokens.INK, Tokens.SLANT))
		row.add_child(col)
	stat.call("THIS WEEK", "%.1f %s" % [float(wk.metres) / unit, "MI" if mi else "KM"])
	stat.call("RIDES", str(wk.rides))
	stat.call("STREAK", "%d WK" % streak)
	stat.call("TOTAL", "%d %s" % [roundi(float(GameState.records.distance) / unit), "MI" if mi else "KM"])
	return card

## "Quit the game?" over the title menu: QUIT / CANCEL (B, Esc and a click beside it cancel)
func _confirm_quit() -> void:
	if not is_instance_valid(menu) or menu.has_node("QuitAsk"): return
	var veil := ColorRect.new()
	veil.name = "QuitAsk"
	veil.color = Color(0, 0, 0, 0.45)
	veil.set_anchors_preset(Control.PRESET_FULL_RECT)
	veil.mouse_filter = Control.MOUSE_FILTER_STOP
	menu.add_child(veil)
	var close := func(): if is_instance_valid(veil): veil.queue_free()
	veil.gui_input.connect(func(e: InputEvent):
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT: close.call())
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	veil.add_child(center)
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", UITheme.card_style(Tokens.PAPER, Tokens.R_XL, Tokens.S7))
	center.add_child(card)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", Tokens.S5)
	card.add_child(vb)
	vb.add_child(UITheme.display("QUIT THE GAME?", Tokens.T_2XL))
	vb.add_child(UITheme.text("Are you sure? Your bike, rider and settings are saved.", Tokens.INK_SOFT, Tokens.T_MD))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", Tokens.S3)
	row.alignment = BoxContainer.ALIGNMENT_END
	vb.add_child(row)
	var cancel := UITheme.make_button("CANCEL", close, "secondary", Tokens.T_LG)
	row.add_child(cancel)
	row.add_child(UITheme.make_button("QUIT", func(): GameState.save(); GameState.quit(), "primary", Tokens.T_LG))
	PadNav.attach(veil, {"back": close, "first": func(): return cancel})
	cancel.grab_focus.call_deferred()

const FSB := preload("res://scripts/ui/fullscreen_button.gd")   # the corner fullscreen button (the version sits beside it)
const MENU_EDGE := Tokens.S8
const MENU_W := Tokens.CARD_W

## the column under the title: everything after the title block (index 1 on) is the page
var menu_col: VBoxContainer
var computer_card: Control   # right side of the ride setup page: the bike computer close-up

## RIDE setup, right card: pick the bike computer (size / model, some have no navigation), turn it round
## in 3D, and it is mounted for every ride from now on
func _build_computer_card() -> HBoxContainer:
	var wrap := HBoxContainer.new()
	wrap.add_theme_constant_override("separation", Tokens.S4)
	computer_card = wrap
	# left: what it is, the models, the device settings
	var left := PanelContainer.new()
	left.add_theme_stylebox_override("panel", UITheme.card_style(Tokens.PAPER, Tokens.R_XL, Tokens.S6))
	left.custom_minimum_size.x = 560
	wrap.add_child(left)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", Tokens.S3)
	left.add_child(vb)
	vb.add_child(UITheme.caption("MODEL"))
	var name_l := UITheme.display("", Tokens.T_3XL + Tokens.S4, Tokens.INK, Tokens.SLANT_TITLE)
	vb.add_child(name_l)
	var spec_l := UITheme.caption("", Tokens.INK_SOFT, Tokens.T_SM)
	vb.add_child(spec_l)
	var blurb_l := UITheme.text("", Tokens.INK_SOFT, Tokens.T_MD)
	vb.add_child(blurb_l)
	# right: the big 3D close-up
	var right := PanelContainer.new()
	right.add_theme_stylebox_override("panel", UITheme.card_style(Tokens.PAPER, Tokens.R_XL, Tokens.S5))
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wrap.add_child(right)
	var rv := VBoxContainer.new()
	right.add_child(rv)
	var pv := ComputerPreview.new()
	pv.size_flags_vertical = Control.SIZE_EXPAND_FILL
	pv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rv.add_child(pv)
	rv.add_child(UITheme.text("DRAG TO TURN  ·  WHEEL TO ZOOM  ·  CLICK THE SCREEN TO FLIP PAGES", Tokens.INK_SOFT, Tokens.T_XS))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", Tokens.S2)
	vb.add_child(row)
	var group := ButtonGroup.new()
	var set_box := VBoxContainer.new()
	var build_settings := func(id: String) -> void: _build_computer_settings(set_box, pv, id)
	vb.add_child(UITheme.spacer(Tokens.S2))
	vb.add_child(UITheme.caption("DEVICE SETTINGS"))
	set_box.add_theme_constant_override("separation", Tokens.S2)
	vb.add_child(set_box)
	var apply := func(id: String) -> void:
		var u := ComputerUnits.get_unit(id)
		name_l.text = u.name
		spec_l.text = ComputerUnits.spec(id)
		blurb_l.text = u.blurb
		pv.set_unit(id)
		build_settings.call(id)
	for id in ComputerUnits.ORDER:
		var u := ComputerUnits.get_unit(id)
		var b := UITheme.make_button(String(u.name).split(" ")[0], Callable(), "chip", Tokens.T_MD)
		b.toggle_mode = true
		b.button_group = group
		b.button_pressed = id == GameState.computer_id
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(func():
			GameState.computer_id = id
			GameState.save()
			apply.call(id)
			if game: game.hud.set_computer())
		row.add_child(b)
	apply.call(GameState.computer_id)
	return wrap

## the DEVICE SETTINGS block of the computer card: pages, alerts, beep, backlight of the picked model (saved per model)
func _build_computer_settings(box: VBoxContainer, pv: ComputerPreview, id: String) -> void:
	for c in box.get_children():
		box.remove_child(c); c.queue_free()
	var u := ComputerUnits.get_unit(id)
	var chip := func(text: String, on: bool, cb: Callable) -> Button:
		var b := UITheme.make_button(text, Callable(), "chip", Tokens.T_SM)
		b.toggle_mode = true
		b.button_pressed = on
		b.toggled.connect(func(v: bool):
			cb.call(v)
			GameState.save()
			pv.refresh()
			if game: game.hud.set_computer())
		return b
	box.add_child(UITheme.caption("PAGES", Tokens.INK_SOFT, Tokens.T_XS))
	var pr := HFlowContainer.new()
	pr.add_theme_constant_override("h_separation", Tokens.S2)
	pr.add_theme_constant_override("v_separation", Tokens.S2)
	box.add_child(pr)
	var off: Array = ComputerUnits.opt(id, "off")
	for p in u.order:
		var pid := int(p)
		if pid == 0: continue
		pr.add_child(chip.call(ComputerUnits.TITLES[pid], not (pid in off), func(v: bool):
			var o: Array = ComputerUnits.opt(id, "off").duplicate()
			if v: o.erase(pid)
			elif not (pid in o): o.append(pid)
			ComputerUnits.set_opt(id, "off", o)))
	var tr := HFlowContainer.new()
	tr.add_theme_constant_override("h_separation", Tokens.S2)
	tr.add_theme_constant_override("v_separation", Tokens.S2)
	box.add_child(tr)
	if u.nav:
		tr.add_child(chip.call("TRAIL ALERTS", bool(ComputerUnits.opt(id, "alerts")), func(v: bool): ComputerUnits.set_opt(id, "alerts", v)))
	tr.add_child(chip.call("BEEP", bool(ComputerUnits.opt(id, "beep")), func(v: bool): ComputerUnits.set_opt(id, "beep", v)))
	tr.add_child(chip.call("BACKLIGHT ALWAYS ON", int(ComputerUnits.opt(id, "light")) == 1, func(v: bool): ComputerUnits.set_opt(id, "light", 1 if v else 0)))

func _menu_clear() -> void:
	if is_instance_valid(computer_card): computer_card.queue_free()
	computer_card = null
	if is_instance_valid(setup_screen): setup_screen.queue_free()
	for i in range(menu_col.get_child_count() - 1, 0, -1):
		var c := menu_col.get_child(i)
		menu_col.remove_child(c); c.queue_free()
	menu_col.add_child(UITheme.spacer(Tokens.S7))

var menu_page := "main"
var menu_focus: Control   # where the pad cursor lands on this page (RIDE, NEXT)

func _menu_back() -> void:
	if menu_page == "levels" or menu_page == "replays": _menu_page_main(); return
	if menu_page != "setup": return
	if setup_step > 0: _menu_page_setup(setup_step - 1)
	else: _menu_page_main()

func _menu_tabs(dir: int) -> void:
	if menu_page == "setup": _menu_page_setup(clampi(setup_step + dir, 0, SETUP_STEPS.size() - 1))

func _menu_page_main() -> void:
	_menu_clear()
	menu_page = "main"
	var vb := menu_col
	var fill := func() -> void:   # equal stretch above and below: the menu sits centred under the logo
		var c := Control.new(); c.size_flags_vertical = Control.SIZE_EXPAND_FILL; vb.add_child(c)
	fill.call()
	var ride := _menu_button("RIDE", "", _menu_page_setup, true, true)
	vb.add_child(ride)
	if Env.s("BMX_LEVEL") == "": GameState.level = ""   # back on the title: RIDE / the garage ride the real world
	# LEVELS: test levels (DEMO is off the title menu: the in-game panel switches the AI rider on; _start_demo is kept)
	vb.add_child(_menu_button("LEVELS", "", _menu_page_levels, false, true))
	vb.add_child(_menu_button("REPLAYS", "", _menu_page_replays, false, true))
	vb.add_child(_menu_button("SHOP", "", _open_garage.bind("shop"), false, true))
	vb.add_child(_menu_button("GARAGE", "", _open_garage, false, true))
	vb.add_child(_menu_button("RIDER", "", _open_garage.bind("rider"), false, true))
	vb.add_child(UITheme.spacer(Tokens.S2))
	# world seed
	var world_cap := UITheme.caption("WORLD")
	world_cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(world_cap)
	var seed_row := HBoxContainer.new()
	seed_row.add_theme_constant_override("separation", Tokens.S2)
	var se := LineEdit.new()
	se.text = str(GameState.seed)
	se.placeholder_text = "World seed"
	se.alignment = HORIZONTAL_ALIGNMENT_CENTER
	se.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	se.custom_minimum_size.y = Tokens.H_CHIP
	se.tooltip_text = "World seed: type a number and press Enter"
	se.text_submitted.connect(func(t):
		if t.is_valid_int():
			GameState.seed = int(t); _seed_changed())
	seed_row.add_child(se)
	seed_row.add_child(UITheme.make_button("NEW WORLD", func(): GameState.new_seed(); se.text = str(GameState.seed); _seed_changed(), "chip", Tokens.T_LG))
	vb.add_child(seed_row)
	var cred := UITheme.make_button("CREDITS", _show_credits, "link", Tokens.T_XL)
	cred.alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(cred)
	fill.call()
	if is_instance_valid(menu_quit): menu_quit.visible = true
	if is_instance_valid(menu_settings): menu_settings.visible = true
	if is_instance_valid(menu_version): menu_version.visible = true
	if is_instance_valid(menu_stats): menu_stats.visible = true
	menu_focus = ride
	ride.grab_focus.call_deferred()
	if Env.s("BMX_REPLAY_WATCH") != "" and not _probe.get("watch", false):   # tests: watch a saved replay file
		_probe.watch = true
		print("AUTOTEST watch: ", Env.s("BMX_REPLAY_WATCH"))
		_watch_replay.call_deferred(Env.s("BMX_REPLAY_WATCH"))

## LEVELS: hand-built places instead of the endless trail. For now only the test playground (scripts/levels:
## measured jumps, drops, rollers, slopes, cambers, berms on a flat plane; every jump is measured on screen)
func _menu_page_levels() -> void:
	_menu_clear()
	menu_page = "levels"
	var vb := menu_col
	var fill := func() -> void:
		var c := Control.new(); c.size_flags_vertical = Control.SIZE_EXPAND_FILL; vb.add_child(c)
	fill.call()
	var cap := UITheme.caption("LEVELS")
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(cap)
	var pg := _menu_button("TEST PLAYGROUND", "Jumps, drops, rollers, slopes, berms · measured", func():
		GameState.level = "playground"
		_start_ride(), true, true)
	vb.add_child(pg)
	vb.add_child(_menu_button("BACK", "", _menu_page_main, false, true))
	fill.call()
	menu_focus = pg
	pg.grab_focus.call_deferred()

## REPLAYS: rides saved from the instant replay (S / pad View in it), newest first. Watching one rebuilds its
## world, bike and rider from the file and plays it; leaving comes back here
func _menu_page_replays() -> void:
	_menu_clear()
	menu_page = "replays"
	var vb := menu_col
	var fill := func() -> void:
		var c := Control.new(); c.size_flags_vertical = Control.SIZE_EXPAND_FILL; vb.add_child(c)
	fill.call()
	var cap := UITheme.caption("REPLAYS")
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(cap)
	var first: Control = null
	var files := ReplayMode.list_saved()
	for path in files.slice(0, 8):
		var h := ReplayMode.read_header(path)
		if h.is_empty(): continue
		var dt := String(h.get("date", "")).split("T")
		var when := "%s  %s" % [dt[0], dt[1].substr(0, 5) if dt.size() > 1 else ""]
		var bike := String(GameState.BIKES.get(str(h.get("bike", "")), {}).get("label", "")).to_upper()
		var b := _menu_button(when, "%s  ·  %s  ·  WORLD %s" % [ReplayMode.clock(float(h.get("secs", 0.0))), bike, str(h.get("seed", ""))],
			_watch_replay.bind(path), false, true)
		vb.add_child(b)
		if first == null: first = b
	if files.is_empty():
		var none := UITheme.caption("Nothing saved yet: press S (pad View) in a replay (I) to keep one")
		none.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		none.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		vb.add_child(none)
	var folder := UITheme.make_button("OPEN FOLDER", func():
		DirAccess.make_dir_recursive_absolute(ReplayMode.dir())
		OS.shell_open(ProjectSettings.globalize_path(ReplayMode.dir())), "link", Tokens.T_LG)
	folder.alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(folder)
	var back := _menu_button("BACK", "", _menu_page_main, false, true)
	vb.add_child(back)
	fill.call()
	menu_focus = first if first != null else back
	menu_focus.grab_focus.call_deferred()

var _view_back := {}
var _menu_after := ""   # _show_menu opens this page instead of the main one (back from a saved replay)
## watch a saved replay: build its world (seed), bike (its build) and rider (its look), then play it
func _watch_replay(path: String) -> void:
	var rd := ReplayMode.read_file(path)
	if rd.is_empty(): return
	var h: Dictionary = rd.head
	_view_back = {"seed": GameState.seed, "bike": GameState.bike_id, "level": GameState.level}
	GameState.view = h
	GameState.seed = int(h.get("seed", GameState.seed))
	if GameState.BIKES.has(str(h.get("bike", ""))): GameState.bike_id = str(h.bike)
	GameState.level = str(h.get("level", ""))
	fade.modulate.a = 1.0
	if menu: menu.queue_free(); menu = null
	if is_instance_valid(setup_screen): setup_screen.queue_free()
	await _new_game(false)
	state = RIDING
	_set_riding(true)
	if h.get("light") is Dictionary and h.has("hour"):   # the light it was ridden in
		LightSettings.ensure_loaded()
		var L: Dictionary = LightSettings.current.duplicate(true)
		L.merge(h.light, true)
		game._apply_light(float(h.hour), L)
	if not game.replay.load_saved(rd) or not game.open_replay():
		_replay_view_done()
		return
	create_tween().set_ignore_time_scale().tween_property(fade, "modulate:a", 0.0, 0.5)

## left a saved replay: the player's own seed / bike back, the title world, the REPLAYS page
func _replay_view_done() -> void:
	GameState.view = {}
	if not _view_back.is_empty():
		GameState.seed = _view_back.seed; GameState.bike_id = _view_back.bike; GameState.level = _view_back.level
	_view_back = {}
	fade.modulate.a = 1.0
	await _new_game(true)
	_menu_after = "replays"
	_show_menu()
	create_tween().set_ignore_time_scale().tween_property(fade, "modulate:a", 0.0, 0.5)
	if Env.s("BMX_REPLAY_WATCH") != "":   # tests: the page, then quit
		await get_tree().create_timer(2.0).timeout
		if Env.s("BMX_REPLAY_WATCH_SHOT") != "": get_viewport().get_texture().get_image().save_png(Env.s("BMX_REPLAY_WATCH_SHOT"))
		var vc := get_viewport().get_camera_3d()
		print("AUTOTEST watch done: menu_page=%s cam=%s at=%s game_title=%s menu=%s vis=%s ui_vis=%s fade=%.2f state=%d disable3d=%s" % [menu_page, vc.name if vc else "none",
			str(vc.global_position) if vc else "-", game.title_world if game else "-", is_instance_valid(menu), menu.is_visible_in_tree() if is_instance_valid(menu) else false,
			ui.visible, fade.modulate.a, state, get_tree().root.disable_3d])
		get_tree().quit()

## RIDE -> choose the bike and the time of day, then GO
const GoggleLens = preload("res://scripts/rider/goggle_lens.gd")   # goggle lens = the ride's colour grade (RACE step)
const TimeSlider = preload("res://scripts/ui/time_slider.gd")
const LensScene = preload("res://scripts/ui/lens_scene.gd")
var lens_view: SubViewportContainer   # the RACE step's trail preview (LensScene)
var GOGGLE_VIEW: Vector3 = Vector3(1.0, 0.12, 0.16) if Env.s("BMX_GOG_VIEW") == "" else str_to_var("Vector3(" + Env.s("BMX_GOG_VIEW") + ")")   # lens cards: the camera looks from here
const LensIcon = preload("res://scripts/ui/lens_icon.gd")
const SETUP_STEPS := ["BIKE", "TUNE", "CHARACTER", "COMPUTER", "RACE"]
const COMPUTER_STEP := 3
var setup_step := 0
var bike_dirty := false   # the bike was changed in the selection flow; the ride is rebuilt on RACE
var bike_thumbs: PartThumbs   # small pictures for the cards
var setup_screen: Control     # the full-screen selection flow (covers the landscape)

func _ensure_thumbs() -> void:
	if not is_instance_valid(bike_thumbs):
		bike_thumbs = PartThumbs.new()
		add_child(bike_thumbs)
	for id in GameState.BIKES:   # pre-render every picture (one per frame, cached) so switching is instant
		bike_thumbs.request(PartThumbs.bike_key(id), PartThumbs.make_bike.bind(id), Vector3(0.45, 0.2, 1.0), func(_t): pass)

func _bike_pic(th: PartThumbs, id: String, min_size: Vector2) -> TextureRect:
	var pic := TextureRect.new()
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	pic.custom_minimum_size = min_size
	pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	th.request(PartThumbs.bike_key(id), PartThumbs.make_bike.bind(id), Vector3(0.45, 0.2, 1.0), func(t): if is_instance_valid(pic): pic.texture = t)
	return pic

var hero_view: BikeTurntable
var hero_name: Label
var hero_spec: Label

func _hero_text(id: String) -> void:
	var bk: Dictionary = GameState.BIKES[id]
	hero_name.text = String(bk.label).to_upper()
	hero_spec.text = "DOWNHILL  ·  GEARED  ·  YOUR GARAGE BUILD" if bk.get("garage", false) else "FREESTYLE  ·  LIGHT  ·  NIMBLE"

## RIDE -> a full-screen flow like a racing game's pre-race screens (it covers the landscape):
## 1 BIKE (presets), 2 RIDER (kit), 3 COMPUTER (Garmin model), 4 RACE (time of day, then RACE).
## Bike / rider / race: the bike turns on its podium in the whole left side (title, name and BACK sit inside
## that view), the picks are a column on the right. Computer: the whole screen is the device.
func _menu_page_setup(step := 0) -> void:
	var probe_t := Time.get_ticks_usec()
	_menu_page_setup_build(step)
	if Env.s("BMX_SETUP_PROBE") != "":
		print("SETUP step=%d build_ms=%.1f" % [setup_step, (Time.get_ticks_usec() - probe_t) / 1000.0])
		_probe_hitches()

## tests (BMX_SETUP_PROBE=1): the slow frames in the 3 s after a menu page was built (`SETUPFRAME`)
func _probe_hitches() -> void:
	var t_end := Time.get_ticks_msec() + 3000
	var last := Time.get_ticks_usec()
	var worst := 0.0
	var slow := 0
	while Time.get_ticks_msec() < t_end:
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		var ms := (now - last) / 1000.0
		last = now
		worst = maxf(worst, ms)
		if ms > 33.0: slow += 1
	print("SETUPFRAME step=%d worst_ms=%.1f frames_over_33ms=%d" % [setup_step, worst, slow])

func _menu_page_setup_build(step := 0) -> void:
	setup_step = clampi(step, 0, SETUP_STEPS.size() - 1)
	# step to step the 3D turntable is kept (its world, light and the bike it shows); only the page round it is rebuilt
	var keep_view: BikeTurntable = hero_view if is_instance_valid(hero_view) and not hero_view.is_queued_for_deletion() else null
	if keep_view: keep_view.get_parent().remove_child(keep_view)
	_menu_clear()
	menu_page = "setup"
	if is_instance_valid(menu_quit): menu_quit.visible = false
	if is_instance_valid(menu_settings): menu_settings.visible = false
	if is_instance_valid(menu_version): menu_version.visible = false
	if is_instance_valid(menu_stats): menu_stats.visible = false
	if is_instance_valid(setup_screen): setup_screen.queue_free()
	_ensure_thumbs()
	var scr := Control.new()
	scr.set_anchors_preset(Control.PRESET_FULL_RECT)
	setup_screen = scr
	menu.add_child(scr)
	var bg := ColorRect.new()
	bg.color = Tokens.PAGE
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	scr.add_child(bg)
	var split := setup_step != COMPUTER_STEP
	var title: String = ["CHOOSE YOUR BIKE", "COLOURS & WHEELS", "YOUR CHARACTER", "BIKE COMPUTER", "READY TO RACE"][setup_step]
	var back_cb: Callable = (_menu_page_setup.bind(setup_step - 1) if setup_step > 0 else _menu_page_main)
	var last := setup_step == SETUP_STEPS.size() - 1
	var next_btn := _menu_button("RACE" if last else "NEXT", "" if last else SETUP_STEPS[setup_step + 1].capitalize(), _start_ride if last else _menu_page_setup.bind(setup_step + 1), true)
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", Tokens.S2)
	for i in SETUP_STEPS.size():
		var sb := UITheme.make_button("%d  %s" % [i + 1, SETUP_STEPS[i]], _menu_page_setup.bind(i), "tab", Tokens.T_LG)
		sb.custom_minimum_size.y = 52
		sb.toggle_mode = true
		sb.button_pressed = i == setup_step
		sb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bar.add_child(sb)
	var content := HBoxContainer.new()
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", Tokens.S6)
	if split:
		var row := HBoxContainer.new()
		row.set_anchors_preset(Control.PRESET_FULL_RECT)
		row.add_theme_constant_override("separation", 0)
		scr.add_child(row)
		# left: the bike on its podium fills the whole side; the text and BACK sit inside it
		var left := Control.new()
		left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(left)
		var race := setup_step == SETUP_STEPS.size() - 1
		if race:   # RACE: a little trail seen from riding height, lit by the picked time, through the picked lens (LensScene)
			if not is_instance_valid(keep_view): keep_view = hero_view if is_instance_valid(hero_view) else null
			lens_view = LensScene.new()
			lens_view.set_anchors_preset(Control.PRESET_FULL_RECT)
			left.add_child(lens_view)
			lens_view.set_hour(LightSettings.get_value("time"))
			lens_view.set_lens(GameState.goggle_lens)
		else:
			hero_view = keep_view if keep_view else BikeTurntable.new()
			keep_view = null
			hero_view.set_anchors_preset(Control.PRESET_FULL_RECT)
			left.add_child(hero_view)
			if setup_step == 2: hero_view.show_rider(RiderPanels.load_look())   # the rider step shows the rider standing
			else: hero_view.set_bike(GameState.bike_id)
		var ov := MarginContainer.new()
		ov.set_anchors_preset(Control.PRESET_FULL_RECT)
		ov.mouse_filter = Control.MOUSE_FILTER_IGNORE
		for side in ["left", "right"]: ov.add_theme_constant_override("margin_" + side, Tokens.S8)
		ov.add_theme_constant_override("margin_top", Tokens.S6)
		ov.add_theme_constant_override("margin_bottom", Tokens.S6)
		left.add_child(ov)
		var lv := VBoxContainer.new()
		lv.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ov.add_child(lv)
		var tcol := VBoxContainer.new()
		tcol.add_theme_constant_override("separation", -Tokens.S3)
		tcol.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tcol.add_child(UITheme.caption("STEP %d OF %d" % [setup_step + 1, SETUP_STEPS.size()], Tokens.INK_SOFT, Tokens.T_SM))
		tcol.add_child(UITheme.display(title, Tokens.T_3XL + Tokens.S4, Tokens.INK, Tokens.SLANT_TITLE))
		lv.add_child(tcol)
		var grow := Control.new(); grow.size_flags_vertical = Control.SIZE_EXPAND_FILL; grow.mouse_filter = Control.MOUSE_FILTER_IGNORE
		lv.add_child(grow)
		hero_name = UITheme.display("", Tokens.T_3XL + Tokens.S6, Tokens.INK, Tokens.SLANT_TITLE)
		hero_name.mouse_filter = Control.MOUSE_FILTER_IGNORE
		lv.add_child(hero_name)
		hero_spec = UITheme.caption("", Tokens.INK_SOFT, Tokens.T_MD)
		hero_spec.mouse_filter = Control.MOUSE_FILTER_IGNORE
		lv.add_child(hero_spec)
		_hero_text(GameState.bike_id)
		if race:   # over the trail scene: white type with a soft shadow
			for lb in [tcol.get_child(0), tcol.get_child(1), hero_name, hero_spec]:
				(lb as Control).add_theme_color_override("font_color", Color.WHITE)
				(lb as Control).add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.45))
				(lb as Control).add_theme_constant_override("shadow_offset_y", 2)
				(lb as Control).add_theme_constant_override("shadow_outline_size", 6)
			hero_spec.text = "THE TRAIL AT THIS TIME OF DAY  ·  THROUGH YOUR LENS"
		if setup_step == 2:
			hero_name.text = "YOUR CHARACTER"
			hero_spec.text = "KIT  ·  HAIR  ·  PLATE  ·  DRAG TO TURN"
		var bl := HBoxContainer.new()
		bl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bl.add_child(UITheme.make_button("BACK", back_cb, "link", Tokens.T_XL))
		bl.add_child(UITheme.make_button("TUNE IN GARAGE", _open_garage, "link", Tokens.T_MD))
		lv.add_child(bl)
		if race:   # the links read on the dark trail scene too
			for lk in bl.get_children():
				for st in ["font_color", "font_hover_color", "font_focus_color", "font_pressed_color"]:
					(lk as Control).add_theme_color_override(st, Color.WHITE if st == "font_color" else Tokens.ACCENT)
		# right: the steps, this step's picks, next
		var rm := MarginContainer.new()
		rm.custom_minimum_size.x = 600
		for side in ["left", "right"]: rm.add_theme_constant_override("margin_" + side, Tokens.S6)
		rm.add_theme_constant_override("margin_top", Tokens.S6)
		rm.add_theme_constant_override("margin_bottom", Tokens.S6)
		row.add_child(rm)
		var rv := VBoxContainer.new()
		rv.add_theme_constant_override("separation", Tokens.S4)
		rm.add_child(rv)
		rv.add_child(bar)
		rv.add_child(content)
		rv.add_child(next_btn)
	else:
		var mg := MarginContainer.new()
		mg.set_anchors_preset(Control.PRESET_FULL_RECT)
		for side in ["left", "right"]: mg.add_theme_constant_override("margin_" + side, Tokens.S8 + Tokens.S4)
		mg.add_theme_constant_override("margin_top", Tokens.S6)
		mg.add_theme_constant_override("margin_bottom", Tokens.S6)
		scr.add_child(mg)
		var root := VBoxContainer.new()
		root.add_theme_constant_override("separation", Tokens.S5)
		mg.add_child(root)
		var head := HBoxContainer.new()
		head.add_theme_constant_override("separation", Tokens.S7)
		root.add_child(head)
		var tcol := VBoxContainer.new()
		tcol.add_theme_constant_override("separation", -Tokens.S3)
		tcol.add_child(UITheme.caption("STEP %d OF %d" % [setup_step + 1, SETUP_STEPS.size()], Tokens.INK_SOFT, Tokens.T_SM))
		tcol.add_child(UITheme.display(title, Tokens.T_3XL + Tokens.S4, Tokens.INK, Tokens.SLANT_TITLE))
		head.add_child(tcol)
		var fill := Control.new(); fill.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		head.add_child(fill)
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		bar.custom_minimum_size.x = 640
		head.add_child(bar)
		root.add_child(content)
		var foot := HBoxContainer.new()
		root.add_child(foot)
		foot.add_child(UITheme.make_button("BACK", back_cb, "link", Tokens.T_XL))
		var fl := Control.new(); fl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		foot.add_child(fl)
		next_btn.custom_minimum_size.x = 420
		foot.add_child(next_btn)
	if keep_view:   # the full-screen computer step has no turntable: park it hidden for the next step
		keep_view.visible = false
		scr.add_child(keep_view)
	elif is_instance_valid(hero_view): hero_view.visible = true
	_lens_preview(GameState.goggle_lens if setup_step == SETUP_STEPS.size() - 1 else "")   # the RACE step shows the bike through the lens
	menu_focus = next_btn   # a step with one main pick moves this onto the picked card
	match setup_step:
		0: _setup_bike(content)
		1: _setup_tune(content)
		2: _setup_rider(content)
		3: _setup_computer(content)
		4: _setup_race(content)
	menu_focus.grab_focus.call_deferred()

## step 1: the presets as picture cards (the big 3D bike is the left side of the screen)
func _setup_bike(content: HBoxContainer) -> void:
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", Tokens.S3)
	content.add_child(list)
	var group := ButtonGroup.new()
	for id in GameState.BIKES:
		var b := UITheme.make_button("", Callable(), "chip")
		b.toggle_mode = true
		b.button_group = group
		b.button_pressed = id == GameState.bike_id
		b.size_flags_vertical = Control.SIZE_EXPAND_FILL
		_pick_card(b)
		var row := HBoxContainer.new()
		row.set_anchors_preset(Control.PRESET_FULL_RECT)
		row.offset_left = Tokens.S3; row.offset_right = -Tokens.S3
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(_bike_pic(bike_thumbs, id, Vector2(190, 0)))
		var tc := VBoxContainer.new()
		tc.alignment = BoxContainer.ALIGNMENT_CENTER
		tc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tc.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var nm := UITheme.display(String(GameState.BIKES[id].label).to_upper(), Tokens.T_2XL, Tokens.INK, Tokens.SLANT_TITLE)
		nm.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tc.add_child(nm)
		var sp := UITheme.caption("GARAGE BUILD" if GameState.BIKES[id].get("garage", false) else "STOCK", Tokens.INK_SOFT, Tokens.T_XS)
		sp.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tc.add_child(sp)
		row.add_child(tc)
		b.add_child(row)
		b.pressed.connect(func():
			hero_view.set_bike(id)
			_hero_text(id)
			if GameState.bike_id != id:   # the world behind is hidden: rebuild it once, when the race starts
				GameState.bike_id = id; GameState.save(); bike_dirty = true)
		list.add_child(b)

var tune_cat := Env.s("BMX_TUNE_CAT") if Env.s("BMX_TUNE_CAT") != "" else "colour"   # tests: BMX_TUNE_CAT=wheels
var tune_body: VBoxContainer
var tune_build := {}
const TUNE_SWATCHES := ["e8432e", "ff6a00", "ffb000", "ffd21f", "c6ff1a", "35d04a", "00a86b", "00c2c7", "2f7de1", "1d2b64",
	"7b3fe4", "d22fbf", "ff4f9a", "f4f4f0", "b8bcc0", "6b6f75", "2b2d31", "111214", "c8a24a", "8a5a2b", "4a6b3a", "e0d3b8"]

## step 2: colours and wheels (frame / fork colour, tyre model, rim colour). Everything else is in the garage.
func _setup_tune(content: HBoxContainer) -> void:
	var garage_bike: bool = GameState.BIKES[GameState.bike_id].get("garage", false)
	tune_build = BikeBuild.load_build() if garage_bike else {}
	if not garage_bike: tune_cat = "wheels"
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", Tokens.S3)
	content.add_child(col)
	if garage_bike:
		var tabs := HBoxContainer.new()
		tabs.add_theme_constant_override("separation", Tokens.S2)
		var grp := ButtonGroup.new()
		for c in [["colour", "COLOURS"], ["wheels", "WHEELS & TYRES"]]:
			var b := UITheme.make_button(c[1], Callable(), "chip", Tokens.T_MD)
			b.toggle_mode = true; b.button_group = grp
			b.button_pressed = c[0] == tune_cat
			b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			b.pressed.connect(func(): tune_cat = c[0]; _tune_fill())
			tabs.add_child(b)
		col.add_child(tabs)
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	SmoothScroll.attach(sc)
	col.add_child(sc)
	tune_body = VBoxContainer.new()
	tune_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tune_body.size_flags_vertical = Control.SIZE_EXPAND_FILL   # the picture strip grows into the free height
	tune_body.add_theme_constant_override("separation", Tokens.S3)
	sc.add_child(tune_body)
	col.add_child(UITheme.make_button("MORE PARTS IN THE GARAGE", _open_garage, "link", Tokens.T_MD))
	_tune_fill()

## something changed: save it, and the ride is rebuilt on RACE
func _tune_changed(repaint_only: bool) -> void:
	if GameState.BIKES[GameState.bike_id].get("garage", false): BikeBuild.save_build(tune_build)
	bike_dirty = true
	bike_thumbs.forget_bikes()
	if repaint_only: hero_view.repaint(tune_build)
	else: hero_view.set_bike(GameState.bike_id, true)

func _tune_fill() -> void:
	for c in tune_body.get_children():
		tune_body.remove_child(c); c.queue_free()
	var garage_bike: bool = GameState.BIKES[GameState.bike_id].get("garage", false)
	if tune_cat == "colour" and garage_bike:
		tune_body.add_child(UITheme.caption("FRAME"))
		tune_body.add_child(_swatch_grid(tune_build.paint.frame.color, func(h):
			for k in ["frame", "rear"]: tune_build.paint[k].color = h
			_tune_changed(true); _tune_fill()))
		tune_body.add_child(UITheme.caption("FORK"))
		tune_body.add_child(_swatch_grid(tune_build.paint.fork.color, func(h):
			tune_build.paint.fork.color = h
			_tune_changed(true); _tune_fill()))
		tune_body.add_child(UITheme.caption("SHOCK SPRING"))
		tune_body.add_child(_swatch_grid(tune_build.paint.spring.color, func(h):
			tune_build.paint.spring.color = h
			_tune_changed(true); _tune_fill()))
		return
	# wheels & tyres: a picture card per tyre model, then the rim colour
	tune_body.add_child(UITheme.caption("TYRES"))
	var cur: String = String(tune_build.wheels.get("tyre_model", "")) if garage_bike else GameState.bmx_tyre
	var group := ButtonGroup.new()
	var strip := PicStrip.new(Tokens.S2)   # big picture tiles in one slidable row, as tall as the page lets them
	strip.size_flags_vertical = Control.SIZE_EXPAND_FILL
	strip.square = 0.95
	tune_body.add_child(strip)
	for k in BikeBuild.TYRE_MODELS:
		var tm: Dictionary = BikeBuild.TYRE_MODELS[k]
		if not tm.has("brand"): continue
		var tmp: Dictionary = tune_build.duplicate(true) if garage_bike else BikeBuild.bmx_build(k)
		if garage_bike: BikeBuild.apply_tyre_model(tmp, k)
		var spec := BikeBuild.wheel_spec(tmp, false)
		var b := UITheme.make_button("", Callable(), "chip")
		b.toggle_mode = true; b.button_group = group
		b.button_pressed = k == cur
		b.custom_minimum_size = Vector2(236, 232)
		var row := VBoxContainer.new()
		row.set_anchors_preset(Control.PRESET_FULL_RECT)
		row.offset_left = Tokens.S3; row.offset_right = -Tokens.S3; row.offset_top = Tokens.S2; row.offset_bottom = -Tokens.S3
		row.add_theme_constant_override("separation", 0)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var pic := TextureRect.new()
		pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		pic.size_flags_vertical = Control.SIZE_EXPAND_FILL
		pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bike_thumbs.request("wheelset|%s|%s" % [k, JSON.stringify(spec)], PartThumbs.make_wheelset.bind(spec), Vector3(0.05, 0.12, 1.0),
			func(t): if is_instance_valid(pic): pic.texture = t)
		row.add_child(pic)
		var tc := VBoxContainer.new()
		tc.add_theme_constant_override("separation", 0)
		tc.mouse_filter = Control.MOUSE_FILTER_IGNORE
		for pair in [[UITheme.caption(String(tm.brand), Tokens.INK_SOFT, Tokens.T_XS), 0], [UITheme.display(String(tm.label).replace(String(tm.brand).capitalize() + " ", ""), Tokens.T_XL, Tokens.INK, Tokens.SLANT_TITLE), 0],
				[UITheme.caption("%s  ·  %.1f in  ·  %s" % [String(tm.tread).to_upper(), float(tm.tyre_w), String(tm.casing).to_upper()], Tokens.INK_SOFT, Tokens.T_XS), 0]]:
			(pair[0] as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
			tc.add_child(pair[0])
		row.add_child(tc)
		b.add_child(row)
		b.pressed.connect(strip.guard(func():
			if garage_bike: BikeBuild.apply_tyre_model(tune_build, k)
			else:
				GameState.bmx_tyre = k; GameState.save()
			_tune_changed(false)))
		strip.add(b, k == cur)
	if garage_bike:
		tune_body.add_child(UITheme.caption("RIM COLOUR"))
		tune_body.add_child(_swatch_grid(tune_build.wheels.rim_color, func(h):
			tune_build.wheels.rim_color = h; tune_build.wheels.rim_model = "custom"
			_tune_changed(false); _tune_fill()))

## a sleek colour grid: flat squares, the picked one lifted with an ink bar under it
func _swatch_grid(cur: String, cb: Callable, palette: Array = TUNE_SWATCHES, cols := 11, size := 40) -> Control:
	var g := GridContainer.new()
	g.columns = cols
	g.add_theme_constant_override("h_separation", Tokens.S2)
	g.add_theme_constant_override("v_separation", Tokens.S2)
	for hex in palette:
		var b := Button.new()
		b.custom_minimum_size = Vector2(size, size)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.tooltip_text = "#" + hex
		var on: bool = hex == cur.to_lower().trim_prefix("#")
		var col := Color(hex)
		for st in ["normal", "pressed"]:
			b.add_theme_stylebox_override(st, UITheme.marked(col, Tokens.INK, SIDE_BOTTOM, Tokens.R_MD, 0) if on else UITheme.box(col, Tokens.R_MD, 0))
		var ring := UITheme.box(Tokens.CLEAR, Tokens.R_MD, 0, Tokens.INK, Tokens.MARK - 1)   # the pad cursor on a colour
		ring.draw_center = false
		b.add_theme_stylebox_override("focus", ring)
		b.add_theme_stylebox_override("hover", UITheme.marked(col.lightened(0.12), Tokens.INK_SOFT, SIDE_BOTTOM, Tokens.R_MD, 0))
		b.pressed.connect(func(): cb.call(hex))
		g.add_child(b)
	return g

var _setup_fill := Callable()   # the CHARACTER step's tab filler (refilled when a pick adds / removes rows)
var char_tab := Env.s("BMX_CHAR_TAB") if Env.s("BMX_CHAR_TAB") != "" else "kit"   # tests: BMX_CHAR_TAB=hair

## step 3: the CHARACTER: everything about her in one place, in four tabs: KIT (clothes), HAIR (helmet or hair preset
## + colour), FACE (skin tone, eyes) and PLATE (the race number). The turntable shows the standing rider.
func _setup_rider(content: HBoxContainer) -> void:
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", Tokens.S3)
	content.add_child(col)
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", Tokens.S2)
	var body := VBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", Tokens.S3)
	var grp := ButtonGroup.new()
	var fill := func() -> void:
		for c in body.get_children():
			body.remove_child(c); c.queue_free()
		match char_tab:
			"kit": _char_kit(body)
			"pants": _char_pants(body)
			"hair": _char_hair(body)
			"plate": _char_plate(body)
	for t in [["kit", "KIT"], ["pants", "PANTS"], ["hair", "HELMET"], ["plate", "PLATE"]]:
		var b := UITheme.make_button(t[1], Callable(), "chip", Tokens.T_MD)
		b.toggle_mode = true; b.button_group = grp
		b.button_pressed = t[0] == char_tab
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(func(): char_tab = t[0]; fill.call())
		tabs.add_child(b)
	col.add_child(tabs)
	col.add_child(body)
	col.add_child(UITheme.make_button("MORE IN THE RIDER ROOM", _open_garage.bind("rider"), "link", Tokens.T_MD))
	_setup_fill = fill
	fill.call()

func _char_kit(body: VBoxContainer) -> void:
	var look := RiderPanels.load_look()
	var grid := GridContainer.new()
	grid.columns = 2
	grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", Tokens.S3)
	grid.add_theme_constant_override("v_separation", Tokens.S3)
	body.add_child(grid)
	var group := ButtonGroup.new()
	for k in RiderPanels.KITS:
		var kit_look: Dictionary = Rider.DEFAULT_LOOK.duplicate()
		kit_look.merge(k[1], true)
		var b := UITheme.make_button("", Callable(), "chip")
		b.toggle_mode = true
		b.button_group = group
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.size_flags_vertical = Control.SIZE_EXPAND_FILL
		var same := true
		for key in kit_look:
			if key in RiderPanels.NON_KIT: continue
			if str(look.get(key, "")) != str(kit_look[key]): same = false; break
		b.button_pressed = same
		_pick_card(b)
		var col := VBoxContainer.new()
		col.set_anchors_preset(Control.PRESET_FULL_RECT)
		col.offset_left = Tokens.S3; col.offset_right = -Tokens.S3; col.offset_top = Tokens.S3; col.offset_bottom = -Tokens.S3
		col.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var sw := HBoxContainer.new()
		sw.size_flags_vertical = Control.SIZE_EXPAND_FILL
		sw.add_theme_constant_override("separation", 0)
		sw.mouse_filter = Control.MOUSE_FILTER_IGNORE
		for part in ["shell", "jersey", "pants", "gloves", "lens"]:
			var c := ColorRect.new(); c.color = Color(kit_look[part]); c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			c.mouse_filter = Control.MOUSE_FILTER_IGNORE
			sw.add_child(c)
		col.add_child(sw)
		var nm := UITheme.display(String(k[0]).to_upper(), Tokens.T_XL, Tokens.INK, Tokens.SLANT_TITLE)
		nm.mouse_filter = Control.MOUSE_FILTER_IGNORE
		col.add_child(nm)
		b.add_child(col)
		b.pressed.connect(func():
			var cur := RiderPanels.load_look()
			var merged := kit_look.duplicate()
			for key in RiderPanels.NON_KIT: merged[key] = cur[key]   # a kit changes the clothes, not the head / plate
			RiderPanels.save_look(merged)
			hero_view.set_look(merged)
			if game and game.rider: game.rider.set_look(merged))
		grid.add_child(b)

## the PANTS tab: colour, fabric (Poly Haven scans), printed pattern + its colour (rider/pants_look.gd)
func _char_pants(body: VBoxContainer) -> void:
	var look := RiderPanels.load_look()
	var chips := func(items: Array, current: String, key: String) -> GridContainer:
		var g := GridContainer.new()
		g.columns = 3
		g.add_theme_constant_override("h_separation", Tokens.S2)
		g.add_theme_constant_override("v_separation", Tokens.S2)
		var grp := ButtonGroup.new()
		for it in items:
			var id: String = it[0]
			var b := UITheme.make_button(String(it[1]).to_upper(), Callable(), "chip", Tokens.T_SM)
			b.toggle_mode = true; b.button_group = grp
			b.button_pressed = id == current
			b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			b.pressed.connect(func(): _look_set({key: id}); _refresh_char())
			g.add_child(b)
		return g
	body.add_child(UITheme.caption("COLOUR"))
	body.add_child(_swatch_grid(str(look.get("pants", Rider.DEFAULT_LOOK.pants)).trim_prefix("#"), func(h): _look_set({"pants": "#" + h}); _refresh_char(), PANTS_COLOURS, 9, 36))
	body.add_child(UITheme.caption("FABRIC"))
	body.add_child(chips.call(PantsLook.FABRICS, str(look.get("pantsFabric", PantsLook.DEFAULT_FABRIC)), "pantsFabric"))
	body.add_child(UITheme.caption("PATTERN"))
	body.add_child(chips.call(PantsLook.PATTERNS, str(look.get("pantsPattern", PantsLook.DEFAULT_PATTERN)), "pantsPattern"))
	if str(look.get("pantsPattern", "none")) != "none":
		body.add_child(UITheme.caption("PATTERN COLOUR"))
		body.add_child(_swatch_grid(str(look.get("pantsPrint", PantsLook.DEFAULT_PRINT)).trim_prefix("#"), func(h): _look_set({"pantsPrint": "#" + h}); _refresh_char(), PANTS_COLOURS, 9, 36))

const PANTS_COLOURS := ["111215", "2c2f33", "6b6f75", "d8d8d8", "1d2b64", "0d2847", "1478d4", "3a4c9a", "2e7d32",
	"4a5d3a", "8a7a52", "6b4a2b", "8c2f1f", "e8231f", "ff7a1a", "ffd21f", "7ed321", "d22fbf"]

## the CHARACTER step's tab again (a pick that adds / removes rows)
func _refresh_char() -> void:
	if _setup_fill.is_valid(): _setup_fill.call()

## change some look keys (helmet / hair / face / plate) and show them at once
func _look_set(d: Dictionary) -> void:
	var lk := RiderPanels.load_look()
	lk.merge(d, true)
	RiderPanels.save_look(lk)
	if is_instance_valid(hero_view): hero_view.set_look(lk)
	if game and game.rider: game.rider.set_look(lk)

const HAIR_COLOURS := ["16130f", "2a1a10", "4a3022", "7a4e2b", "b07a3c", "d9b36a", "e8d9a8", "8a8a8a", "d8d8d8", "8c2f1f", "c8452a", "3b5bd6", "d22fbf", "35a86a"]
const SKIN_TONES := ["fbe3d0", "f3d0b4", "efc29f", "e0a982", "c98d68", "a96f4d", "7d4c33", "5a3624"]
const EYE_COLOURS := ["4a6b8a", "2f7de1", "35a86a", "7a8f3b", "8a5a2b", "4a2f1c", "6b6f75", "7b3fe4"]

func _char_hair(body: VBoxContainer) -> void:
	var look := RiderPanels.load_look()
	_ensure_thumbs()
	body.add_child(UITheme.caption("HEAD"))
	var grid := _pic_grid(4)
	var grp := ButtonGroup.new()
	for id in Rider.HELMETS:   # the rider always wears a helmet: pick the model
		var hid: String = id
		var lk := _look_with(look, {"helmet": hid, "camMount": "none", "hairStyle": "short"})
		grid.add(_pic_chip(grid, String(Rider.HELMETS[hid][0]).to_upper(), "head|helm|%s|%s|%s" % [hid, look.shell, look.peak],
			PartThumbs.make_head.bind(lk), Vector3(1.0, 0.25, 0.75), grp, str(look.helmet) == hid,
			func(): _look_set({"helmetOn": "1", "helmet": hid})))
	body.add_child(grid)
	body.add_child(UITheme.caption("ACTION CAM"))
	var cgrid := _pic_grid(4)
	var cgrp := ButtonGroup.new()
	for m in ActionCam.HELMET_MOUNTS:   # where the helmet camera sits (the Helmet view looks out of it)
		var mid: String = m[0]
		var lk := _look_with(look, {"camMount": mid, "hairStyle": "short"})
		cgrid.add(_pic_chip(cgrid, String(m[1]).to_upper(), "head|cam|%s|%s|%s" % [mid, look.helmet, ActionCam.gear_sig(ActionCam.gear_from_look(look))],
			PartThumbs.make_head.bind(lk), Vector3(0.75, 0.45, -1.0), cgrp, str(look.get("camMount", "top")) == mid,
			func(): _look_set({"camMount": mid})))
	body.add_child(cgrid)
	body.add_child(UITheme.caption("HAIR STYLE"))
	var hgrid := _pic_grid(4)
	var hgrp := ButtonGroup.new()
	for st in Hair.HELMET_STYLES:   # what comes out under the back of the helmet
		var sid: String = st[0]
		var lk := _look_with(look, {"hairStyle": sid, "camMount": "none"})
		hgrid.add(_pic_chip(hgrid, String(st[1]).to_upper(), "head|hair|%s|%s|%s" % [sid, look.helmet, look.hair],
			PartThumbs.make_head.bind(lk, 0.22), Vector3(-1.0, 0.2, 0.55), hgrp, str(look.hairStyle) == sid,
			func(): _look_set({"hairStyle": sid})))
	body.add_child(hgrid)
	body.add_child(UITheme.caption("HAIR COLOUR"))
	body.add_child(_swatch_grid(str(look.hair), func(h): _look_set({"hair": "#" + h}), HAIR_COLOURS, 7, 44))

## the look with some keys changed (a picture's rider)
func _look_with(look: Dictionary, d: Dictionary) -> Dictionary:
	var lk := look.duplicate()
	lk.merge(d, true)
	lk.helmetOn = "1"
	return lk

## a slidable row of picture tiles (cols: unused)
func _pic_grid(_cols: int) -> PicStrip:
	return PicStrip.new(Tokens.S2)

## a picked-or-not tile: a rendered picture (PartThumbs) with the name under it
func _pic_chip(strip: PicStrip, label: String, key: String, make: Callable, view: Vector3, grp: ButtonGroup, on: bool, cb: Callable) -> Button:
	var b := UITheme.make_button("", Callable(), "chip")
	b.toggle_mode = true; b.button_group = grp
	b.button_pressed = on
	b.custom_minimum_size = Vector2(264, 236)   # big enough to see the part; the strip slides
	b.tooltip_text = label
	var col := VBoxContainer.new()
	col.set_anchors_preset(Control.PRESET_FULL_RECT)
	col.offset_left = Tokens.S1; col.offset_right = -Tokens.S1; col.offset_top = Tokens.S1; col.offset_bottom = -Tokens.S1
	col.add_theme_constant_override("separation", 0)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var pic := TextureRect.new()
	pic.size_flags_vertical = Control.SIZE_EXPAND_FILL
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(pic)
	var ref: WeakRef = weakref(pic)
	bike_thumbs.request(key, make, view, func(t):
		var pr = ref.get_ref()
		if pr: pr.texture = t)
	var nm := UITheme.display(label, Tokens.T_SM, Tokens.INK, 0.0)
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nm.clip_text = true
	nm.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	nm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(nm)
	b.add_child(col)
	b.pressed.connect(strip.guard(cb))
	if on: strip._reveal.call_deferred(b)
	return b

func _char_plate(body: VBoxContainer) -> void:
	var look := RiderPanels.load_look()
	body.add_child(UITheme.caption("RACE PLATE ON THE BACK"))
	var on := UITheme.make_button("SHOW THE PLATE", Callable(), "chip", Tokens.T_MD)
	on.toggle_mode = true
	on.button_pressed = str(look.bibOn) != "0"
	on.toggled.connect(func(v: bool): _look_set({"bibOn": "1" if v else "0"}))
	body.add_child(on)
	body.add_child(UITheme.caption("NUMBER"))
	var num := LineEdit.new()
	num.text = str(look.bibNumber); num.max_length = 3; num.placeholder_text = "Race number"; num.custom_minimum_size.y = Tokens.H_CHIP
	num.text_changed.connect(func(t: String): _look_set({"bibNumber": t}))
	body.add_child(num)
	body.add_child(UITheme.caption("HEADER LINE"))
	var hdr := LineEdit.new()
	hdr.text = str(look.bibText); hdr.max_length = 30; hdr.placeholder_text = "Header line"; hdr.custom_minimum_size.y = Tokens.H_CHIP
	hdr.text_changed.connect(func(t: String): _look_set({"bibText": t}))
	body.add_child(hdr)

## step 3: the Garmin (bike computer) model: controls left, a big 3D close-up right
func _setup_computer(content: HBoxContainer) -> void:
	var card := _build_computer_card()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(card)

## step 4: the time of day, then RACE (the bike on the left is the one you picked)
func _setup_race(content: HBoxContainer) -> void:
	var side := VBoxContainer.new()
	side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	side.add_theme_constant_override("separation", Tokens.S3)
	content.add_child(side)
	side.add_child(UITheme.caption("TIME OF DAY"))
	# one slider over the whole day: the sky's colours, the sun's arc rising and setting (TimeSlider)
	var ts = TimeSlider.new()
	ts.hour = LightSettings.get_value("time")
	ts.cycle = LightSettings.get_value("cycle") > 0.5
	ts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ts.set_meta(&"nav_accept", _setup_next)
	ts.committed.connect(func(h: float): LightSettings.set_value("time", h))
	ts.changed.connect(func(h: float): if is_instance_valid(lens_view): lens_view.set_hour(h))
	side.add_child(ts)
	menu_focus = ts
	# quick picks under it + the day / night cycle
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", Tokens.S2)
	for q in [["SUNRISE", 6.55], ["GOLDEN HOUR", 19.33], ["NOON", 13.0], ["DUSK", 20.1], ["NIGHT", 23.5]]:
		var qb := UITheme.make_button(String(q[0]), func(): ts._set_hour(float(q[1]), true), "chip")
		qb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		qb.set_meta(&"nav_accept", _setup_next)
		row.add_child(qb)
	var cyc := UITheme.make_button("DAY / NIGHT CYCLE", Callable(), "chip")
	cyc.toggle_mode = true
	cyc.button_pressed = ts.cycle
	cyc.tooltip_text = "Time runs: the day goes round from the hour picked above"
	cyc.toggled.connect(func(on: bool):
		LightSettings.set_value("cycle", 1.0 if on else 0.0)
		ts.cycle = on
		ts.queue_redraw())
	row.add_child(cyc)
	side.add_child(row)
	_setup_lenses(side)
	side.add_child(UITheme.text("Computer: " + String(ComputerUnits.get_unit(GameState.computer_id).name), Tokens.INK_SOFT, Tokens.T_MD))

## the RACE step's GOGGLES picks: each lens is a colour grade for the whole ride (GoggleLens). The bike view on the
## left is graded live by the picked lens (_lens_preview); the line under the picks says what the lens does.
func _setup_lenses(side: VBoxContainer) -> void:
	_ensure_thumbs()
	side.add_child(UITheme.caption("GOGGLES  ·  LENS"))
	var lg := GridContainer.new()
	lg.columns = 4
	lg.add_theme_constant_override("h_separation", Tokens.S2)
	lg.add_theme_constant_override("v_separation", Tokens.S2)
	var desc := UITheme.caption(GoggleLens.description(GameState.goggle_lens), Tokens.INK_SOFT, Tokens.T_XS)
	var grp := ButtonGroup.new()
	for id in GoggleLens.ids():
		var b := UITheme.make_button("", Callable(), "chip")
		b.toggle_mode = true
		b.button_group = grp
		b.button_pressed = id == GameState.goggle_lens
		b.set_meta(&"nav_accept", _setup_next)   # A on a lens = RACE, like the time cards
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size.y = 96
		b.tooltip_text = GoggleLens.description(id)
		var cv := VBoxContainer.new()
		cv.set_anchors_preset(Control.PRESET_FULL_RECT)
		cv.offset_left = Tokens.S2; cv.offset_right = -Tokens.S2; cv.offset_top = Tokens.S1; cv.offset_bottom = -Tokens.S1
		cv.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cv.add_theme_constant_override("separation", 0)
		# the newest helmets' goggle model with this lens (GoggleLens.make_goggles), rendered once by PartThumbs
		var pic := TextureRect.new()
		pic.size_flags_vertical = Control.SIZE_EXPAND_FILL
		pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cv.add_child(pic)
		var pref: WeakRef = weakref(pic)
		bike_thumbs.request("goggles|2|" + id, GoggleLens.make_goggles.bind(id), GOGGLE_VIEW, func(t):
			var pr = pref.get_ref()
			if pr: pr.texture = t)
		var nl := UITheme.display(GoggleLens.display_name(id).to_upper(), Tokens.T_SM, Tokens.INK, Tokens.SLANT_TITLE)
		nl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		nl.clip_text = true
		nl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		nl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cv.add_child(nl)
		b.add_child(cv)
		b.pressed.connect(func():
			if is_instance_valid(desc): desc.text = GoggleLens.description(id)
			if GameState.goggle_lens != id:
				GameState.goggle_lens = id
				GameState.save()
			_lens_preview(id))
		lg.add_child(b)
	side.add_child(lg)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	side.add_child(desc)

## grades the setup page's bike view with a lens ("" / "neutral" = none); the turntable is kept across steps,
## so every other step sets it back to none
func _lens_preview(id: String) -> void:
	if is_instance_valid(lens_view) and id != "": lens_view.set_lens(id)
	if not is_instance_valid(hero_view): return
	for we in hero_view.find_children("*", "WorldEnvironment", true, false):
		var env: Environment = (we as WorldEnvironment).environment
		if env: env.adjustment_color_correction = GoggleLens.lut(id) if id != "" else null

## a setup pick that follows the pad cursor: the picked one is where the cursor starts, A on it = next step
func _pick_card(b: Button) -> void:
	b.set_meta(&"nav_accept", _setup_next)
	if b.button_pressed: menu_focus = b

func _setup_next() -> void:
	if setup_step < SETUP_STEPS.size() - 1: _menu_page_setup(setup_step + 1)
	else: _start_ride()

## a big menu button: display-font title (+ optional small line under it); primary = the yellow one
func _menu_button(text: String, sub: String, cb: Callable, primary := false, centred := false) -> Button:
	var b := UITheme.make_button("", cb, "menu")   # one look for every line: the focused one is yellow (console cursor)
	# room above the name and below the second line (they used to touch the box's edges)
	b.custom_minimum_size.y = (Tokens.H_HERO if primary else Tokens.H_SUB) + Tokens.S3
	var m := MarginContainer.new()
	m.set_anchors_preset(Control.PRESET_FULL_RECT)
	m.add_theme_constant_override("margin_left", Tokens.S4)    # same inset as the seed field's text below
	m.add_theme_constant_override("margin_right", Tokens.S4)
	m.add_theme_constant_override("margin_top", Tokens.S3)
	m.add_theme_constant_override("margin_bottom", Tokens.S3)
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", -Tokens.S3)   # name and second line sit close (the display font has tall line spacing)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(UITheme.display(text, Tokens.T_3XL if primary else Tokens.T_2XL + Tokens.S1))
	if sub != "":
		col.add_child(UITheme.text(sub, Tokens.INK if primary else Tokens.INK_SOFT, Tokens.T_SM))
	if centred:
		for l in col.get_children(): (l as Label).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	m.add_child(col)
	b.add_child(m)
	return b

var garage: Garage

## mode "bike" = the garage, "rider" = the rider room (same room: position on the rollers + kit)
var _garage_reopened := false
func _open_garage(mode := "bike") -> void:
	Steam.presence({"bike": "In the garage", "shop": "In the bike shop"}.get(mode, "Setting up the rider"))
	if menu: menu.queue_free(); menu = null
	fade.modulate.a = 1.0
	var t0 := Time.get_ticks_usec()
	if game:
		if game.title_world and _title_keep.is_empty():   # its terrain + far hills wait for the way back (~0.9 s to rebuild)
			_title_keep = game.take_world()
		game.queue_free()
		await game.tree_exited
		game = null
	if Env.s("BMX_GARAGE_PROBE") != "": print("GARAGE free title world ms=%.1f" % ((Time.get_ticks_usec() - t0) / 1000.0))
	if not GameState.BIKES[GameState.bike_id].get("garage", false): GameState.bike_id = "dh"   # the garage builds the DH frames
	t0 = Time.get_ticks_usec()
	garage = Garage.new()
	garage.mode = mode
	add_child(garage)
	if Env.s("BMX_GARAGE_PROBE") != "": print("GARAGE open total ms=%.1f" % ((Time.get_ticks_usec() - t0) / 1000.0))
	garage.closed.connect(_close_garage)
	create_tween().set_ignore_time_scale().tween_property(fade, "modulate:a", 0.0, 0.5)
	if Env.s("BMX_GARAGE_REOPEN") != "" and not _garage_reopened:   # tests: back to the menu and in again (the kept outside)
		_garage_reopened = true
		await get_tree().create_timer(float(Env.s("BMX_GARAGE_REOPEN"))).timeout
		await _close_garage(false)
		await get_tree().create_timer(1.0).timeout
		_open_garage(mode)

func _close_garage(ride: bool) -> void:
	fade.modulate.a = 1.0
	var t0 := Time.get_ticks_usec()
	garage.queue_free()
	await garage.tree_exited
	garage = null
	bike_dirty = false   # the world is rebuilt right here (with the new build)
	if ride: _free_title_keep()
	await _new_game(not ride)   # back to the menu = the title backdrop world (its lookout spot belongs to that world)
	if ride: _start_ride()
	else: _show_menu()
	if Env.s("BMX_GARAGE_PROBE") != "": print("GARAGE close total ms=%.1f" % ((Time.get_ticks_usec() - t0) / 1000.0))
	create_tween().set_ignore_time_scale().tween_property(fade, "modulate:a", 0.0, 0.5)

func _start_ride() -> void:
	if game and game.title_world and _take_prebuilt():   # the world built during the intro: straight in
		bike_dirty = false
	elif game and game.title_world:   # leave the title backdrop: build the player's own world first
		bike_dirty = false
		fade.modulate.a = 1.0
		await _new_game(false)
		create_tween().set_ignore_time_scale().tween_property(fade, "modulate:a", 0.0, 0.5)
	elif bike_dirty or (game and game.level != GameState.level):
		bike_dirty = false
		await restart_ride()
	if menu: menu.queue_free(); menu = null
	if game: game.exit_photo()
	state = RIDING
	game.swallow_held()   # the A that pressed RACE is not a sprint
	game.respawn(false)
	_set_riding(true)
	GameState.begin_ride()   # counts as an activity once it has covered GameState.ACTIVITY_M
	Steam.event("FIRST_DROP")
	Steam.presence("Riding · " + game.biome_cur)

## DEMO: the same ride, an AI rider at the bars (F2 hands it back); the tuning card opens on the Demo tab
func _start_demo() -> void:
	await _start_ride()
	GameState.end_ride()   # the AI's riding is no activity of the player's
	game.set_demo(true)
	if game.hud:
		TuneCard.last_cat["ride"] = 8
		game.hud._toggle_side("tune")

# ---------------------------------------------------------------- pause
func _unhandled_input(e: InputEvent) -> void:
	if not e.is_action_pressed("pause") or e.is_echo(): return
	if is_instance_valid(settings_open) or garage: return
	if state == RIDING and game and game.photo:   # Esc leaves photo mode first (back to the replay, if one is up)
		game.toggle_photo()
		get_viewport().set_input_as_handled()
		return
	if state == RIDING and game and game.replay_on:   # Esc leaves the replay
		game.exit_replay()
		get_viewport().set_input_as_handled()
		return
	if is_instance_valid(controls_open):   # Esc closes the controls card, back to the pause menu
		_close_controls()
		get_viewport().set_input_as_handled()
		return
	if state == RIDING: _pause()
	elif state == PAUSED: _resume()
	get_viewport().set_input_as_handled()

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and state == RIDING and Settings.get_v("pause_unfocused") and OS.get_cmdline_user_args().is_empty():
		# (deferred: focus can go while this node is busy adding children - the ride moving in - and the leaflet's
		# add_child then failed, 80 errors and no pause menu)
		_pause_unfocused.call_deferred()

## the controller the player was riding with went away (battery, cable): pause, so the bike doesn't carry on with no
## hands on it. Only when a pad was the active device (a keyboard rider unplugging a spare pad isn't interrupted).
func _on_pad_connection(_device: int, connected: bool) -> void:
	if connected or state != RIDING or not Settings.pad_active: return
	if Settings._test_run or not OS.get_cmdline_user_args().is_empty(): return
	if not Input.get_connected_joypads().is_empty(): return   # another pad is still there
	_pause_unfocused.call_deferred()

func _pause_unfocused() -> void:
	if state == RIDING: _pause()

## paused during the crash slow motion: the menus (leaflet, its sounds, the tuning card) run at normal speed and
## pitch; the slow motion comes back on resume
var _held_time_scale := -1.0
var _held_audio_speed := -1.0
func _pause() -> void:
	if game: game.exit_photo()
	state = PAUSED
	if _held_time_scale < 0.0:
		_held_time_scale = Engine.time_scale
		_held_audio_speed = AudioServer.playback_speed_scale
	Engine.time_scale = 1.0
	AudioServer.playback_speed_scale = 1.0
	# the cover photo: the ride as it is now (the last frame drawn, before the leaflet is over it)
	var shot := get_viewport().get_texture().get_image()
	get_tree().paused = true
	_close_pause(true)
	# the pause menu replaces any side card (tuning, P / K / L): with it still up, its menu took the pad cursor
	# and the leaflet had no highlight. Pause > Tuning brings it back.
	_tuning_paused = false   # (else closing the card would resume the ride)
	if game and game.hud.card and game.hud.card.visible: game.hud.close_sides()
	var pm := PausePamphlet.new()
	pm.photo = shot
	if game:
		pm.place = game.terrain.biome_name(game.phys.x, game.phys.z)
		pm.sheet_no = GameState.seed
	add_child(pm)
	pm.close_requested.connect(func():   # Esc / B: an open leaflet folds back to its cover first
		if state != PAUSED or pause_menu != pm: return
		if pm.is_unfolded(): pm.fold_inside()
		else: _resume())
	pm.add_item("Resume", _resume)
	pm.add_item("Back to start", func(): _resume(); game.respawn(false))
	if game == null or game.level == "": pm.add_item("New world", func(): _resume(); game.respawn(true))
	pm.add_item("Tuning", _open_tuning)
	pm.add_item("Photo mode", func(): _resume(); game.toggle_photo())
	if game and game.replay and game.replay.ready_to_play():
		pm.add_item("Replay", func(): _resume(); game.open_replay())
	pm.add_item("Settings", _open_settings)
	pm.add_item("Main menu", func(): _close_pause(true); GameState.save(); _show_menu())
	pm.add_item("Quit to desktop", func(): GameState.save(); GameState.quit())
	pause_menu = pm
	pm.open()
	pm.focus_first.call_deferred()

## fold the leaflet away (now = gone at once: menus, a new ride)
func _close_pause(now := false) -> void:
	if not is_instance_valid(pause_menu): pause_menu = null; return
	var pm = pause_menu
	pause_menu = null
	if pm.state == 0: pm.queue_free(); return
	pm.closed.connect(pm.queue_free)
	pm.close(now)

## pause > Tuning: the tuning card over the paused ride (the pad drives it); closing it rides on
var _tuning_paused := false
func _open_tuning() -> void:
	_close_pause(true)
	_tuning_paused = true
	if game.hud.card and game.hud.card.visible: game.hud.card.show_tab("ride")   # already up (P, demo): keep it, never toggle it shut
	else: game.hud._toggle_side("tune")
	var card: Control = game.hud.card
	if not card.visibility_changed.is_connected(_tuning_shown): card.visibility_changed.connect(_tuning_shown)
	if card.get("nav"): card.nav.focus_first.call_deferred()

func _tuning_shown() -> void:
	if not game.hud.card.visible and _tuning_paused and state == PAUSED: _resume()

func _resume() -> void:
	if _tuning_paused:
		_tuning_paused = false
		if game and game.hud.card and game.hud.card.visible: game.hud.close_sides()
	_close_pause()
	_close_controls()
	state = RIDING
	get_tree().paused = false
	if _held_time_scale >= 0.0:   # back into the slow motion it was paused in
		Engine.time_scale = _held_time_scale if _held_time_scale > 0.0 else 1.0   # (0 = a map / photo freeze that was closing)
		AudioServer.playback_speed_scale = _held_audio_speed
		_held_time_scale = -1.0
	if game: game.swallow_held()   # the A that resumed is not a sprint

func _open_settings() -> void:
	if is_instance_valid(settings_open): return
	if is_instance_valid(pause_menu) and pause_menu is PausePamphlet:   # printed inside the leaflet
		settings_open = load("res://scripts/ui/settings_menu.gd").new()
		pause_menu.open_inside(settings_open)
		return
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

## the Controls window (bindings + camera): its own screen, not part of Settings
func _show_controls() -> void:
	if is_instance_valid(controls_open) or is_instance_valid(settings_open): return
	if is_instance_valid(pause_menu) and pause_menu is PausePamphlet:   # printed inside the leaflet
		controls_open = load("res://scripts/ui/controls_menu.gd").new()
		pause_menu.open_inside(controls_open)
		return
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.35)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui.add_child(dim)
	var w: Control = load("res://scripts/ui/controls_menu.gd").new()
	controls_open = w
	if pause_menu: pause_menu.visible = false
	w.tree_exiting.connect(func():
		if is_instance_valid(dim): dim.queue_free()
		if controls_open == w: controls_open = null
		if is_instance_valid(pause_menu): pause_menu.visible = true)
	ui.add_child(w)

## credits + licences (title menu)
func _show_credits() -> void:
	if is_instance_valid(controls_open) or is_instance_valid(settings_open): return
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.35)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui.add_child(dim)
	var w: Control = load("res://scripts/ui/credits_menu.gd").new()
	controls_open = w   # (one window at a time: shares the Controls slot)
	w.tree_exiting.connect(func():
		if is_instance_valid(dim): dim.queue_free()
		if controls_open == w: controls_open = null)
	ui.add_child(w)

# ---------------------------------------------------------------- unattended smoke test
var _probe := {}
func _autotest(seconds: float) -> void:
	if Env.s("BMX_SEED") != "":
		GameState.seed = int(Env.s("BMX_SEED"))
		await _new_game()
	_start_ride()
	if Env.s("BMX_CAM") != "": game.cam.set_mode(Env.s("BMX_CAM"))
	if Env.s("BMX_CAM_CYCLE") != "":   # tests: press C (next camera; Y on a pad) every 0.6 s, print each mode
		var cyc := func() -> void:
			for i in game.cam.PRESETS.size() + 1:
				await get_tree().create_timer(0.6).timeout
				for down in [true, false]:
					var ev := InputEventKey.new()
					ev.keycode = KEY_C; ev.physical_keycode = KEY_C; ev.pressed = down
					Input.parse_input_event(ev)
				await get_tree().process_frame
				print("CAMCYCLE ", i, " ", game.cam.mode)
		cyc.call()
	if Env.s("BMX_AT") != "":   # tests: start this many metres down the course
		var cp: Array = game.terrain.field.course.at(float(Env.s("BMX_AT")))
		game.phys.reset_at(cp[0], cp[1], atan2(-float(cp[3]), float(cp[2])))
		game._snap_prev()
		game.cam.snap_to(Vector3(cp[0], game.phys.y + 0.5, cp[1]))
	var pedal := Env.s("BMX_IDLE") == ""
	if Env.s("BMX_DEMO") != "": game.set_demo(true)   # tests: the AI rider rides (DEMO lines every 5 s)
	if Env.s("BMX_PANEL") != "":   # tests: open the tuning card (ride/rider/look), BMX_PANEL_CAT = category tab
		var pt: String = game.hud.SIDE_TABS.get(Env.s("BMX_PANEL"), "ride")
		if Env.s("BMX_PANEL_CAT") != "": TuneCard.last_cat[pt] = int(Env.s("BMX_PANEL_CAT"))
		if Env.s("BMX_RIDE_ALL") != "": TuneCard.ride_all = true   # tests: the Ride pages' "All sliders" view
		game.hud._toggle_side(Env.s("BMX_PANEL"))
	if Env.s("BMX_NOLOD") != "": get_viewport().mesh_lod_threshold = 0.0
	if Env.s("BMX_LOD") != "": get_viewport().mesh_lod_threshold = float(Env.s("BMX_LOD"))
	if Env.s("BMX_NOVSYNC") != "": DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED); Engine.max_fps = 0
	if Env.s("BMX_FPS") != "": DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED); Engine.max_fps = int(Env.s("BMX_FPS"))   # tests: a fixed frame rate (60 = a vsynced screen)
	var rec: AudioEffectRecord = null
	if Env.s("BMX_REC") != "":   # tests: record the game's own sound to a wav
		rec = AudioEffectRecord.new()
		AudioServer.add_bus_effect(0, rec)
		rec.set_recording_active(true)
	var t0 := Time.get_ticks_msec()
	var frames := 0
	var tris := 0.0
	var draws := 0.0
	while (Time.get_ticks_msec() - t0) / 1000.0 < seconds:
		var el := (Time.get_ticks_msec() - t0) / 1000.0
		if game.demo != null and int(el * 2) != int(_probe.get("demo_k", -1)):
			_probe["demo_k"] = int(el * 2)
			var dp: DemoPilot = game.demo
			var dph = game.phys
			_probe["demo_vmax"] = maxf(float(_probe.get("demo_vmax", 0.0)), dph.v * 3.6)
			_probe["demo_xmax"] = maxf(float(_probe.get("demo_xmax", 0.0)), dp.cross)
			_probe["demo_slip"] = maxf(float(_probe.get("demo_slip", 0.0)), absf(dph.slip))
			if int(el * 2) % 4 == 0: print("DEMO max=%s/%s t=%.1f s=%.0f v=%.1f/%.1f km/h cross=%.2f slip=%.2f air=%s resets=%d crash=%s" % [str(Tune.base.get("demoMaxKmh")), str(Tune.ride.get("demoMaxKmh")), el, dp.s_here, dph.v * 3.6, dp.target_v * 3.6, dp.cross, dph.slip, dph.air, dp.resets, dph.crash_on])
		if Env.s("BMX_FREEZE") != "":   # tests: time frozen from a to b s (no map), as the map / photo mode do
			var fz := Env.s("BMX_FREEZE").split(",")
			Engine.time_scale = 0.0 if (el >= float(fz[0]) and el < float(fz[1])) else 1.0
		if Env.s("BMX_MAP") != "" and el >= float(Env.s("BMX_MAP")) and not _probe.get("map", false):   # tests: open the trail map
			_probe.map = true; game.open_map()
			if Env.s("BMX_MAP_TILT") != "":   # tests: hold the right stick (body actions) while it's open
				var tv := Env.s("BMX_MAP_TILT").split(",")
				Input.action_press("body_right" if float(tv[0]) > 0 else "body_left", absf(float(tv[0])))
				Input.action_press("body_fwd" if float(tv[1]) > 0 else "body_back", absf(float(tv[1])))
		if Env.s("BMX_REPLAY") != "" and el >= float(Env.s("BMX_REPLAY")) and not _probe.get("replay", false):   # tests: the instant replay (BMX_REPLAY_SET / _SHOTS)
			_probe.replay = true
			print("AUTOTEST replay: opened=%s secs=%.1f" % [game.open_replay(), game.replay.duration()])
		if Env.s("BMX_REPLAY_SAVE") != "" and el >= float(Env.s("BMX_REPLAY_SAVE")) and not _probe.get("replay_s", false):   # tests: save it (tests/ folder)
			_probe.replay_s = true
			print("AUTOTEST replay saved: ", game.replay.save())
		if Env.s("BMX_REPLAY_CLOSE") != "" and el >= float(Env.s("BMX_REPLAY_CLOSE")) and not _probe.get("replay_x", false):
			_probe.replay_x = true
			game.exit_replay()
			print("AUTOTEST replay closed: time_scale=%.2f cam=%s" % [Engine.time_scale, get_viewport().get_camera_3d().name])
		if Env.s("BMX_PHOTO") != "" and el >= float(Env.s("BMX_PHOTO")) and not _probe.get("photo", false):   # tests: photo mode (BMX_PHOTO_SET / _FLY / _SNAP)
			_probe.photo = true; game.toggle_photo()
		if Env.s("BMX_PHOTO_CLOSE") != "" and el >= float(Env.s("BMX_PHOTO_CLOSE")) and not _probe.get("photo_x", false):   # tests: O again
			_probe.photo_x = true
			var ko := InputEventKey.new(); ko.keycode = KEY_O; ko.physical_keycode = KEY_O; ko.pressed = true
			Input.parse_input_event(ko)
		if Env.s("BMX_MAP_CLOSE") != "" and el >= float(Env.s("BMX_MAP_CLOSE")) and not _probe.get("map_x", false):   # tests: M again
			_probe.map_x = true
			var ke := InputEventKey.new(); ke.keycode = KEY_M; ke.physical_keycode = KEY_M; ke.pressed = true
			Input.parse_input_event(ke)
		if Env.s("BMX_IDLE_FOR") != "": pedal = el >= float(Env.s("BMX_IDLE_FOR"))   # tests: stand still, then ride off
		if Env.s("BMX_HOLD_BRAKE") != "" and el >= float(Env.s("BMX_HOLD_BRAKE")):   # tests: brake held to the end
			pedal = false; Input.action_press("brake")
			if int(el * 4) % 2 == 0 and int(el * 40) % 20 == 0: print("HOLD t=%.1f v=%.3f pos=(%.2f, %.2f) slope=%.2f" % [el, game.phys.v, game.phys.x, game.phys.z, game.phys._g_pitch])
		var stop_at := Env.s("BMX_STOP_AT")   # tests: "a,b" = pedal, brake to a stop from a s, ride off again at b s
		if stop_at != "":
			var sa := stop_at.split(",")
			var braking := el >= float(sa[0]) and (sa.size() < 2 or el < float(sa[1]))
			pedal = not braking
			if braking and game.phys.v > 0.3: Input.action_press("brake")   # off once stopped (held brake backs up)
			else: Input.action_release("brake")
		if Env.s("BMX_SHIFT") != "" and el >= float(Env.s("BMX_SHIFT")):   # tests: shift every 0.7 s (3 easier, 3 harder...)
			var si := int((el - float(Env.s("BMX_SHIFT"))) / 0.7)
			if si != _probe.get("shift_i", -1):
				_probe.shift_i = si
				var srun := int(Env.s("BMX_SHIFT_RUN")) if Env.s("BMX_SHIFT_RUN") != "" else 3   # shifts each way (12 = run into the ends)
				game._shift(1 if (si / srun) % 2 == 0 else -1)
				print("SHIFT t=%.2f d=%d gear=%d" % [el, 1 if (si / srun) % 2 == 0 else -1, game.phys.gear])
		if pedal and not (Env.s("BMX_COAST") != "" and int(el) % 6 >= 3): Input.action_press("pedal")   # BMX_COAST: 3 s pedal / 3 s coast
		else: Input.action_release("pedal")
		if Env.s("BMX_BRAKETURN") != "" and el > float(Env.s("BMX_BRAKETURN")):   # tests: 2 s pedal up to speed, 1.5 s hard brake + full steer, repeat
			var ph_bt = (el - float(Env.s("BMX_BRAKETURN"))) 
			var k_bt := fmod(ph_bt, 7.5)
			var hard := k_bt > 6.0
			game.jitter_on = hard
			var jshot := Env.s("BMX_JIT_SHOTS")   # tests: 8 frames in a row, 0.4 s into the first hard brake-turn
			if jshot != "" and hard and k_bt > 6.4 and int(_probe.get("jit_n", 0)) < 8:
				_probe.jit_n = int(_probe.get("jit_n", 0)) + 1
				get_viewport().get_texture().get_image().save_png("%s_%d.png" % [jshot, _probe.jit_n])
			if game.phys.crash_on:   # back up and on again after a crash (the probe skips crashed frames)
				_probe.bt_crash = _probe.get("bt_crash", 0.0) + get_process_delta_time()
				if _probe.bt_crash > 1.5:
					_probe.bt_crash = 0.0
					var crs_bt = game.terrain.field.course
					var cp_bt: Array = crs_bt.at(maxf(0.0, crs_bt.nearest(game.phys.x, game.phys.z) if crs_bt.has_method("nearest") else 20.0))
					game.get_up()
					game.phys.reset_at(cp_bt[0], cp_bt[1], atan2(-float(cp_bt[3]), float(cp_bt[2])))
					game._snap_prev()
			if hard:
				Input.action_release("pedal"); Input.action_press("brake")
				Input.action_press("steer_left" if int(ph_bt / 7.5) % 2 == 0 else "steer_right")
			else:
				Input.action_release("brake"); Input.action_release("steer_left"); Input.action_release("steer_right"); Input.action_press("pedal"); Input.action_press("sprint")
		if Env.s("BMX_SAVELOG") != "" and el >= float(Env.s("BMX_SAVELOG")) and not _probe.has("logged"):   # tests: press "save ride log"
			_probe["logged"] = true
			var ev := InputEventAction.new(); ev.action = "save_log"; ev.pressed = true
			Input.parse_input_event(ev)
		var body_t := Env.s("BMX_BODY")   # tests: the body stick. manual / fwd / lean / flick (from 3 s)
		if body_t != "" and el >= 3.0:
			var ph2: BikePhysics = game.phys
			if body_t == "manual": Input.action_press("body_back", 0.9 if int(el) % 4 < 3 else 0.0)
			elif body_t.begins_with("slowback:"):   # tests: lean back slowly (over 1 s) to that far and hold: must NOT start a manual
				if ph2.v > 4.0 and not _probe.has("sb0"): _probe["sb0"] = el   # (from rolling: the test clock runs while the ride loads)
				Input.action_press("body_back", float(body_t.trim_prefix("slowback:")) * clampf(el - float(_probe.get("sb0", INF)), 0.0, 1.0))
			elif body_t.begins_with("cornerpull:"):   # tests: a quick pull back only once leaned into a turn (corner gate: must NOT lift)
				Input.action_press("body_back", float(body_t.trim_prefix("cornerpull:")) if absf(ph2.lean) > 0.3 else 0.0)
			elif body_t.begins_with("pull:"):   # tests: hold the stick back that far (direct manual: stick = front height)
				Input.action_press("body_back", float(body_t.trim_prefix("pull:")))
			elif body_t == "balance" or body_t == "overpull":   # balance the manual like a player: pull while it's under the balance point
				var bp: float = float(Tune.v.get("manBalance", 0.55)) - (0.12 if body_t == "balance" else -0.6)
				var mf: float = float(Tune.v.get("manualFrom", 0.4))
				var need: float = float(Tune.v.get("manGravity", 7.0)) * sin(maxf(0.0, float(Tune.v.get("manBalance", 0.55)) - ph2.man_a)) / float(Tune.v.get("manLift", 9.0))
				var pull: float = clampf(need + 3.0 * (bp - ph2.man_a) - 0.8 * ph2.man_w, 0.0, 1.0) if body_t == "balance" else (1.0 if ph2.man_a < bp else 0.0)
				if ph2.air: pull = 0.0   # a player lets the manual go off a lip
				Input.action_press("body_back", mf + pull * (1.0 - mf)) if pull > 0.0 else Input.action_release("body_back")
			elif body_t == "bhop":   # the stick hop every 3 s: back for BMX_BHOP_HOLD s (0.3), then snapped forward
				var ph_h := fmod(el, 3.0)
				var hold_s: float = float(Env.s("BMX_BHOP_HOLD")) if Env.s("BMX_BHOP_HOLD") != "" else 0.3
				if ph_h < hold_s:
					Input.action_release("body_fwd"); Input.action_press("body_back", 1.0)
				elif ph_h < hold_s + 0.15:
					Input.action_release("body_back"); Input.action_press("body_fwd", 1.0)
				else:
					Input.action_release("body_back"); Input.action_release("body_fwd")
				if ph2.air and int(el * 30) % 3 == 0: print("BHOP air=%.2f h=%.2f vy=%.2f pitch=%.2f" % [ph2.air_time, ph2.y - ph2._g_y, ph2.vy, ph2.pitch])
			elif body_t == "manhop":   # every 3 s: stick back (a manual) with hop held, hop let go after 0.35 s = a hop out of the manual
				var ph_m := fmod(el, 3.0)
				if ph_m < 0.45: Input.action_press("body_back", 1.0)
				else: Input.action_release("body_back")
				if ph_m < 0.35: Input.action_press("hop")
				else: Input.action_release("hop")
				if ph2.air and int(el * 30) % 3 == 0: print("BHOP air=%.2f h=%.2f vy=%.2f pitch=%.2f" % [ph2.air_time, ph2.y - ph2._g_y, ph2.vy, ph2.pitch])
			elif body_t == "stoppie":   # every 7 s: front brake + stick forward, then balanced like a player (brake let go after 0.7 s)
				var ph_s := fmod(el - 3.0, 7.0)
				var nb: float = float(Tune.v.get("noseBalance", 0.5)) - 0.1
				if ph_s > 1.5 and ph_s < 5.0:
					Input.action_release("pedal"); Input.action_release("sprint")
					if ph_s < 2.2 and ph2.nose_a < nb: Input.action_press("brake_front", 1.0)
					else: Input.action_release("brake_front")
					if ph2.nose_a < nb - 0.5 * ph2.nose_w:
						Input.action_release("body_back"); Input.action_press("body_fwd", 1.0)
					else:
						Input.action_release("body_fwd"); Input.action_press("body_back", 0.5)
				else:
					Input.action_release("brake_front"); Input.action_release("body_fwd"); Input.action_release("body_back")
					Input.action_press("pedal"); Input.action_press("sprint")
			elif body_t == "fwd": Input.action_press("body_fwd", 1.0)
			elif body_t == "lightfwd": Input.action_press("body_fwd", 0.25)   # resting the stick a little forward (attack position)
			elif body_t == "holdback":   # in the air: stick held fully back (wind up a back flip), hands off on the ground
				var on2 := ph2.air and ph2.air_time > 0.08
				Input.action_press("body_back", 1.0) if on2 else Input.action_release("body_back")
				if on2 and Env.s("BMX_BODY_PRINT") != "":
					print("SPIN t=%.2f air=%.2f edge=%.2f hold=%.2f k=%.2f pitch_v=%.2f lean=%.2f" % [el, ph2.air_time, ph2.edge_s, ph2.spin_hold, ph2.spin_k, ph2.pitch_v, ph2.bike_lean])
			elif body_t == "spin360":   # in the air: stick fully left until ~300° round, then let go (the landing twist finishes it)
				var on3: bool = ph2.air and ph2.air_time > 0.08 and absf(ph2.spin_acc) < 5.3
				Input.action_press("body_left", 1.0) if on3 else Input.action_release("body_left")
				if ph2.air and Env.s("BMX_BODY_PRINT") != "" and int(el * 20) % 2 == 0:
					print("YAW t=%.2f air=%.2f stick_yaw=%.2f edge=%.2f hold=%.2f spin=%.0fdeg slip=%.2f" % [el, ph2.air_time, ph2.stick_yaw, ph2.yaw_edge_s, ph2.yaw_hold, rad_to_deg(ph2.spin_acc), ph2.slip])
			elif body_t.begins_with("air:"):   # tests: in the air hold the stick at x,y (+x left, +y forward), e.g. air:0,0.75
				var xy := body_t.trim_prefix("air:").split(",")
				var on4: bool = ph2.air and ph2.air_time > 0.08
				var ax := float(xy[0]) if on4 else 0.0
				var ay := float(xy[1]) if on4 else 0.0
				Input.action_press("body_left", ax) if ax > 0.0 else Input.action_release("body_left")
				Input.action_press("body_right", -ax) if ax < 0.0 else Input.action_release("body_right")
				Input.action_press("body_fwd", ay) if ay > 0.0 else Input.action_release("body_fwd")
				Input.action_press("body_back", -ay) if ay < 0.0 else Input.action_release("body_back")
			elif body_t == "circle":   # in the air: circle the stick (0.8 deflection, ~1 turn / s); hands off on the ground
				var ca := el * TAU * 1.0
				var on := ph2.air and ph2.air_time > 0.08
				var sx := sin(ca) * 0.8 if on else 0.0
				var sy := cos(ca) * 0.8 if on else 0.0
				Input.action_press("body_left", sx) if sx > 0.0 else Input.action_release("body_left")
				Input.action_press("body_right", -sx) if sx < 0.0 else Input.action_release("body_right")
				Input.action_press("body_fwd", sy) if sy > 0.0 else Input.action_release("body_fwd")
				Input.action_press("body_back", -sy) if sy < 0.0 else Input.action_release("body_back")
				if on and Env.s("BMX_BODY_PRINT") != "":
					print("AIRSTICK t=%.2f stick=(%.2f,%.2f) pitch=%.2f g=%.2f bike_lean=%.2f air_tilt=%.2f" % [el, ph2.air_stick.x, ph2.air_stick.y, ph2.pitch, ph2._g_pitch, ph2.bike_lean, ph2.air_tilt])
			elif body_t == "circle2":   # tests (air smoothness): in the air circle the right stick AND steer the left stick back and forth
				var ca2 := el * TAU * 0.8
				var on2 := ph2.air and ph2.air_time > 0.08
				var sx2 := sin(ca2) * 0.9 if on2 else 0.0
				var sy2 := cos(ca2) * 0.9 if on2 else 0.0
				var ls := sin(el * TAU * 0.6) * 0.8 if on2 else 0.0
				Input.action_press("body_left", sx2) if sx2 > 0.0 else Input.action_release("body_left")
				Input.action_press("body_right", -sx2) if sx2 < 0.0 else Input.action_release("body_right")
				Input.action_press("body_fwd", sy2) if sy2 > 0.0 else Input.action_release("body_fwd")
				Input.action_press("body_back", -sy2) if sy2 < 0.0 else Input.action_release("body_back")
				if on2:
					Input.action_press("steer_left", ls) if ls > 0.0 else Input.action_release("steer_left")
					Input.action_press("steer_right", -ls) if ls < 0.0 else Input.action_release("steer_right")
			elif body_t == "scrub":   # tests (air step 3): the stick diagonal (forward + to the side) into the lip and in the air
				var on6: bool = (ph2.air and ph2.air_time < 0.7) or (not ph2.air and ph2.lip_state == 2)
				if on6: Input.action_press("body_left", 0.6); Input.action_press("body_fwd", 0.6)
				else: Input.action_release("body_left"); Input.action_release("body_fwd")
				if ph2.air and int(el * 10) % 2 == 0 and Env.s("BMX_BODY_PRINT") != "": print("SCRUBT t=%.2f h=%.2f lean=%.0f yaw=%.0f squash_fx=%.2f whip_in=%.2f" % [ph2.air_time, ph2.y - ph2._g_y, rad_to_deg(ph2.bike_lean), rad_to_deg(ph2.slip), ph2.squash_fx, ph2._whip_in])
			elif body_t.begins_with("whiplip") or body_t.begins_with("whipair"):   # tests (air step 2): the stick to the side, 0.7 by default
				# whiplip: held from when a lip is spotted ahead and through the air (carved in); whipair: only once in the air
				var wx := float(body_t.get_slice(":", 1)) if body_t.contains(":") else 0.7
				var on5: bool = (ph2.air and ph2.air_time > 0.05 and ph2.air_time < 0.9) or (body_t.begins_with("whiplip") and not ph2.air and ph2.lip_state == 2)
				if on5: Input.action_press("body_left", wx)
				else: Input.action_release("body_left")
				if ph2.air and int(el * 20) % 2 == 0 and Env.s("BMX_BODY_PRINT") != "": print("WHIPT t=%.2f load=%.2f whip_in=%.2f air_tw=%.0f deg" % [ph2.air_time, ph2.whip_load, ph2._whip_in, rad_to_deg(ph2.air_tw)])
			elif body_t.begins_with("spinlip") or body_t.begins_with("spinair") or body_t.begins_with("fliplip") or body_t.begins_with("flipair"):
				# tests (spins / flips): the stick to the left edge (spin) / pulled back (back flip), held from the lip spotted
				# ahead (*lip) or only in the air (*air), let go once ~300 deg round (a 360 / a back flip landed)
				var is_spin: bool = body_t.begins_with("spin")
				var from_lip: bool = body_t.ends_with("lip")   # ("flipair" contains "lip")
				var turned: float = absf(ph2.spin_acc) if is_spin else absf(ph2.flip_acc)
				var early: float = float(Env.s("BMX_FLIP_EARLY")) if Env.s("BMX_FLIP_EARLY") != "" else 0.4   # tests: how long before the lip it is pulled (s)
				var on7: bool = (ph2.air and (from_lip or ph2.air_time > 0.08) and turned < TAU - 1.0) or (from_lip and not ph2.air and ph2.lip_state == 2 and ph2.lip_last < early)
				if Env.s("BMX_BODY_PRINT") != "" and not ph2.air and ph2.lip_state == 2: print("SPINLIP on=%s back=%.2f body_in=%.2f crouch=%.2f throw=%.2f lip=%.2f" % [on7, Input.get_action_strength("body_back"), ph2.body_in, ph2.crouch, ph2.throw_v, ph2.lip_last])
				if is_spin:
					if on7: Input.action_press("body_left", 1.0)
					else: Input.action_release("body_left")
				else:
					if on7: Input.action_press("body_back", 1.0)
					else: Input.action_release("body_back")
				if ph2.air and int(el * 10) % 2 == 0 and Env.s("BMX_BODY_PRINT") != "": print("SPINT t=%.2f spin=%.0f flip=%.0f spin_in=%.2f flip_in=%.2f yaw=%.2f air_w=%.2f" % [ph2.air_time, rad_to_deg(ph2.spin_acc), rad_to_deg(ph2.flip_acc), ph2._spin_in, ph2._flip_in, ph2.stick_yaw, ph2.air_w])
			elif body_t == "lean": Input.action_press("body_left", 1.0)
			elif body_t == "both":   # both sticks: the right stick leans the way the left stick steers (+ hand wobble)
				var s_l := Input.get_action_strength("steer_left") - Input.get_action_strength("steer_right")
				var bl := clampf(s_l * 1.2 + sin(el * 7.3) * 0.12, -1.0, 1.0)
				Input.action_press("body_left", bl) if bl > 0.0 else Input.action_release("body_left")
				Input.action_press("body_right", -bl) if bl < 0.0 else Input.action_release("body_right")
			elif body_t == "thumb":   # a real thumb on the right stick, leaning with the steer: never on the axis
				# (+-0.35 fore / aft drift), re-grips (a jump to a new spot every ~0.4 s), small tremor
				var s_l2 := Input.get_action_strength("steer_left") - Input.get_action_strength("steer_right")
				var seg := floori(el / 0.4)
				var rr := RandomNumberGenerator.new(); rr.seed = seg * 7919 + 13
				var sx := clampf(s_l2 * rr.randf_range(0.7, 1.3) + rr.randf_range(-0.25, 0.25) + sin(el * 23.0) * 0.05, -1.0, 1.0)
				var sy := rr.randf_range(-0.35, 0.35) + sin(el * 19.0) * 0.04
				Input.action_press("body_left", sx) if sx > 0.0 else Input.action_release("body_left")
				Input.action_press("body_right", -sx) if sx < 0.0 else Input.action_release("body_right")
				Input.action_press("body_fwd", sy) if sy > 0.0 else Input.action_release("body_fwd")
				Input.action_press("body_back", -sy) if sy < 0.0 else Input.action_release("body_back")
				var ph3: BikePhysics = game.phys
				if not ph3.air and not ph3.crash_on:
					_probe.thumb_n = int(_probe.get("thumb_n", 0)) + 1
					if ph3.man_a > 0.05: _probe.thumb_manual = int(_probe.get("thumb_manual", 0)) + 1
					if absf(ph3.flick_kick) > 0.01: _probe.thumb_kick = int(_probe.get("thumb_kick", 0)) + 1
					var dp: float = absf(ph3.body_in_s - float(_probe.get("thumb_bs", 0.0)))
					_probe.thumb_bs = ph3.body_in_s; _probe.thumb_bsj = float(_probe.get("thumb_bsj", 0.0)) + dp
			elif body_t == "flick":
				var side := int(el * 1.5) % 2 == 0
				Input.action_press("body_left", 1.0) if side else Input.action_release("body_left")
				Input.action_press("body_right", 1.0) if not side else Input.action_release("body_right")
			if Env.s("BMX_BODY_PRINT") != "" and int(el * 10) % 5 == 0:
				print("BODY t=%.1f v=%.1f in=%.2f flick=%.2f manual=%.2f pitch=%.2f g=%.2f bike_lean=%.2f lean=%.2f yaw=%.2f slip=%.2f hip=%.3f air=%s" % [el, ph2.v, ph2.body_in, ph2.flick, ph2.man_a, ph2.pitch, ph2._g_pitch, ph2.bike_lean, ph2.lean, ph2.yaw_rate, ph2.slip, ph2.hip_shift, ph2.air])
		if Env.s("BMX_MUD") != "": game.grime.mud = float(Env.s("BMX_MUD"))   # tests: hold the mud level
		var straight := Env.s("BMX_STRAIGHT") != ""   # tests: ride straight, no steering / hops
		if Env.s("BMX_CAM_ORBIT") != "": game.cam.orbit_t = float(Env.s("BMX_CAM_ORBIT")); game.cam.pan_t = 1e9   # held: no re-centre
		if Env.s("BMX_CAM_DIST") != "": game.cam.dist = float(Env.s("BMX_CAM_DIST"))
		if Env.s("BMX_CAM_PROBE") != "":   # tests: the camera's offset from the rider, frame to frame
			var off: Vector3 = game.cam.global_position - game.drawn_pos
			if _probe.has("cam_off") and el > 1.0:
				var jump: float = (off - _probe.cam_off).length()
				_probe.cam_jump_max = maxf(_probe.get("cam_jump_max", 0.0), jump)
				_probe.cam_dist_min = minf(_probe.get("cam_dist_min", 1e9), off.length())
				_probe.cam_dist_max = maxf(_probe.get("cam_dist_max", 0.0), off.length())
			_probe.cam_off = off
		var trick := Env.s("BMX_TRICK")   # tests: back / front flip lean, side = A / D lean (alternating) in every jump
		if Env.s("BMX_KNEE_PROBE") != "" and game.rider != null:   # tests: biggest knee jump per frame
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
		var launch := Env.s("BMX_LAUNCH")   # tests: stop at 3 s, then pedal (sprint=1: sprint) away; prints 0-15 / 0-25 / 0-35 km/h times
		if launch != "" and el > 3.0:
			var ph = game.phys
			if not _probe.has("l_t0"):
				_probe.l_t0 = el; ph.v = 0.0
			var hold := float(Env.s("BMX_LAUNCH_HOLD")) if Env.s("BMX_LAUNCH_HOLD") != "" else 99.0   # tests: let go of sprint after this long
			if launch == "sprint" and el - float(_probe.l_t0) < hold: Input.action_press("sprint")
			else: Input.action_release("sprint")
			Input.action_press("pedal")
			var lt: float = el - float(_probe.l_t0)
			if ph.front_air: _probe.l_wh = float(_probe.get("l_wh", 0.0)) + get_process_delta_time()
			_probe.l_pmax = maxf(float(_probe.get("l_pmax", 0.0)), ph.pitch - ph._g_pitch)
			if (ph.crash_on or ph.crash_pending != "") and not _probe.has("l_crash"):
				_probe.l_crash = true
				print("LAUNCH crash %s at %.2f s v=%.1f" % [ph.crash_pending, lt, ph.v])
			if Env.s("BMX_LAUNCH_DBG") != "" and lt < 2.0: print("WH t=%.2f fa=%s ra=%s up=%.2f pitch=%.2f g=%.2f nref=%s spr=%.2f thr=%s" % [lt, ph.front_air, ph.rear_air, ph.wheelie_up, ph.pitch, ph._g_pitch, ph.nose_ref, ph.sprint, Input.get_action_strength("pedal")])
			if int(lt * 2) != int(_probe.get("l_tick", -1)):
				_probe.l_tick = int(lt * 2)
				print("LAUNCH t=%.1f v=%.1f km/h nose_up=%.2f wheelie_s=%.2f max=%.2f" % [lt, ph.v * 3.6, ph.pitch - ph._g_pitch, float(_probe.get("l_wh", 0.0)), float(_probe.l_pmax)])
			for kmh in [15, 25, 35]:
				if ph.v * 3.6 >= kmh and not _probe.has("l_%d" % kmh):
					_probe["l_%d" % kmh] = lt
					print("LAUNCH %s 0-%d km/h in %.2f s (stamina %.2f)" % [launch, kmh, lt, ph.stamina])
			var ls := Env.s("BMX_LAUNCH_SHOTS")
			if ls != "" and lt > 0.3 and lt - float(_probe.get("l_shot", -1.0)) > 0.4 and int(_probe.get("l_n", 0)) < 6:
				_probe.l_shot = lt; _probe.l_n = int(_probe.get("l_n", 0)) + 1
				get_viewport().get_texture().get_image().save_png("%s_%d.png" % [ls, _probe.l_n])
		if Env.s("BMX_GRIP_PROBE") != "" and el - float(_probe.get("grip_t", -1.0)) >= 0.25:   # tests: tyre grip sim
			_probe.grip_t = el
			var gp = game.phys
			_probe.grip_max = maxf(float(_probe.get("grip_max", 0.0)), absf(gp.slip) if not gp.air else 0.0)
			print("GRIP t=%.2f v=%.1f slip=%.1fdeg slip_w=%.2f grip_r=%.2f loose=%.2f squirm=%.1fdeg bars=%.1fdeg skid=%s air=%s" % [el, gp.v, rad_to_deg(gp.slip), gp.slip_w, gp.grip_r, gp.loose, rad_to_deg(gp._squirm), rad_to_deg(gp.bar_catch), gp.skid_fx, gp.air])
		if Env.s("BMX_VMAX") != "" and not game.phys.air: _probe.vmax_kmh = maxf(_probe.get("vmax_kmh", 0.0), game.phys.v * 3.6)   # tests
		var airshot := Env.s("BMX_AIRSHOT")   # tests: dir/prefix -> shots mid-air (up to 8)
		if airshot != "" and game.phys.air and game.phys.air_time > 0.25 and _airshots < 8 and el - _airshot_t > 0.6:
			_airshot_t = el
			get_viewport().get_texture().get_image().save_png("%s_%d.png" % [airshot, _airshots])
			_airshots += 1
		if Env.s("BMX_FAKIE") != "":   # tests: every jump lands backwards; 1 s later both sticks go towards the centre
			var fp = game.phys
			if fp.air and fp.air_time > 0.1 and fp.v > 0.0 and not _probe.has("fk_done"):
				fp.slip = (deg_to_rad(float(Env.s("BMX_FAKIE"))) if float(Env.s("BMX_FAKIE")) > 1.0 else PI - 0.1); _probe.fk_land = el; _probe.fk_air = true
			var since: float = el - float(_probe.get("fk_land", -99.0))
			var go: bool = fp.v < -0.5 and not fp.air and since > 0.2 and since < 1.5
			if _probe.has("fk_air") and since > 1.2 and fp.v > 0.5 and not fp.air: _probe.fk_done = true
			if go: Input.action_press("steer_right"); Input.action_press("body_left")
			else: Input.action_release("steer_right"); Input.action_release("body_left")
			if int(el * 4) != int(_probe.get("fk_tick", -1)):
				_probe.fk_tick = int(el * 4)
				print("FAKIE t=%.2f v=%.1f air=%s crash=%s '%s' slip=%.2f head-course=%.2f turn_off=%.2f" % [el, fp.v, fp.air, fp.crash_on, fp.crash_pending, fp.slip, wrapf(fp.heading - fp.course, -PI, PI), fp.turn_off])
		if trick != "" and game.phys.air:
			var ph = game.phys
			if ph.air_time > 0.06 and trick == "side": trick = "left" if int(el / 2.0) % 2 == 0 else "right"
			if trick != "hold": Input.action_release("pedal")   # hold: keeps pedalling through the air, like a pad trigger held down
			Input.action_release("brake"); Input.action_release("steer_left"); Input.action_release("steer_right")
			if Env.s("BMX_BIGAIR") != "" and ph.air_time < 0.03 and ph.vy < 7.0: ph.vy = 7.0   # tests: big air for full flips
			if ph.air_time > 0.06:   # a fresh press after take-off (held keys are locked)
				if trick == "back": Input.action_press("brake")
				elif trick == "manual":   # lean back to this nose-up angle (BMX_MANUAL_PITCH, rad) and hold it
					var mp := float(Env.s("BMX_MANUAL_PITCH")) if Env.s("BMX_MANUAL_PITCH") != "" else 1.0
					var e: float = mp - ph.pitch - ph.pitch_v * 0.25
					if e > 0.05: Input.action_press("brake")
					elif e < -0.05: Input.action_press("pedal")
				elif trick == "front": Input.action_press("pedal")
				elif trick == "left": Input.action_press("steer_left")
				elif trick == "right": Input.action_press("steer_right")
				elif trick == "spin" and absf(ph.air_yaw) < 1.0:   # a flat spin (as the right stick gives)
					ph.air_yaw = 7.0
				if trick == "whip":   # an air whip: right stick 75 % to the side (short of its spin edge), let go for the landing
					if ph.land_prep < 0.15: Input.action_press("body_left", 0.75)
					else: Input.action_release("body_left")
					if Engine.get_physics_frames() % 10 == 0:
						print("WHIPA t=%.2f tw=%+.0fdeg slip=%+.0fdeg land_prep=%.2f" % [ph.air_time, rad_to_deg(ph.air_tw), rad_to_deg(wrapf(ph.slip, -PI, PI)), ph.land_prep])
				if trick == "spin" and Engine.get_physics_frames() % 12 == 0:
					print("SPIN t=%.2f cam_yaw=%.2f course=%.2f heading=%.2f" % [ph.air_time, game.cam.cam_yaw, ph.course, ph.heading])
			await get_tree().process_frame
			frames += 1; tris += RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME); draws += RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)   # these early continues skip the counters at the bottom
			continue
		elif trick != "":
			Input.action_release("brake"); Input.action_release("sprint")
			if trick == "whip": Input.action_release("body_left")
			var ph = game.phys
			if (trick == "back" or trick == "front") and (ph.prep > 0.25 or ph.front_air or ph.rear_air):
				# a fresh press at the lip throws the rider into the flip (a key held from before doesn't count)
				if trick == "back": Input.action_press("brake")
				elif _probe.get("lip_rel", false): Input.action_press("pedal")
				else: Input.action_release("pedal"); _probe.lip_rel = true
			else:
				_probe.lip_rel = false
		if Env.s("BMX_FOLLOW") != "":   # tests: steer along the trail centreline, get up after a crash
			var ph = game.phys
			var crs = game.terrain.field.course
			if Env.s("BMX_RESPAWN") != "" and el > float(Env.s("BMX_RESPAWN")) and not _probe.has("respawned"):   # tests: Backspace here
				_probe["respawned"] = true; _probe.fs = 0.0
				print("AUTOTEST respawn: ride_t before=%.1f" % game.hud.ride_t)
				game.respawn(false)
			var best_d := 1e9
			var s0: float = _probe.get("fs", 0.0)
			for k in range(-40, 81):   # nearest centreline point near the last one (1 m steps)
				var cp: Array = crs.at(s0 + k)
				var dd: float = Vector2(cp[0] - ph.x, cp[1] - ph.z).length_squared()
				if dd < best_d: best_d = dd; _probe.fs = s0 + k
			var tp: Array = crs.at(float(_probe.fs) + 6.0 + absf(ph.v) * 0.5)
			var ra = game.terrain.rope_aim(ph.x, ph.z, 6.0 + absf(ph.v) * 0.5)   # a rope bridge: along its line
			if ra != null: tp = [ra.x, ra.y, tp[2], tp[3]]
			var wv := Env.s("BMX_WEAVE")   # tests: weave this far (m) either side of the centreline, over berm / trail edges
			if wv != "":
				var off: float = float(wv) * sin(el * 1.3)
				tp = [tp[0] - float(tp[3]) * off, tp[1] + float(tp[2]) * off, tp[2], tp[3]]
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
					game._out_of_crevasse()   # (the trail's line can run over a rope canyon: back onto the rim)
					game._snap_prev()
			var pr := Env.s("BMX_PUMPRIDE")   # tests: hold hop on every downhill (down) / all the time (all) / never (off)
			if Env.s("BMX_PUMP") != "" and not ph.air and ph.prep > 0.15: Input.action_press("hop")   # tests: pump into lips
			elif pr == "stick" and el > 3.0 and not ph.air:   # the pro way: stick forward on the downs, eased back on the ups
				Input.action_release("hop")
				if Input.is_action_pressed("brake"): Input.action_release("body_fwd"); Input.action_release("body_back")   # no pumping into the brakes
				elif ph._g_pitch < -0.02: Input.action_release("body_back"); Input.action_press("body_fwd", 0.75)
				elif ph._g_pitch > 0.02: Input.action_release("body_fwd"); Input.action_press("body_back", 0.25)
				else: Input.action_release("body_fwd"); Input.action_release("body_back")
			elif pr != "" and pr != "off" and pr != "stick" and el > 3.0 and not ph.air and (pr == "all" or ph._g_pitch < -0.02): Input.action_press("hop")
			elif Env.s("BMX_BODY") != "manhop": Input.action_release("hop")   # (manhop works the hop button itself)
			if pr != "" and int(el * 2.0) != int(_probe.get("pr_k", -1)):
				_probe["pr_k"] = int(el * 2.0)
				print("PUMPRIDE %s t=%.1f v=%.1f km/h push=%.2f gain=%.1f slope=%.3f at=(%.1f,%.1f) surf=%d slip=%.2f man=%.2f air=%s" % [pr, el, ph.v * 3.6, ph.pump_push, ph.pump_gain, ph._g_pitch, ph.x, ph.z, ph.surf, ph.slip, ph.man_a, ph.air])
			await get_tree().process_frame
			if Env.s("BMX_DUST_SHOTS") != "":   # the timed screenshots work here too
				var t0f := float(Env.s("BMX_DUST_T0")) if Env.s("BMX_DUST_T0") != "" else 3.0
				var nkf := int((el - t0f) * 2.0)
				if el > t0f and nkf != _probe.get("dust_k", -1) and nkf < 8:
					_probe["dust_k"] = nkf
					get_viewport().get_texture().get_image().save_png("%s_%d.png" % [Env.s("BMX_DUST_SHOTS"), nkf])
			frames += 1; tris += RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME); draws += RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)   # these early continues skip the counters at the bottom
			continue
		if Env.s("BMX_WHIP") != "":   # tests: corner whip - from 4 s hold steer + body lean the same way for secs, coast 1.5 s, other side
			var hold := float(Env.s("BMX_WHIP"))
			var w0 := float(Env.s("BMX_WHIP_T0")) if Env.s("BMX_WHIP_T0") != "" else 4.0
			var cyc := fmod(el - w0, (hold + 1.5) * 2.0) if el > w0 else -1.0
			var side := 0.0
			if cyc >= 0.0 and cyc < hold: side = 1.0
			elif cyc >= hold + 1.5 and cyc < hold * 2.0 + 1.5: side = -1.0
			for a in [["steer_left", "body_left", 1.0], ["steer_right", "body_right", -1.0]]:
				if side == a[2]:
					Input.action_press(a[0], 1.0)
					if Env.s("BMX_WHIP_STEERONLY") == "": Input.action_press(a[1], 1.0)
				else:
					Input.action_release(a[0]); Input.action_release(a[1])
			var ph4 = game.phys
			if el - float(_probe.get("wh_t", 0.0)) > 0.1:
				_probe["wh_t"] = el
				print("WHIP t=%.1f in=%+.0f whip=%.2f slip=%+.2f v=%.1f bike=%+.0fdeg crash=%s" % [el, side, ph4.whip, ph4.slip, ph4.v, rad_to_deg(ph4.bike_lean), ph4.crash_on])
		elif Env.s("BMX_FLIPFLOP") != "":   # tests: full left / full right, swapped every half period (s), from 3 s
			var per := float(Env.s("BMX_FLIPFLOP"))
			var sv := 0.0 if el < 3.0 else (1.0 if fmod(el - 3.0, per) < per * 0.5 else -1.0)
			Input.action_press("steer_left", 1.0) if sv > 0 else Input.action_release("steer_left")
			Input.action_press("steer_right", 1.0) if sv < 0 else Input.action_release("steer_right")
			var ph3 = game.phys
			var bl_prev: float = _probe.get("ff_bl", ph3.bike_lean)
			var fdt := maxf(get_process_delta_time(), 1e-4)
			_probe["ff_rate"] = maxf(_probe.get("ff_rate", 0.0), absf(ph3.bike_lean - bl_prev) / fdt) if el > 3.5 else 0.0
			_probe["ff_bl"] = ph3.bike_lean
			if el - float(_probe.get("ff_t", 0.0)) > 0.1:
				_probe["ff_t"] = el
				print("LEANFF t=%.1f v=%.1f key=%+.0f steer_in=%+.2f lat=%+.1f bike=%+.0fdeg body_hip=%+.0fdeg body_chest=%+.0fdeg max_rate=%.1frad/s" % [el, ph3.v, sv, ph3.steer_in, ph3.lat_a, rad_to_deg(ph3.bike_lean), rad_to_deg(game.rider.roll_p), rad_to_deg(game.rider.roll_c), _probe["ff_rate"]])
		elif Env.s("BMX_STEER") != "":   # tests: hold a steady turn (+ left, - right) after 2 s
			var sv := float(Env.s("BMX_STEER")) if el > 2.0 else 0.0
			if Env.s("BMX_STEER_AT_ROPE") != "":   # tests: hold it only once that far (m) along the first rope bridge
				var rp: Array = game.terrain.ropes
				sv = float(Env.s("BMX_STEER")) if not rp.is_empty() and rp[0].local(game.phys.x, game.phys.z).x > float(Env.s("BMX_STEER_AT_ROPE")) else 0.0
			Input.action_press("steer_left", maxf(sv, 0.0)) if sv > 0 else Input.action_release("steer_left")
			Input.action_press("steer_right", maxf(-sv, 0.0)) if sv < 0 else Input.action_release("steer_right")
		elif pedal and not straight and int(el) % 6 == 3: Input.action_press("steer_left")
		elif not game.jitter_on: Input.action_release("steer_left")   # (BMX_BRAKETURN steers itself)
		if pedal and not straight and int(el * 2) % 7 == 0: Input.action_press("hop")
		elif Env.s("BMX_AIRPULL") != "" and game.phys.air and game.phys.air_time > 0.1: Input.action_press("hop")   # tests: tuck in the air
		elif Env.s("BMX_BODY") != "manhop": Input.action_release("hop")
		if Env.s("BMX_RESPAWN") != "" and el > float(Env.s("BMX_RESPAWN")) and not _probe.has("respawned"):   # tests: Backspace here
			_probe["respawned"] = true
			print("AUTOTEST respawn: ride_t before=%.1f" % game.hud.ride_t)
			game.respawn(false)
		if Env.s("BMX_BAIL") != "" and el > float(Env.s("BMX_BAIL")) and not _probe.has("bailed"):   # tests: bail (crash) here
			_probe["bailed"] = true
			game.phys.crash_pending = "BAIL!"
		if Env.s("BMX_TAP_RESET") != "" and el > float(Env.s("BMX_TAP_RESET")) and not _probe.has("tapped"):   # tests: tap bail -> back on the trail
			_probe["tapped"] = true
			var p0 := Vector3(game.phys.x, game.phys.y, game.phys.z)
			game.reset_to_trail()
			var tc: TrailCourse = game.terrain.field.course
			var dm := INF
			for i in tc.n: dm = minf(dm, Vector2(tc.X[i] - game.phys.x, tc.Z[i] - game.phys.z).length())
			print("TAPRESET from %s to (%.1f, %.1f) dist_to_trail=%.2f v=%.1f crash=%s" % [str(p0), game.phys.x, game.phys.z, dm, game.phys.v, str(game.phys.crash_on)])
		if (Env.s("BMX_GOPRO_PROBE") != "" or Env.s("BMX_GETUP_PROBE") != "") and _probe.has("bailed") and not _probe.has("gotup") \
				and el > float(Env.s("BMX_BAIL")) + 2.5 and game.phys.crash_on:   # tests: get up (new GoPro on)
			_probe["gotup"] = true
			game.begin_getup()
		if Env.s("BMX_LAND_TEST") != "" and el > float(Env.s("BMX_LAND_TEST")) and not _probe.has("landed"):   # tests: fake a hard landing
			_probe["landed"] = true
			game.on_landing(1.0, 8.0)
		if Env.s("BMX_SKID") != "" and el > float(Env.s("BMX_SKID")):   # tests: lock the rear (skid) from this time on
			Input.action_release("pedal"); Input.action_press("brake")
		await get_tree().process_frame
		if Env.s("BMX_DUST_SHOTS") != "":   # tests: dir/prefix - a screenshot every 0.5 s after BMX_DUST_T0 (3 s)
			var t0d := float(Env.s("BMX_DUST_T0")) if Env.s("BMX_DUST_T0") != "" else 3.0
			var nk := int((el - t0d) * 2.0)
			if el > t0d and nk != _probe.get("dust_k", -1) and nk < 8:
				_probe["dust_k"] = nk
				get_viewport().get_texture().get_image().save_png("%s_%d.png" % [Env.s("BMX_DUST_SHOTS"), nk])
		if Env.s("BMX_TAPE") != "":   # tests: ride square into the nearest race tape, shots as it stretches / snaps
			_tape_test(el)
		if Env.s("BMX_FENCE") != "":   # tests: ride straight into the nearest fence, shots around the hit
			_fence_test(el)
		if Env.s("BMX_FENCE_ALL") != "":   # tests: smash every fence within 70 m, then check each piece
			_fence_all(el)
		if Env.s("BMX_CACTUS_ROW") != "":   # tests: the five cactus kinds in a row in front of the camera
			_cactus_row(el)
		if Env.s("BMX_BODY_PROBE") != "":   # tests: the rider's body vs the bike
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
	if Env.s("BMX_PAUSE") != "":
		_pause()
		if Env.s("BMX_PAUSE") == "settings":
			_open_settings()
			if Env.s("BMX_TAB") != "": settings_open.get_child(0).get_child(2).current_tab = int(Env.s("BMX_TAB"))
		if Env.s("BMX_PAUSE") == "controls":
			_show_controls()
			if Env.s("BMX_TAB") != "": controls_open.get_child(0).get_child(2).current_tab = int(Env.s("BMX_TAB"))
		for i in 10: await get_tree().process_frame
		await get_tree().create_timer(1.0, true, false, true).timeout   # the pause leaflet comes up
		if Env.s("BMX_PAUSE_HOVER") != "" and is_instance_valid(pause_menu):   # tests: point at a menu line
			var mv := InputEventMouseMotion.new()
			mv.position = get_viewport().get_visible_rect().size * Vector2(0.5, float(Env.s("BMX_PAUSE_HOVER")))
			Input.parse_input_event(mv)
			for i in 5: await get_tree().process_frame
			print("HOVER at ", mv.position, " -> page ", pause_menu.page_point(pause_menu._screen_px(mv.position)), " win ", get_window().size)
		if Env.s("BMX_PAUSE") == "pad":   # tests (with BMX_PAD=1): pad down twice + A on the leaflet
			for ev_b in [JOY_BUTTON_DPAD_DOWN, JOY_BUTTON_DPAD_DOWN, JOY_BUTTON_A]:
				for down in [true, false]:
					var jb := InputEventJoypadButton.new(); jb.button_index = ev_b; jb.pressed = down
					Input.parse_input_event(jb)
					for i in 3: await get_tree().process_frame
				var f: Control = pause_menu.page.gui_get_focus_owner() if is_instance_valid(pause_menu) else null
				print("PADPRESS ", ev_b, " focus=", f.get("text") if f else "-", " paused=", get_tree().paused)
			await get_tree().create_timer(1.5, true, false, true).timeout
		if Env.s("BMX_PAUSE") == "preset":   # pause > settings > a quality preset > Done > resume
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
	if Env.s("BMX_BODY_CLIP") != "":   # tests: the rider's body parts inside each other / the bike (frames > 1.5 cm in, deepest)
		var cpz: Dictionary = game.rider.clip_pairs
		var nfr: int = maxi(1, int(cpz.get("n", 0)))
		var keys := cpz.keys(); keys.erase("n"); keys.sort()
		for kk in keys:
			if int(cpz[kk][0]) > 0: print("BODYCLIP %-18s frames=%5.1f%% deepest=%4.1f cm" % [kk, 100.0 * cpz[kk][0] / nfr, cpz[kk][1] * 100.0])
		print("BODYCLIP frames=%d" % nfr)
	if Env.s("BMX_BAR_PROBE") != "":   # tests: the rider's chest / helmet against the handlebar
		var br: Array = game.rider.bar_stats
		print("BARCLEAR deepest_cm=%.1f held_frames=%d of %d least_chest_cm=%.1f least_head_cm=%.1f" % [br[0] * 100.0, int(br[1]), int(br[2]), br[3] * 100.0, br[4] * 100.0])
	if game.clip_probe:
		var bs: Array = game.rider.bounce_stats
		print("BOUNCE body_rms=%.1fcm body_max=%.1fcm legs_feel=%.2fg" % [sqrt(bs[0] / maxi(bs[1], 1)) * 100, bs[2] * 100, sqrt(bs[3] / maxi(bs[1], 1)) / 9.81])
		var cs: Dictionary = game.clip_stats
		print("RIDE bottom_outs=%d body=%.2fg ground=%.2fg" % [st.probe_bottom, sqrt(st.probe_acc2 / maxi(st.probe_n, 1)) / 9.81, sqrt(st.probe_g2 / maxi(st.probe_n, 1)) / 9.81])
		print("CLIP frames=%d lifted=%d deepest_before=%.1fcm deepest_after=%.2fcm frames_inside=%d" % [cs.frames, cs.fixed, cs.before * 100, cs.after * 100, cs.bad])
	if Env.s("BMX_KNEE_PROBE") != "":
		for row in game.rider.knee_dbg: print("KNEE ", row)
	if game.rider.limb_probe:
		for k in game.rider.limb_stats:
			var s: Dictionary = game.rider.limb_stats[k]
			print("LIMB %s frames=%d turn_max=%.1fdeg jump_max=%.1fcm flips=%d jumps=%d" % [k, s.frames, s.turn_max, s.jump_max * 100, s.flips, s.jumps])
			for w in s.worst: print("  LIMBW %s %s" % [k, w])
	print("AUTOTEST avg triangles/frame=%dk draw calls=%d" % [tris / maxi(frames, 1) / 1000, draws / maxi(frames, 1)])
	if Env.s("BMX_PHOTO") != "": print("AUTOTEST photo: on=%s time_scale=%.2f hud=%s fov=%.1f" % [game.photo, Engine.time_scale, game.hud.visible, game.cam.fov])
	if game.rumble and game.rumble.probe: print(game.rumble.probe_summary())
	if Env.s("BMX_MAP") != "": print("AUTOTEST map: open=%s time_scale=%.2f hud=%s" % [game.paper_map.busy() if game.paper_map else "none", Engine.time_scale, game.hud.visible])
	print("AUTOTEST frames=%d fps=%.1f pos=(%.1f, %.1f, %.1f) v=%.2f crash=%s sane=%s" % [frames, frames / seconds, st.x, st.y, st.z, st.v, st.crash_on, st.is_sane()])
	if Env.s("BMX_BRAKETURN") != "" or Env.s("BMX_JITTER_ALL") != "": game.jitter_report()
	if Env.s("BMX_BANK_PROBE") != "":
		for k in game._base_bins:
			var acc: Array = game._base_bins[k]
			print("BASEBIN lean %.2f-%.2f rad: base below ground %.3f m avg, load %.2f g, %d frames" % [k * 0.25, k * 0.25 + 0.25, -acc[0] / acc[1], acc[2] / acc[1], acc[1]])
	if rec != null:
		rec.set_recording_active(false)
		rec.get_recording().save_to_wav(Env.s("BMX_REC"))
	var shot := Env.s("BMX_SHOT")
	if shot != "":
		get_viewport().get_texture().get_image().save_png(shot)
	GameState.quit()

## BMX_TAPE test (=dir/prefix, BMX_TAPE_SPEED m/s, default 7; BMX_TAPE_STOP=secs brakes after the hit):
## at 2 s the bike is put 6 m from the middle of the nearest tape span, square on; prints TAPE lines
## (state, strain, strips) and saves a shot every 0.2 s for 2.4 s
var _tape := {}
func _tape_test(el: float) -> void:
	var ph = game.phys
	var ts: TapeSim = game.terrain._tapes
	if _tape.is_empty() and el > 2.0:
		var best = null
		var bd := INF
		for key in game.terrain._col_grid:
			for c in game.terrain._col_grid[key]:
				if c.has("tape") and not c["tape"]["broken"] and (c["tape"]["len"] as float) > 5.0:
					var d := Vector2(c.x - ph.x, c.z - ph.z).length()
					if d < bd: bd = d; best = c["tape"]
		if best == null: return
		var pts: PackedVector3Array = best["pts"]
		var mid := pts[pts.size() / 2]
		var along := Vector2(pts[pts.size() - 1].x - pts[0].x, pts[pts.size() - 1].z - pts[0].z).normalized()
		var rd := Vector2(-along.y, along.x)
		var spd := float(Env.s("BMX_TAPE_SPEED")) if Env.s("BMX_TAPE_SPEED") != "" else 7.0
		var off := float(Env.s("BMX_TAPE_OFF")) if Env.s("BMX_TAPE_OFF") != "" else 0.0   # aim this far along the span
		var start := Vector2(mid.x, mid.z) + along * off - rd * 6.0
		ph.reset_at(start.x, start.y, atan2(-rd.y, rd.x))
		ph.v = spd
		_tape = {"sp": best, "t": el, "shot": 0, "next": el}
		print("TAPE test: span len=%.1f m at (%.1f, %.1f) speed=%.1f" % [best["len"], mid.x, mid.z, spd])
	elif not _tape.is_empty():
		# BMX_TAPE_FRAMES=n: from the hit, time at 0.15x and a shot every drawn frame (n of them: the tear up close)
		if Env.s("BMX_TAPE_FRAMES") != "" and _tape.sp.broken and Env.s("BMX_TAPE").contains("/"):
			var fi: int = _tape.get("fi", 0)
			if fi == 0: Engine.time_scale = 0.15
			if fi < int(Env.s("BMX_TAPE_FRAMES")):
				var im := get_viewport().get_texture().get_image()   # kept in memory: a png per frame drops it to ~4 fps
				im.resize(im.get_width() / 2, im.get_height() / 2, Image.INTERPOLATE_BILINEAR)
				var keep: Array = _tape.get("ims", [])
				var nst := 0
				for s in ts.strips: if s.get("state", "free") == "stretch": nst += 1
				keep.append([im, "%d strips=%d held=%d" % [fi, ts.strips.size(), nst]])
				_tape.ims = keep
			elif fi == int(Env.s("BMX_TAPE_FRAMES")):
				Engine.time_scale = 1.0
				var k := 0
				for e in _tape.get("ims", []):
					(e[0] as Image).save_png(Env.s("BMX_TAPE") + "_f%03d.png" % k)
					print("TAPEFRAME " + e[1])
					k += 1
			_tape.fi = fi + 1
		if Env.s("BMX_TAPE_STOP") != "" and el > _tape.t + float(Env.s("BMX_TAPE_STOP")):
			Input.action_press("brake"); Input.action_release("pedal")
		if el >= _tape.next and _tape.shot < 120:
			_tape.next = el + 0.05
			var st := "-"; var strain := 0.0
			for s in ts.strips:
				if s.has("state") and is_same(s["sp"], _tape.sp): st = s["state"]; strain = s.get("strain", 0.0)
			print("TAPE t=%.2f v=%.1f broken=%s state=%s strain=%.3f strips=%d" % [el - _tape.t, ph.v, _tape.sp.broken, st, strain, ts.strips.size()])
			if Env.s("BMX_TAPE").contains("/") and (_tape.shot in [16, 18, 20, 22, 26, 34] or st == "stretch"):
				get_viewport().get_texture().get_image().save_png(Env.s("BMX_TAPE") + "_%02d.png" % _tape.shot)
			_tape.shot += 1


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
				if c.has("fence") and not c["fence"]["broken"] and (Env.s("BMX_FENCE_STYLE") == "" or c["fence"]["style"] == Env.s("BMX_FENCE_STYLE")):
					var d := Vector2(c.x - ph.x, c.z - ph.z).length()
					if d < bd: bd = d; best = c
		if best == null: return
		var p: Dictionary = best["fence"]
		var dir := Vector2(p.cx - best.x, p.cz - best.z)
		# the panel's own direction: from its first collider to its centre; ride across it
		var along := Vector2(p.cx, p.cz) - Vector2(best.x, best.z)
		var nrm := Vector2(-along.y, along.x).normalized() if along.length() > 0.1 else Vector2(1, 0)
		# BMX_FENCE_SPEED (m/s, default 7) / BMX_FENCE_ANGLE (degrees off square-on, default 0)
		var ang := deg_to_rad(float(Env.s("BMX_FENCE_ANGLE"))) if Env.s("BMX_FENCE_ANGLE") != "" else 0.0
		var rd := nrm.rotated(ang)
		var spd := float(Env.s("BMX_FENCE_SPEED")) if Env.s("BMX_FENCE_SPEED") != "" else 7.0
		var start := Vector2(p.cx, p.cz) - rd * maxf(6.0, spd * 0.8)
		ph.reset_at(start.x, start.y, atan2(-rd.y, rd.x))
		ph.v = spd
		_fence = {"panel": p, "t": el, "shot": 0}
		print("FENCE test: panel at (%.1f, %.1f) style=%s parts=%d" % [p.cx, p.cz, p.style, p.parts.size()])
	elif not _fence.is_empty():
		var p: Dictionary = _fence.panel
		var pre := Env.s("BMX_FENCE")
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
		var dist := float(Env.s("BMX_CACTUS_DIST")) if Env.s("BMX_CACTUS_DIST") != "" else 7.0
		for k in CactusGeo.KINDS:
			var side := float(Env.s("BMX_CACTUS_SIDE")) if Env.s("BMX_CACTUS_SIDE") != "" else 0.0
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
	if not _cacti.is_empty() and Env.s("BMX_CACTUS_SMASH") != "" and el > float(Env.s("BMX_CACTUS_SMASH")) and _cacti[0]["mi"].visible:
		var t0 := Time.get_ticks_usec()
		for c in _cacti:
			c["mi"].visible = false
			var o: Vector3 = c["rec"]["xform"].origin
			tr._debris.smash_cactus(c["rec"], c["rt"] * 7.0, o + Vector3(0, 0.45, 0) - c["rt"] * 0.25)
		print("CACTUS smashed %d in %.1f ms, debris moving=%d" % [_cacti.size(), (Time.get_ticks_usec() - t0) / 1000.0, tr._debris._items.size()])


## BMX_FENCE_ALL=1: at 2 s smash every fence panel within 70 m (random 4-18 m/s), at 9 s report where every
## piece is: buried under the drawn ground, far away, invisible, gone
var _fall := {}
func _fence_all(el: float) -> void:
	var tr = game.terrain
	var ph = game.phys
	if _fall.is_empty() and el > 2.0:
		var n := 0
		var seen := {}
		for k in tr._col_grid:
			for c in tr._col_grid[k]:
				if not c.has("fence") or c["fence"]["broken"] or seen.has(c["fence"]): continue
				if Vector2(c.x - ph.x, c.z - ph.z).length() > 70.0: continue
				seen[c["fence"]] = true
				var a := randf() * TAU
				var sp := 4.0 + randf() * 14.0
				if tr.break_collider(c, Vector3(cos(a) * sp, 0, sin(a) * sp)): n += 1
		_fall = {"t": el, "n": n, "pieces": tr._debris._items.size()}
		print("FENCEALL smashed panels=%d pieces=%d" % [n, _fall.pieces])
		# the parts left standing must stay drawn: a hidden instance may not stretch its MultiMesh's box
		# (the draw distance is measured to the box's middle)
		var stretched := 0
		for ck in tr.chunks:
			var mms: Dictionary = tr.chunks[ck].get("mms", {})
			for kind in ["post", "rail", "picket", "stake", "cactus0", "cactus1", "cactus2", "cactus3", "cactus4"]:
				if not mms.has(kind): continue
				var ab: AABB = (mms[kind] as MultiMesh).get_aabb()
				var off := Vector2(ab.get_center().x - ck.x * tr.SIZE, ab.get_center().z - ck.y * tr.SIZE).length()
				if maxf(ab.size.x, ab.size.z) > 62.0:
					stretched += 1
					print("FENCEALL stretched %s chunk=%s size=%s centre_off=%.0f m" % [kind, str(ck), str(ab.size), off])
		print("FENCEALL stretched boxes=%d" % stretched)
	elif not _fall.is_empty() and not _fall.has("done") and el > _fall.t + 7.0:
		_fall.done = true
		var d = tr._debris
		var bad_under := 0; var bad_far := 0; var bad_vis := 0; var gone := 0
		for w in d._wrecks:
			var mi = w["node"]
			if not is_instance_valid(mi): gone += 1; continue
			if not mi.is_visible_in_tree(): bad_vis += 1
			var ab: AABB = mi.global_transform * mi.get_aabb()
			var top := ab.position.y + ab.size.y
			var c := ab.get_center()
			if top < tr.top_height(c.x, c.z) + 0.01: bad_under += 1; print("FENCEALL under at %s top=%.2f ground=%.2f" % [str(c), top, tr.top_height(c.x, c.z)])
		print("FENCEALL after 7 s: moving=%d lying=%d (of %d) buried=%d invisible=%d freed=%d" % [d._items.size(), d._wrecks.size(), _fall.pieces, bad_under, bad_vis, gone])


## --shot=<png path>@<seconds>: save a screenshot after that long, then quit (testing / store shots)
func _shot(arg: String) -> void:
	var path := arg.get_slice("@", 0)
	var secs := float(arg.get_slice("@", 1)) if "@" in arg else 4.0
	await get_tree().create_timer(secs, true, false, true).timeout
	if Env.s("BMX_SHOT_NOUI") != "":   # store / splash shots: the view without the menu card
		ui.visible = false
		await get_tree().process_frame
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(path)
	print("SHOT ", path)
	GameState.quit()


## --bench=<dir>: fixed world (BMX_SEED, default 7), scripted ride through three cameras; prints frame
## time (avg / 1% low), GPU time, triangles and draw calls per camera and saves a screenshot of each.
## Combine with --quality=0..3. Vsync off, no frame cap.
func _bench(dir: String) -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	GameState.seed = int(Env.s("BMX_SEED")) if Env.s("BMX_SEED") != "" else 7
	await _new_game()
	_start_ride()
	game.hud.visible = false
	var vp := get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(vp, true)
	for i in 90: await get_tree().process_frame   # let the world stream in, shaders compile
	var q: int = Settings.get_v("quality")
	var line := "BENCH quality=%s" % Settings.QUALITY_NAMES[q]
	for cam in ["trail", "chase", "drone"]:
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
	GameState.quit()


## --hitch=<secs>: scripted ride (chase camera, vsync off) that looks for frame-time spikes and what
## the main thread was doing in them: terrain streaming (chunks turned into nodes, split into ground /
## occluder / collider / decorations / grids), physics, the rest. Prints one summary.
func _hitch(secs: float) -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	GameState.seed = int(Env.s("BMX_SEED")) if Env.s("BMX_SEED") != "" else 7
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
	var ph := PackedFloat32Array()     # TIME_PHYSICS_PROCESS: the slowest single tick of the last second, not an average
	var parts := PackedFloat64Array([0, 0, 0, 0, 0])
	var fin_ms := PackedFloat32Array()
	var t0 := Time.get_ticks_msec()
	var last := Time.get_ticks_usec()
	var p0 := Vector2(game.phys.x, game.phys.z)
	var dist := 0.0
	var csv := FileAccess.open(Env.s("BMX_HITCH_CSV"), FileAccess.WRITE) if Env.s("BMX_HITCH_CSV") != "" else null
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
	print("HITCH GPU: normal frames %.2f ms, frame after a finalize %.2f ms | worst physics tick per second (avg) %.2f ms" % [
		gpu_norm / maxi(n_norm, 1), gpu_after / maxi(n_after, 1), Array(ph).reduce(func(a, b): return a + b, 0.0) / n])
	GameState.quit()


## --showcase=<dir>: screenshots of each effect forced on (mud, wet, dust cloud, speed blur, photo DoF)
func _showcase(dir: String) -> void:
	GameState.seed = int(Env.s("BMX_SEED")) if Env.s("BMX_SEED") != "" else 7
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
	game.cam.set_mode("drone")
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
	game.cam.set_mode("side")
	await ride.call(1.5)
	game.toggle_photo()
	for i in 20: await get_tree().process_frame
	await shot.call("photo")
	game.toggle_photo()
	GameState.quit()
