extends "res://scripts/main.gd"
## The game's root in dev builds (the editor and its test runs, the "Windows Dev" export): main.gd + the test harness.
## Picked by the project settings run/main_scene.editor / run/main_scene.dev (scene res://dev/main_dev.tscn); a
## release export runs scenes/main.tscn (main.gd alone) and has none of this file.

## command-line test switches (main._ready hands every argument it doesn't know here)
func _dev_cmd(a: String) -> void:
	if a.begins_with("--autotest"): _autotest(float(a.get_slice("=", 1)) if "=" in a else 10.0)
	elif a.begins_with("--shot="): _shot(a.get_slice("=", 1))
	elif a.begins_with("--bench="): _bench(a.get_slice("=", 1))
	elif a.begins_with("--showcase="): _showcase(a.get_slice("=", 1))
	elif a.begins_with("--hitch"): _hitch(float(a.get_slice("=", 1)) if "=" in a else 30.0)

func _dev_ready() -> void:
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
		if Env.s("BMX_POSELAB") != "" and not _probe.get("poselab", false):   # tests: the Pose Lab (opens paused: "air" = at the first flight, else after n s); BMX_POSELAB_SET="t:ch=v,ch=v;t:..." keys, BMX_POSELAB_PLAY=1
			var pw := Env.s("BMX_POSELAB")
			if (pw == "air" and game.phys.air) or (pw != "air" and el >= float(pw)):
				_probe.poselab = true
				game.toggle_pose_lab()
				game.pose_lab.test_script(Env.s("BMX_POSELAB_SET"), Env.s("BMX_POSELAB_PLAY"))
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
			elif body_t.begins_with("springback"):   # tests: held back, then let go: the stick springs past centre (+0.35, 0.07 s) like a real thumb. Must NOT pop
				var ph3 := fmod(el, 2.5)
				var over := float(body_t.trim_prefix("springback:")) if body_t.begins_with("springback:") else 0.35
				Input.action_press("body_back", 0.95 if ph3 < 0.4 else 0.0)
				if ph3 >= 0.45 and ph3 < 0.52: Input.action_press("body_fwd", over)
				else: Input.action_release("body_fwd")
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
			# (2026-11-24: the rider's body keys - the arrows, the pad's right stick - tilt / flip the bike in the air now, not W / S)
			if trick in ["back", "front", "manual"]: Input.action_release("body_back"); Input.action_release("body_fwd")
			if Env.s("BMX_BIGAIR") != "" and ph.air_time < 0.03 and ph.vy < 7.0: ph.vy = 7.0   # tests: big air for full flips
			if ph.air_time > 0.06:
				if trick == "back": Input.action_press("body_back")
				elif trick == "manual":   # lean back to this nose-up angle (BMX_MANUAL_PITCH, rad) and hold it
					var mp := float(Env.s("BMX_MANUAL_PITCH")) if Env.s("BMX_MANUAL_PITCH") != "" else 1.0
					var e: float = mp - ph.pitch - ph.pitch_v * 0.25
					if e > 0.05: Input.action_press("body_back", 0.6)
					elif e < -0.05: Input.action_press("body_fwd", 0.6)
				elif trick == "front": Input.action_press("body_fwd")
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
				# ↓ / ↑ (the body keys) pressed at the lip throw the rider into the flip
				if trick == "back": Input.action_press("body_back")
				else: Input.action_press("body_fwd")
			elif trick == "back" or trick == "front":
				Input.action_release("body_back"); Input.action_release("body_fwd")
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
		# tests: consecutive frames of a crash start (BMX_CRASH_SHOTS) / a bail-tap reset (BMX_TAP_SHOTS), at 0.15x time,
		# kept in memory and written after (a png a frame stalled ~0.1 s: the shots were far apart)
		var ss_pre := Env.s("BMX_CRASH_SHOTS") if Env.s("BMX_CRASH_SHOTS") != "" else Env.s("BMX_TAP_SHOTS")
		var ss_go: bool = (Env.s("BMX_CRASH_SHOTS") != "" and game.phys.crash_on) or (Env.s("BMX_TAP_SHOTS") != "" and _probe.has("tapped"))
		if Env.s("BMX_RESET_DUMP") != "" and _probe.has("tapped") and int(_probe.get("rd_n", 0)) < 10:   # tests: camera / helmet cam right after the tap
			_probe.rd_n = int(_probe.get("rd_n", 0)) + 1
			var rc = game.rider.action_cam
			var cm: Camera3D = get_viewport().get_camera_3d()
			print("RESETDUMP f=%d cam=%s cam_to_rider=%.2f zoom=%.3f crash=%s helmetcam=%s vis=%s body=%s rider_par=%s" % [_probe.rd_n, cm.name if cm else "-", cm.global_position.distance_to(game.rider.global_position) if cm else -1.0, game.cam.crash_zoom, game.phys.crash_on, rc != null and is_instance_valid(rc), rc.visible if rc and is_instance_valid(rc) else false, rc.get_node_or_null("Body") != null if rc and is_instance_valid(rc) else false, game.rider.get_parent().name])
		if ss_pre != "" and ss_go and not _probe.has("ss_done"):
			if not _probe.has("ss_imgs"): _probe["ss_imgs"] = []; Engine.time_scale = 0.15
			var imgs: Array = _probe["ss_imgs"]
			imgs.append(get_viewport().get_texture().get_image())
			var cm2: Camera3D = get_viewport().get_camera_3d()
			print("SSHOT %d drawn=%d cam=%s rider=%s crash=%s" % [imgs.size(), Engine.get_frames_drawn(), str(cm2.global_position.snapped(Vector3.ONE * 0.01)) if cm2 else "-", str(game.rider.global_position.snapped(Vector3.ONE * 0.01)), game.phys.crash_on])
			if imgs.size() >= 16:
				for k in imgs.size(): (imgs[k] as Image).save_png("%s_%d.png" % [ss_pre, k + 1])
				_probe["ss_done"] = true; Engine.time_scale = 1.0
		if Env.s("BMX_TAP_RESET") != "" and el > float(Env.s("BMX_TAP_RESET")) and not _probe.has("tapped"):   # tests: tap bail -> back on the trail
			_probe["tapped"] = true
			var p0 := Vector3(game.phys.x, game.phys.y, game.phys.z)
			print("TAPRESET at drawn=%d" % Engine.get_frames_drawn())
			if Env.s("BMX_TAP_INPUT") != "":   # (as a player does: a bail press + release, handled before the next frame)
				for prs in [true, false]:
					var evb := InputEventAction.new(); evb.action = "bail"; evb.pressed = prs
					Input.parse_input_event(evb)
			else: game.reset_to_trail()
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
	if game.gap_probe:
		var keys: Array = game.gap_stats.keys(); keys.sort()
		for k in keys:
			var s: Array = game.gap_stats[k]
			print("GAP %-16s frames=%5d mean=%.1fcm max=%.1fcm over1cm=%3d%% mesh-field=%+.1fcm lift=%.1fcm" % [k, s[0], s[1] / s[0] * 100, s[2] * 100, 100 * s[5] / s[0], s[3] / s[0] * 100, s[4] / s[0] * 100])
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
