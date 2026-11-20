extends CanvasLayer
## In-ride HUD: bike computer (speed / slope / grade / gear / elevation), stamina, flow,
## hop-charge and get-up bars, message flashes, the live jump card with records, FPS.
## Port of gauge.js, airhud.js and the HUD bits of index.html / main.js.

const HIST := 120
const HIST_DT := 0.25

var game
var root := Control.new()
var info_l: Label
var msg_l: MsgView
var flow_leds := FlowLeds.new()   # flow shown on the bike computer's LEDs
var biome_l: Label
var gauge: GaugeView
var stamina: StaminaView
var life_bar: StaminaView
var life := 1.0          # rider health 0..1: crashes hurt (by speed), heals slowly while riding
var hurt_t := 99.0       # seconds since the last crash
var hop_bar: BarView
var getup: GetUpPrompt
var air_card: AirCard
var records_panel: PanelContainer
var quick: Control
var fps_acc := 0.0
var fps_frames := 0
var msg_a := 0.0
const FRAME_HIST := 120          # frames kept for the SYSTEM page's frame-time graph
var frame_ms := PackedFloat32Array()
var fps_now := 0.0
var _frame_us := 0
var _sys_overlay := false        # the SYSTEM page turned the 3D physics overlay on
var _overlay_was := false        # ...and it was off before
var _demo_t := 0.0 if Env.s("BMX_FLASH") != "" else -1.0
var elev_hist := PackedFloat32Array()
var elev_t := 0.0
var elev_up := 0.0     # metres climbed / descended this ride (bike computer page 2)
var elev_down := 0.0
var track_hist := PackedVector2Array()   # ridden path (x, z) for the map page, same sampling
const TRACK := 360
# ride stats for the bike computer pages
var ride_t := 0.0
var beep                # GarminBeep: the bike computer's piezo (power-on chime, key beeps)
var _power_t := -1.0    # seconds the HUD has been showing (the computer switches on at 0.35 s)
# bike computer tones (garmin_beep.gd): what has already beeped this ride
var _gps_beeped := false
var _paused := false    # auto-pause: stood still > AUTO_PAUSE s
var _still_t := 0.0
var _lap := 0           # auto lap every LAP_M of trip distance
var _bat_warned := false
var _alert_beep_t := 0.0
var _alert_key := -99   # where on the trail the last prompted turn / feature is (12 m bins)
const AUTO_PAUSE := 2.0
const LAP_M := 1000.0
var moving_t := 0.0
var ride_dist := 0.0
var max_v := 0.0
var cad := 0.0          # rpm, from the crank
var power := 0.0        # W, from the drive force
var hr := 72.0          # bpm, made up from effort, sprint, stamina
var _crank_last := NAN
var jump_last := Vector3.ZERO   # air time, distance, height of the last landed jump
var jump_best := Vector3.ZERO
var jumps := 0
var tricks := 0
var style_pop: StylePop
var trick_last := ""
var trail_i := -1       # nearest trail centreline point
var trail_d := INF      # how far off the trail centreline (m)
var alert := {}         # the next turn / feature on the trail: {kind, text, d}, or empty
var alert_new := 0.0    # seconds left to show a just-appeared alert while it is still far off
const FEAT_NAMES := {"table": "TABLETOP", "tableLine": "JUMP LINE", "kicker": "KICKER", "rhythm": "ROLLERS",
	"flow": "FLOW LINE", "woodKicker": "WOOD KICKER", "bridge": "BRIDGE", "gorge": "GORGE BRIDGE", "rope": "ROPE BRIDGE"}
var hidden := false

func _ready() -> void:
	add_to_group("hud")
	layer = 5
	beep = preload("res://scripts/ui/garmin_beep.gd").new()
	add_child(beep)
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = UITheme.get_theme()
	add_child(root)
	# bottom right, small and right-aligned, stacked over the fullscreen button: biome / ride info
	# (FPS lives on the bike computer's SYSTEM page)
	info_l = _corner_label("", UITheme.MUTED, 52)
	msg_l = MsgView.new()   # BERM +2 km/h, BONK!, tricks...: an achievement pop in the WASTED type
	msg_l.set_anchors_preset(Control.PRESET_FULL_RECT)
	msg_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(msg_l)
	biome_l = _corner_label("", UITheme.MUTED, 68)
	gauge = GaugeView.new(); gauge.hud = self
	gauge.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	gauge.size = Vector2(150, 224); gauge.position = Vector2(20, -244)   # +12 px top bezel for the flow LEDs
	gauge.pivot_offset = Vector2(0, 224)   # smaller / larger models grow from the bottom left corner
	set_computer()
	gauge.page = clampi(int(Env.s("BMX_GARMIN_PAGE")), 0, gauge.order.size() - 1)
	root.add_child(gauge)
	stamina = StaminaView.new(); stamina.hud = self
	stamina.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	stamina.size = Vector2(220, 16); stamina.position = Vector2(-240, 36)   # top right, under the life bar
	root.add_child(stamina)
	life_bar = StaminaView.new(); life_bar.hud = self; life_bar.life = true
	life_bar.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	life_bar.size = Vector2(220, 16); life_bar.position = Vector2(-240, 14)   # top right
	root.add_child(life_bar)
	hop_bar = BarView.new()
	hop_bar.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	hop_bar.size = Vector2(180, 12); hop_bar.position = Vector2(-90, -100)
	root.add_child(hop_bar)
	getup = GetUpPrompt.new(); getup.hud = self
	getup.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	getup.size = Vector2(280, 84); getup.position = Vector2(-140, -160)   # bottom centre (the crash caption sits under it)
	getup.mouse_filter = Control.MOUSE_FILTER_IGNORE
	getup.visible = false
	root.add_child(getup)
	style_pop = StylePop.new()
	style_pop.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	style_pop.size = Vector2(420, 130); style_pop.position = Vector2(-440, 62)   # top right, under the life + stamina bars (right-aligned)
	style_pop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(style_pop)
	air_card = AirCard.new(); air_card.hud = self
	air_card.size = Vector2(260, 112); air_card.position = Vector2(20, 14)   # top left (top centre is the area banner's)
	root.add_child(air_card)
	on_respawn()
	_build_records()
	quick = load("res://scripts/ui/quick_tune.gd").new()
	quick.hud = self
	root.add_child(quick)
	gear_changed()
	apply_settings()
	root.resized.connect(_layout)
	_layout()

## a small right-aligned line in the bottom-right corner, `up` px from the bottom
func _corner_label(text: String, col: Color, up: float) -> Label:
	var l := UITheme.label(text, 11, col)
	l.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	l.size = Vector2(420, 16); l.position = Vector2(-440, -up - 16)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(l)
	return l

func _layout() -> void:
	pass

func apply_settings() -> void:
	if gauge: gauge.visible = Settings.get_v("hud_gauge")
	if gauge: gauge.show_gear = Settings.get_v("hud_gear"); gauge.queue_redraw()
	if air_card: air_card.enabled = Settings.get_v("hud_jump")
	if quick: quick.visible = Settings.get_v("hud_quick") and not _side_open()

func speed_text(ms: float) -> String:
	return "%d" % roundi(absf(ms) * (2.23694 if Settings.get_v("units") == 1 else 3.6))

func speed_unit() -> String:
	return "mph" if Settings.get_v("units") == 1 else "km/h"

func flash(text: String) -> void:
	msg_l.show_msg(text)
	msg_a = 1.4

func gear_changed(at_end: bool = false) -> void:
	if gauge: gauge.bump = 1.0; gauge.queue_redraw()
	if at_end and beep: beep.tone("gear_end")      # now in the easiest / hardest gear

## a shift asked for with no gear left that way (or a single speed): the computer says no
func gear_blocked() -> void:
	if beep: beep.tone("gear_none")

func on_takeoff() -> void:
	air_card.takeoff()

func on_landing(air_time: float, dist: float, height: float, impact: float) -> void:
	air_card.land(air_time, dist, height, impact)
	if air_time > 0.25 and not game.phys.crash_on:
		jumps += 1
		jump_last = Vector3(air_time, dist, height)
		if jumps > 2 and air_time > 0.7 and air_time > jump_best.x: beep.tone("record")   # a new best jump today
		jump_best = Vector3(maxf(jump_best.x, air_time), maxf(jump_best.y, dist), maxf(jump_best.z, height))

## style points for a landed jump (bike_physics._style_points): the popup chains them into a combo
func on_style(points: int, label: String) -> void:
	if style_pop: style_pop.add(points, label)

func on_trick(trick: String) -> void:
	tricks += 1
	trick_last = trick
	Steam.trick(trick)

## a crash hurts by how fast the body was going: a slow tip-over ~15 %, 12 m/s+ ~70 %+
const LIFE_REGEN := 0.012   # per second while riding, from LIFE_WAIT s after a crash
const LIFE_WAIT := 4.0
const REVIVE_HOLD := 1.2    # out of life: hold hop this long to revive...
const REVIVE_LIFE := 0.5    # ...and come back with this much
func on_crash(speed := 0.0) -> void:
	life = maxf(0.0, life - clampf(0.12 + speed / 12.0 * 0.6, 0.12, 0.95))
	hurt_t = 0.0
	life_bar.shake = 1.0
	if speed >= 9.0: Steam.event("WASTED")
	# knocked out: the computer's incident detection sounds its alarm (once the crash slow motion is over)
	if life <= 0.0 and is_inside_tree():
		get_tree().create_timer(2.6, true, false, true).timeout.connect(_incident_alarm)
	if Env.s("BMX_LIFE_PROBE") != "": print("LIFE crash v=%.1f life=%.2f" % [speed, life])

func _incident_alarm() -> void:
	if life <= 0.0: beep.tone("incident")

## rolled through a health pack (the backpacks beside the roadside sheds): life back, the bar glows green
func on_health_pack(amount: float) -> void:
	if life >= 1.0:
		return
	life = minf(1.0, life + amount)
	life_bar.heal = 1.0
	flash("HEALTH +%d%%" % roundi(amount * 100.0))
	Steam.event("HEALTH_PACK")
	if Env.s("BMX_LIFE_PROBE") != "": print("LIFE health pack life=%.2f" % life)

## back on the bike: at zero life that was a revive (half life back, the bar glows green)
func on_get_up() -> void:
	if life <= 0.0:
		life = REVIVE_LIFE
		hurt_t = LIFE_WAIT
		life_bar.heal = 1.0
		flash("REVIVED")
		Steam.event("REVIVE")
		if game and game.grime: game.grime.blood = 0.0   # the blood on the rider washes off with a revive
		if Env.s("BMX_LIFE_PROBE") != "": print("LIFE revived life=%.2f" % life)

## back to start / new world: full life, and the bike computer restarts (ride timer, trip, a full battery,
## the GPS fix and the power-on chime again)
func on_respawn() -> void:
	if life <= 0.0 and game and game.grime: game.grime.blood = 0.0   # dead, then restarted: a fresh rider
	life = 1.0; hurt_t = 99.0
	ride_t = 0.0; ride_dist = 0.0; moving_t = 0.0; max_v = 0.0
	if visible: _power_t = 0.0
	_gps_beeped = false; _paused = false; _still_t = 0.0; _lap = 0; _bat_warned = false
	if Env.s("BMX_LIFE") != "": life = float(Env.s("BMX_LIFE"))   # tests: start with this much life
	if style_pop: style_pop.bail()
	air_card.bail()

func _unhandled_input(e: InputEvent) -> void:
	if get_tree().paused or (game and game.photo): return   # photo mode has its own keys (and its own shot)
	if e.is_action_pressed("records") and not e.is_echo():
		_refresh_records(); records_panel.visible = not records_panel.visible
	elif e.is_action_pressed("toggle_hud") and not e.is_echo():
		hidden = not hidden; root.visible = not hidden
	elif e.is_action_pressed("tune") and not e.is_echo():
		toggle_tune()
	elif e.is_action_pressed("pose_panel") and not e.is_echo():
		_toggle_side("pose")
	elif e.is_action_pressed("look_panel") and not e.is_echo():
		_toggle_side("look")
	elif e.is_action_pressed("screenshot") and not e.is_echo():
		var dir := "user://screenshots"
		DirAccess.make_dir_recursive_absolute(dir)
		var p := "%s/bmx_%s.png" % [dir, Time.get_datetime_string_from_system().replace(":", "-")]
		get_viewport().get_texture().get_image().save_png(p)
		flash("Screenshot saved")

