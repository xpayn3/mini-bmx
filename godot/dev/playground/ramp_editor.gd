class_name RampEditor
extends PanelContainer
## The test playground's ramp editor (dev view > RAMPS, or K... no key: the LAB row's RAMPS button): put down jumps
## made by JumpDesign anywhere on the playground, move them (MOVE, then the mouse; the wheel turns it; click drops it),
## change every number of the recipe with sliders and see the result at once: the ramp's ground is rebuilt, the side
## view shows the shape with where riders at 85 / 100 / 115 % of the design speed fly and land, and the readout gives
## the lip radius + g, straight lip, deck / gap, landing angle and each landing's EFH. RIDE sends the test rider over
## it on repeat (at the design speed; "auto" on the RIDER row learns the speed that lands on the spot).
## Ramps are saved to user://playground/ramps.json (PlaygroundCourse.RAMP_FILE) and come back next time.
## Tests: BMX_PG_RAMP_ADD=1 puts one down 40 m ahead of the start if there is none; BMX_PG_RAMP_SET=key=val,...
## sets the selected ramp's numbers; BMX_PG_RAMP_RIDE=1 rides it.

const ROWS := [
	# key, label, min, max, step, unit / format, hint
	["v", "Design speed", 15.0, 70.0, 1.0, "km/h", "run-in speed at the foot of the face: everything is sized for it"],
	["lip_deg", "Lip angle", 8.0, 50.0, 1.0, "°", "take-off angle (the straight lip's)"],
	["lip_g", "Take-off g", 0.6, 3.5, 0.05, "g", "most g the curve puts on the rider at the design speed (1.5 = comfortable): sets the radius"],
	["lip_t", "Straight lip", 0.0, 0.5, 0.01, "s", "straight lip, seconds at the lip speed (0.25-0.30: both wheels leave on one line)"],
	["height", "Lip height", 0.0, 6.0, 0.05, "m", "0 = what the curve + lip give; else this height (the radius follows, watch the g)"],
	["deck", "Deck / gap", 0.0, 30.0, 0.25, "m", "lip to the landing's knuckle; 0 = auto: as long as the flight"],
	["land_h", "Landing height", 0.0, 6.0, 0.05, "m", "gap: the landing's knuckle height (0 = the lip's)"],
	["land_deg", "Landing angle", 0.0, 50.0, 1.0, "°", "0 = auto: matched to the flight where it comes down"],
	["aim", "Aim on landing", 0.0, 1.0, 0.05, "", "where on the landing slope the design speed comes down (0 knuckle .. 1 bottom)"],
	["land_g", "Landing g", 1.0, 5.0, 0.1, "g", "most g in the landing's bottom transition (sets its radius)"],
	["knuckle_r", "Knuckle radius", 0.3, 6.0, 0.1, "m", "how round the deck's edge into the landing is"],
	["width", "Width", 1.0, 8.0, 0.25, "m", "riding width of the top"],
	["yaw", "Heading", -180.0, 180.0, 1.0, "°", "which way it faces (0 = along the lanes, +x)"],
]

var game
var diag
var course: PlaygroundCourse
var terrain
var sel: PlaygroundCourse.PlacedRamp = null
var moving := false
var _pick: OptionButton
var _kind: OptionButton
var _build: OptionButton
var _move_b: Button
var _sliders := {}
var _vals := {}
var _view: Control
var _info: Label
var _dirty := false
var _dirty_t := 0.0
var _save_t := -1.0
var _quiet := false


