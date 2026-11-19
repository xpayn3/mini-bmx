extends CanvasLayer
## In-ride HUD: bike computer (speed / slope / grade / gear / elevation), stamina, flow,
## hop-charge and get-up bars, message flashes, the live jump card with records, FPS.
## Port of gauge.js, airhud.js and the HUD bits of index.html / main.js.

const HIST := 120
const HIST_DT := 0.25

var game
var root := Control.new()
var fps_l: Label
var info_l: Label
var msg_l: Label
var flow_m: FlowMeter
var biome_l: Label
var gauge: GaugeView
var stamina: StaminaView
var hop_bar: BarView
var getup: Control
var getup_bar: BarView
var getup_l: Label
var air_card: AirCard
var records_panel: PanelContainer
var quick: Control
var fps_acc := 0.0
var fps_frames := 0
var msg_a := 0.0
var elev_hist := PackedFloat32Array()
var elev_t := 0.0
var elev_up := 0.0     # metres climbed / descended this ride (bike computer page 2)
var elev_down := 0.0
var track_hist := PackedVector2Array()   # ridden path (x, z) for the map page, same sampling
const TRACK := 360
# ride stats for the bike computer pages
var ride_t := 0.0
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
var trick_last := ""
var trail_i := -1       # nearest trail centreline point
var trail_d := INF      # how far off the trail centreline (m)
var alert := {}         # the next turn / feature on the trail: {kind, text, d}, or empty
var alert_new := 0.0    # seconds left to show a just-appeared alert while it is still far off
const FEAT_NAMES := {"table": "TABLETOP", "tableLine": "JUMP LINE", "kicker": "KICKER", "rhythm": "ROLLERS",
	"flow": "FLOW LINE", "woodKicker": "WOOD KICKER", "bridge": "BRIDGE"}
var hidden := false

func _ready() -> void:
	add_to_group("hud")
	layer = 5
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = UITheme.get_theme()
	add_child(root)
	fps_l = UITheme.label("-- FPS", 13, Color("b9ffb0"))
	fps_l.position = Vector2(20, 14)
	root.add_child(fps_l)
	info_l = UITheme.label("", 14, UITheme.MUTED)
	info_l.position = Vector2(20, 36)
	root.add_child(info_l)
	msg_l = UITheme.label("", 44, Color.WHITE, true)
	msg_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	msg_l.set_anchors_preset(Control.PRESET_TOP_WIDE)
	msg_l.offset_top = 0
	msg_l.add_theme_constant_override("shadow_offset_y", 3)
	msg_l.add_theme_constant_override("outline_size", 8)
	msg_l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.25))
	root.add_child(msg_l)
	biome_l = UITheme.label("", 13, UITheme.MUTED)
	biome_l.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	biome_l.position = Vector2(-240, 38)
	biome_l.size = Vector2(222, 20)
	biome_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	root.add_child(biome_l)
	gauge = GaugeView.new(); gauge.hud = self
	gauge.page = clampi(int(OS.get_environment("BMX_GARMIN_PAGE")), 0, GaugeView.PAGES - 1)
	gauge.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	gauge.size = Vector2(150, 212); gauge.position = Vector2(20, -232)
	root.add_child(gauge)
	stamina = StaminaView.new(); stamina.hud = self
	stamina.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	stamina.size = Vector2(196, 15); stamina.position = Vector2(-214, 20)
	root.add_child(stamina)
	flow_m = FlowMeter.new(); flow_m.hud = self
	flow_m.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	flow_m.size = Vector2(270, 46); flow_m.position = Vector2(-135, -136)
	flow_m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flow_m.visible = false
	root.add_child(flow_m)
	hop_bar = BarView.new()
	hop_bar.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	hop_bar.size = Vector2(180, 12); hop_bar.position = Vector2(-90, -100)
	root.add_child(hop_bar)
	getup = HBoxContainer.new()
	getup.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	getup.size = Vector2(320, 34); getup.position = Vector2(-140, -112)
	getup.add_theme_constant_override("separation", 12)
	getup_bar = BarView.new(); getup_bar.custom_minimum_size = Vector2(92, 30); getup_bar.always = true
	getup_l = UITheme.label("Hold SPACE to get up", 17, Color.WHITE, true)
	getup.add_child(getup_bar); getup.add_child(getup_l)
	getup.visible = false
	root.add_child(getup)
	air_card = AirCard.new(); air_card.hud = self
	air_card.set_anchors_preset(Control.PRESET_CENTER_TOP)
	air_card.size = Vector2(230, 110); air_card.position = Vector2(-115, 14)
	root.add_child(air_card)
	_build_records()
	quick = load("res://scripts/ui/quick_tune.gd").new()
	quick.hud = self
	root.add_child(quick)
	gear_changed()
	apply_settings()
	root.resized.connect(_layout)
	_layout()