var card: TuneCard   # the tuning card (P Ride, K Rider, L Look): built on first use

const SIDE_TABS := {"tune": "ride", "pose": "rider", "look": "look", "ride": "ride", "rider": "rider", "sound": "sound", "light": "light", "dust": "dust"}

func toggle_tune() -> void:
	_toggle_side("tune")

func _side_open() -> bool:
	return card != null and card.visible

## the ✕ on the card
func close_sides() -> void:
	if card: card.visible = false
	quick.visible = Settings.get_v("hud_quick")

## open the card on a tab (tune / pose / look, or ride / rider / look); the same key again closes it
func _toggle_side(which: String) -> void:
	var t: String = SIDE_TABS.get(which, "ride")
	if card and card.visible and card.tab == t:
		close_sides()
		return
	if card == null:
		card = TuneCard.new(game)
		card.tab = t
		root.add_child(card)
	else:
		card.show_tab(t)
	card.visible = true
	quick.visible = false

func _build_records() -> void:
	records_panel = PanelContainer.new()
	records_panel.set_anchors_preset(Control.PRESET_CENTER)
	records_panel.custom_minimum_size = Vector2(340, 0)
	records_panel.position = Vector2(-170, -150)
	records_panel.visible = false
	var vb := VBoxContainer.new(); vb.name = "VB"
	records_panel.add_child(vb)
	root.add_child(records_panel)

func _refresh_records() -> void:
	var vb := records_panel.get_node("VB")
	for c in vb.get_children(): c.queue_free()
	var head := HBoxContainer.new()
	var title := UITheme.label("🏆  RECORDS", 22, UITheme.ACCENT, true)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	head.add_child(UITheme.close_button(func(): records_panel.visible = false))
	vb.add_child(head)
	var r: Dictionary = GameState.records
	var rows := [["Longest jump", "%.1f m" % r.longest], ["Highest jump", "%.1f m" % r.highest], ["Longest air", "%.2f s" % r.air],
		["Top speed", "%s %s" % [speed_text(r.top_speed / 3.6), speed_unit()]], ["Jumps landed", "%d" % r.jumps], ["Distance ridden", "%.1f km" % (r.distance / 1000.0)]]
	for row in rows:
		var hb := HBoxContainer.new()
		var a := UITheme.label(row[0], 16, UITheme.MUTED); a.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hb.add_child(a); hb.add_child(UITheme.label(row[1], 17, Color.WHITE, true))
		vb.add_child(hb)
	vb.add_child(UITheme.label("H or ✕ to close", 12, UITheme.MUTED))

func update_hud(dt: float) -> void:
	UITheme.warm_punch_step()   # the big display letters, one a frame, before the first pop / banner needs them
	# the bike computer switches on when the ride starts (the HUD shows): its power-on chime
	if not visible: _power_t = -1.0
	elif _power_t < 0.35:
		var was := _power_t
		_power_t = maxf(_power_t, 0.0) + dt
		if was < 0.35 and _power_t >= 0.35: beep.power_on()
	var st: BikePhysics = game.phys
	# frame times on real time (the SYSTEM page): FPS over half a second + the last FRAME_HIST frames
	var now_us := Time.get_ticks_usec()
	var fdt := (now_us - _frame_us) / 1000.0 if _frame_us > 0 else 16.7
	_frame_us = now_us
	frame_ms.append(fdt)
	if frame_ms.size() > FRAME_HIST: frame_ms.remove_at(0)
	fps_frames += 1; fps_acc += fdt / 1000.0
	if fps_acc > 0.5:
		fps_now = fps_frames / fps_acc
		fps_frames = 0; fps_acc = 0
	# the SYSTEM page shows the ride in 3D too: the Debug Draw 3D physics overlay is on while it's up
	var sys_up: bool = gauge != null and gauge.visible and visible and gauge.order.size() > gauge.page and int(gauge.order[gauge.page]) == GaugeView.SYS_PAGE
	if sys_up != _sys_overlay:
		_sys_overlay = sys_up
		if sys_up:
			_overlay_was = DebugOverlay.on
			if not DebugOverlay.on and DebugOverlay.available(): DebugOverlay.toggle()
		elif DebugOverlay.on and not _overlay_was: DebugOverlay.toggle()
	info_l.text = "%s  ·  %s cam  ·  world #%d" % [GameState.BIKES[GameState.bike_id].label, game.cam.preset().label, GameState.seed]
	if msg_a > 0:
		msg_a -= dt
	msg_l.low = false   # the banner is up top now; messages keep their spot
	msg_l.tick(dt)
	if _demo_t >= 0.0:   # tests: BMX_FLASH=text shows it (and a scored trick) 3 s in; BMX_MSG_AT freezes the pop
		_demo_t += dt
		if _demo_t >= 3.0:
			_demo_t = -1.0
			flash(Env.s("BMX_FLASH"))
			if style_pop: style_pop.add(1250, "BACKFLIP")
	if Env.s("BMX_MSG_AT") != "" and _demo_t < 0.0:
		msg_l.t = float(Env.s("BMX_MSG_AT")); msg_l.queue_redraw()
	flow_leds.tick(st, dt)
	hop_bar.visible = st.hop_bar_show
	hop_bar.k = st.hop_bar
	getup.tick(dt)
	stamina.queue_redraw()
	hurt_t += dt
	if not st.crash_on and hurt_t > LIFE_WAIT: life = minf(1.0, life + LIFE_REGEN * dt)
	life_bar.shake = maxf(0.0, life_bar.shake - dt * 2.0)
	life_bar.heal = maxf(0.0, life_bar.heal - dt * 0.8)
	st.getup_need = REVIVE_HOLD if life <= 0.0 else BikePhysics.GETUP_HOLD
	life_bar.queue_redraw()
	gauge.bump = maxf(0.0, gauge.bump - dt * 4)
	# elevation profile
	elev_t += dt
	if elev_t >= HIST_DT:
		elev_t = 0
		if elev_hist.size() > 0 and not st.crash_on:
			var dy: float = st.y - elev_hist[elev_hist.size() - 1]
			if absf(dy) < 30.0:   # skip teleports (Backspace / new world)
				if dy > 0: elev_up += dy
				else: elev_down -= dy
		elev_hist.append(st.y)
		var tp := Vector2(st.x, st.z)
		if track_hist.size() > 0 and track_hist[track_hist.size() - 1].distance_to(tp) > 30.0:
			track_hist.clear()   # teleported (Backspace / new world)
		track_hist.append(tp)
		if track_hist.size() > TRACK: track_hist.remove_at(0)
		if elev_hist.size() > HIST: elev_hist.remove_at(0)
	_ride_stats(st, dt)
	_computer_tones(st, dt)
	alert_new = maxf(0.0, alert_new - dt)
	_trail_watch(st)
	gauge.queue_redraw()
	air_card.tick(dt)
	biome_l.text = game.biome_cur
	if st.crash_on: GameState.records.distance = GameState.records.distance   # (kept: saved on landing / menu)

func _ride_stats(st: BikePhysics, dt: float) -> void:
	ride_t += dt
	if not st.crash_on:
		var ds := absf(st.v) * dt
		ride_dist += ds
		GameState.add_distance(ds)   # total + today's log (title card: this week, streak)
		if absf(st.v) > 0.5: moving_t += dt
		max_v = maxf(max_v, absf(st.v))
	if is_nan(_crank_last): _crank_last = st.crank
	var dc := st.crank - _crank_last
	_crank_last = st.crank
	var rpm := absf(dc) / maxf(dt, 1e-4) / TAU * 60.0 if (st.pedal > 0.15 and not st.air) else 0.0
	cad += (minf(rpm, 150.0) - cad) * minf(1.0, dt * 3.0)
	var pw := 0.0
	if not st.air and not st.crash_on and st.pedal > 0.05:
		pw = 32.0 * maxf(0.0, st.a_drive) * absf(st.v) + st.pedal * (30.0 + 5.0 * absf(st.v))
	power += (minf(pw, 1100.0) - power) * minf(1.0, dt * 2.0)
	var hr_t := 68.0 + 95.0 * clampf(power / 650.0, 0, 1) + 22.0 * st.sprint + 18.0 * (1.0 - st.stamina) \
		+ 8.0 * clampf(absf(st.v) / 15.0, 0, 1) + (25.0 if st.crash_on else 0.0)
	hr += (hr_t - hr) * minf(1.0, dt * 0.35)

## the bike computer's own beeps: satellites found, auto-pause / resume, auto lap, low battery
func _computer_tones(st: BikePhysics, dt: float) -> void:
	_alert_beep_t = maxf(0.0, _alert_beep_t - dt)
	if not visible or _power_t < 0.35: return
	if not _gps_beeped and ride_t >= GaugeView.FIX_T:
		_gps_beeped = true
		beep.tone("gps")
	if ride_t < GaugeView.FIX_T + 1.0: return
	var va := absf(st.v)
	if not _paused:
		_still_t = _still_t + dt if (va < 0.4 and not st.crash_on) else 0.0
		if _still_t > AUTO_PAUSE:
			_paused = true
			beep.tone("pause")
	elif va > 1.0 and not st.crash_on:
		_paused = false; _still_t = 0.0
		beep.tone("resume")
	var lap := int(ride_dist / LAP_M)
	if lap > _lap:
		_lap = lap
		beep.tone("lap")
	if not _bat_warned and ride_t > GaugeView.BAT_LIFE * 0.9:
		_bat_warned = true
		beep.tone("battery")

## mount the bike computer chosen on the ride setup page (size, pages, navigation)
func set_computer() -> void:
	gauge.unit = ComputerUnits.current()
	gauge.order = ComputerUnits.pages(GameState.computer_id)
	gauge.page = 0
	gauge.scale = Vector2.ONE * float(gauge.unit.scale)
	if not gauge.unit.nav: alert = {}
	gauge.queue_redraw()

## where you are on the trail, and the next turn or feature ahead of you (the Garmin's alerts)
func _trail_watch(st: BikePhysics) -> void:
	if Env.s("BMX_ALERT_PROBE") != "" and ride_t > 1.0 and not _probed:
		_probed = true
		_probe_alerts()
	_trail_scan(Vector2(st.x, st.z), Vector2(cos(st.heading), -sin(st.heading)), st.crash_on)

var _probed := false
## test: ride the trail centreline in thought and print every alert the Garmin would give
func _probe_alerts() -> void:
	var tc: TrailCourse = game.terrain.field.course
	var last := ""
	for i in range(0, mini(tc.n - 1, 1200), 2):
		_trail_scan(Vector2(tc.X[i], tc.Z[i]), Vector2(tc.TX[i], tc.TZ[i]), false)
		var t: String = alert.get("text", "")
		if t != last and t != "":
			print("ALERT at trail %4.0f m: %s in %.0f m" % [i * TrailCourse.STEP, t, alert.d])
		last = t
	trail_i = -1

