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
	if _cmdline_level() and (Dev.on or _cmdline_level() != "playground"): GameState.level = _cmdline_level()   # (--level=playground, or a level from the editor's level builder)
	if "--garage" not in OS.get_cmdline_user_args() and "--rider" not in OS.get_cmdline_user_args() and "--shop" not in OS.get_cmdline_user_args():   # straight to the garage: don't build the world first
		var plain := true   # only a plain launch (or a title screenshot) gets the title backdrop; tests ride the real world
		for a in OS.get_cmdline_user_args():
			if not a.begins_with("--shot="): plain = false
		var tt0 := Time.get_ticks_usec()
		_new_game(plain)
		var tt1 := Time.get_ticks_usec()
		_show_menu()
		if Env.s("BMX_TITLE_PROBE") != "":   # tests: what the title backdrop costs to build, and its frame time
			print("TITLEPROBE build game=%.0f ms menu=%.0f ms" % [(tt1 - tt0) / 1000.0, (Time.get_ticks_usec() - tt1) / 1000.0])
			(func() -> void:
				for i in 120: await get_tree().process_frame   # (settled)
				var w := 0.0; var s := 0.0; var last := Time.get_ticks_usec()
				for i in 300:
					await get_tree().process_frame
					var now := Time.get_ticks_usec(); var d := (now - last) / 1000.0; last = now
					w = maxf(w, d); s += d
				print("TITLEPROBE frames avg=%.2f ms worst=%.1f ms  draws=%d prims=%d  static_mem=%.0f MB vram=%.0f MB" % [s / 300.0, w,
					RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
					RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME),
					OS.get_static_memory_usage() / 1048576.0,
					RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_VIDEO_MEM_USED) / 1048576.0])
				if Env.s("BMX_TITLE_PROBE_SHOT") != "": get_viewport().get_texture().get_image().save_png(Env.s("BMX_TITLE_PROBE_SHOT"))
				GameState.quit()).call()
	create_tween().set_ignore_time_scale().tween_property(fade, "modulate:a", 0.0, 0.8)
	if Env.s("BMX_PAUSE_PROBE") != "":   # tests: Esc every 4 s from 6 s, resume after 2.5 s, 4 times; plus riding frame times
		for i in 4:
			get_tree().create_timer(6.0 + i * 4.0, true, false, true).timeout.connect(func() -> void:
				var worst := 0.0; var sum := 0.0; var last := Time.get_ticks_usec()
				for f in 30:
					await get_tree().process_frame
					var now := Time.get_ticks_usec(); var d := (now - last) / 1000.0; last = now
					worst = maxf(worst, d); sum += d
				print("PAUSEPROBE riding 30 frames worst=%.1f avg=%.1f ms" % [worst, sum / 30.0])
				_pause()
				await get_tree().create_timer(2.5, true, false, true).timeout
				_resume())
	# tests: from the title (launch with only --shot=...@999): RIDE at a, pause > Main menu at b, RIDE again at c, quit at d
	# (BMX_MENU_LOOP=a,b,c,d), each timed: MENULOOP lines. With --ride only b (BMX_MENU_AT) works: Main menu from a ride
	var loop := Env.s("BMX_MENU_LOOP").split_floats(",") if Env.s("BMX_MENU_LOOP") != "" else PackedFloat64Array()
	if Env.s("BMX_MENU_AT") != "": loop = PackedFloat64Array([-1.0, float(Env.s("BMX_MENU_AT")), -1.0, -1.0])
	var steps := [["ride", _start_ride], ["menu", _menu_from_ride], ["ride_again", _start_ride], ["quit", func(): GameState.quit()]]
	for i in mini(loop.size(), 4):
		if loop[i] < 0.0: continue
		var st: Array = steps[i]
		get_tree().create_timer(loop[i], true, false, true).timeout.connect(func() -> void:
			var t0 := Time.get_ticks_usec()
			if st[0] == "ride" or st[0] == "ride_again": _prebuilt_taken = false
			await st[1].call()
			print("MENULOOP %s ms=%.0f title=%s parked_title=%s parked_ride=%s reused=%s at=%s" % [st[0], (Time.get_ticks_usec() - t0) / 1000.0,
				game.title_world if game else "-", is_instance_valid(title_parked), is_instance_valid(ride_ready), _prebuilt_taken,
				str(Vector2(game.phys.x, game.phys.z)) if game else "-"])
			var f0 := Engine.get_frames_drawn()
			var w0 := Time.get_ticks_msec()
			await get_tree().create_timer(3.0, true, false, true).timeout
			print("MENULOOP   frames drawn after: %d in %d ms" % [Engine.get_frames_drawn() - f0, Time.get_ticks_msec() - w0])
			if Env.s("BMX_MENU_LOOP_SHOT") != "": get_viewport().get_texture().get_image().save_png("%s_%s.png" % [Env.s("BMX_MENU_LOOP_SHOT"), st[0]]))
	# boot intro (the CRT TV): a plain launch only, or BMX_INTRO=1
	if (OS.get_cmdline_user_args().is_empty() or Env.raw("BMX_INTRO") != "") and CrtTv.assets_ok():   # (no TV files: no intro, straight to the menu)
		var intro := CrtIntro.new()
		intro.hold = true
		intro.still = (not Settings.get_v("boot_intro") and Env.raw("BMX_INTRO") != "1") or Env.raw("BMX_INTRO") == "still"
		add_child(intro)
		_prebuild_behind(intro)
		intro.finished.connect(func() -> void:
			var tw := create_tween().set_ignore_time_scale()
			tw.tween_property(intro.root, "modulate:a", 0.0, 0.5 if intro.skipped() else 4.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)   # the menu fades in slowly
			tw.tween_callback(intro.queue_free)
			if Env.raw("BMX_INTRO_SHOTS") != "":   # tests: a frame of the menu after it, then quit
				await get_tree().create_timer(2.5, true, false, true).timeout
				get_viewport().get_texture().get_image().save_png(Env.raw("BMX_INTRO_SHOTS") + "_menu.png")
				if Env.raw("BMX_INTRO_RIDE") != "":   # ... then RIDE: the pre-built world goes straight in
					var r0 := Time.get_ticks_msec()
					await _start_ride()
					print("INTRO ride start ms=", Time.get_ticks_msec() - r0, " prebuilt_used=", _prebuilt_taken)
					await get_tree().create_timer(4.0, true, false, true).timeout
					get_viewport().get_texture().get_image().save_png(Env.raw("BMX_INTRO_SHOTS") + "_ride.png")
				GameState.quit())
	# command-line: --ride skips the title screen; --autotest=N rides N seconds unattended then quits
	for a in OS.get_cmdline_user_args():
		if a == "--ride" or a.begins_with("--level="): _start_ride()
		elif a == "--demo": _start_demo()
		elif a == "--garage": _open_garage()
		elif a == "--rider": _open_garage("rider")
		elif a == "--anim" and Dev.on: _open_anim_studio()
		elif a == "--shop": _open_garage("shop")
		else: _dev_cmd(a)   # test / bench switches (dev/main_dev.gd; none in a release build)
	_dev_ready()



