extends CanvasLayer
## In-ride HUD: bike computer (speed / slope / grade / elevation), gear shifter, stamina, flow,
## hop-charge and get-up bars, message flashes, the live jump card with records, FPS.
## Port of gauge.js, airhud.js and the HUD bits of index.html / main.js.

const HIST := 120
const HIST_DT := 0.25

var game
var root := Control.new()
var fps_l: Label
var info_l: Label
var msg_l: Label
var flow_l: Label
var biome_l: Label
var gauge: GaugeView
var gear_v: GearView
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
	gauge.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	gauge.size = Vector2(150, 222); gauge.position = Vector2(20, -242)
	root.add_child(gauge)
	gear_v = GearView.new(); gear_v.hud = self
	gear_v.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	root.add_child(gear_v)
	stamina = StaminaView.new(); stamina.hud = self
	stamina.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	stamina.size = Vector2(196, 15); stamina.position = Vector2(-214, 20)
	root.add_child(stamina)
	flow_l = UITheme.label("", 14, Color.WHITE, true)
	flow_l.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	flow_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	flow_l.size = Vector2(240, 24); flow_l.position = Vector2(-120, -122)
	root.add_child(flow_l)
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
	if gear_v: gear_v.visible = Settings.get_v("hud_gear")
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
	if gear_v: gear_v.bump = 1.0; gear_v.queue_redraw()

func on_takeoff() -> void:
	air_card.takeoff()

func on_landing(air_time: float, dist: float, height: float, impact: float) -> void:
	air_card.land(air_time, dist, height, impact)

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

const SIDE_TABS := {"tune": "ride", "pose": "rider", "look": "look", "ride": "ride", "rider": "rider"}

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
	info_l.text = "%s  ·  %s cam  ·  world #%d" % [GameState.BIKES[GameState.bike_id].label, CameraRig.PRESETS[game.cam.mode].label, GameState.seed]
	if msg_a > 0:
		msg_a -= dt
	msg_l.modulate.a = clampf(msg_a / 0.3, 0, 1)
	var n := ceili(st.flow - 0.01)
	flow_l.visible = n > 0
	flow_l.text = "FLOW  " + "●".repeat(n) + "○".repeat(int(BikePhysics.FLOW_MAX) - n)
	hop_bar.visible = st.hop_bar_show
	hop_bar.k = st.hop_bar
	getup.visible = st.crash_on and st.crash_t > 0.6
	if getup.visible:
		getup_bar.k = st.crash_hold / BikePhysics.GETUP_HOLD
		getup_l.text = "Hold %s to get up" % Settings.binding_text("hop", Input.get_connected_joypads().size() > 0 and Input.get_joy_name(0) != "" and false)
	stamina.queue_redraw()
	gear_v.bump = maxf(0.0, gear_v.bump - dt * 4)
	gear_v.queue_redraw()
	# elevation profile
	elev_t += dt
	if elev_t >= HIST_DT:
		elev_t = 0
		elev_hist.append(st.y)
		if elev_hist.size() > HIST: elev_hist.remove_at(0)
	gauge.queue_redraw()
	air_card.tick(dt)
	biome_l.text = game.biome_cur
	if st.crash_on: GameState.records.distance = GameState.records.distance   # (kept: saved on landing / menu)

# ======================================================================
class GaugeView extends Control:
	## a compact GPS bike computer: black body, pale LCD
	var hud
	func _draw() -> void:
		var st: BikePhysics = hud.game.phys
		var f := UITheme.font(true)
		var r := Rect2(Vector2.ZERO, size)
		draw_style_box(UITheme.box(Color("16181a"), 16, 0), r)
		var scr := Rect2(7, 8, size.x - 14, size.y - 26)
		draw_style_box(UITheme.box(Color("eceee8"), 6, 0), scr)
		var ink := Color("111417")
		var x0 := scr.position.x + 6
		var w := scr.size.x - 12
		draw_rect(Rect2(scr.position.x, scr.position.y, scr.size.x, 14), ink)
		var tm := Time.get_time_dict_from_system()
		draw_string(f, Vector2(x0, scr.position.y + 11), "%02d:%02d" % [tm.hour, tm.minute], HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color("f2f3ef"))
		if st.air:
			draw_string(f, Vector2(x0, scr.position.y + 11), "AIR", HORIZONTAL_ALIGNMENT_RIGHT, w, 10, Color("ffd21f"))
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
		draw_line(Vector2(scr.position.x, y), Vector2(scr.end.x, y), Color(ink, 0.22))
		draw_string(f, Vector2(x0, y + 12), "ELEV", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(ink, 0.6))
		draw_string(f, Vector2(x0, y + 12), "%d m" % roundi(st.y), HORIZONTAL_ALIGNMENT_RIGHT, w, 10, ink)
		var hist: PackedFloat32Array = hud.elev_hist
		if hist.size() > 1:
			var lo: float = hist[0]
			var hi: float = hist[0]
			for e in hist:
				lo = minf(lo, e); hi = maxf(hi, e)
			hi = maxf(hi, lo + 2)
			var gh := scr.end.y - y - 20
			var pts := PackedVector2Array()
			pts.append(Vector2(x0, scr.end.y - 4))
			for i in hist.size():
				pts.append(Vector2(x0 + w * i / float(HIST - 1), scr.end.y - 4 - (hist[i] - lo) / (hi - lo) * gh))
			pts.append(Vector2(x0 + w * (hist.size() - 1) / float(HIST - 1), scr.end.y - 4))
			draw_colored_polygon(pts, Color(0.18, 0.7, 0.29, 0.55))
		draw_circle(Vector2(26, size.y - 9), 3, Color("3a3d41"))
		draw_circle(Vector2(size.x - 26, size.y - 9), 3, Color("3a3d41"))