func _trail_scan(p: Vector2, fw: Vector2, crashed: bool) -> void:
	var was: String = alert.get("text", "")
	alert = {}
	if not gauge.unit.nav or not ComputerUnits.opt(GameState.computer_id, "alerts"): return   # no navigation, or alerts off: no turn / feature alerts
	if Env.s("BMX_ALERT_DEMO") != "":   # tests: a fixed alert to look at
		alert = {"kind": Env.s("BMX_ALERT_DEMO"), "text": "HAIRPIN RIGHT", "d": 22.0}
		return
	var t = game.terrain
	if t == null or t.field == null or t.field.course == null: return
	var tc: TrailCourse = t.field.course
	if tc.n < 2: return
	if trail_i < 0 or trail_i >= tc.n:
		trail_i = _nearest(tc, p, 0, tc.n)
	else:
		trail_i = _nearest(tc, p, maxi(0, trail_i - 60), mini(tc.n, trail_i + 60))
		if Vector2(tc.X[trail_i], tc.Z[trail_i]).distance_to(p) > 40.0:   # teleported
			trail_i = _nearest(tc, p, 0, tc.n)
	trail_d = Vector2(tc.X[trail_i], tc.Z[trail_i]).distance_to(p)
	if trail_d > 15.0 or crashed: return
	if fw.dot(Vector2(tc.TX[trail_i], tc.TZ[trail_i])) < 0.3: return   # riding the trail backwards
	var S := TrailCourse.STEP
	var best_d := 120.0
	# the next bend worth calling out (KAP > 0 turns right)
	var i := trail_i + 2
	var end := mini(tc.n - 2, trail_i + int(best_d / S))
	while i < end:
		if absf(tc.KAP[i]) > 1.0 / 22.0:
			var sg := signf(tc.KAP[i])
			var j := i
			while j > trail_i and absf(tc.KAP[j - 1]) > 1.0 / 60.0 and signf(tc.KAP[j - 1]) == sg: j -= 1
			var k := i
			var ang := 0.0
			while k < tc.n - 1 and absf(tc.KAP[k]) > 1.0 / 60.0 and signf(tc.KAP[k]) == sg:
				ang += tc.KAP[k] * S; k += 1
			var d := (j - trail_i) * S
			if d < 4.0 or absf(ang) < 0.6:
				i = k + 1; continue
			var side := "RIGHT" if sg > 0 else "LEFT"
			var kind := ("H" if absf(ang) > 2.3 else "S" if absf(ang) > 1.2 else "") + side[0]
			var txt := ("HAIRPIN " if absf(ang) > 2.3 else "SHARP " if absf(ang) > 1.2 else "") + side
			if d < best_d:
				best_d = d; alert = {"kind": kind, "text": txt, "d": d}
			break
		i += 1
	# the next route feature (jumps, rollers, wood)
	var s_here := trail_i * S
	var rf: Array = t.field.route_feats
	var lo := 0
	var hi := rf.size()
	while lo < hi:
		var mid := (lo + hi) >> 1
		if rf[mid].s + rf[mid].len > s_here: hi = mid
		else: lo = mid + 1
	for q in range(lo, mini(lo + 3, rf.size())):
		var d: float = rf[q].s - s_here
		if d >= 4.0:
			if d < best_d:
				best_d = d; alert = {"kind": "J", "text": FEAT_NAMES.get(rf[q].type, String(rf[q].type).to_upper()), "d": d}
			break
	# rock gardens
	for q in range(trail_i + 2, mini(tc.n, trail_i + int(best_d / S))):
		if tc.KD[q] == TrailCourse.ROCKS and tc.KD[q - 1] != TrailCourse.ROCKS:
			var d := (q - trail_i) * S
			if d >= 4.0 and d < best_d:
				best_d = d; alert = {"kind": "K", "text": "ROCKS", "d": d}
			break
	if alert.get("text", "") != "" and alert.text != was:
		if int(gauge.order[gauge.page]) == GaugeView.MAP_PAGE: gauge.light = 3.0   # the screen lights up for a new alert (map page only)
		alert_new = 3.5
	# the navigation prompt, once per turn / feature as it comes within 100 m: a turn tune for bends,
	# a double beep for a feature / rocks (keyed by where it is on the trail, so two LEFTs in a row both beep)
	if not alert.is_empty() and alert.d < 100.0:
		var key := int((trail_i * S + alert.d) / 12.0)
		if absi(key - _alert_key) > 1:
			_alert_key = key
			if _alert_beep_t <= 0.0 and ride_t > GaugeView.FIX_T + 1.0:
				_alert_beep_t = 2.5
				beep.tone("turn" if (alert.kind as String).right(1) in ["L", "R"] else "feature")

func _nearest(tc: TrailCourse, p: Vector2, a: int, b: int) -> int:
	var best := a
	var bd := INF
	for i in range(a, b):
		var d: float = (tc.X[i] - p.x) * (tc.X[i] - p.x) + (tc.Z[i] - p.y) * (tc.Z[i] - p.y)
		if d < bd: bd = d; best = i
	return best