## dev builds: main's scene is res://dev/main_dev.tscn (project setting run/main_scene.editor / .dev), whose script
## extends this one with the test harness (autotest, bench, showcase, hitch hunt, pad sequences, shots) and
## overrides these two. A release export runs this script alone: no test code.
func _dev_cmd(_a: String) -> void: pass
func _dev_ready() -> void: pass

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
	if title and _unpark_title():   # the title backdrop parked while riding: back in at once, nothing rebuilt
		_rebuilding = false
		return
	if not title and game and game.title_world and _park_title(game):   # leaving the title for a ride: kept for the way back
		game = null
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

## The title backdrop Game, parked whole (out of view, not processing, its sound paused) while a ride is on, and the
## ride parked the same way while the menu is up (as ride_ready, which RIDE takes back). Main menu from a ride used to
## move the rider to TITLE_SPOT on the ride's own world and build every chunk there in one frame: 0.7-2 s the further
## you had ridden. Swapping the parked worlds is a few ms. Costs: the memory of the other world while it waits.
var title_parked: Game
var _title_park: SubViewport

func _park_title(g: Game) -> bool:
	if Env.s("BMX_NO_TITLE_PARK") != "": return false   # tests: the old way (the title world freed, rebuilt on the way back)
	if is_instance_valid(title_parked): return false
	g.exit_photo()
	_title_park = SubViewport.new()
	_title_park.own_world_3d = true
	_title_park.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_title_park.size = Vector2i(get_viewport().get_visible_rect().size)
	add_child(_title_park)
	g.process_mode = Node.PROCESS_MODE_DISABLED   # (players in it pause with it)
	g.reparent(_title_park, false)
	title_parked = g
	return true

func _unpark_title() -> bool:
	if not is_instance_valid(title_parked): return false
	var t := title_parked
	title_parked = null
	if game and game != t:
		if game.level == "" and _park_ride(game): pass   # the ride waits for RIDE (ride_ready / _take_prebuilt)
		else: game.queue_free()
	t.reparent(self, false)
	move_child(t, 0)
	t.process_mode = Node.PROCESS_MODE_PAUSABLE
	t.cam.current = true
	game = t
	if is_instance_valid(_title_park): _title_park.queue_free()
	_title_park = null
	return true

## the ride behind the menu, parked like the intro's pre-built one: RIDE moves it back in if nothing it was built from changed
func _park_ride(g: Game) -> bool:
	g.exit_photo()
	if is_instance_valid(ride_ready) and ride_ready != g: ride_ready.queue_free()   # (an unused intro one)
	if not is_instance_valid(_ride_park):
		_ride_park = SubViewport.new()
		_ride_park.own_world_3d = true
		_ride_park.render_target_update_mode = SubViewport.UPDATE_DISABLED
		_ride_park.size = Vector2i(get_viewport().get_visible_rect().size)
		add_child(_ride_park)
	g.process_mode = Node.PROCESS_MODE_DISABLED
	g.reparent(_ride_park, false)
	ride_ready = g
	_ride_sig = _ride_sig_now()
	return true

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
		_leaflet_warm.call_deferred()