func setup(g, d) -> void:
	game = g; diag = d
	terrain = g.terrain; course = terrain.course
	theme = RideDiag._dev_theme()
	var sb := StyleBoxFlat.new(); sb.bg_color = Color(0.07, 0.08, 0.1, 0.92)
	sb.content_margin_left = 8; sb.content_margin_right = 8; sb.content_margin_top = 6; sb.content_margin_bottom = 6
	add_theme_stylebox_override("panel", sb)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 3)
	add_child(vb)
	var head := HBoxContainer.new()
	vb.add_child(head)
	var t := Label.new(); t.text = "RAMPS"; t.add_theme_color_override("font_color", Color(1.0, 0.88, 0.3))
	head.add_child(t)
	_pick = OptionButton.new()
	_pick.focus_mode = Control.FOCUS_NONE
	_pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_pick.fit_to_longest_item = false
	_pick.item_selected.connect(func(i): _select(course.ramps[i] if i < course.ramps.size() else null))
	head.add_child(_pick)
	diag._dev_btn(head, "+ ADD", add_ramp, "a new ramp 35 m ahead of the rider, facing his way")
	diag._dev_btn(head, "DEL", del_ramp, "remove the selected ramp")
	_move_b = diag._dev_btn(head, "MOVE", func(): moving = _move_b.button_pressed, "move it with the mouse (its lip follows), the wheel turns it, click drops it", true)
	diag._dev_btn(head, "RIDE", ride, "the test rider rides it on repeat")
	diag._dev_btn(head, "✕", func(): visible = false, "close (RAMPS on the LAB row opens it)")
	var kr := HBoxContainer.new()
	vb.add_child(kr)
	var kl := Label.new(); kl.text = "Kind"; kl.custom_minimum_size = Vector2(104, 0); kr.add_child(kl)
	_kind = OptionButton.new()
	_kind.focus_mode = Control.FOCUS_NONE
	_kind.add_item("TABLE (deck)"); _kind.add_item("GAP (open)"); _kind.add_item("KICKER (to flat)")
	_kind.item_selected.connect(func(i): _setp("kind", ["table", "gap", "kicker"][i]))
	kr.add_child(_kind)
	_build = OptionButton.new()
	_build.focus_mode = Control.FOCUS_NONE
	_build.add_item("DIRT"); _build.add_item("WOOD")
	_build.item_selected.connect(func(i): _setp("build", "wood" if i == 1 else "dirt"))
	kr.add_child(_build)
	diag._dev_btn(kr, "reset numbers", func(): _reset_numbers(), "back to the recipe's defaults (keeps where it is)")
	var grid := GridContainer.new()
	grid.columns = 6
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 1)
	vb.add_child(grid)
	for row in ROWS:
		var lb := Label.new(); lb.text = row[1]; lb.tooltip_text = row[6]; lb.custom_minimum_size = Vector2(92, 0)
		lb.mouse_filter = Control.MOUSE_FILTER_PASS
		grid.add_child(lb)
		var s := HSlider.new()
		s.min_value = row[2]; s.max_value = row[3]; s.step = row[4]
		s.custom_minimum_size = Vector2(96, 16)
		s.focus_mode = Control.FOCUS_NONE
		s.scrollable = false
		s.tooltip_text = row[6]
		var key: String = row[0]
		s.value_changed.connect(func(v): _on_slider(key, v))
		grid.add_child(s)
		var vl := Label.new(); vl.custom_minimum_size = Vector2(76, 0)
		grid.add_child(vl)
		_sliders[key] = s; _vals[key] = vl
	_view = Control.new()
	_view.custom_minimum_size = Vector2(0, 120)
	_view.draw.connect(_draw_view)
	vb.add_child(_view)
	_info = Label.new()
	_info.add_theme_font_size_override("font_size", 11)
	_info.add_theme_color_override("font_color", Color(0.8, 0.86, 0.92))
	vb.add_child(_info)
	_refresh_pick()
	_select(course.ramps[0] if not course.ramps.is_empty() else null)
	if Env.s("BMX_PG_RAMP_ADD") != "" and course.ramps.is_empty(): _add_at_start.call_deferred()
	if Env.s("BMX_PG_RAMP_SET") != "": _apply_env.call_deferred()
	if Env.s("BMX_PG_RAMP_RIDE") != "": ride.call_deferred()