# ======================================================================
class GaugeView extends Control:
	## a compact GPS bike computer: black body, pale LCD, pages flipped with the bezel buttons under the
	## screen; a turn / feature alert drops over any page; GPS fix at the start, battery, backlight.
	const TITLES := ["RIDE", "TRIP", "EFFORT", "AIR", "ELEV", "MAP", "SYSTEM"]
	const PAGES := 7
	const MAP_PAGE := 5
	const SYS_PAGE := 6
	const LOGO := "CHARMIN"
	const LOGO_TRACK := 0.8   # letter spacing of the wordmark
	const LCD := Color("eceee8")
	const LCD_LIT := Color("f2fbff")
	const FIX_T := 3.0     # seconds to "find satellites" at the start of a ride
	const BAT_LIFE := 1800.0   # seconds of riding from a full battery to empty
	var map_v: MapView
	var ov: Overlay
	var hud
	var unit := ComputerUnits.get_unit("classic")
	var order: Array = [0, 1, 2, 3, 4, 5, 6]   # the page ids this model has
	var page := 0          # index into `order`
	var bump := 0.0        # 1 on a shift, fades out: the gear digit flashes inverted
	var show_gear := true  # Settings › HUD › Gear shifter
	var press := [0.0, 0.0]   # bezel button press flash (left, right)
	var light := 0.0       # backlight seconds left (a button press or a new alert)
	var scr := Rect2()
	var lcd := LCD
	func _ready() -> void:
		map_v = MapView.new(); map_v.hud = hud
		map_v.visible = false
		add_child(map_v)
		ov = Overlay.new(); ov.g = self
		ov.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(ov)
	func _btn_rect(i: int) -> Rect2:
		return Rect2(12 if i == 0 else size.x - 46, size.y - 23, 34, 14)
	func _gui_input(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			for i in 2:
				if _btn_rect(i).grow(4).has_point(e.position):
					page = posmod(page + (-1 if i == 0 else 1), order.size())
					hud.beep.key()
					press[i] = 1.0
					light = 3.0
					queue_redraw()
					accept_event()
					return
	func _draw() -> void:
		var st: BikePhysics = hud.game.phys
		var f := UITheme.lcd_font()
		light = maxf(0.0, light - get_process_delta_time())
		if int(ComputerUnits.opt(GameState.computer_id, "light")) == 1: light = 3.0   # backlight: always on
		var lk := clampf(light / 0.4, 0, 1)
		lcd = LCD.lerp(LCD_LIT, lk)
		UITheme.draw_box(self, Rect2(Vector2.ZERO, size), unit.body, 16)
		scr = Rect2(7, 20, size.x - 14, size.y - 50)
		hud.flow_leds.draw(self, size, scr)
		if lk > 0: UITheme.draw_box(self, scr.grow(2), Color(0.7, 0.88, 1.0, 0.22 * lk), 8)
		UITheme.draw_box(self, scr, lcd, 6)
		var ink := Color("111417")
		var x0 := scr.position.x + 6
		var w := scr.size.x - 12
		# status bar: clock | page title (AIR when airborne) | battery
		draw_rect(Rect2(scr.position.x, scr.position.y, scr.size.x, 14), ink)
		var tm := Time.get_time_dict_from_system()
		var hy := scr.position.y + 11
		draw_string(f, Vector2(x0, hy), "%02d:%02d" % [tm.hour, tm.minute], HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color("f2f3ef"))
		if st.air: draw_string(f, Vector2(x0, hy), "AIR", HORIZONTAL_ALIGNMENT_CENTER, w, 10, Color("ffd21f"))
		else: draw_string(f, Vector2(x0, hy), TITLES[order[page]], HORIZONTAL_ALIGNMENT_CENTER, w, 9, Color(0.95, 0.95, 0.94, 0.75))
		var bat := clampf(1.0 - hud.ride_t / BAT_LIFE, 0.0, 1.0)   # full to empty in 30 min of riding
		if bat < 0.1 and fmod(hud.ride_t, 1.0) < 0.5: bat = -1.0   # nearly flat: the icon blinks
		var br := Rect2(scr.end.x - 22, scr.position.y + 4, 14, 7)
		if bat >= 0.0:
			draw_rect(br, Color(0.95, 0.95, 0.94, 0.8), false, 1.0)
			draw_rect(Rect2(br.end.x, br.position.y + 2, 2, 3), Color(0.95, 0.95, 0.94, 0.8))
			if bat > 0.0: draw_rect(Rect2(br.position.x + 1.5, br.position.y + 1.5, (br.size.x - 3) * bat, br.size.y - 3), Color("8be36a") if bat > 0.2 else Color("ff6a4d"))
		var pid: int = order[page]
		map_v.visible = pid == MAP_PAGE and hud.ride_t > FIX_T
		match pid:
			0: _page_ride(st, f, ink, scr, x0, w)
			1: _page_trip(f, ink, scr, x0, w)
			2: _page_effort(st, f, ink, scr, x0, w)
			3: _page_air(f, ink, scr, x0, w)
			4: _page_elev(st, f, ink, scr, x0, w)
			SYS_PAGE: _page_sys(f, ink, scr, x0, w)
			_: _page_map(st, f, ink, scr, x0, w)
		_page_bar()
		_bezel()
		ov.size = size
		ov.queue_redraw()
	## a label (left) + unit (right) over a big value
	func _big(f: Font, ink: Color, x0: float, w: float, y: float, label: String, unit: String, val: String) -> void:
		draw_string(f, Vector2(x0, y), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(ink, 0.6))
		draw_string(f, Vector2(x0, y), unit, HORIZONTAL_ALIGNMENT_RIGHT, w, 9, Color(ink, 0.7))
		draw_string(f, Vector2(x0, y + 36), val, HORIZONTAL_ALIGNMENT_RIGHT, w, 38 if val.length() <= 4 else 30, ink)
	## two fields side by side in a 40 px row
	func _pair(f: Font, ink: Color, scr_: Rect2, x0: float, w: float, y: float, la: String, va: String, lb: String, vb: String) -> void:
		draw_line(Vector2(scr_.position.x, y), Vector2(scr_.end.x, y), Color(ink, 0.22))
		draw_string(f, Vector2(x0, y + 12), la, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(ink, 0.6))
		draw_string(f, Vector2(x0 + w * 0.5 + 4, y + 12), lb, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(ink, 0.6))
		draw_string(f, Vector2(x0, y + 32), va, HORIZONTAL_ALIGNMENT_RIGHT, w * 0.5 - 4, 18, ink)
		draw_string(f, Vector2(x0 + w * 0.5 + 4, y + 32), vb, HORIZONTAL_ALIGNMENT_RIGHT, w * 0.5 - 4, 18, ink)
		draw_line(Vector2(scr_.position.x + scr_.size.x * 0.5, y), Vector2(scr_.position.x + scr_.size.x * 0.5, y + 40), Color(ink, 0.22))
	static func _clock(t: float) -> String:
		var si := int(t)
		return "%d:%02d:%02d" % [si / 3600, (si / 60) % 60, si % 60] if si >= 3600 else "%d:%02d" % [si / 60, si % 60]
	## SYSTEM: frame rate, a frame-time graph (the last 120 frames; lines at 60 / 30 fps), average / worst
	## frame, and whether the 3D physics view (Debug Draw 3D, drawn in the world while this page is up) is on
	func _page_sys(f: Font, ink: Color, scr_: Rect2, x0: float, w: float) -> void:
		var y := scr_.position.y + 28
		_big(f, ink, x0, w, y, "FRAME RATE", "fps", "%d" % roundi(hud.fps_now))
		y += 46
		var g := Rect2(x0, y, w, 44)
		draw_rect(g, Color(ink, 0.06))
		var ms: PackedFloat32Array = hud.frame_ms
		var top := 50.0                                   # ms at the top of the graph
		for ref: float in [16.7, 33.3]:
			var ly := g.end.y - g.size.y * ref / top
			draw_line(Vector2(g.position.x, ly), Vector2(g.end.x, ly), Color(ink, 0.3), 1.0)
			draw_string(f, Vector2(g.position.x + 1, ly - 1), "60" if ref < 20 else "30", HORIZONTAL_ALIGNMENT_LEFT, -1, 7, Color(ink, 0.45))
		var n := ms.size()
		var bw := g.size.x / float(FRAME_HIST)
		var avg := 0.0
		var worst := 0.0
		for i in n:
			var v := ms[i]
			avg += v; worst = maxf(worst, v)
			var h := minf(v / top, 1.0) * g.size.y
			var c := ink if v <= 20.0 else (Color("b07a00") if v <= 34.0 else Color("c0392b"))
			draw_rect(Rect2(g.end.x - (n - i) * bw, g.end.y - h, maxf(bw, 1.0), h), c)
		if n > 0: avg /= n
		y += 48
		_pair(f, ink, scr_, x0, w, y, "AVG MS", "%.1f" % avg, "WORST", "%.0f" % worst)
		# the 3D physics view's state, small in the graph's top right
		var on3d := DebugOverlay.on and DebugOverlay.available()
		draw_string(f, Vector2(g.position.x, g.position.y + 8), "3D " + ("ON" if on3d else ("OFF" if DebugOverlay.available() else "N/A")), HORIZONTAL_ALIGNMENT_RIGHT, g.size.x - 2, 7, Color(ink, 0.6))
	## TRIP: ride time, distance, average / max speed, odometer (every ride, saved)
	func _page_trip(f: Font, ink: Color, scr_: Rect2, x0: float, w: float) -> void:
		var y := scr_.position.y + 28
		_big(f, ink, x0, w, y, "RIDE TIME", "", _clock(hud.ride_t))
		y += 46
		var km: bool = Settings.get_v("units") != 1
		var dk := 1000.0 if km else 1609.34
		var du := "km" if km else "mi"
		var avg: float = hud.ride_dist / maxf(1.0, hud.moving_t)
		_pair(f, ink, scr_, x0, w, y, "DIST " + du, "%.2f" % (hud.ride_dist / dk), "AVG", hud.speed_text(avg))
		y += 40
		_pair(f, ink, scr_, x0, w, y, "MAX", hud.speed_text(hud.max_v), "ODO " + du, "%.1f" % (float(GameState.records.distance) / dk))
	## EFFORT: heart rate (beating heart, zone), cadence, power, stamina, gear ratio
	func _page_effort(st: BikePhysics, f: Font, ink: Color, scr_: Rect2, x0: float, w: float) -> void:
		var y := scr_.position.y + 28
		_big(f, ink, x0, w, y, "HEART", "bpm", "%d" % roundi(hud.hr))
		var beat := pow(maxf(0.0, sin(hud.ride_t * hud.hr / 60.0 * TAU)), 8.0)
		var hc := Vector2(x0 + 10, y + 20)
		var hs := 5.0 * (1.0 + 0.18 * beat)
		draw_circle(hc + Vector2(-hs * 0.5, 0), hs * 0.58, Color("d8344a"))
		draw_circle(hc + Vector2(hs * 0.5, 0), hs * 0.58, Color("d8344a"))
		draw_colored_polygon(PackedVector2Array([hc + Vector2(-hs * 1.05, hs * 0.2), hc + Vector2(hs * 1.05, hs * 0.2), hc + Vector2(0, hs * 1.4)]), Color("d8344a"))
		var zone := clampi(int((hud.hr - 95.0) / 18.0) + 1, 1, 5)
		for z in 5:
			draw_rect(Rect2(x0 + z * 6, y + 34, 5, 4), ink if z < zone else Color(ink, 0.18))
		draw_string(f, Vector2(x0 + 32, y + 39), "Z%d" % zone, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(ink, 0.7))
		y += 46
		_pair(f, ink, scr_, x0, w, y, "CADENCE", "%d" % roundi(hud.cad), "POWER W", "%d" % roundi(hud.power))
		y += 40
		draw_line(Vector2(scr_.position.x, y), Vector2(scr_.end.x, y), Color(ink, 0.22))
		draw_line(Vector2(scr_.position.x + scr_.size.x * 0.5, y), Vector2(scr_.position.x + scr_.size.x * 0.5, y + 40), Color(ink, 0.22))
		draw_string(f, Vector2(x0, y + 12), "STAMINA", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(ink, 0.6))
		var bw := w * 0.5 - 6
		draw_rect(Rect2(x0, y + 20, bw, 10), Color(ink, 0.8), false, 1.0)
		draw_rect(Rect2(x0 + 2, y + 22, (bw - 4) * clampf(st.stamina, 0, 1), 6), ink if not st.tired else Color("d8344a"))
		var ring := roundi(34.0 * st.ring_k)
		var cog: int = st.cogs[maxi(st.gear, 0)] if st.cogs.size() > 0 else 16
		draw_string(f, Vector2(x0 + w * 0.5 + 4, y + 12), "%dx%d" % [ring, cog], HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(ink, 0.6))
		draw_string(f, Vector2(x0 + w * 0.5 + 4, y + 32), "%.2f" % (float(ring) / cog), HORIZONTAL_ALIGNMENT_RIGHT, w * 0.5 - 4, 18, ink)
	## AIR: the last jump, today's best, jumps and tricks landed
	func _page_air(f: Font, ink: Color, scr_: Rect2, x0: float, w: float) -> void:
		var y := scr_.position.y + 28
		var lj: Vector3 = hud.jump_last
		var bj: Vector3 = hud.jump_best
		_big(f, ink, x0, w, y, "LAST JUMP", "m", "%.1f" % lj.y if hud.jumps > 0 else "--")
		y += 46
		_pair(f, ink, scr_, x0, w, y, "HEIGHT m", "%.1f" % lj.z, "AIR s", "%.2f" % lj.x)
		y += 40
		_pair(f, ink, scr_, x0, w, y, "BEST m", "%.1f" % bj.y, "JUMPS", "%d" % hud.jumps)
		y += 40
		draw_line(Vector2(scr_.position.x, y), Vector2(scr_.end.x, y), Color(ink, 0.22))
		var tl: String = hud.trick_last
		draw_string(f, Vector2(x0, y + 13), "TRICKS %d" % hud.tricks + ("  " + tl if tl != "" else ""), HORIZONTAL_ALIGNMENT_LEFT, w, 9, ink)
	## drawn over everything (the map included): the GPS fix screen, then turn / feature alerts
	func draw_over(c: Control) -> void:
		var f := UITheme.lcd_font()
		var ink := Color("111417")
		var t: float = hud.ride_t
		var inner := Rect2(scr.position.x, scr.position.y + 14, scr.size.x, scr.size.y - 14)
		if t < FIX_T + 0.8:
			UITheme.draw_box(c, inner, lcd, 6)
			var cx := inner.get_center()
			if t < FIX_T:
				# satellite dish: an arc that sweeps, and signal bars filling as satellites lock on
				var a := t * 4.0
				c.draw_arc(cx + Vector2(0, -16), 14, a, a + 1.6, 12, ink, 2.0)
				c.draw_arc(cx + Vector2(0, -16), 8, a + PI, a + PI + 1.6, 10, Color(ink, 0.6), 2.0)
				c.draw_circle(cx + Vector2(0, -16), 2.5, ink)
				c.draw_string(f, Vector2(inner.position.x, cx.y + 14), "ACQUIRING", HORIZONTAL_ALIGNMENT_CENTER, inner.size.x, 10, ink)
				c.draw_string(f, Vector2(inner.position.x, cx.y + 26), "SATELLITES", HORIZONTAL_ALIGNMENT_CENTER, inner.size.x, 10, ink)
				var nb := int(t / FIX_T * 6.0)
				for b in 6:
					var bh := 4.0 + b * 3.0
					c.draw_rect(Rect2(cx.x - 22 + b * 8, cx.y + 50 - bh, 5, bh), ink if b < nb else Color(ink, 0.15))
			else:
				c.draw_string(f, Vector2(inner.position.x, cx.y - 2), "GPS READY", HORIZONTAL_ALIGNMENT_CENTER, inner.size.x, 12, ink)
				c.draw_polyline(PackedVector2Array([cx + Vector2(-8, 12), cx + Vector2(-2, 18), cx + Vector2(9, 6)]), ink, 2.5)
			return
		if int(order[page]) != MAP_PAGE: return   # the what's-next alert card is only for the MAP page
		var al: Dictionary = hud.alert
		# pops up when it first appears, then stays from 40 m in (the page shows the rest of the time)
		if al.is_empty() or al.d > 100.0 or (al.d > 40.0 and hud.alert_new <= 0.0): return
		# the bottom half of the screen: a dark box, the turn / feature icon + distance, the name under them
		var bh := scr.size.y / 3.0   # the card takes the bottom third of the screen height
		var top := inner.end.y - bh - 3
		var bx := Rect2(inner.position.x + 3, top, inner.size.x - 6, bh)
		draw_alert(c, bx, al, f)

	## the trail alert in a box: icon top left, distance big on the right, the name along the bottom
	static func draw_alert(c: CanvasItem, bx: Rect2, al: Dictionary, f: Font) -> void:
		var yel := Color("ffd21f")
		UITheme.draw_box(c, bx, Color("111417"), 6)
		var wide := bx.size.y < 64.0   # a short card (a third of the screen): icon left, distance + name stacked on the right
		var row := bx.size.y - 10.0 if wide else bx.size.y * 0.62
		var ic := bx.position + Vector2(row * 0.5 + 2, bx.size.y * 0.5 if wide else row * 0.5 + 3)
		var sc := row / 26.0 * 0.95
		var kind: String = al.kind
		c.draw_set_transform(ic * (1.0 - sc), 0.0, Vector2(sc, sc))
		if kind.ends_with("L") or kind.ends_with("R"):
			var sx := -1.0 if kind.ends_with("L") else 1.0
			var pts := PackedVector2Array()
			if kind.begins_with("H"):   # hairpin: a U
				pts.append(ic + Vector2(-5 * sx, 11))
				for q in 9:
					var an := PI * q / 8.0
					pts.append(ic + Vector2(-5 * sx * cos(an), -2 - 7 * sin(an)))
				pts.append(ic + Vector2(5 * sx, 4))
			else:
				var bend := 9.0 if kind.begins_with("S") else 6.0
				pts.append(ic + Vector2(-2 * sx, 11)); pts.append(ic + Vector2(-2 * sx, 0))
				pts.append(ic + Vector2(0, -bend * 0.6)); pts.append(ic + Vector2(bend * sx * 0.7, -bend * 0.9))
			c.draw_polyline(pts, Color.WHITE, 3.0)
			var tip := pts[pts.size() - 1]
			var dv := (tip - pts[pts.size() - 2]).normalized()
			var nv := Vector2(-dv.y, dv.x)
			c.draw_colored_polygon(PackedVector2Array([tip + dv * 5, tip + nv * 4.5, tip - nv * 4.5]), Color.WHITE)
		elif kind == "J":   # a ramp
			c.draw_colored_polygon(PackedVector2Array([ic + Vector2(-11, 8), ic + Vector2(6, 8), ic + Vector2(6, -6)]), Color.WHITE)
			c.draw_arc(ic + Vector2(0, -2), 9, -PI * 0.95, -PI * 0.45, 8, yel, 1.5)
		else:   # rocks
			c.draw_circle(ic + Vector2(-5, 5), 5, Color.WHITE)
			c.draw_circle(ic + Vector2(5, 6), 4, Color.WHITE)
			c.draw_circle(ic + Vector2(1, -3), 4, Color(1, 1, 1, 0.8))
		c.draw_set_transform(Vector2.ZERO)
		var dm: float = al.d
		var dtx := "%dm" % (roundi(dm / 10.0) * 10 if dm > 50.0 else roundi(dm))
		if wide:
			var fs := int(clampf(bx.size.y * 0.42, 12.0, 22.0))
			c.draw_string(f, Vector2(bx.position.x + row + 4, bx.position.y + 6 + fs), dtx, HORIZONTAL_ALIGNMENT_RIGHT, bx.size.x - row - 10, fs, yel)
			c.draw_string(f, Vector2(bx.position.x + row + 4, bx.end.y - 6), al.text, HORIZONTAL_ALIGNMENT_RIGHT, bx.size.x - row - 10, 9, Color.WHITE)
			return
		c.draw_string(f, Vector2(bx.position.x + row + 4, bx.position.y + row * 0.5 + 12), dtx, HORIZONTAL_ALIGNMENT_RIGHT, bx.size.x - row - 10, 26, yel)
		c.draw_string(f, Vector2(bx.position.x + 6, bx.end.y - 7), al.text, HORIZONTAL_ALIGNMENT_CENTER, bx.size.x - 12, 10, Color.WHITE)
	## bezel under the screen: a page button left and right, page dots between them
	func _bezel() -> void:
		var dt := get_process_delta_time()
		for i in 2:
			var br := _btn_rect(i)
			var k: float = press[i]
			UITheme.draw_box(self, br, Color("2b2e32").lerp(Color("55595e"), k), 7, Color(1, 1, 1, 0.1), 1)
			var c := br.get_center() + Vector2(0, k)
			var s := 1.0 if i == 1 else -1.0
			draw_colored_polygon(PackedVector2Array([c + Vector2(-3 * s, -4), c + Vector2(-3 * s, 4), c + Vector2(3 * s, 0)]), Color("b8bcc0"))
			press[i] = maxf(0.0, k - dt * 5.0)
		# the maker's wordmark between the buttons (made-up brand)
		var lf := UITheme.font(true)
		var lw := lf.get_string_size(LOGO, HORIZONTAL_ALIGNMENT_LEFT, -1, 8).x + LOGO_TRACK * (LOGO.length() - 1)
		var lx := size.x * 0.5 - lw * 0.5
		for ch in LOGO:
			draw_string(lf, Vector2(lx, size.y - 13), ch, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color("c9ccd0"))
			lx += lf.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, 8).x + LOGO_TRACK
	## which page: a segmented bar along the bottom edge of the screen, the current page's segment dark
	func _page_bar() -> void:
		var np := order.size()
		if np < 2: return
		var strip := Rect2(scr.position.x + 3, scr.end.y - 6, scr.size.x - 6, 6)
		draw_rect(Rect2(scr.position.x + 2, strip.position.y - 1, scr.size.x - 4, 7), lcd)
		var gap := 2.0
		var sw := (strip.size.x - gap * (np - 1)) / np
		for j in np:
			var r := Rect2(strip.position.x + j * (sw + gap), strip.position.y + 1, sw, 3)
			draw_rect(r, Color("111417") if j == page else Color(0.07, 0.08, 0.09, 0.18))
	func _page_ride(st: BikePhysics, f: Font, ink: Color, scr: Rect2, x0: float, w: float) -> void:
		var y := scr.position.y + 28
		draw_string(f, Vector2(x0, y), "SPEED", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(ink, 0.6))
		draw_string(f, Vector2(x0, y), hud.speed_unit(), HORIZONTAL_ALIGNMENT_RIGHT, w, 9, Color(ink, 0.7))
		draw_string(f, Vector2(x0, y + 36), hud.speed_text(st.v), HORIZONTAL_ALIGNMENT_RIGHT, w, 38, ink)
		y += 46
		draw_line(Vector2(scr.position.x, y), Vector2(scr.end.x, y), Color(ink, 0.22))
		var dir := -1.0 if st.v < -0.1 else 1.0
		var hx := cos(st.heading) * 0.6 * dir
		var hz := -sin(st.heading) * 0.6 * dir
		var slope := atan2(hud.game.terrain.height(st.x + hx, st.z + hz) - hud.game.terrain.height(st.x - hx, st.z - hz), 1.2)
		draw_string(f, Vector2(x0, y + 12), "SLOPE", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(ink, 0.6))
		draw_string(f, Vector2(x0 + w * 0.5 + 4, y + 12), "GRADE", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(ink, 0.6))
		draw_string(f, Vector2(x0, y + 32), "%d°" % roundi(rad_to_deg(slope)), HORIZONTAL_ALIGNMENT_RIGHT, w * 0.5 - 4, 18, ink)
		draw_string(f, Vector2(x0 + w * 0.5 + 4, y + 32), "%d%%" % roundi(tan(slope) * 100), HORIZONTAL_ALIGNMENT_RIGHT, w * 0.5 - 4, 18, ink)
		draw_line(Vector2(scr.position.x + scr.size.x * 0.5, y), Vector2(scr.position.x + scr.size.x * 0.5, y + 40), Color(ink, 0.22))
		y += 40
		if show_gear:
			draw_line(Vector2(scr.position.x, y), Vector2(scr.end.x, y), Color(ink, 0.22))
			_gear_row(st, f, ink, x0, y, w, scr.end.y)
	## page 3: the map screen is its own clipped control (MapView) laid over the LCD
	func _page_map(_st: BikePhysics, _f: Font, _ink: Color, scr: Rect2, _x0: float, _w: float) -> void:
		var area := Rect2(scr.position.x, scr.position.y + 14, scr.size.x, scr.size.y - 14)
		if map_v.position != area.position or map_v.size != area.size:
			map_v.position = area.position; map_v.size = area.size
		map_v.queue_redraw()
	## elevation now, climbed / descended this ride; the profile: the last 30 s, then the trail ahead
	## (next 400 m, coloured by how steep it is, like ClimbPro)
	func _page_elev(st: BikePhysics, f: Font, ink: Color, scr_: Rect2, x0: float, w: float) -> void:
		var y := scr_.position.y + 28
		_big(f, ink, x0, w, y, "ELEV", "m", "%d" % roundi(st.y))
		y += 46
		_pair(f, ink, scr_, x0, w, y, "ASC", "%d" % roundi(hud.elev_up), "DESC", "%d" % roundi(hud.elev_down))
		y += 40
		draw_line(Vector2(scr_.position.x, y), Vector2(scr_.end.x, y), Color(ink, 0.22))
		var hist: PackedFloat32Array = hud.elev_hist
		var ahead := PackedFloat32Array()
		var tc = hud.game.terrain.field.course if hud.game.terrain and hud.game.terrain.field else null
		var ti: int = hud.trail_i
		if tc and ti >= 0 and ti < tc.n and hud.trail_d < 15.0:
			var off: float = st.y - tc.E[ti]
			for m in range(0, 404, 4):
				var q := mini(tc.n - 1, ti + int(m / TrailCourse.STEP))
				ahead.append(tc.E[q] + off)
		var lo := st.y
		var hi := st.y
		for e in hist: lo = minf(lo, e); hi = maxf(hi, e)
		for e in ahead: lo = minf(lo, e); hi = maxf(hi, e)
		hi = maxf(hi, lo + 4)
		var gt := y + 12
		var gb := scr_.end.y - 4
		var gh := gb - gt
		var split := x0 + w * (0.35 if ahead.size() > 0 else 1.0)
		var ey := func(e: float) -> float: return gb - (e - lo) / (hi - lo) * gh
		if hist.size() > 1:
			var pts := PackedVector2Array([Vector2(x0, gb)])
			for i in hist.size():
				pts.append(Vector2(x0 + (split - x0) * i / float(hist.size() - 1), ey.call(hist[i])))
			pts.append(Vector2(split, gb))
			draw_colored_polygon(pts, Color(ink, 0.22))
		if ahead.size() > 1:
			var cw := (x0 + w - split) / float(ahead.size() - 1)
			for i in ahead.size() - 1:
				var g := absf(ahead[i + 1] - ahead[i]) / 4.0
				var col := Color("3fae49") if g < 0.04 else Color("e2c21c") if g < 0.08 else Color("ec7a1c") if g < 0.13 else Color("d8344a")
				var xa := split + i * cw
				draw_colored_polygon(PackedVector2Array([Vector2(xa, gb), Vector2(xa, ey.call(ahead[i])),
					Vector2(xa + cw, ey.call(ahead[i + 1])), Vector2(xa + cw, gb)]), col)
			var gr: float = (ahead[mini(25, ahead.size() - 1)] - ahead[0]) / (mini(25, ahead.size() - 1) * 4.0)
			draw_string(f, Vector2(x0, y + 10), "NEXT 400m  %+d%%" % roundi(gr * 100.0), HORIZONTAL_ALIGNMENT_RIGHT, w, 8, Color(ink, 0.75))
			draw_line(Vector2(split, gt - 2), Vector2(split, gb), ink, 1.0)
			draw_colored_polygon(PackedVector2Array([Vector2(split - 3, gt - 4), Vector2(split + 3, gt - 4), Vector2(split, gt)]), ink)
	## GEAR n | the cassette side-on, chain on the dark cog | teeth (LCD ink, no colour)
	## the shifter: fills the rest of the screen below y (to y1), digit | cassette | teeth centred in it
	func _gear_row(st: BikePhysics, f: Font, ink: Color, x0: float, y: float, w: float, y1: float) -> void:
		draw_string(f, Vector2(x0, y + 12), "GEAR", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(ink, 0.6))
		var top := y + 15.0
		var bot := y1 - 4.0
		var mid := (top + bot) * 0.5 + 3.0      # cassette centre (the shift arrow sits above it)
		if st.gear < 0:
			draw_string(f, Vector2(x0, mid + 9), "1", HORIZONTAL_ALIGNMENT_LEFT, -1, 26, ink)
			draw_string(f, Vector2(x0, mid + 4), "SINGLE", HORIZONTAL_ALIGNMENT_RIGHT, w, 11, Color(ink, 0.7))
			return
		var n := st.cogs.size()
		draw_string(f, Vector2(x0, y + 12), "%d/%d" % [st.gear + 1, n], HORIZONTAL_ALIGNMENT_RIGHT, w, 9, Color(ink, 0.6))
		# the gear digit, inverted for a moment after a shift
		var d := str(st.gear + 1)
		var dw := 22.0 if d.length() == 1 else 32.0
		if bump > 0.05:
			draw_rect(Rect2(x0 - 3, mid - 14, dw + 4, 28), Color(ink, clampf(bump * 1.5, 0, 1)))
		var dc := ink.lerp(Color("eceee8"), clampf(bump * 1.5, 0, 1))
		draw_string(f, Vector2(x0, mid + 10), d, HORIZONTAL_ALIGNMENT_LEFT, -1, 26, dc)
		# cassette: biggest cog on the left, between the digit and the teeth count
		var tw := 30.0
		var cx := x0 + dw + 6.0
		var span := w - (dw + 6.0) - tw - 4.0
		var step := minf(9.0, span / maxf(1.0, n))
		cx += (span - step * n) * 0.5
		var hmax := maxf(12.0, (bot - top) - 10.0)
		draw_line(Vector2(cx - 2, mid), Vector2(cx + step * n, mid), Color(ink, 0.25), 1)
		var big: float = st.cogs[n - 1]
		for j in n:
			var gi: int = n - 1 - j
			var on := gi == st.gear
			var hgt: float = st.cogs[gi] / big * hmax
			var bw := step - 2.0 if on else step - 3.0
			draw_rect(Rect2(cx + j * step, mid - hgt / 2, maxf(1.5, bw), hgt), ink if on else Color(ink, 0.3))
			if on:
				var px := cx + j * step + bw / 2
				draw_colored_polygon(PackedVector2Array([Vector2(px - 3.5, mid - hgt / 2 - 7), Vector2(px + 3.5, mid - hgt / 2 - 7), Vector2(px, mid - hgt / 2 - 2)]), ink)
		draw_string(f, Vector2(x0, mid + 5), "%dT" % st.cogs[st.gear], HORIZONTAL_ALIGNMENT_RIGHT, w, 13, ink)