# ---------------------------------------------------------------- the ride, built during the boot intro
var ride_ready: Game            # the player's own world, built off-screen while the intro holds on black
var _ride_park: SubViewport     # its own World3D, never drawn
var _prebuilt_taken := false     # tests: RIDE used the pre-built world
var _ride_sig := ""             # what it was built from (seed, bike, garage build, rider): stale if that changed

func _ride_sig_now() -> String:
	var cfg: Dictionary = GameState.bike_config()
	return JSON.stringify([GameState.seed, RouteStyle.sig(), GameState.bike_id, cfg, RiderPanels.load_look(),
		RiderPanels.load_pose(GameState.bike_id, cfg.get("pose", {}))])

## while the intro shows black (only the TV's standby LED), build the ride world (the main-thread hitch is hidden
## there), then let the intro play. RIDE then just moves it in (_take_prebuilt).
func _prebuild_behind(intro: CrtIntro) -> void:
	for i in 3: await get_tree().process_frame   # the black frame is up first
	if Env.raw("BMX_NO_PREBUILD") != "":   # tests: the old way (RIDE builds the world)
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
	if game and not (game.title_world and _park_title(game)): game.queue_free()   # (the title backdrop waits for Main menu)
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
	# (no logo on the title menu any more: just the lines)
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
	# PROFILE: the rider's avatar just left of the gear: the profile page (stats, rider look, achievements)
	menu_profile = UITheme.make_button("", _open_profile, "secondary", Tokens.T_LG)
	menu_profile.tooltip_text = "Rider profile"
	menu_profile.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	menu_profile.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	menu_profile.offset_right = menu_settings.offset_left - Tokens.S3; menu_profile.offset_top = MENU_EDGE
	menu_profile.offset_left = menu_profile.offset_right - bh; menu_profile.offset_bottom = MENU_EDGE + bh
	var avatar := ProfileIcon.new()
	avatar.set_anchors_preset(Control.PRESET_FULL_RECT)
	avatar.offset_left = Tokens.S2; avatar.offset_top = Tokens.S2; avatar.offset_right = -Tokens.S2; avatar.offset_bottom = -Tokens.S2
	menu_profile.add_child(avatar)
	menu_avatar = avatar
	menu.add_child(menu_profile)
	# WALLET: the balance as a chip left of the avatar (opens the profile too)
	menu_wallet = UITheme.make_button("", _open_profile, "secondary", Tokens.T_LG)
	menu_wallet.tooltip_text = "Wallet"
	menu_wallet.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	menu_wallet.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	menu_wallet.offset_right = menu_profile.offset_left - Tokens.S3; menu_wallet.offset_top = MENU_EDGE
	menu_wallet.offset_left = menu_wallet.offset_right - 150; menu_wallet.offset_bottom = MENU_EDGE + bh
	menu_wallet_l = UITheme.display("", Tokens.T_XL, Tokens.INK, Tokens.SLANT)
	menu_wallet_l.set_anchors_preset(Control.PRESET_FULL_RECT)
	menu_wallet_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	menu_wallet_l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	menu_wallet_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	menu_wallet.add_child(menu_wallet_l)
	menu.add_child(menu_wallet)
	_update_profile_hud()
	# version: small, bottom right of the screen, just left of the fullscreen button and centred on it
	menu_version = UITheme.text("© 2026 Luka Grcar. All rights reserved.  ·  v%s  ·  Godot %s" % [ProjectSettings.get_setting("application/config/version", "1.0.0"), Engine.get_version_info().string], Color(1, 1, 1, 0.8), Tokens.T_XS)
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
	if Env.s("BMX_MENU_PAGE") == "profile": _open_profile.call_deferred()   # tests: the rider profile
	if Env.s("BMX_MENU_PAGE") == "credits": _show_credits()   # tests: the credits window
	if Env.s("BMX_MENU_PAGE") == "levels": _menu_page_levels()   # tests: the LEVELS page
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
var menu_profile: Button
var menu_avatar: ProfileIcon
var menu_wallet: Button
var menu_wallet_l: Label
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

## the rider profile over the title menu (ui/profile_page.gd): a Strava-style overview, CUSTOMIZE RIDER, achievements
## the balance chip and the claim dot on the avatar
func _update_profile_hud() -> void:
	Steam._check_records()
	if is_instance_valid(menu_wallet_l): menu_wallet_l.text = Shop.fmt(GameState.money)
	if is_instance_valid(menu_avatar):
		menu_avatar.badge = Goals.claimable() > 0
		menu_avatar.queue_redraw()