func _add_at_start() -> void:
	var sp: Vector3 = terrain.level_spawn()
	var r := course.add_ramp({}, Vector2(sp.x - 120.0, sp.z + 30.0), 0.0)
	terrain.refresh_ramp(r)
	_refresh_pick(); _select(r)
	print("RAMPED add %s at %.1f,%.1f %s" % [r.id, r.pos.x, r.pos.y, JumpDesign.describe(r.d)])


func _apply_env() -> void:
	if sel == null: return
	for kv in Env.s("BMX_PG_RAMP_SET").split(","):
		var p := kv.split("=")
		if p.size() != 2: continue
		if p[0] == "kind" or p[0] == "build": sel.prm[p[0]] = p[1]
		elif p[0] == "yaw": sel.yaw = deg_to_rad(float(p[1]))
		elif p[0] == "v": sel.prm.v = float(p[1]) / 3.6
		else: sel.prm[p[0]] = float(p[1])
	_rebuild_now()
	_select(sel)


func _refresh_pick() -> void:
	_pick.clear()
	for r in course.ramps: _pick.add_item("%s  %.0f km/h %s" % [r.id, float(r.prm.v) * 3.6, r.prm.kind])
	if course.ramps.is_empty(): _pick.add_item("(no ramps: + ADD)")


func _select(r) -> void:
	sel = r
	var i := course.ramps.find(r)
	if i >= 0: _pick.select(i)
	_quiet = true
	for row in ROWS:
		var s: HSlider = _sliders[row[0]]
		s.editable = r != null
		if r != null: s.set_value_no_signal(_pv(row[0]))
		_show_val(row[0])
	if r != null:
		_kind.select(["table", "gap", "kicker"].find(str(r.prm.kind)))
		_build.select(1 if str(r.prm.get("build", "dirt")) == "wood" else 0)
	_quiet = false
	_update_info()


func _pv(key: String) -> float:
	if key == "v": return float(sel.prm.v) * 3.6
	if key == "yaw": return rad_to_deg(sel.yaw)
	if key == "deck": return float(sel.prm.gap if sel.prm.kind == "gap" else sel.prm.deck)
	return float(sel.prm[key])


func _show_val(key: String) -> void:
	var lb: Label = _vals[key]
	if sel == null: lb.text = ""; return
	var v := _pv(key)
	var row: Array = []
	for r in ROWS:
		if r[0] == key: row = r
	var auto := key in ["height", "deck", "land_deg", "land_h"] and v <= 0.0
	if auto:   # show what auto made of it
		var d: Dictionary = sel.d
		var got: float = {"height": d.lip_h, "deck": d.deck, "land_deg": d.land_deg, "land_h": d.land_h}[key]
		lb.text = "auto %.1f %s" % [got, row[5]]
	else:
		lb.text = ("%.2f %s" if row[4] < 1.0 else "%.0f %s") % [v, row[5]]


func _on_slider(key: String, v: float) -> void:
	if _quiet or sel == null: return
	if key == "v": sel.prm.v = v / 3.6
	elif key == "yaw": sel.yaw = deg_to_rad(v)
	elif key == "deck":
		if sel.prm.kind == "gap": sel.prm.gap = v
		else: sel.prm.deck = v
	else: sel.prm[key] = v
	_dirty = true


func _setp(key: String, v) -> void:
	if sel == null: return
	sel.prm[key] = v
	_rebuild_now()
	_select(sel)


func _reset_numbers() -> void:
	if sel == null: return
	sel.prm = JumpDesign.params({})
	_rebuild_now()
	_select(sel)


func _rebuild_now() -> void:
	if sel == null: return
	sel.rebuild()
	terrain.refresh_ramp(sel)
	_dirty = false
	_save_t = 1.0
	for k in _sliders: _show_val(k)
	_update_info()
	_refresh_pick()
	_pick.select(course.ramps.find(sel))