func _layout() -> void:
	msg_l.position.y = root.size.y * 0.2

func apply_settings() -> void:
	if fps_l: fps_l.visible = Settings.get_v("show_fps") and not hidden
	if gauge: gauge.visible = Settings.get_v("hud_gauge")
	if gauge: gauge.show_gear = Settings.get_v("hud_gear"); gauge.queue_redraw()
	if air_card: air_card.enabled = Settings.get_v("hud_jump")
	if quick: quick.visible = Settings.get_v("hud_quick") and not _side_open()

func speed_text(ms: float) -> String:
	return "%d" % roundi(absf(ms) * (2.23694 if Settings.get_v("units") == 1 else 3.6))

func speed_unit() -> String:
	return "mph" if Settings.get_v("units") == 1 else "km/h"

func flash(text: String) -> void:
	msg_l.text = text
	msg_a = 1.4

func gear_changed() -> void:
	if gauge: gauge.bump = 1.0; gauge.queue_redraw()

func on_takeoff() -> void:
	air_card.takeoff()

func on_landing(air_time: float, dist: float, height: float, impact: float) -> void:
	air_card.land(air_time, dist, height, impact)
	if air_time > 0.25 and not game.phys.crash_on:
		jumps += 1
		jump_last = Vector3(air_time, dist, height)
		jump_best = Vector3(maxf(jump_best.x, air_time), maxf(jump_best.y, dist), maxf(jump_best.z, height))

func on_trick(trick: String) -> void:
	tricks += 1
	trick_last = trick

func on_crash() -> void:
	air_card.bail()

func _unhandled_input(e: InputEvent) -> void:
	if get_tree().paused: return
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

const SIDE_TABS := {"tune": "ride", "pose": "rider", "look": "look", "ride": "ride", "rider": "rider", "sound": "sound"}

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
	var st: BikePhysics = game.phys
	fps_frames += 1; fps_acc += dt
	if fps_acc > 0.5:
		var fps := fps_frames / fps_acc
		fps_l.text = "%d FPS · %.1f ms" % [roundi(fps), 1000.0 / fps]
		fps_l.add_theme_color_override("font_color", Color("b9ffb0") if fps >= 55 else Color("ffe38a") if fps >= 40 else Color("ff9a8a"))
		fps_frames = 0; fps_acc = 0
	info_l.text = "%s  ·  %s cam  ·  world #%d" % [GameState.BIKES[GameState.bike_id].label, game.cam.preset().label, GameState.seed]
	if msg_a > 0:
		msg_a -= dt
	msg_l.modulate.a = clampf(msg_a / 0.3, 0, 1)
	flow_m.tick(dt)
	hop_bar.visible = st.hop_bar_show
	hop_bar.k = st.hop_bar
	getup.visible = st.crash_on and st.crash_t > 0.6
	if getup.visible:
		getup_bar.k = st.crash_hold / BikePhysics.GETUP_HOLD
		getup_l.text = "Hold %s to get up" % Settings.binding_text("hop", Input.get_connected_joypads().size() > 0 and Input.get_joy_name(0) != "" and false)
	stamina.queue_redraw()
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
		GameState.records.distance += ds
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