func _open_profile() -> void:
	if not is_instance_valid(menu) or menu.has_node("ProfilePage"): return
	var pg := ProfilePage.new()
	pg.name = "ProfilePage"
	pg.on_customize = func(where := "rider"):
		pg.queue_free()
		_open_garage(where)
	pg.tree_exited.connect(_update_profile_hud)
	menu.add_child(pg)

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
	if Env.s("BMX_LEVEL") == "" and not _cmdline_level().ends_with(".tscn"): GameState.level = ""   # back on the title: RIDE / the garage ride the real world
	# LEVELS: test levels (DEMO is off the title menu: the in-game panel switches the AI rider on; _start_demo is kept)
	if Dev.on or not LevelPublish.list().is_empty(): vb.add_child(_menu_button("LEVELS", "", _menu_page_levels, false, true))
	vb.add_child(_menu_button("REPLAYS", "", _menu_page_replays, false, true))
	vb.add_child(_menu_button("SHOP", "", _open_garage.bind("shop"), false, true))
	vb.add_child(_menu_button("GARAGE", "", _open_garage, false, true))
	vb.add_child(UITheme.spacer(Tokens.S2))
	var cred := UITheme.make_button("CREDITS", _show_credits, "link", Tokens.T_XL)
	cred.alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(cred)
	fill.call()
	if is_instance_valid(menu_quit): menu_quit.visible = true
	if is_instance_valid(menu_settings): menu_settings.visible = true
	if is_instance_valid(menu_profile): menu_profile.visible = true
	if is_instance_valid(menu_wallet): menu_wallet.visible = true
	_update_profile_hud()
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
	if Dev.on: vb.add_child(pg)   # (a developer tool: not in release builds)
	else: pg.queue_free()
	# levels built in the editor and published (levels/levels.cfg, LevelPublish): a card each with its map, stars,
	# length / drop, medal times and the player's best (with this bike) + the medal it earned
	var pub := LevelPublish.list()
	var lv := VBoxContainer.new()   # (a scrolling list: any number of levels fits the column)
	lv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lv.add_theme_constant_override("separation", 6)
	if not pub.is_empty():
		var sc := ScrollContainer.new()
		sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		sc.custom_minimum_size.y = minf(pub.size() * 106.0, 300.0)
		sc.add_child(lv)
		vb.add_child(sc)
	for e in pub:
		var med: Array = e.get("medals", [0.0, 0.0, 0.0])
		var d := int(e.get("difficulty", 1))
		var best := LevelRace.best_time(e.path, str(GameState.bike_id))
		var won := LevelRace.medal_for(best, med) if best < INF else ""
		var lp: String = e.path
		var b := _menu_button("", "", func():
			GameState.level = lp
			_start_ride(), false, false)
		b.custom_minimum_size.y = 100.0
		var row := HBoxContainer.new()
		row.set_anchors_preset(Control.PRESET_FULL_RECT)
		row.offset_left = 12; row.offset_right = -12; row.offset_top = 10; row.offset_bottom = -10
		row.add_theme_constant_override("separation", 14)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(row)
		var tex := _level_picture(str(e.get("picture", "")))
		if tex:
			var tr := TextureRect.new()
			tr.texture = tex
			tr.custom_minimum_size = Vector2(108, 0)
			tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
			tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
			row.add_child(tr)
		var col := VBoxContainer.new()
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.alignment = BoxContainer.ALIGNMENT_CENTER
		col.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(col)
		var t1 := Label.new()
		t1.text = str(e.get("title", lp.get_file())).to_upper()
		t1.add_theme_font_override("font", UITheme.display_font(700, false))
		t1.add_theme_font_size_override("font_size", 26)
		t1.clip_text = true
		t1.add_theme_color_override("font_color", Tokens.INK)
		col.add_child(t1)
		var t2 := Label.new()
		t2.text = "%s  %.0f m · %.0f m ↓ · %d jumps" % ["★".repeat(d) + "☆".repeat(5 - d), float(e.get("length", 0)), float(e.get("drop", 0)), int(e.get("jumps", 0))]
		t2.add_theme_font_size_override("font_size", 13)
		t2.clip_text = true
		t2.add_theme_color_override("font_color", Tokens.INK_SOFT)
		col.add_child(t2)
		var t3 := Label.new()
		var best_s := ((LevelRace._fmt(best) + ("  " + won.to_upper() if won != "" else "")) if best < INF else "--")
		t3.text = "G %s · S %s · B %s" % [_short_t(float(med[0])), _short_t(float(med[1])), _short_t(float(med[2]))]
		t3.add_theme_font_size_override("font_size", 12)
		t3.clip_text = true
		t3.add_theme_color_override("font_color", {"gold": Color(0.75, 0.55, 0.0), "silver": Color(0.45, 0.47, 0.52), "bronze": Color(0.62, 0.38, 0.18)}.get(won, Color(0.35, 0.37, 0.4)))
		col.add_child(t3)
		var t4 := Label.new()
		t4.text = "YOUR BEST  " + best_s
		t4.add_theme_font_size_override("font_size", 12)
		t4.add_theme_color_override("font_color", Tokens.INK if best < INF else Tokens.INK_SOFT)
		t4.clip_text = true
		col.add_child(t4)
		col.add_theme_constant_override("separation", 0)
		for c in [t1, t2, t3, t4]: c.mouse_filter = Control.MOUSE_FILTER_IGNORE
		lv.add_child(b)
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
const SETUP_STEPS := ["BIKE", "TUNE", "CHARACTER", "COMPUTER", "ROUTE", "RACE"]
var route_view: RoutePreview   # the ROUTE step's top-down trail map
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
	if is_instance_valid(menu_profile): menu_profile.visible = false
	if is_instance_valid(menu_wallet): menu_wallet.visible = false
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
	var title: String = ["CHOOSE YOUR BIKE", "COLOURS & WHEELS", "YOUR CHARACTER", "BIKE COMPUTER", "PLAN YOUR ROUTE", "READY TO RACE"][setup_step]
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
		var route := setup_step == SETUP_STEPS.size() - 2
		if route:   # ROUTE: the trail this seed + style lays out, from straight above (RoutePreview), live
			if not is_instance_valid(keep_view): keep_view = hero_view if is_instance_valid(hero_view) else null
			route_view = RoutePreview.new()
			route_view.set_anchors_preset(Control.PRESET_FULL_RECT)
			left.add_child(route_view)
		elif race:   # RACE: a little trail seen from riding height, lit by the picked time, through the picked lens (LensScene)
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

		if route:
			hero_name.text = ""
			hero_spec.text = ""
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
		4: _setup_route(content)
		5: _setup_race(content)
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