func add_ramp() -> void:
	var ph = game.phys
	var f := Vector2(cos(ph.heading), -sin(ph.heading))
	var r := course.add_ramp(sel.prm if sel != null else {}, Vector2(ph.x, ph.z) + f * 35.0, ph.heading)
	terrain.refresh_ramp(r)
	_refresh_pick(); _select(r)
	_save_t = 0.5


func del_ramp() -> void:
	if sel == null: return
	terrain.drop_ramp_node(sel.id)
	course.remove_ramp(sel)
	_refresh_pick()
	_select(course.ramps[0] if not course.ramps.is_empty() else null)
	_save_t = 0.5


func ride() -> void:
	if sel == null:
		if course.ramps.is_empty(): return
		_select(course.ramps[0])
	diag.pilot_ramp(sel.id)


func _process(dt: float) -> void:
	if _dirty:
		_dirty_t -= dt
		if _dirty_t <= 0.0:
			_dirty_t = 0.12
			_rebuild_now()
	if _save_t > 0.0:
		_save_t -= dt
		if _save_t <= 0.0: course.save_ramps()
	if moving and sel != null:
		var hit = _ground_under_mouse()
		if hit != null and (hit as Vector2).distance_to(sel.pos) > 0.05:
			sel.pos = hit; _dirty = true


func _ground_under_mouse():
	var cam: Camera3D = get_viewport().get_camera_3d()
	if cam == null: return null
	var mp := get_viewport().get_mouse_position()
	var o := cam.project_ray_origin(mp)
	var d := cam.project_ray_normal(mp)
	if d.y > -0.01: return null
	var t := -o.y / d.y
	var p := o + d * t
	return Vector2(p.x, p.z)


func _input(e: InputEvent) -> void:
	if not moving or sel == null or not visible: return
	if get_global_rect().has_point(get_viewport().get_mouse_position()): return
	if e is InputEventMouseButton and e.pressed:
		if e.button_index == MOUSE_BUTTON_WHEEL_UP or e.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			sel.yaw = wrapf(sel.yaw + deg_to_rad(5.0 if e.button_index == MOUSE_BUTTON_WHEEL_UP else -5.0), -PI, PI)
			_quiet = true; (_sliders["yaw"] as HSlider).set_value_no_signal(rad_to_deg(sel.yaw)); _quiet = false
			_dirty = true
			get_viewport().set_input_as_handled()
		elif e.button_index == MOUSE_BUTTON_LEFT:
			moving = false; _move_b.set_pressed_no_signal(false)
			_rebuild_now()
			get_viewport().set_input_as_handled()


func _update_info() -> void:
	if sel == null:
		_info.text = "+ ADD puts a ramp down 35 m ahead of the rider."
		_view.queue_redraw(); return
	var d: Dictionary = sel.d
	var s := "R %.1f m = %.2f g at %.0f km/h · clothoid %.1f m + straight %.1f m · lip %.2f m at %.0f km/h\n" % [
		d.R, d.lip_gs, float(sel.prm.v) * 3.6, 2.0 * deg_to_rad(float(d.lip_deg)) * float(d.R), d.Ls, d.lip_h, float(d.v_lip) * 3.6]
	s += "%s %.1f m · knuckle %.1f m · landing %.0f° · bottom R %.1f m · %.1f m long\n" % [
		{"table": "deck", "gap": "gap", "kicker": "no landing: to flat ·"}[d.kind], d.deck, d.rk, d.land_deg, d.rb, d.length]
	for pr in d.pred:
		var bad: bool = float(pr.efh) > JumpDesign.EFH_MAX
		s += "%3.0f km/h → %4.1f m (%s) · air %.2f s · apex %.2f m · EFH %.2f m%s\n" % [
			float(pr.v) * 3.6, pr.dist, pr.spot, pr.air, pr.apex, pr.efh, "  ⚠" if bad else ""]
	_info.text = s.strip_edges()
	_view.queue_redraw()