class MapView extends Control:
	## Garmin-style 2D topo map, heading-up: contour lines (5 m, every 25 m bolder), the trail,
	## the path you rode, you as an arrow. Drawn in world (x, z) through one transform, clipped here.
	const MAP_M := 170.0     # metres across the screen
	const R := 180.0         # contour grid radius (covers the rotated screen)
	const STEP := 6.0        # contour grid spacing (m)
	const N := int(2 * R / STEP) + 1
	const CI := 5.0          # contour interval (m)
	const ROWS := 4          # grid rows sampled per frame
	var hud
	var _minor := PackedVector2Array()   # finished contour segments (world x, z pairs)
	var _major := PackedVector2Array()
	var _at := Vector2(INF, INF)         # centre of the finished contours
	var _bc := Vector2.ZERO              # building: centre, heights, next row
	var _bh := PackedFloat32Array()
	var _row := -1
	func _ready() -> void:
		clip_contents = true
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func _process(_dt: float) -> void:
		if not visible: return
		var st: BikePhysics = hud.game.phys
		var p := Vector2(st.x, st.z)
		if _row < 0 and p.distance_to(_at) > 40.0:
			_bc = p.snapped(Vector2(STEP, STEP)); _bh.resize(N * N); _row = 0
		if _row >= 0:
			var t = hud.game.terrain
			for r in ROWS:
				if _row >= N: break
				var z := _bc.y - R + _row * STEP
				for c in N:
					_bh[_row * N + c] = t.height(_bc.x - R + c * STEP, z)
				_row += 1
			if _row >= N:
				_contours(); _at = _bc; _row = -1
	## marching squares over the finished height grid
	func _contours() -> void:
		_minor = PackedVector2Array(); _major = PackedVector2Array()
		var ox := _bc.x - R; var oz := _bc.y - R
		for j in N - 1:
			for i in N - 1:
				var h0 := _bh[j * N + i]; var h1 := _bh[j * N + i + 1]
				var h2 := _bh[(j + 1) * N + i + 1]; var h3 := _bh[(j + 1) * N + i]
				var lo := minf(minf(h0, h1), minf(h2, h3)); var hi := maxf(maxf(h0, h1), maxf(h2, h3))
				var lv := ceilf(lo / CI) * CI
				while lv < hi:
					var pts := PackedVector2Array()
					var x := ox + i * STEP; var z := oz + j * STEP
					if (h0 < lv) != (h1 < lv): pts.append(Vector2(x + STEP * (lv - h0) / (h1 - h0), z))
					if (h1 < lv) != (h2 < lv): pts.append(Vector2(x + STEP, z + STEP * (lv - h1) / (h2 - h1)))
					if (h3 < lv) != (h2 < lv): pts.append(Vector2(x + STEP * (lv - h3) / (h2 - h3), z + STEP))
					if (h0 < lv) != (h3 < lv): pts.append(Vector2(x, z + STEP * (lv - h0) / (h3 - h0)))
					var dst := _major if is_equal_approx(fposmod(lv, CI * 5), 0.0) else _minor
					for q in range(0, pts.size() - 1, 2):
						dst.append(pts[q]); dst.append(pts[q + 1])
					lv += CI
	func _draw() -> void:
		var st: BikePhysics = hud.game.phys
		var ink := Color("111417")
		var k := size.x / MAP_M
		var me := Vector2(size.x * 0.5, size.y * 0.66)
		var fw := Vector2(cos(st.heading), -sin(st.heading))   # forward in (x, z)
		var rt := Vector2(-fw.y, fw.x)                         # right in (x, z)
		var org := Vector2(st.x, st.z)
		# world (x, z) -> screen: right = +x on screen, forward = up
		var xa := Vector2(rt.x, -fw.x) * k
		var ya := Vector2(rt.y, -fw.y) * k
		draw_set_transform_matrix(Transform2D(xa, ya, me - (xa * org.x + ya * org.y)))
		var u := 1.0 / k   # one screen pixel in metres
		if _minor.size() > 1: draw_multiline(_minor, Color(0.55, 0.38, 0.2, 0.32), 1.0 * u)
		if _major.size() > 1: draw_multiline(_major, Color(0.55, 0.38, 0.2, 0.6), 1.4 * u)
		var tc = hud.game.terrain.field.course if hud.game.terrain and hud.game.terrain.field else null
		var _ci: int = hud.trail_i
		if tc and tc.n > 1 and _ci >= 0 and _ci < tc.n:
			var reach := int(MAP_M * 1.2 / TrailCourse.STEP)
			var line := PackedVector2Array()
			for i in range(maxi(0, _ci - reach), mini(tc.n, _ci + reach), 2):
				line.append(Vector2(tc.X[i], tc.Z[i]))
			if line.size() > 1:
				draw_polyline(line, Color(1, 1, 1, 0.9), 6.0 * u)
				draw_polyline(line, Color(ink, 0.55), 3.5 * u)
		var th: PackedVector2Array = hud.track_hist
		if th.size() > 1: draw_polyline(th, Color("c2187a"), 2.0 * u)
		draw_set_transform_matrix(Transform2D.IDENTITY)
		# you
		draw_colored_polygon(PackedVector2Array([me + Vector2(0, -8), me + Vector2(6, 6), me + Vector2(0, 2), me + Vector2(-6, 6)]), ink)
		# north (rotates with the map), the scale bar, elevation
		var f := UITheme.lcd_font()
		var nc := Vector2(size.x - 13, 13)
		var nd := Vector2(-rt.y, fw.y).normalized()   # screen direction of world north (-z)
		draw_circle(nc, 9, Color(0.93, 0.93, 0.91, 0.85))
		draw_line(nc - nd * 6, nc + nd * 6, Color(ink, 0.35), 1.5)
		draw_circle(nc + nd * 5, 2.2, Color("e8452c"))
		draw_string(f, nc - nd * 1 + Vector2(-3, 4), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, 8, ink)
		var sb := 50.0 * k
		var sy := size.y - 7
		var x0 := 7.0
		draw_rect(Rect2(x0 - 3, sy - 12, sb + 36, 16), Color(0.93, 0.93, 0.91, 0.75))
		draw_line(Vector2(x0, sy), Vector2(x0 + sb, sy), ink, 1.5)
		draw_line(Vector2(x0, sy - 3), Vector2(x0, sy), ink, 1.5)
		draw_line(Vector2(x0 + sb, sy - 3), Vector2(x0 + sb, sy), ink, 1.5)
		draw_string(f, Vector2(x0 + sb + 4, sy + 1), "50m", HORIZONTAL_ALIGNMENT_LEFT, -1, 8, ink)
		draw_string(f, Vector2(0, sy + 1), "%dm" % roundi(st.y), HORIZONTAL_ALIGNMENT_RIGHT, size.x - 6, 9, ink)