## step 4: the ROUTE. The map on the left is the trail of this seed + style, built live as the sliders move
func _setup_route(content: HBoxContainer) -> void:
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", Tokens.S2)
	content.add_child(col)
	var rv := route_view
	# the world seed
	col.add_child(UITheme.caption("WORLD SEED"))
	var seed_row := HBoxContainer.new()
	seed_row.add_theme_constant_override("separation", Tokens.S2)
	var se := LineEdit.new()
	se.text = str(GameState.seed)
	se.alignment = HORIZONTAL_ALIGNMENT_CENTER
	se.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	se.custom_minimum_size.y = Tokens.H_CHIP
	se.tooltip_text = "World seed: type a number and press Enter"
	var ui := {}   # the course code line, filled below
	var sliders := {}
	var ask := func():
		if ui.has("code"): (ui["code"] as LineEdit).text = RouteStyle.code(GameState.seed)
		if is_instance_valid(rv): rv.request(GameState.seed, RouteStyle.snapshot())
	# a course code (or a bare seed) typed / pasted in: the same world + style
	var load_code := func(t: String) -> bool:
		var d := RouteStyle.parse(t)
		if d.is_empty(): return false
		GameState.seed = int(d["seed"])
		se.text = str(GameState.seed)
		RouteStyle.apply(d)
		for k in sliders: (sliders[k] as HSlider).set_value_no_signal(RouteStyle.get_value(k))
		var bc: Array = ui.get("biomes", [])
		for bi in bc.size(): (bc[bi] as Button).set_pressed_no_signal(roundi(RouteStyle.get_value("biome")) == bi)
		bike_dirty = true
		_seed_changed()
		ask.call()
		return true
	se.text_submitted.connect(func(t):
		if t.is_valid_int():
			GameState.seed = int(t); _seed_changed(); ask.call())
	seed_row.add_child(se)
	var nw := UITheme.make_button("NEW WORLD", func(): GameState.new_seed(); se.text = str(GameState.seed); _seed_changed(); ask.call(), "chip", Tokens.T_LG)
	seed_row.add_child(nw)
	col.add_child(seed_row)
	# the course code: this seed + style as one line to share
	var code_row := HBoxContainer.new()
	code_row.add_theme_constant_override("separation", Tokens.S2)
	var ce := LineEdit.new()
	ce.text = RouteStyle.code(GameState.seed)
	ce.alignment = HORIZONTAL_ALIGNMENT_CENTER
	ce.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ce.custom_minimum_size.y = Tokens.H_CHIP
	ce.tooltip_text = "Course code: seed + jumps + bends + rolling + steepness. Paste a friend's code and press Enter."
	ce.text_submitted.connect(func(t):
		if not load_code.call(t): ce.text = RouteStyle.code(GameState.seed))
	ui["code"] = ce
	code_row.add_child(ce)
	code_row.add_child(UITheme.make_button("COPY", func(): DisplayServer.clipboard_set(RouteStyle.code(GameState.seed)), "chip", Tokens.T_MD))
	code_row.add_child(UITheme.make_button("PASTE", func():
		if not load_code.call(DisplayServer.clipboard_get()): ce.text = RouteStyle.code(GameState.seed), "chip", Tokens.T_MD))
	col.add_child(code_row)
	# presets
	var pg := GridContainer.new()
	pg.columns = 3
	pg.add_theme_constant_override("h_separation", Tokens.S2)
	pg.add_theme_constant_override("v_separation", Tokens.S2)
	col.add_child(pg)
	for pr in RouteStyle.PRESETS:
		var vals: Dictionary = pr[1]
		var pb := UITheme.make_button(String(pr[0]), func():
			RouteStyle.apply(vals)
			for k in sliders: (sliders[k] as HSlider).set_value_no_signal(RouteStyle.get_value(k))
			bike_dirty = true
			ask.call(), "chip", Tokens.T_MD)
		pb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		pg.add_child(pb)
	# one slider per trait
	var rows := [
		["jumps", "JUMPS", "NONE", "JUMP PARK"],
		["twist", "BENDS", "FLOWING", "TWISTY"],
		["rolling", "ROLLING & DROPS", "SMOOTH", "ROLLERS"],
		["grade", "STEEPNESS", "GENTLE", "STEEP"]]
	var sgrid := GridContainer.new()   # the four sliders two by two: the page has to fit one screen
	sgrid.columns = 2
	sgrid.add_theme_constant_override("h_separation", Tokens.S5)
	sgrid.add_theme_constant_override("v_separation", Tokens.S1)
	col.add_child(sgrid)
	for rw in rows:
		var k: String = rw[0]
		var cell := VBoxContainer.new()
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cell.add_theme_constant_override("separation", 0)
		sgrid.add_child(cell)
		var head := HBoxContainer.new()
		head.add_child(UITheme.caption(String(rw[1])))
		cell.add_child(head)
		var sl := HSlider.new()
		sl.min_value = RouteStyle.LIMITS[k][0]
		sl.max_value = RouteStyle.LIMITS[k][1]
		sl.step = 0.05
		sl.scrollable = false
		sl.value = RouteStyle.get_value(k)
		sl.add_theme_stylebox_override("focus", StyleBoxEmpty.new())   # the focus wash covered the whole slider (the knob vanished)
		sl.custom_minimum_size.y = 20
		sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sl.value_changed.connect(func(v: float):
			RouteStyle.set_value(k, v, false)
			bike_dirty = true
			ask.call())
		sl.drag_ended.connect(func(_c): RouteStyle.save_file())
		sliders[k] = sl
		cell.add_child(sl)
		var ends := HBoxContainer.new()
		ends.add_child(UITheme.caption(String(rw[2]), Tokens.INK_FAINT, Tokens.T_XS))
		var fl := Control.new(); fl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		ends.add_child(fl)
		ends.add_child(UITheme.caption(String(rw[3]), Tokens.INK_FAINT, Tokens.T_XS))
		cell.add_child(ends)
	# where: the biome the ride is in
	var bm := HBoxContainer.new()
	bm.add_theme_constant_override("separation", Tokens.S2)
	var bgrp := ButtonGroup.new()
	var bchips := []
	for bi in RouteStyle.BIOMES.size():
		var bb := UITheme.make_button(String(RouteStyle.BIOMES[bi][0]).replace(" MOUNTAINS", "").replace(" HILLS", " HILLS"), Callable(), "chip", Tokens.T_XS)
		bb.toggle_mode = true; bb.button_group = bgrp
		bb.button_pressed = roundi(RouteStyle.get_value("biome")) == bi
		bb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bb.pressed.connect(func():
			RouteStyle.set_value("biome", float(bi))
			bike_dirty = true
			ask.call())
		bchips.append(bb)
		bm.add_child(bb)
	ui["biomes"] = bchips
	col.add_child(bm)
	# colouring of the map
	var cm := HBoxContainer.new()
	cm.add_theme_constant_override("separation", Tokens.S2)
	var cgrp := ButtonGroup.new()
	for c in [["type", "PAPER MAP"], ["grade", "COLOUR BY GRADE"]]:
		var cb := UITheme.make_button(String(c[1]), Callable(), "chip", Tokens.T_SM)
		cb.toggle_mode = true; cb.button_group = cgrp
		cb.button_pressed = is_instance_valid(rv) and rv.color_mode == c[0]
		cb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cb.pressed.connect(func(): if is_instance_valid(rv): rv.color_mode = c[0]; rv.queue_redraw())
		cm.add_child(cb)
	col.add_child(cm)
	# what this trail is
	var rate := UITheme.display("", Tokens.T_XL, Tokens.INK, Tokens.SLANT_TITLE)
	col.add_child(rate)
	var stats := UITheme.text("", Tokens.INK, Tokens.T_SM)
	stats.add_theme_constant_override("line_spacing", -4)
	stats.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(stats)
	var fill := Control.new(); fill.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(fill)
	if is_instance_valid(rv):
		rv.built.connect(func(st: Dictionary):
			rate.text = ["GREEN  ·  EASY", "BLUE  ·  INTERMEDIATE", "BLACK  ·  HARD", "DOUBLE BLACK  ·  EXPERT"][st.rating]
			rate.add_theme_color_override("font_color", [Color("2f9e58"), Color("2f6fd0"), Color("151a23"), Color("d22b25")][st.rating])
			stats.text = "ABOUT %d:%02d AT A GOOD RIDER'S PACE  ·  %d KM/H
%.1f KM  ·  FALLS %d M  ·  AVERAGE %.1f %%  ·  STEEPEST 100 M: %d M
%d JUMPS  ·  %d ROLLER SETS  ·  %d BRIDGES  ·  %d CLIFF DROPS
%d BENDS, %d TIGHT" % [
				int(st.time) / 60, int(st.time) % 60, roundi(st.avg_kmh), st.length / 1000.0, roundi(st.fall), st.avg, roundi(st.steepest), st.jumps, st.rollers, st.bridges, st.drops, st.bends, st.tight])
		rv.request(GameState.seed, RouteStyle.snapshot())
	menu_focus = nw