## where you are on the trail, and the next turn or feature ahead of you (the Garmin's alerts)
func _trail_watch(st: BikePhysics) -> void:
	if OS.get_environment("BMX_ALERT_PROBE") != "" and ride_t > 1.0 and not _probed:
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
		gauge.light = 3.0   # the screen lights up for a new alert
		alert_new = 3.5

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
	const TITLES := ["RIDE", "TRIP", "EFFORT", "AIR", "ELEV", "MAP"]
	const PAGES := 6
	const MAP_PAGE := 5
	const LCD := Color("eceee8")
	const LCD_LIT := Color("f2fbff")
	const FIX_T := 3.0     # seconds to "find satellites" at the start of a ride
	var map_v: MapView
	var ov: Overlay
	var hud
	var page := 0
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
					page = posmod(page + (-1 if i == 0 else 1), PAGES)
					press[i] = 1.0
					light = 3.0
					queue_redraw()
					accept_event()
					return
	func _draw() -> void:
		var st: BikePhysics = hud.game.phys
		var f := UITheme.lcd_font()
		light = maxf(0.0, light - get_process_delta_time())
		var lk := clampf(light / 0.4, 0, 1)
		lcd = LCD.lerp(LCD_LIT, lk)
		draw_style_box(UITheme.box(Color("16181a"), 16, 0), Rect2(Vector2.ZERO, size))
		scr = Rect2(7, 8, size.x - 14, size.y - 38)
		if lk > 0: draw_style_box(UITheme.box(Color(0.7, 0.88, 1.0, 0.22 * lk), 8, 0), scr.grow(2))
		draw_style_box(UITheme.box(lcd, 6, 0), scr)
		var ink := Color("111417")
		var x0 := scr.position.x + 6
		var w := scr.size.x - 12
		# status bar: clock | page title (AIR when airborne) | battery
		draw_rect(Rect2(scr.position.x, scr.position.y, scr.size.x, 14), ink)
		var tm := Time.get_time_dict_from_system()
		var hy := scr.position.y + 11
		draw_string(f, Vector2(x0, hy), "%02d:%02d" % [tm.hour, tm.minute], HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color("f2f3ef"))
		if st.air: draw_string(f, Vector2(x0, hy), "AIR", HORIZONTAL_ALIGNMENT_CENTER, w, 10, Color("ffd21f"))
		else: draw_string(f, Vector2(x0, hy), TITLES[page], HORIZONTAL_ALIGNMENT_CENTER, w, 9, Color(0.95, 0.95, 0.94, 0.75))
		var bat := clampf(1.0 - hud.ride_t / 3600.0 * 0.6, 0.05, 1.0)   # drains 60 % an hour
		var br := Rect2(scr.end.x - 22, scr.position.y + 4, 14, 7)
		draw_rect(br, Color(0.95, 0.95, 0.94, 0.8), false, 1.0)
		draw_rect(Rect2(br.end.x, br.position.y + 2, 2, 3), Color(0.95, 0.95, 0.94, 0.8))
		draw_rect(Rect2(br.position.x + 1.5, br.position.y + 1.5, (br.size.x - 3) * bat, br.size.y - 3), Color("8be36a") if bat > 0.2 else Color("ff6a4d"))
		map_v.visible = page == MAP_PAGE and hud.ride_t > FIX_T
		match page:
			0: _page_ride(st, f, ink, scr, x0, w)
			1: _page_trip(f, ink, scr, x0, w)
			2: _page_effort(st, f, ink, scr, x0, w)
			3: _page_air(f, ink, scr, x0, w)
			4: _page_elev(st, f, ink, scr, x0, w)
			_: _page_map(st, f, ink, scr, x0, w)
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
			c.draw_style_box(UITheme.box(lcd, 6, 0), inner)
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
		var al: Dictionary = hud.alert
		# pops up when it first appears, then stays from 40 m in (the page shows the rest of the time)
		if al.is_empty() or al.d > 100.0 or (al.d > 40.0 and hud.alert_new <= 0.0): return
		var bx := Rect2(inner.position.x + 3, inner.position.y + 2, inner.size.x - 6, 26)
		c.draw_style_box(UITheme.box(ink, 5, 0), bx)
		var yel := Color("ffd21f")
		var ic := bx.position + Vector2(15, 13)
		var sc := 0.72
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
		c.draw_string(f, Vector2(bx.position.x + 28, bx.position.y + 11), al.text, HORIZONTAL_ALIGNMENT_LEFT, bx.size.x - 32, 8, Color.WHITE)
		c.draw_string(f, Vector2(bx.position.x + 28, bx.position.y + 23), dtx, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, yel)
	## bezel under the screen: a page button left and right, page dots between them
	func _bezel() -> void:
		var dt := get_process_delta_time()
		for i in 2:
			var br := _btn_rect(i)
			var k: float = press[i]
			draw_style_box(UITheme.box(Color("2b2e32").lerp(Color("55595e"), k), 7, 0, Color(1, 1, 1, 0.1), 1), br)
			var c := br.get_center() + Vector2(0, k)
			var s := 1.0 if i == 1 else -1.0
			draw_colored_polygon(PackedVector2Array([c + Vector2(-3 * s, -4), c + Vector2(-3 * s, 4), c + Vector2(3 * s, 0)]), Color("b8bcc0"))
			press[i] = maxf(0.0, k - dt * 5.0)
		for j in PAGES:
			draw_circle(Vector2(size.x / 2 + (j - (PAGES - 1) / 2.0) * 8, size.y - 16), 2.2, Color("d8dbd6") if j == page else Color("3a3d41"))
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
			_gear_row(st, f, ink, x0, y, w)
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
				var q := mini(tc.n - 1, ti + m / 2)
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
	func _gear_row(st: BikePhysics, f: Font, ink: Color, x0: float, y: float, w: float) -> void:
		draw_string(f, Vector2(x0, y + 12), "GEAR", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(ink, 0.6))
		if st.gear < 0:
			draw_string(f, Vector2(x0, y + 33), "1", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, ink)
			draw_string(f, Vector2(x0, y + 31), "SINGLE", HORIZONTAL_ALIGNMENT_RIGHT, w, 10, Color(ink, 0.7))
			return
		var n := st.cogs.size()
		draw_string(f, Vector2(x0, y + 12), "%d/%d" % [st.gear + 1, n], HORIZONTAL_ALIGNMENT_RIGHT, w, 9, Color(ink, 0.6))
		# the gear digit, inverted for a moment after a shift
		var d := str(st.gear + 1)
		if bump > 0.05:
			draw_rect(Rect2(x0 - 2, y + 16, 26, 20), Color(ink, clampf(bump * 1.5, 0, 1)))
		var dc := ink.lerp(Color("eceee8"), clampf(bump * 1.5, 0, 1))
		draw_string(f, Vector2(x0, y + 33), d, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, dc)
		# cassette: biggest cog on the left, between the digit and the teeth count
		var tw := 30.0
		var cx := x0 + 28.0
		var span := w - 28.0 - tw - 4.0
		var step := minf(7.0, span / maxf(1.0, n))
		cx += (span - step * n) * 0.5
		var mid := y + 26.0
		draw_line(Vector2(cx - 2, mid), Vector2(cx + step * n, mid), Color(ink, 0.25), 1)
		var big: float = st.cogs[n - 1]
		for j in n:
			var gi: int = n - 1 - j
			var on := gi == st.gear
			var hgt: float = st.cogs[gi] / big * 20.0
			var bw := step - 2.0 if on else step - 3.0
			draw_rect(Rect2(cx + j * step, mid - hgt / 2, maxf(1.5, bw), hgt), ink if on else Color(ink, 0.3))
			if on:
				var px := cx + j * step + bw / 2
				draw_colored_polygon(PackedVector2Array([Vector2(px - 3, mid - hgt / 2 - 6), Vector2(px + 3, mid - hgt / 2 - 6), Vector2(px, mid - hgt / 2 - 2)]), ink)
		draw_string(f, Vector2(x0, y + 33), "%dT" % st.cogs[st.gear], HORIZONTAL_ALIGNMENT_RIGHT, w, 12, ink)

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
	## ten flat blocks, the last part-filled (sprint stamina)
	var hud
	var shake := 0.0
	func _draw() -> void:
		var st: BikePhysics = hud.game.phys
		var sprinting := st.sprint > 0.5
		var col := Color("4fd1ff")
		if st.tired: col = Color("8d979c")
		elif st.stamina < 0.25: col = Color("ff8a2a")
		elif sprinting: col = UITheme.ACCENT
		draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.45))
		for i in 10:
			var r := Rect2(3 + i * 19, 3, 16, 9)
			draw_rect(r, Color(1, 1, 1, 0.14))
			var k := clampf(st.stamina * 10 - i, 0, 1)
			if k > 0: draw_rect(Rect2(r.position, Vector2(16 * k, 9)), col)