class Overlay extends Control:
	## draws GaugeView.draw_over() on top of the map
	var g
	func _draw() -> void: g.draw_over(self)

class StaminaView extends Control:
	## slim rounded capsule with a bolt icon: the fill ends straight (no rounded end, no edge line), tick marks,
	## a glow while sprinting and a pulse when low (sprint stamina)
	## life = true: the rider's life bar instead (heart icon, red, shakes on a crash)
	var hud
	var life := false
	var shake := 0.0
	var heal := 0.0    # 1 on a revive, fades: the life bar glows green
	var shown := 1.0   # eased fill so it glides instead of jumping

	static func _pill(ci: CanvasItem, r: Rect2, c: Color, square_end := false) -> void:
		UITheme.draw_box(ci, r, c, int(r.size.y * 0.5), Tokens.CLEAR, 0, square_end)

	func _draw() -> void:
		var st: BikePhysics = hud.game.phys
		var val: float = hud.life if life else st.stamina
		var tired := st.tired and not life
		var sprinting := st.sprint > 0.5 and not life
		var low := val < 0.25 and not tired
		var col := Color("ff4d5e") if life else Color("4fd1ff")
		if tired: col = Color("8d979c")
		elif low and not life: col = Color("ff8a2a")
		elif sprinting: col = UITheme.ACCENT
		if heal > 0.0: col = col.lerp(Color("5dff8a"), heal)
		shown = lerpf(shown, val, 0.25 if heal <= 0.0 else 0.06)   # a revive fills up visibly
		var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.012) if low else 1.0
		var h := size.y
		if shake > 0.0:
			draw_set_transform(Vector2(sin(Time.get_ticks_msec() * 0.09) * 4.0 * shake, 0))
		var ix := 8.0
		var cy := h * 0.5
		if life:   # heart icon on the left
			var hc := Color(col, 0.55 + 0.45 * pulse)
			draw_circle(Vector2(ix - 2.6, cy - 1.8), 3.2, hc)
			draw_circle(Vector2(ix + 2.6, cy - 1.8), 3.2, hc)
			draw_colored_polygon(PackedVector2Array([Vector2(ix - 5.6, cy - 0.8), Vector2(ix + 5.6, cy - 0.8), Vector2(ix, cy + 6)]), hc)
		else:   # bolt icon on the left
			var bolt := PackedVector2Array([Vector2(ix + 3, cy - 6), Vector2(ix - 3, cy + 1), Vector2(ix, cy + 1),
				Vector2(ix - 2, cy + 6), Vector2(ix + 4, cy - 1.5), Vector2(ix + 1, cy - 1.5)])
			draw_colored_polygon(bolt, Color(col, 0.55 + 0.45 * pulse))
		# track
		var tr := Rect2(22, 3, size.x - 22, h - 6)
		if heal > 0.0: _pill(self, tr.grow(3 + 3 * heal), Color(0.36, 1.0, 0.54, 0.3 * heal))
		_pill(self, Rect2(tr.position - Vector2(1, 1), tr.size + Vector2(2, 2)), Color(0, 0, 0, 0.55))
		_pill(self, tr, Color(1, 1, 1, 0.10))
		# fill
		var fw := maxf(tr.size.y, tr.size.x * clampf(shown, 0, 1)) if shown > 0.01 else 0.0
		if fw > 0.0:
			if sprinting and not tired:
				_pill(self, Rect2(tr.position - Vector2(2, 2), Vector2(fw + 2, tr.size.y + 4)), Color(col, 0.22), true)
			_pill(self, Rect2(tr.position, Vector2(fw, tr.size.y)), Color(col, 0.55 + 0.45 * pulse), fw < tr.size.x - 0.5)
			# lighter top half for a soft gloss
			_pill(self, Rect2(tr.position + Vector2(1, 1), Vector2(maxf(fw - 1, 2), tr.size.y * 0.4)), Color(1, 1, 1, 0.22), fw < tr.size.x - 0.5)
		# tick marks every 10 %
		for i in range(1, 10):
			var x := tr.position.x + tr.size.x * i / 10.0
			draw_rect(Rect2(x - 0.5, tr.position.y + 1, 1, tr.size.y - 2), Color(0, 0, 0, 0.35))