## step 5: the time of day, then RACE (the bike on the left is the one you picked)
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
	b.custom_minimum_size.y = Tokens.H_SUB + Tokens.S3   # every line the same height + type size: the focused one only turns yellow
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
	col.add_child(UITheme.display(text, Tokens.T_2XL + Tokens.S1))
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
	garage.anim_requested.connect(func(): await _close_garage(false); _open_anim_studio())
	create_tween().set_ignore_time_scale().tween_property(fade, "modulate:a", 0.0, 0.5)
	if Env.s("BMX_GARAGE_REOPEN") != "" and not _garage_reopened:   # tests: back to the menu and in again (the kept outside)
		_garage_reopened = true
		await get_tree().create_timer(float(Env.s("BMX_GARAGE_REOPEN"))).timeout
		await _close_garage(false)
		await get_tree().create_timer(1.0).timeout
		_open_garage(mode)

## the Anim Studio (--anim, Insert in the rider room): the menus' standing rider + their animation library (ui/anim_studio.gd)
var anim_studio = null   # AnimStudio (res://dev: dev builds only)

func _open_anim_studio() -> void:
	if not Dev.on: return
	if menu: menu.queue_free(); menu = null
	fade.modulate.a = 1.0
	if game:
		if game.title_world and _title_keep.is_empty(): _title_keep = game.take_world()
		game.queue_free()
		await game.tree_exited
		game = null
	anim_studio = Dev.make("anim_studio.gd")
	add_child(anim_studio)
	anim_studio.closed.connect(_close_anim_studio)
	create_tween().set_ignore_time_scale().tween_property(fade, "modulate:a", 0.0, 0.4)