class FlowMeter extends Control:
	## flow combo: slanted segments that fill and recolour by level, a pop + sparks + "+1" on every level
	## up, a hold strip showing how long until the flow drains (red flash while braking it away),
	## a shimmer at MAX. Slides / fades in when flow starts, out when it is gone.
	const COLS := [Color("4fd1ff"), Color("5cf0a0"), Color("ffd21f"), Color("ff9a2a"), Color("ff4fb4")]
	var hud
	var a := 0.0           # fade
	var shown := 0.0       # displayed fill (smoothed)
	var level := 0
	var pop := 0.0         # 1 right after a level up, decays
	var drain_flash := 0.0
	var t := 0.0
	var prev_flow := 0.0
	var sparks: Array = []  # [pos, vel, life, col]
	var floats: Array = []  # [text, y, life]

	func tick(dt: float) -> void:
		var st: BikePhysics = hud.game.phys
		t += dt
		# tests: BMX_FLOW_DEMO=1 adds a flow level every 0.9 s from 3 s until MAX, then lets it drain
		if OS.get_environment("BMX_FLOW_DEMO") != "" and t > 3.0 and fmod(t - 3.0, 0.9) < dt and t < 3.0 + 0.9 * BikePhysics.FLOW_MAX:
			st.flow_up()
		var n := ceili(st.flow - 0.01)
		if n > level and n > 0:
			pop = 1.0
			var seg := _seg_rect(n - 1)
			var c: Color = COLS[n - 1]
			for i in 14:
				var ang := randf() * TAU
				sparks.append([seg.get_center(), Vector2(cos(ang), sin(ang) * 0.7) * randf_range(60, 170), randf_range(0.35, 0.6), c])
			floats.append(["MAX FLOW!" if n >= int(BikePhysics.FLOW_MAX) else "+1", 0.0, 0.9])
		level = n
		shown = lerpf(shown, st.flow, minf(1.0, dt * 14))
		# losing flow before the hold time is up = braking it away
		var ft: float = st.T.get("flowTime", 4.0)
		var braking: bool = st.flow < prev_flow - 1e-4 and st.flow_t < ft
		prev_flow = st.flow
		drain_flash = move_toward(drain_flash, 1.0 if braking else 0.0, dt * 8)
		pop = maxf(0.0, pop - dt * 3.2)
		for s in sparks:
			s[0] += s[1] * dt; s[1] *= 1.0 - dt * 4.0; s[1].y += 140 * dt; s[2] -= dt
		sparks = sparks.filter(func(s): return s[2] > 0)
		for f in floats:
			f[1] += dt * 46; f[2] -= dt
		floats = floats.filter(func(f): return f[2] > 0)
		a = move_toward(a, 1.0 if n > 0 else 0.0, dt * (5 if n > 0 else 2.5))
		visible = a > 0.01 or not sparks.is_empty()
		modulate.a = a
		pivot_offset = size / 2
		var e := pop * pop
		scale = Vector2.ONE * (1.0 + 0.16 * e) * (0.92 + 0.08 * a)
		offset_top = -136.0 + (1.0 - a) * 14.0   # anchored to the bottom centre: slide up as it fades in
		offset_bottom = offset_top + 46.0
		if visible: queue_redraw()

	func _col() -> Color:
		return COLS[clampi(level - 1, 0, COLS.size() - 1)]

	## segment i as a slanted bar (its bounding rect)
	func _seg_rect(i: int) -> Rect2:
		var x0 := 92.0; var w := (size.x - x0 - 16) / BikePhysics.FLOW_MAX
		return Rect2(x0 + i * w, 12, w - 6, 18)

	func _slant(r: Rect2, k: float) -> PackedVector2Array:
		var sk := 6.0
		var x1 := r.position.x + (r.size.x) * k
		return PackedVector2Array([Vector2(r.position.x + sk, r.position.y), Vector2(x1 + sk, r.position.y),
			Vector2(x1, r.end.y), Vector2(r.position.x, r.end.y)])

	func _draw() -> void:
		var st: BikePhysics = hud.game.phys
		var f := UITheme.font(true)
		var c := _col()
		var mx := level >= int(BikePhysics.FLOW_MAX)
		var red := Color(1, 0.3, 0.25)
		var bord := c.lerp(red, drain_flash)
		bord.a = 0.35 + 0.5 * pop + (0.25 * (0.5 + 0.5 * sin(t * 8.0)) if mx else 0.0)
		draw_style_box(UITheme.box(Color(0.055, 0.094, 0.12, 0.8), int(size.y / 2), 0, bord, 2), Rect2(Vector2.ZERO, size))
		# glow behind the panel at high flow
		if level >= 3:
			var g := c; g.a = 0.10 + 0.06 * sin(t * 6.0) + 0.25 * pop
			draw_style_box(UITheme.box(Color(0, 0, 0, 0), int(size.y / 2) + 4, 0, g, 4), Rect2(Vector2(-4, -4), size + Vector2(8, 8)))
		# label + multiplier
		draw_string(f, Vector2(16, 19), "FLOW", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, UITheme.MUTED)
		var mc := c.lerp(Color.WHITE, pop * 0.7)
		draw_string(f, Vector2(15, 41), "×%d" % maxi(level, 1), HORIZONTAL_ALIGNMENT_LEFT, -1, int(22 + 6 * pop), mc)
		# segments
		for i in int(BikePhysics.FLOW_MAX):
			var r := _seg_rect(i)
			draw_colored_polygon(_slant(r, 1.0), Color(1, 1, 1, 0.09))
			var k := clampf(shown - i, 0.0, 1.0)
			if k <= 0.0: continue
			var sc := c
			if i == level - 1: sc = sc.lerp(Color.WHITE, pop * 0.8)
			sc = sc.lerp(red, drain_flash * 0.6)
			# glow under the filled part
			var gl := sc; gl.a = 0.28
			draw_colored_polygon(_slant(r.grow(2.5), k), gl)
			draw_colored_polygon(_slant(r, k), sc)
			# top highlight
			var hl := Color(1, 1, 1, 0.35)
			draw_line(Vector2(r.position.x + 6, r.position.y + 1.5), Vector2(r.position.x + 6 + (r.size.x - 2) * k, r.position.y + 1.5), hl, 1.5)
		# shimmer sweeping across at MAX
		if mx:
			var x0 := 92.0; var span := size.x - x0 - 16
			var sx := x0 + fmod(t * 160.0, span + 120.0)   # sweep, then a short pause off the end
			for j in (3 if sx < x0 + span - 24.0 else 0):
				var w := 10.0 - j * 3.0
				draw_colored_polygon(PackedVector2Array([Vector2(sx + j * 4 + 6, 12), Vector2(sx + j * 4 + 6 + w, 12),
					Vector2(sx + j * 4 + w, 30), Vector2(sx + j * 4, 30)]), Color(1, 1, 1, 0.22 - j * 0.06))
		# hold strip: time until the flow starts to drain
		var ft: float = st.T.get("flowTime", 4.0)
		var hold := clampf(1.0 - st.flow_t / maxf(ft, 0.01), 0.0, 1.0) if level > 0 else 0.0
		var hr := Rect2(92, 35, size.x - 92 - 22, 4)
		draw_rect(hr, Color(1, 1, 1, 0.08))
		var hc := c if hold > 0.25 else c.lerp(red, 0.5 + 0.5 * sin(t * 14.0))
		hc = hc.lerp(red, drain_flash)
		draw_rect(Rect2(hr.position, Vector2(hr.size.x * hold, hr.size.y)), hc)
		if hold <= 0.0 and level > 0:
			draw_string(f, Vector2(hr.end.x - 60, hr.position.y - 1), "DRAINING", HORIZONTAL_ALIGNMENT_RIGHT, 60, 8, red)
		# sparks + floating "+1"
		for s in sparks:
			var sp: Color = s[3]; sp.a = clampf(s[2] / 0.4, 0, 1)
			draw_line(s[0], s[0] - (s[1] as Vector2) * 0.04, sp, 2.0, true)
		for fl in floats:
			var fa := clampf(fl[2] / 0.4, 0, 1)
			var fc := c; fc.a = fa
			var fs := int(20 + 8 * clampf((fl[2] - 0.7) / 0.2, 0, 1))   # starts big, settles
			draw_string_outline(f, Vector2(0, -6 - fl[1]), fl[0], HORIZONTAL_ALIGNMENT_CENTER, size.x, fs, 5, Color(0, 0, 0, 0.55 * fa))
			draw_string(f, Vector2(0, -6 - fl[1]), fl[0], HORIZONTAL_ALIGNMENT_CENTER, size.x, fs, fc)