class GetUpPrompt extends Control:
	## after a crash, bottom centre: "HOLD SPACE TO GET UP" and a thin bar that fills while the hop key
	## is held. Fades in / out.
	var hud
	var a := 0.0
	var k := 0.0
	var t := 0.0
	var held := 0.0
	var key := "Space"

	func tick(dt: float) -> void:
		var st: BikePhysics = hud.game.phys
		t += dt
		var show: bool = st.crash_on and st.crash_t > 0.6 and hud.game.getup_anim == null   # (not once they're getting up)
		k = clampf(st.crash_hold / st.getup_need, 0.0, 1.0) if show else k
		held = move_toward(held, 1.0 if (show and st.crash_hold > 0.0) else 0.0, dt * 12)
		if Env.s("BMX_GETUP_K") != "" and show:   # tests: draw it as if held this far
			k = float(Env.s("BMX_GETUP_K")); held = 1.0
		a = move_toward(a, 1.0 if show else 0.0, dt * (7 if show else 5))
		visible = a > 0.01
		if not visible: return
		key = Settings.prompt("hop")   # "A" on a pad, "Space" on keys
		modulate.a = a
		queue_redraw()

	func _draw() -> void:
		# GTA-like and plain: one line of white text, a thin bar under it that fills while the key is held
		var f := UITheme.font(true)
		var fs := 18
		var y := size.y * 0.5
		var ko: bool = hud.life <= 0.0   # out of life: revive instead of getting up
		var act := "REVIVE" if ko else "GET UP"
		if ko:
			var p := 0.75 + 0.25 * sin(t * 6.0)
			var tl := "KNOCKED OUT"
			var tw0 := f.get_string_size(tl, HORIZONTAL_ALIGNMENT_LEFT, -1, 26).x
			draw_string(f, Vector2((size.x - tw0) * 0.5 + 2, y - 22), tl, HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Color(0, 0, 0, 0.5))
			draw_string(f, Vector2((size.x - tw0) * 0.5, y - 24), tl, HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Color(1, 0.3 * p, 0.28 * p))
		# "HOLD [button] TO GET UP": the button / key drawn as its icon (PadGlyph)
		var g := PadGlyph.glyph_for("hop")
		var gh := 30.0
		var gw := PadGlyph.width(g, gh)
		var l1 := "HOLD"
		var l2 := "TO " + act
		var w1 := f.get_string_size(l1, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var w2 := f.get_string_size(l2, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var x0 := (size.x - (w1 + 12 + gw + 12 + w2)) * 0.5
		for sh in [Vector2(1, 1), Vector2.ZERO]:
			var c := Color(0, 0, 0, 0.45) if sh != Vector2.ZERO else Color.WHITE
			draw_string(f, Vector2(x0, y) + sh, l1, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, c)
			draw_string(f, Vector2(x0 + w1 + 24 + gw, y) + sh, l2, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, c)
		PadGlyph.draw(self, g, Vector2(x0 + w1 + 12 + gw * 0.5, y - 6), gh)
		var bar := Rect2((size.x - 240) * 0.5, y + 14, 240, 5)
		draw_rect(bar, Color(0, 0, 0, 0.45))
		if k > 0.0: draw_rect(Rect2(bar.position, Vector2(bar.size.x * k, bar.size.y)), Color("5dff8a") if ko else Color.WHITE)
		if ko:   # the other way out: back to the start with full life
			var g3 := PadGlyph.glyph_for("respawn")
			var l3 := "BACK TO START"
			var w3 := f.get_string_size(l3, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
			var g3w := PadGlyph.width(g3, 20.0)
			var x3 := (size.x - (g3w + 8 + w3)) * 0.5
			PadGlyph.draw(self, g3, Vector2(x3 + g3w * 0.5, y + 34), 20.0, 0.8)
			draw_string(f, Vector2(x3 + g3w + 8, y + 39), l3, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1, 1, 1, 0.6))

class FlowLeds extends RefCounted:
	## flow on the bike computer's LEDs, kept like real hardware (Wahoo-style): small pinhole LEDs in a
	## recessed slit along the top bezel, one per flow level, all showing the current level's colour;
	## light bleeds softly onto the black plastic. A newly lit LED blinks twice, MAX breathes slowly,
	## while flow drains the last LED blinks. Short side slits = hold time left before it drains.
	const COLS := [Color("2f8cff"), Color("2fe36a"), Color("ffd21a"), Color("ff8a1a"), Color("b04dff")]
	const SIDE := 4
	var level := 0
	var shown := 0.0
	var drain := 0.0       # 1 = losing flow right now
	var hold := 0.0        # 0..1 hold time left
	var t := 0.0
	var new_t := 9.0       # seconds since the last level up (for the double blink)
	var prev_flow := 0.0
	var top_b := PackedFloat32Array()    # per-LED brightness (LEDs switch fast, not instantly)
	var side_b := PackedFloat32Array()

	func tick(st: BikePhysics, dt: float) -> void:
		t += dt
		new_t += dt
		# tests: BMX_FLOW_DEMO=1 adds a flow level every 0.9 s from 3 s until MAX, then lets it drain
		if Env.s("BMX_FLOW_DEMO") != "" and t > 3.0 and fmod(t - 3.0, 0.9) < dt and t < 3.0 + 0.9 * BikePhysics.FLOW_MAX:
			st.flow_up()
		var n := ceili(st.flow - 0.01)
		if n > level and n > 0: new_t = 0.0
		level = n
		shown = st.flow
		var ft: float = st.T.get("flowTime", 4.0)
		hold = clampf(1.0 - st.flow_t / maxf(ft, 0.01), 0.0, 1.0) if n > 0 else 0.0
		drain = 1.0 if st.flow < prev_flow - 1e-4 else move_toward(drain, 0.0, dt * 4)
		prev_flow = st.flow
		var nl := int(BikePhysics.FLOW_MAX)
		if top_b.size() != nl: top_b.resize(nl); side_b.resize(SIDE)
		var on_blink := float(int(t * 4.0) % 2)          # 2 Hz blink
		for i in nl:
			var target := 0.0
			if i < level:
				target = 1.0
				if i == level - 1:
					if new_t < 0.45: target = float(int(new_t / 0.1125) % 2 == 0)   # blink twice
					elif drain > 0.5: target = on_blink * clampf(shown - i, 0.2, 1.0)
				if level >= nl and drain < 0.5: target = 0.72 + 0.28 * (0.5 + 0.5 * sin(t * TAU * 0.6))   # MAX: slow breathe
			top_b[i] = move_toward(top_b[i], target, dt * 30.0)
		for j in SIDE:
			var target := 1.0 if (level > 0 and drain < 0.5 and hold * SIDE > j) else 0.0
			if j == 0 and level > 0 and drain < 0.5 and hold > 0.0 and hold <= 1.0 / SIDE: target = on_blink   # last bit of hold: blink
			side_b[j] = move_toward(side_b[j], target, dt * 30.0)

	func col() -> Color:
		return COLS[clampi(level - 1, 0, COLS.size() - 1)]

	## a dark recessed slit in the bezel
	static func _slit(ci: CanvasItem, r: Rect2) -> void:
		UITheme.draw_box(ci, r, Color("060707"), int(minf(r.size.x, r.size.y) / 2))
		ci.draw_line(Vector2(r.position.x + 2, r.end.y + 0.5), Vector2(r.end.x - 2, r.end.y + 0.5), Color(1, 1, 1, 0.07), 1.0)   # lower lip catching light

	## one small LED: a dim lens when off; lit = hot core, coloured lens, soft bleed on the plastic
	static func _led(ci: CanvasItem, c: Vector2, sz: Vector2, col: Color, k: float) -> void:
		var r := Rect2(c - sz / 2, sz)
		UITheme.draw_box(ci, r, Color(0.10, 0.105, 0.11), 1)
		if k <= 0.01: return
		for g in [[9.0, 0.05], [6.0, 0.09], [3.8, 0.16]]:
			ci.draw_circle(c, g[0], Color(col, g[1] * k))
		UITheme.draw_box(ci, r, Color(col, k), 1)
		ci.draw_rect(Rect2(c - Vector2(sz.x * 0.25, 0.5), Vector2(sz.x * 0.5, 1.0)), Color(col.lerp(Color.WHITE, 0.6), k * 0.9))   # hot core

	func draw(ci: CanvasItem, size: Vector2, scr: Rect2) -> void:
		var c := col()
		var nl := int(BikePhysics.FLOW_MAX)
		if top_b.size() != nl: return
		# top: one slit, LEDs evenly spaced in it
		var sw := size.x * 0.62
		var slit := Rect2(size.x / 2 - sw / 2, 7, sw, 5)
		_slit(ci, slit)
		for i in nl:
			var x := slit.position.x + sw * (i + 0.5) / nl
			_led(ci, Vector2(x, slit.get_center().y), Vector2(6, 2.5), c, top_b[i])
		# sides: a short slit each, LEDs bottom-up
		var sh := 34.0
		for side in 2:
			var sx := 1.5 if side == 0 else size.x - 4.5
			var sr := Rect2(sx, scr.position.y + 22, 3, sh)
			_slit(ci, sr)
			for j in SIDE:
				var y := sr.end.y - sh * (j + 0.5) / SIDE
				_led(ci, Vector2(sr.get_center().x, y), Vector2(1.6, 4.0), c, side_b[j])

class BarView extends Control:
	var k := 0.0
	var always := false
	func _process(_dt: float) -> void: queue_redraw()
	func _draw() -> void:
		var full := k >= 1
		UITheme.draw_box(self, Rect2(Vector2.ZERO, size), Color(0.08, 0.16, 0.2, 0.55), int(size.y / 2), UITheme.ACCENT if full else Color(1, 1, 1, 0.7), 2)
		if k > 0:
			UITheme.draw_box(self, Rect2(Vector2(2, 2), Vector2((size.x - 4) * minf(1, k), size.y - 4)), UITheme.ACCENT, int(size.y / 2))

class AirCard extends Control:
	## live jump counter: distance from the take-off point, height and air time; the result holds for a
	## moment after landing, a new record turns the card gold. Crashing mid-air marks it BAILED.
	const MIN_AIR := 0.25
	const SHOW_AFTER := 0.2
	const HOLD := 2.2
	var hud
	var flying := false
	var hold := 0.0
	var dist := 0.0
	var height := 0.0
	var air := 0.0
	var record := ""
	var bailed := false
	var path := PackedVector2Array()
	var a := 0.0
	var enabled := true
	func takeoff() -> void:
		flying = true; hold = 0; record = ""; bailed = false; path.clear(); dist = 0; height = 0; air = 0
	func land(at: float, d: float, h: float, impact: float) -> void:
		if not flying: return
		flying = false
		if at < MIN_AIR:
			hold = 0; return
		dist = d; height = h; air = at
		hold = HOLD
		var recs := []
		if GameState.submit("longest", d): recs.append("LONGEST")
		if GameState.submit("highest", h): recs.append("HIGHEST")
		if GameState.submit("air", at): recs.append("HANG TIME")
		GameState.records.jumps = int(GameState.records.jumps) + 1
		GameState.records.distance = float(GameState.records.distance) + 0.0
		GameState.save()
		if recs.size() > 0: record = "NEW RECORD · " + " · ".join(recs)
	func bail() -> void:
		if flying and air > SHOW_AFTER:
			bailed = true; hold = HOLD
		flying = false
	func tick(dt: float) -> void:
		var st: BikePhysics = hud.game.phys
		if flying:
			air = st.air_time
			var tk: Vector3 = hud.game.takeoff
			dist = Vector2(st.x - tk.x, st.z - tk.z).length()
			height = maxf(height, st.y - tk.y)
			if path.size() < 200: path.append(Vector2(dist, st.y - tk.y))
		else:
			hold -= dt
		var show := ((flying and air > SHOW_AFTER) or hold > 0) and enabled
		a = move_toward(a, 1.0 if show else 0.0, dt * 6)
		modulate.a = a
		visible = a > 0.01
		if visible: queue_redraw()
	func _draw() -> void:
		# same look as the trail alert banner: dark LCD-ink box, dot-matrix font, white + yellow
		var f := UITheme.lcd_font()
		var yel := Color("ffd21f")
		var dim := Color(1, 1, 1, 0.6)
		var bg := Color(Color("111417"), 0.92)
		var border := Color(1, 1, 1, 0.12)
		if record != "": border = yel
		elif bailed: bg = Color(0.25, 0.04, 0.04, 0.92); border = Color(1, 0.31, 0.27, 0.8)
		UITheme.draw_box(self, Rect2(Vector2.ZERO, size), bg, 12, border, 2)
		var tag := "BAILED" if bailed else ("AIR" if flying else "LANDED")
		draw_string(f, Vector2(14, 22), tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color.WHITE)
		var best := "BEST %.1fm" % float(GameState.records.longest)
		draw_string(f, Vector2(14, 22), best, HORIZONTAL_ALIGNMENT_RIGHT, size.x - 28, 14, dim)
		draw_string(f, Vector2(0, 62), "%.1f" % dist, HORIZONTAL_ALIGNMENT_CENTER, size.x - 30, 34, yel)
		draw_string(f, Vector2(size.x / 2 + 34, 62), "m", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, dim)
		if path.size() > 1:
			var mx := maxf(1.0, path[path.size() - 1].x)
			var my := 0.5
			for p in path: my = maxf(my, absf(p.y))
			var pts := PackedVector2Array()
			for p in path: pts.append(Vector2(14 + (size.x - 28) * p.x / mx, 80 - p.y / my * 10))
			draw_polyline(pts, Color("ff6a5a") if bailed else yel, 2.5, true)
		draw_string(f, Vector2(14, 102), "H %.1fm" % height, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color.WHITE)
		draw_string(f, Vector2(14, 102), "%.2fs" % air, HORIZONTAL_ALIGNMENT_RIGHT, size.x - 28, 16, Color.WHITE)
		if record != "":
			var rw := f.get_string_size(record, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x + 24
			UITheme.draw_box(self, Rect2(size.x / 2 - rw / 2, -11, rw, 22), yel, 8)
			draw_string(f, Vector2(size.x / 2 - rw / 2, 5), record, HORIZONTAL_ALIGNMENT_CENTER, rw, 12, Color("111417"))


## Style points, top left: the ride's STYLE total on top, the latest trick + "+1,250 x2" under it (a combo
## multiplies every landing chained within COMBO_GAP seconds). Points count once the landing holds (BANK s);
## a crash before that drops them ("BAILED") and ends the combo.
## Eye candy: the trick's points roll up from 0, a shine sweeps over them; when they bank a "+N" flies up into
## the total, which then counts up (gold, growing), sparks burst off it and a glow ring pulses out.
class StylePop extends Control:
	const COMBO_GAP := 4.0
	const BANK := 0.7
	const FLY_T := 0.45      # seconds the banked "+N" takes to fly into the total
	const GOLD := Color("ffd21f")
	var total := 0
	var combo := 0
	var since := 99.0      # seconds since the last scored landing
	var label := ""
	var pts := 0
	var pend := 0.0        # time the shown points have been waiting to bank (-1 = banked)
	var bailed := false
	var a := 0.0
	var pop := 0.0
	var roll := 0.0        # the trick's points as shown, rolling up to pts
	var shown := 0.0       # the total as shown, counting up to total
	var tot_pop := 0.0     # the total's bump when points land in it
	var ring := 1.0        # glow ring pulsing out of the total (0..1, 1 = done)
	var combo_pop := 0.0
	var flies := []        # {t, v}: banked points flying into the total
	var sparks := []       # {p, v, life, max, c, s}

	func add(p: int, l: String) -> void:
		combo = combo + 1 if since < COMBO_GAP else 1
		since = 0.0
		pts = p * combo
		label = l
		pend = 0.0
		bailed = false
		roll = 0.0
		a = 1.0; pop = 1.0
		if combo > 1: combo_pop = 1.0
		_burst(Vector2(size.x - 30, 70), 8, Color.WHITE, 120.0)

	func bail() -> void:
		if pend >= 0.0 and pend < BANK and a > 0.0:
			bailed = true; pend = -1.0; a = 1.0; pop = 0.6
		combo = 0; since = 99.0

	func _burst(at: Vector2, n: int, c: Color, speed: float) -> void:
		for i in n:
			var an := randf() * TAU
			var sp := speed * (0.4 + randf() * 0.8)
			var life := 0.45 + randf() * 0.4
			sparks.append({"p": at + Vector2(randf() - 0.5, randf() - 0.5) * 10.0, "v": Vector2(cos(an), sin(an) - 0.6) * sp,
				"life": life, "max": life, "c": c if randf() < 0.7 else Color.WHITE, "s": 1.5 + randf() * 2.5})

	func _total_end() -> float:   # right-aligned: the total ends at the right edge
		return size.x

	func _process(dt: float) -> void:
		since += dt
		if pend >= 0.0:
			pend += dt
			if pend >= BANK:
				pend = -1.0
				flies.append({"t": 0.0, "v": pts})
		# the "+N" lands in the total: it counts up, bumps, sparks fly
		for fl in flies: fl.t += dt
		while flies.size() > 0 and flies[0].t >= FLY_T:
			total += int(flies[0].v)
			flies.pop_front()
			tot_pop = 1.0; ring = 0.0
			_burst(Vector2(_total_end() + 6, 10), 18, GOLD, 170.0)
		if since > COMBO_GAP and not bailed: combo = 0
		# roll the trick's points up (~0.35 s), count the total up (~0.8 s, eased)
		roll = move_toward(roll, pts, maxf(pts * dt / 0.35, 1.0))
		if shown < total:
			shown = minf(total, shown + maxf((total - shown) * dt * 5.0, 60.0 * dt))
		else: shown = total
		pop = maxf(0.0, pop - dt * 4.0)
		tot_pop = maxf(0.0, tot_pop - dt * 2.5)
		combo_pop = maxf(0.0, combo_pop - dt * 3.0)
		ring = minf(1.0, ring + dt * 2.2)
		for sp in sparks:
			sp.life -= dt
			sp.v.y += 260.0 * dt
			sp.v *= 1.0 - 1.5 * dt
			sp.p += sp.v * dt
		sparks = sparks.filter(func(sp): return sp.life > 0.0)
		if since > 2.6 or (bailed and since > 1.6): a = maxf(0.0, a - dt * 2.0)
		queue_redraw()

	static func _num(n: int) -> String:
		var t := str(absi(n))
		var out := ""
		while t.length() > 3:
			out = "," + t.substr(t.length() - 3) + out
			t = t.substr(0, t.length() - 3)
		return t + out

	## a string with a drop shadow, scaled about its left baseline point
	func _txt(f: Font, at: Vector2, t: String, fs: int, c: Color, sc := 1.0) -> void:
		draw_set_transform(at * (1.0 - sc), 0.0, Vector2(sc, sc))
		draw_string(f, at + Vector2(1.5, 1.5), t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0, 0, 0, 0.5 * c.a))
		draw_string(f, at, t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, c)
		draw_set_transform(Vector2.ZERO)

	func _draw() -> void:
		var f := UITheme.font(true)
		var hi := 0.7 + 0.3 * a
		# ---- the total: counts up gold while it's catching up, bumps when points land
		var counting := shown < total - 0.5
		var lab := "STYLE  "
		var lw := f.get_string_size(lab, HORIZONTAL_ALIGNMENT_LEFT, -1, 17).x
		var num := _num(roundi(shown))
		var nw := f.get_string_size(num, HORIZONTAL_ALIGNMENT_LEFT, -1, 17).x
		var o1 := size.x - lw - nw      # each line is right-aligned
		_txt(f, Vector2(o1, 16), lab, 17, Color(1, 1, 1, hi * 0.8))
		lw += o1
		var tc := Color(1, 1, 1, hi).lerp(GOLD, clampf(tot_pop * 1.4 + (0.6 if counting else 0.0), 0, 1))
		var nsc := 1.0 + 0.45 * ease(tot_pop, 0.4)
		if tot_pop > 0.0:   # soft gold glow behind the number
			draw_circle(Vector2(lw + nw * 0.5, 10), (nw * 0.5 + 10) * nsc, Color(GOLD, 0.18 * tot_pop))
		if ring < 1.0:      # a glow ring pulsing out
			draw_arc(Vector2(lw + nw * 0.5, 10), 12 + ring * (nw * 0.5 + 40), 0, TAU, 40, Color(GOLD, 0.6 * (1.0 - ring)), 3.0 * (1.0 - ring) + 1.0, true)
		_txt(f, Vector2(lw - nw * (nsc - 1.0), 16), num, 17, tc, nsc)
		# ---- the banked points flying up into the total
		for fl in flies:
			var k := clampf(fl.t / FLY_T, 0, 1)
			var e := k * k * (3.0 - 2.0 * k)
			var from := Vector2(size.x - 60, 84)
			var to := Vector2(lw + nw * 0.5, 16)
			var pos := from.lerp(to, e) + Vector2(0, -38 * sin(PI * e))   # arcs up and over
			var fs := int(lerpf(30, 15, e))
			var fw := f.get_string_size("+" + _num(int(fl.v)), HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			_txt(f, pos - Vector2(fw * 0.5, 0), "+" + _num(int(fl.v)), fs, Color(GOLD, 1.0 - 0.3 * k))
		# ---- sparks
		for sp in sparks:
			var t: float = sp.life / sp.max
			var c: Color = sp.c
			draw_circle(sp.p, sp.s * (0.5 + 0.5 * t), Color(c, t))
			draw_line(sp.p, sp.p - sp.v * 0.03, Color(c, t * 0.6), sp.s * 0.6)
		if a <= 0.0: return
		# ---- the trick name and its points
		_txt(f, Vector2(size.x - f.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x, 44), label, 20, Color(1, 1, 1, a))
		var big := 34
		var psc := 1.0 + 0.35 * ease(pop, 0.5)
		if bailed:
			var bw := f.get_string_size("BAILED", HORIZONTAL_ALIGNMENT_LEFT, -1, big).x
			_txt(f, Vector2(size.x - bw * psc, 84), "BAILED", big, Color(0.95, 0.3, 0.25, a), psc)
			return
		var banked := pend < 0.0
		# once banked the points leave their spot: the flying copy takes over
		var pa := a
		if banked: pa = a * (1.0 - clampf(flies[flies.size() - 1].t / (FLY_T * 0.3), 0, 1) if flies.size() > 0 else 0.0)
		if pa <= 0.01: return
		var pc := Color(UITheme.ACCENT, pa) if banked else Color(1, 1, 1, pa)
		var pt := "+" + _num(roundi(roll))
		var pw := f.get_string_size(pt, HORIZONTAL_ALIGNMENT_LEFT, -1, big).x * psc
		var cw := 0.0
		if combo > 1: cw = 14.0 + f.get_string_size("x%d" % combo, HORIZONTAL_ALIGNMENT_LEFT, -1, 26).x
		var o3 := size.x - pw - cw
		_txt(f, Vector2(o3, 84), pt, big, pc, psc)
		# a shine sweeping across the number while it rolls up
		if not banked and pend < 0.5:
			var sx := o3 + lerpf(-20, pw + 20, pend / 0.5)
			draw_colored_polygon(PackedVector2Array([Vector2(sx, 54), Vector2(sx + 10, 54), Vector2(sx - 2, 90), Vector2(sx - 12, 90)]), Color(1, 1, 1, 0.35 * pa))
		if combo > 1:   # combo multiplier punches in
			var cs := 1.0 + 0.8 * ease(combo_pop, 0.4)
			var cc := Color(GOLD, pa).lerp(Color(1, 1, 1, pa), combo_pop * 0.6)
			_txt(f, Vector2(o3 + pw + 14, 82), "x%d" % combo, 26, cc, cs)


## A flash message as a little achievement: the same condensed display face as WASTED / the area banner.
## "BERM +2 km/h" -> BERM in warm white, "+2 KM/H" in gold beside it. In: punches down from big with an
## overshoot and a tilt, white-hot, a gold streak shoots out to each side and a shine sweeps over it.
## Out: lifts a little and fades. Plain info lines ("Screenshot saved") come in quieter, smaller.
class MsgView extends Control:
	const T_SHOW := 1.4
	const GOLD := Color("ffc93a")
	const INK := Color(1.0, 0.97, 0.9)
	const CAP_H := 0.068         # cap height, of the screen height (achievements)
	const Y := 0.25              # cap centre, of the screen height
	const Y_LOW := 0.37          # under the area banner while it's up
	var head := ""
	var tail := ""
	var loud := true
	var t := 99.0
	var low := false
	var y_k := 0.0               # eased low / normal
	var font: SystemFont

	func _init() -> void:
		font = UITheme.punch_font(48)   # range 48: room for the dark outline

	func show_msg(text: String) -> void:
		var i := text.find(" +")
		head = text if i < 0 else text.substr(0, i)
		tail = "" if i < 0 else text.substr(i + 1)
		# all caps = something done (BERM, BACKFLIP!, BONK!); mixed case = an info line
		loud = text == text.to_upper()
		head = head.to_upper(); tail = tail.to_upper()
		t = 0.0
		queue_redraw()

	func tick(dt: float) -> void:
		y_k = move_toward(y_k, 1.0 if low else 0.0, dt * 5.0)
		if t < T_SHOW + 0.5:
			t += dt
			queue_redraw()

	static func _back(x: float) -> float:
		var c := 2.2
		x -= 1.0
		return 1.0 + (c + 1.0) * x * x * x + c * x * x

	func _draw() -> void:
		if head == "" or t >= T_SHOW: return
		var fs := 200
		var cap := font.get_ascent(fs) * 0.74
		var sy := size.y * CAP_H * (1.0 if loud else 0.62) / cap
		var sx := sy * 0.86                          # squeezed a little, like the banner
		var tail_k := 0.6                            # the "+2 KM/H" part is smaller
		var gap := fs * 0.22
		var hw := font.get_string_size(head, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var tw := 0.0 if tail == "" else font.get_string_size(tail, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x * tail_k + gap
		var w := hw + tw
		var k := clampf(t / 0.32, 0.0, 1.0)          # in
		var e := _back(k) if loud else k * k * (3.0 - 2.0 * k)
		var out := clampf((t - (T_SHOW - 0.35)) / 0.35, 0.0, 1.0)
		var a := clampf(k * 3.0, 0.0, 1.0) * (1.0 - out)
		var sc := lerpf(1.9 if loud else 1.15, 1.0, e)
		var rot := lerpf(-0.09, 0.0, e) if loud else 0.0
		var hot := clampf(1.0 - (t - 0.1) / 0.35, 0.0, 1.0) if loud else 0.0
		var cy := size.y * lerpf(Y, Y_LOW, y_k) - out * size.y * 0.02
		var c := Vector2(size.x * 0.5, cy)
		var outline := Color(0.08, 0.05, 0.03, 0.75 * a)
		var shadow := Color(0, 0, 0, 0.35 * a)
		var ol := 18
		# gold streaks shooting out to each side as it lands
		if loud:
			var sk := clampf((t - 0.08) / 0.45, 0.0, 1.0)
			if sk > 0.0 and sk < 1.0:
				var se := 1.0 - pow(1.0 - sk, 3.0)
				var half := w * sx * 0.5
				var len := size.x * 0.12 * se
				var th := maxf(2.0, size.y * 0.0035) * (1.0 - sk)
				for sd: float in [-1.0, 1.0]:
					var x0 := c.x + sd * (half + size.x * 0.012 + se * size.x * 0.03)
					draw_line(Vector2(x0, cy), Vector2(x0 + sd * len, cy), Color(GOLD, (1.0 - sk) * a), th, true)
		draw_set_transform(c, rot, Vector2(sx * sc, sy * sc))
		var base := Vector2(-w * 0.5, cap * 0.5)
		var hc := INK.lerp(Color.WHITE, hot)
		hc.a = a
		draw_string_outline(font, base + Vector2(6, 12), head, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, ol, shadow)
		draw_string_outline(font, base, head, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, ol, outline)
		draw_string(font, base, head, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, hc)
		if tail != "":
			var tb := Vector2(base.x + hw + gap, base.y)
			draw_set_transform(c + Vector2(tb.x * sx * sc, tb.y * sy * sc).rotated(rot), rot, Vector2(sx * sc * tail_k, sy * sc * tail_k))
			var gc := GOLD.lerp(Color.WHITE, hot)
			gc.a = a
			draw_string_outline(font, Vector2(6, 12), tail, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, ol, shadow)
			draw_string_outline(font, Vector2.ZERO, tail, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, ol, outline)
			draw_string(font, Vector2.ZERO, tail, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, gc)
		draw_set_transform(Vector2.ZERO)