func _close_anim_studio() -> void:
	fade.modulate.a = 1.0
	anim_studio.queue_free()
	await anim_studio.tree_exited
	anim_studio = null
	await _new_game(true)
	_show_menu()
	create_tween().set_ignore_time_scale().tween_property(fade, "modulate:a", 0.0, 0.5)

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
	if not Dev.on: return
	await _start_ride()
	GameState.end_ride()   # the AI's riding is no activity of the player's
	game.set_demo(true)
	if game.hud:
		Dev.script("tune/tune_card.gd").last_cat["ride"] = 8
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
		_pause_greyed.call_deferred()
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN and _grey_dim != null:
		_resume.call_deferred()   # back in the window: straight on where it was

## the controller the player was riding with went away (battery, cable): pause, so the bike doesn't carry on with no
## hands on it. Only when a pad was the active device (a keyboard rider unplugging a spare pad isn't interrupted).
func _on_pad_connection(_device: int, connected: bool) -> void:
	if connected or state != RIDING or not Settings.pad_active: return
	if Settings._test_run or not OS.get_cmdline_user_args().is_empty(): return
	if not Input.get_connected_joypads().is_empty(): return   # another pad is still there
	_pause_unfocused.call_deferred()

func _pause_unfocused() -> void:
	if state == RIDING: _pause()

## window lost focus: freeze the ride and grey the screen, no pause menu; coming back resumes (FOCUS_IN above)
var _grey_dim: ColorRect = null
func _pause_greyed() -> void:
	if state != RIDING: return
	_pause(false)
	_grey_dim = ColorRect.new()
	_grey_dim.color = Color(0.42, 0.42, 0.42, 0.62)
	_grey_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_grey_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui.add_child(_grey_dim)