class BarView extends Control:
	var k := 0.0
	var always := false
	func _process(_dt: float) -> void: queue_redraw()
	func _draw() -> void:
		var full := k >= 1
		draw_style_box(UITheme.box(Color(0.08, 0.16, 0.2, 0.55), int(size.y / 2), 0, UITheme.ACCENT if full else Color(1, 1, 1, 0.7), 2), Rect2(Vector2.ZERO, size))
		if k > 0:
			draw_style_box(UITheme.box(UITheme.ACCENT, int(size.y / 2), 0), Rect2(Vector2(2, 2), Vector2((size.x - 4) * minf(1, k), size.y - 4)))

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
		var f := UITheme.font(true)
		var bg := Color(0.055, 0.094, 0.12, 0.78)
		var border := Color(1, 1, 1, 0.1)
		if record != "": bg = Color(0.42, 0.28, 0.0, 0.85); border = Color("ffcf3a")
		elif bailed: bg = Color(0.31, 0.05, 0.05, 0.8); border = Color(1, 0.31, 0.27, 0.8)
		draw_style_box(UITheme.box(bg, 18, 0, border, 2), Rect2(Vector2.ZERO, size))
		var tag := "BAILED" if bailed else ("AIR" if flying else "LANDED")
		draw_string(f, Vector2(14, 18), tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, UITheme.MUTED)
		var best := "best %.1f m" % float(GameState.records.longest)
		draw_string(f, Vector2(14, 18), best, HORIZONTAL_ALIGNMENT_RIGHT, size.x - 28, 10, UITheme.MUTED)
		draw_string(f, Vector2(0, 58), "%.1f" % dist, HORIZONTAL_ALIGNMENT_CENTER, size.x - 30, 38, UITheme.ACCENT if record != "" else Color.WHITE)
		draw_string(f, Vector2(size.x / 2 + 30, 58), "m", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, UITheme.MUTED)
		if path.size() > 1:
			var mx := maxf(1.0, path[path.size() - 1].x)
			var my := 0.5
			for p in path: my = maxf(my, absf(p.y))
			var pts := PackedVector2Array()
			for p in path: pts.append(Vector2(14 + (size.x - 28) * p.x / mx, 76 - p.y / my * 10))
			draw_polyline(pts, Color("ff6a5a") if bailed else UITheme.ACCENT, 2.5, true)
		draw_string(f, Vector2(14, 100), "↑ %.1f m" % height, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color.WHITE)
		draw_string(f, Vector2(14, 100), "%.2f s" % air, HORIZONTAL_ALIGNMENT_RIGHT, size.x - 28, 12, Color.WHITE)
		if record != "":
			var rw := f.get_string_size(record, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x + 24
			draw_style_box(UITheme.box(Color("ffc21a"), 10, 0), Rect2(size.x / 2 - rw / 2, -10, rw, 20))
			draw_string(f, Vector2(size.x / 2 - rw / 2, 4), record, HORIZONTAL_ALIGNMENT_CENTER, rw, 10, Color("3a2400"))