class GearView extends Control:
	## Q | GEAR n | the cassette side-on with the chain on the lit cog | teeth | E
	var hud
	var bump := 0.0
	func _draw() -> void:
		var st: BikePhysics = hud.game.phys
		var f := UITheme.font(true)
		var n := st.cogs.size()
		var w := 300.0 + n * 12.0 if st.gear >= 0 else 200.0
		# anchored to the bottom centre: offsets, not position (position is from the parent's corner)
		if not is_equal_approx(offset_right - offset_left, w):
			offset_left = -w / 2; offset_right = w / 2; offset_top = -66; offset_bottom = -12
		draw_style_box(UITheme.box(Color(0.08, 0.15, 0.2, 0.72), 18, 0, Color(1, 1, 1, 0.14), 1), Rect2(Vector2.ZERO, size))
		if st.gear < 0:
			draw_string(f, Vector2(18, 16), "GEAR", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, UITheme.MUTED)
			draw_string(f, Vector2(18, 44), "1", HORIZONTAL_ALIGNMENT_LEFT, -1, 30, UITheme.ACCENT)
			draw_string(f, Vector2(60, 34), "single speed", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, UITheme.MUTED)
			return
		var kq := Settings.binding_text("gear_easier", false)
		var ke := Settings.binding_text("gear_harder", false)
		_key(Vector2(14, 8), kq, "easier", f)
		_key(Vector2(w - 50, 8), ke, "harder", f)
		draw_string(f, Vector2(66, 16), "GEAR", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, UITheme.MUTED)
		draw_string(f, Vector2(66, 46), str(st.gear + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, int(32 + bump * 10), UITheme.ACCENT)
		# cassette: biggest cog on the left
		var cx := 112.0
		draw_line(Vector2(cx - 4, 27), Vector2(cx + n * 12, 27), Color(1, 1, 1, 0.12), 2)
		var big: float = st.cogs[n - 1]
		for j in n:
			var gi: int = n - 1 - j
			var teeth: int = st.cogs[gi]
			var hgt := teeth / big * 40.0
			var on := gi == st.gear
			var rr := Rect2(cx + j * 12, 27 - hgt / 2, 7.5 if on else 6.0, hgt)
			draw_style_box(UITheme.box(UITheme.ACCENT if on else Color("737d83"), 3, 0), rr)
			if on:
				draw_colored_polygon(PackedVector2Array([Vector2(rr.position.x - 1, rr.position.y - 9), Vector2(rr.end.x + 1, rr.position.y - 9), Vector2(rr.position.x + rr.size.x / 2, rr.position.y - 3)]), UITheme.ACCENT)
		draw_string(f, Vector2(cx + n * 12 + 8, 30), str(st.cogs[st.gear]), HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color.WHITE)
		draw_string(f, Vector2(cx + n * 12 + 8, 44), "teeth", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, UITheme.MUTED)
	func _key(p: Vector2, k: String, sub: String, f: Font) -> void:
		draw_style_box(UITheme.box(Color(1, 1, 1, 0.1), 8, 0, Color(1, 1, 1, 0.45), 1), Rect2(p + Vector2(4, 0), Vector2(30, 26)))
		draw_string(f, p + Vector2(4, 19), k.substr(0, 3), HORIZONTAL_ALIGNMENT_CENTER, 30, 14, Color.WHITE)
		draw_string(f, p + Vector2(0, 40), sub, HORIZONTAL_ALIGNMENT_CENTER, 38, 9, UITheme.MUTED)

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