## paused during the crash slow motion: the menus (leaflet, its sounds, the tuning card) run at normal speed and
## pitch; the slow motion comes back on resume
var _held_time_scale := -1.0
var _held_audio_speed := -1.0
func _pause(menu := true) -> void:
	if game: game.exit_photo()
	state = PAUSED
	if _held_time_scale < 0.0:
		_held_time_scale = Engine.time_scale
		_held_audio_speed = AudioServer.playback_speed_scale
	Engine.time_scale = 1.0
	AudioServer.playback_speed_scale = 1.0
	var pt0 := Time.get_ticks_usec()
	# the cover photo: the ride as it is now (the last frame drawn, before the leaflet is over it)
	var shot := get_viewport().get_texture().get_image()
	var pt1 := Time.get_ticks_usec()
	get_tree().paused = true
	_close_pause(true)
	if not menu: return
	# the pause menu replaces any side card (tuning, P / K / L): with it still up, its menu took the pad cursor
	# and the leaflet had no highlight. Pause > Tuning brings it back.
	_tuning_paused = false   # (else closing the card would resume the ride)
	if game and game.hud.card and game.hud.card.visible: game.hud.close_sides()
	var pm := _leaflet_get()
	pm.prepare(shot, game.terrain.biome_name(game.phys.x, game.phys.z) if game else "", GameState.seed)
	var pt2 := Time.get_ticks_usec()
	pm.add_item("Resume", _resume)
	pm.add_item("Back to start", func(): _resume(); game.respawn(false))
	if game == null or game.level == "": pm.add_item("New world", func(): _resume(); game.respawn(true))
	if Dev.on: pm.add_item("Tuning", _open_tuning)
	pm.add_item("Photo mode", func(): _resume(); game.toggle_photo())
	if game and game.replay and game.replay.ready_to_play():
		pm.add_item("Replay", func(): _resume(); game.open_replay())
	pm.add_item("Settings", _open_settings)
	pm.add_item("Main menu", _menu_from_ride)
	pm.add_item("Quit to desktop", func(): GameState.save(); GameState.quit())
	pause_menu = pm
	pm.open()
	pm.focus_first.call_deferred()
	if Env.s("BMX_PAUSE_PROBE") != "":   # tests: what opening the leaflet costs (sync parts + the frames after)
		var pt3 := Time.get_ticks_usec()
		var worst := 0.0; var sum := 0.0; var n := 0
		var last := Time.get_ticks_usec()
		while n < 60:
			await get_tree().process_frame
			var now := Time.get_ticks_usec()
			var d := (now - last) / 1000.0; last = now
			worst = maxf(worst, d); sum += d; n += 1
		print("PAUSEPROBE photo=%.1f build=%.1f items+open=%.1f ms | next 60 frames worst=%.1f avg=%.1f ms" % [(pt1 - pt0) / 1000.0, (pt2 - pt1) / 1000.0, (pt3 - pt2) / 1000.0, worst, sum / n])

## pause > Main menu: the parked title world back in (instant); without one, the menu over the ride's own world as before
func _menu_from_ride() -> void:
	_close_pause(true)
	GameState.save()
	get_tree().paused = false
	if is_instance_valid(title_parked): await _new_game(true)
	_show_menu()

## fold the leaflet away (now = gone at once: menus, a new ride). It is kept (hidden, its render targets
## stopped) for the next pause: see _leaflet_get
func _close_pause(now := false) -> void:
	if not is_instance_valid(pause_menu): pause_menu = null; return
	var pm = pause_menu
	pause_menu = null
	if is_instance_valid(pm._inside_menu): pm._inside_menu.queue_free()   # (Settings / Controls printed inside: gone with it, as when it was freed)
	if pm.state != 0: pm.close(now)

## the one pause leaflet of the session, built on first use (or by _leaflet_warm at a ride's start)
var _leaflet: PausePamphlet
func _leaflet_get() -> PausePamphlet:
	if not is_instance_valid(_leaflet):
		_leaflet = PausePamphlet.new()
		add_child(_leaflet)
		_leaflet.close_requested.connect(func():   # Esc / B: an open leaflet folds back to its cover first
			if state != PAUSED or pause_menu != _leaflet: return
			if _leaflet.is_unfolded(): _leaflet.fold_inside()
			else: _resume())
	return _leaflet

## a ride started: the leaflet built now (~95 ms, behind the ride's own start), so the first Esc only shows it.
## (Drawing its render targets once here as well was tried: frames while paused went 6 -> 14 ms. Not done.)
func _leaflet_warm() -> void:
	if is_instance_valid(_leaflet) or Env.s("BMX_NO_LEAFLET_WARM") != "": return
	_leaflet_get()

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
	if _grey_dim != null:
		if is_instance_valid(_grey_dim): _grey_dim.queue_free()
		_grey_dim = null
	if state != PAUSED: return
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


## --level=<id or res://levels/x.tscn> on the command line ("" none): kept as the level for the whole session
## (the editor's level builder starts the game this way)
func _cmdline_level() -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--level="): return a.get_slice("=", 1)
	return ""


## a published level's map picture (imported texture, else the png read straight off the disk; null = none)
func _level_picture(path: String) -> Texture2D:
	if path == "": return null
	if ResourceLoader.exists(path):
		var t = load(path)
		if t is Texture2D: return t
	var img := Image.load_from_file(ProjectSettings.globalize_path(path))
	return ImageTexture.create_from_image(img) if img else null


## a medal time, short: 33.9 / 1:17.1
static func _short_t(secs: float) -> String:
	if secs < 60.0: return "%.1f" % secs
	return "%d:%04.1f" % [int(secs / 60.0), fmod(secs, 60.0)]