## the side view: the shape (to scale), the lip, and the flights at 85 / 100 / 115 % of the design speed
func _draw_view() -> void:
	var r := Rect2(Vector2.ZERO, _view.size)
	_view.draw_rect(r, Color(0, 0, 0, 0.35))
	if sel == null: return
	var d: Dictionary = sel.d
	var L: float = d.length
	var top := float(d.lip_h)
	for pr in d.pred: top = maxf(top, float(d.lip_h) + float(pr.apex))
	var sc := minf((r.size.x - 12.0) / L, (r.size.y - 16.0) / maxf(0.5, top))
	var o := Vector2(6.0, r.size.y - 6.0)
	var P := func(uu: float, hh: float) -> Vector2: return o + Vector2(uu * sc, -hh * sc)
	# grid: 1 m
	for m in range(0, int(L) + 1):
		_view.draw_line(P.call(m, 0.0), P.call(m, top), Color(1, 1, 1, 0.04 if m % 5 else 0.1))
	for m in range(0, int(top) + 1):
		_view.draw_line(P.call(0.0, m), P.call(L, m), Color(1, 1, 1, 0.1))
	var hs: PackedFloat32Array = d.h
	var pts := PackedVector2Array()
	pts.append(P.call(0.0, 0.0))
	for i in range(0, hs.size(), 2): pts.append(P.call(i * JumpDesign.DS, hs[i]))
	pts.append(P.call(L, 0.0))
	_view.draw_colored_polygon(pts, Color(0.66, 0.46, 0.30, 0.85))
	# the take-off's pieces: clothoid (yellow), straight lip (orange)
	var c0 := float(d.face_u); var c1 := float(d.lip_u) - float(d.Ls) * cos(deg_to_rad(float(d.lip_deg)))
	var lip := float(d.lip_u)
	for i in range(int(c0 / JumpDesign.DS), mini(hs.size() - 1, int(lip / JumpDesign.DS))):
		var uu := i * JumpDesign.DS
		_view.draw_line(P.call(uu, hs[i]), P.call(uu + JumpDesign.DS, hs[i + 1]), Color(1, 0.85, 0.2) if uu < c1 else Color(1, 0.45, 0.15), 2.5)
	# landing zone
	_view.draw_line(P.call(float(d.land0), JumpDesign.sample(hs, float(d.land0)) + 0.05), P.call(float(d.land1), 0.05), Color(0.4, 1, 0.5, 0.8), 2.0)
	# flights
	var cols := [Color(0.5, 0.8, 1.0), Color(1, 1, 1), Color(1.0, 0.5, 0.5)]
	var th := deg_to_rad(float(d.lip_deg) + JumpDesign.TAKEOFF_EXTRA)
	for k in d.pred.size():
		var pr: Dictionary = d.pred[k]
		var vl := sqrt(maxf(0.1, float(pr.v) * float(pr.v) - 2.0 * JumpDesign.G * float(d.lip_h) - JumpDesign.FACE_LOSS * float(d.lip_h) * float(pr.v)))
		var line := PackedVector2Array()
		var t := 0.0
		while t <= float(pr.air) + 1e-3:
			line.append(P.call(lip + vl * cos(th) * t, float(d.lip_h) + vl * sin(th) * t - 0.5 * JumpDesign.G * t * t))
			t += 0.02
		if line.size() > 1: _view.draw_polyline(line, cols[k], 1.5, true)
		if is_finite(float(pr.u)):
			_view.draw_circle(P.call(float(pr.u), JumpDesign.sample(hs, float(pr.u))), 3.0, cols[k])
	var f := get_theme_default_font()
	_view.draw_string(f, Vector2(8, 13), "side view · 1 m grid · clothoid yellow, straight lip orange, landing green · flights at 85 / 100 / 115 %",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(1, 1, 1, 0.6))
