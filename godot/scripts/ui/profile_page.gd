class_name ProfilePage
extends Control
## The rider's profile, full screen and dark, Zwift-style (title menu, the avatar top right).
## Left: the rider as a magazine hero shot (3D, standing, looking down the lens), level ring + name on top, CUSTOMIZE RIDER and the XP bar at the bottom.
## Right: tabs OVERVIEW (ring gauges, stats, 12 weeks) · GOALS (daily streak + weekly / monthly goals to CLAIM) · BADGES (3D medals) · CARDS (holo
## collectibles) · WALLET. The balance sits top right. Numbers count up, rings and bars fill, cards fade in.
## Data: GameState, Goals, Collection, Steam.ACHIEVEMENTS.

var on_customize := Callable()
const WEEKS := 12
const CARD_PAD := Tokens.S6   # every card: 24 px on all four sides, a header caption, then the body
const C_BG := Tokens.PAGE
const C_STAGE := Color("171b26")
const C_CARD := Tokens.PAPER
const C_CARD2 := Tokens.FILL
const C_LINE := Tokens.LINE
const C_TXT := Tokens.INK
const C_SOFT := Tokens.INK_SOFT
const C_FAINT := Tokens.INK_FAINT
const C_GREEN := Color("2f9e63")
const C_RED := Color("d64545")
const ACC := Tokens.ACCENT
const LEVEL_NAMES := ["ROOKIE", "SCRUB", "LOCAL", "SHREDDER", "PRO", "LEGEND"]
const TABS := ["OVERVIEW", "SKILLS", "GOALS", "BADGES", "WALLET"]
const T_SKILLS := 1
const T_GOALS := 2
const T_WALLET := 4
var _tab := 0
var _content: VBoxContainer
var _tab_btns: Array = []
var _name_edit: LineEdit
var _wallet_l: Label
var _shown_money := 0
var _sel_badge := ""
var _sel_card := ""

func _ready() -> void:
	Steam._check_records()   # records already earned count now (the check otherwise runs once a second)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var bg := ColorRect.new()
	bg.color = C_BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	var root := HBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 0)
	add_child(root)
	root.add_child(_stage())
	var right := MarginContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for k in ["left", "right"]: right.add_theme_constant_override("margin_" + k, Tokens.S7)
	right.add_theme_constant_override("margin_top", Tokens.S6)
	right.add_theme_constant_override("margin_bottom", Tokens.S6)
	root.add_child(right)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", Tokens.S5)
	right.add_child(col)
	col.add_child(_top_bar())
	_content = VBoxContainer.new()
	_content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_content.add_theme_constant_override("separation", Tokens.S4)
	col.add_child(_content)
	_show(int(Env.s("BMX_PROFILE_TAB")) if Env.s("BMX_PROFILE_TAB") != "" else 0)
	var cust := _find_button(self, "CUSTOMIZE RIDER")
	PadNav.attach(self, {"back": _close, "first": func(): return cust,
		"tabs": func(dir: int): _show(posmod(_tab + dir, TABS.size()))})
	if cust: cust.grab_focus.call_deferred()
	modulate.a = 0.0
	create_tween().tween_property(self, "modulate:a", 1.0, 0.22)

func _find_button(n: Node, text: String) -> Button:
	if n is Button and (n as Button).text == text: return n
	for c in n.get_children():
		var r := _find_button(c, text)
		if r: return r
	return null

func _close() -> void:
	_commit_name()
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 0.0, 0.15)
	tw.tween_callback(queue_free)

func _unhandled_key_input(e: InputEvent) -> void:
	if e.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_close()

# ---------------------------------------------------------------- small helpers
func _count(l: Label, to: float, fmt: Callable, delay := 0.0, dur := 0.9) -> void:
	l.text = fmt.call(0.0)
	var tw := l.create_tween()
	tw.tween_interval(delay)
	tw.tween_method(func(v: float): l.text = fmt.call(v), 0.0, to, dur).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

func _appear(nodes: Array, step := 0.045, start := 0.0) -> void:
	for i in nodes.size():
		var n: CanvasItem = nodes[i]
		n.modulate.a = 0.0
		var tw := n.create_tween()
		tw.tween_interval(start + i * step)
		tw.tween_property(n, "modulate:a", 1.0, 0.25)

func _money(v: int) -> String:
	return ("-" if v < 0 else "") + Shop.fmt(absi(v))

func _num(text: String, size := 40, col := C_TXT) -> Label:
	return UITheme.display(text, size, col, 0.0, 900)

func _cap(text: String, col := C_SOFT, size := Tokens.T_SM) -> Label:
	return UITheme.caption(text, col, size)

func _body(text: String, col := C_TXT, size := Tokens.T_MD) -> Label:
	return UITheme.text(text, col, size)

func _card(pad := CARD_PAD, fill := C_CARD, _stroke := Color(0, 0, 0, 0)) -> PanelContainer:
	var pc := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = fill
	sb.set_corner_radius_all(3)
	sb.anti_aliasing = true
	sb.content_margin_left = pad; sb.content_margin_right = pad
	sb.content_margin_top = pad; sb.content_margin_bottom = pad
	pc.add_theme_stylebox_override("panel", sb)
	return pc

## a card with its header caption on top and an empty body column under it (the same gap everywhere)
func _titled(title: String, fill := C_CARD) -> Array:
	var pc := _card(CARD_PAD, fill)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", Tokens.S4)
	pc.add_child(col)
	col.add_child(_cap(title, C_SOFT, Tokens.T_SM))
	var body := VBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", Tokens.S3)
	col.add_child(body)
	return [pc, body]

func _bar(frac: float, delay := 0.0, h := 8, col := ACC) -> ProgressBar:
	var b := ProgressBar.new()
	b.show_percentage = false
	b.min_value = 0.0; b.max_value = 1.0; b.value = 0.0
	b.custom_minimum_size = Vector2(0, h)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var fg := StyleBoxFlat.new(); fg.bg_color = col; fg.set_corner_radius_all(h / 2)
	var bgs := StyleBoxFlat.new(); bgs.bg_color = C_LINE; bgs.set_corner_radius_all(h / 2)
	b.add_theme_stylebox_override("fill", fg); b.add_theme_stylebox_override("background", bgs)
	var tw := b.create_tween()
	tw.tween_interval(delay)
	tw.tween_property(b, "value", clampf(frac, 0.0, 1.0), 0.8).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	return b

## a flat rounded button: active / primary = yellow, else a dark pill
func _pill(text: String, cb: Callable, active := false, size := Tokens.T_LG, primary := false) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_ALL
	b.pressed.connect(cb)
	b.add_theme_font_override("font", UITheme.display_font(900, 0.0))
	b.add_theme_font_size_override("font_size", size)
	var mk := func(fill: Color) -> StyleBoxFlat:
		var s := StyleBoxFlat.new(); s.bg_color = fill; s.set_corner_radius_all(2); s.anti_aliasing = true
		s.content_margin_left = 22; s.content_margin_right = 22; s.content_margin_top = 10; s.content_margin_bottom = 10
		return s
	var lit := active or primary
	b.add_theme_stylebox_override("normal", mk.call(ACC if lit else C_CARD))
	b.add_theme_stylebox_override("hover", mk.call(Tokens.ACCENT_HOT if lit else Tokens.FILL))
	b.add_theme_stylebox_override("pressed", mk.call(Tokens.ACCENT_DOWN if lit else Tokens.FILL_HOT))
	b.add_theme_stylebox_override("focus", mk.call(Tokens.ACCENT_HOT if lit else Tokens.FILL))
	for k in ["font_color", "font_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(k, Tokens.INK if lit else C_SOFT)
	b.add_theme_color_override("font_hover_color", Tokens.INK if lit else C_TXT)
	return b

# ---------------------------------------------------------------- a round check mark: a day ridden (yellow disc + check) or still to come (empty ring)
class CheckDot extends Control:
	var done := false
	var dot := 30.0
	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func _ready() -> void:
		custom_minimum_size = Vector2(dot, dot)
	func _draw() -> void:
		var c := Vector2(dot, dot) * 0.5
		var r := dot * 0.5 - 1.5
		if done:
			draw_circle(c, r, Tokens.ACCENT)
			draw_arc(c, r, 0.0, TAU, 40, Tokens.ACCENT_DOWN, 1.5, true)
			var k := dot / 30.0
			# the check, centred by its visual weight (a touch up and right of the box centre), round ends and joint
			var o := Vector2(0.0, -1.3) * k
			var p0 := c + o + Vector2(-6.4, 0.2) * k
			var p1 := c + o + Vector2(-1.9, 4.7) * k
			var p2 := c + o + Vector2(6.6, -4.9) * k
			draw_polyline(PackedVector2Array([p0, p1, p2]), Tokens.INK, 3.0 * k, true)
			for q in [p0, p1, p2]: draw_circle(q, 1.5 * k, Tokens.INK)
		else:
			draw_arc(c, r, 0.0, TAU, 40, Tokens.LINE, 2.0, true)

func _check_dot(done: bool, size := 30.0) -> Control:
	var d := CheckDot.new()
	d.done = done
	d.dot = size
	return d

# ---------------------------------------------------------------- ring gauge
class Ring extends Control:
	var frac := 0.0:
		set(v):
			frac = v
			queue_redraw()
	var col := Tokens.ACCENT
	var track := Tokens.LINE
	var width := 12.0
	var big := ""
	var small := ""
	var big_size := 36
	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.5 - width * 0.5 - 1.0
		draw_arc(c, r, 0.0, TAU, 72, track, width, true)
		if frac > 0.001:
			draw_arc(c, r, -PI * 0.5, -PI * 0.5 + TAU * clampf(frac, 0.0, 1.0), 72, col, width, true)
		var f := UITheme.display_font(900, 0.0)
		if big != "":
			var w := f.get_string_size(big, HORIZONTAL_ALIGNMENT_LEFT, -1, big_size).x
			draw_string(f, Vector2(c.x - w * 0.5, c.y + big_size * (0.22 if small == "" else 0.12)), big, HORIZONTAL_ALIGNMENT_LEFT, -1, big_size, Tokens.INK)
		if small != "":
			var f2 := UITheme.display_font(700)
			var w2 := f2.get_string_size(small, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
			draw_string(f2, Vector2(c.x - w2 * 0.5, c.y + big_size * 0.12 + 20.0), small, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Tokens.INK_SOFT)

func _ring(frac: float, size: float, w: float, big: String, small := "", col := ACC, bs := 36, delay := 0.0) -> Ring:
	var r := Ring.new()
	r.custom_minimum_size = Vector2(size, size)
	r.col = col; r.width = minf(w, 5.0); r.big = big; r.small = small; r.big_size = bs
	var tw := r.create_tween()
	tw.tween_interval(delay)
	tw.tween_property(r, "frac", clampf(frac, 0.0, 1.0), 0.9).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	return r

# ---------------------------------------------------------------- left: the hero shot
func _stage() -> Control:
	var st := Control.new()
	st.custom_minimum_size.x = 540
	st.size_flags_vertical = Control.SIZE_EXPAND_FILL
	st.clip_contents = false
	var gr := Gradient.new()   # a warm soft light behind the rider, on the same page background as everything else
	gr.colors = PackedColorArray([Color(1.0, 0.82, 0.12, 0.16), Color(1.0, 0.82, 0.12, 0.0)])
	var gt := GradientTexture2D.new()
	gt.gradient = gr; gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5); gt.fill_to = Vector2(1.0, 0.5)
	gt.width = 512; gt.height = 512
	var glow := TextureRect.new()
	glow.texture = gt
	glow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	glow.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	glow.offset_left = -80; glow.offset_right = 80; glow.offset_top = 60; glow.offset_bottom = -120
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	st.add_child(glow)
	var hero := BikeTurntable.new()
	hero.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hero.offset_bottom = -172   # the picture ends above the button + XP bar: nothing covers the rider
	st.add_child(hero)
	hero.hero_stage(C_STAGE, float(Env.s("BMX_PROFILE_YAW")) if Env.s("BMX_PROFILE_YAW") != "" else -1.95)
	hero.show_rider(RiderPanels.load_look())
	hero.look_pitch = float(Env.s("BMX_PROFILE_LOOK")) if Env.s("BMX_PROFILE_LOOK") != "" else -0.5
	var m := MarginContainer.new()
	m.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for k in ["left", "top", "bottom"]: m.add_theme_constant_override("margin_" + k, Tokens.S7)
	m.add_theme_constant_override("margin_right", Tokens.S7)
	st.add_child(m)
	var vb := VBoxContainer.new()
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_theme_constant_override("separation", Tokens.S3)
	m.add_child(vb)
	var metres := float(GameState.records.distance)
	var lvl := GameState.level_for(metres)
	var rank: String = LEVEL_NAMES[mini(lvl / 5, LEVEL_NAMES.size() - 1)]
	var top := HBoxContainer.new()
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_theme_constant_override("separation", Tokens.S4)
	vb.add_child(top)
	top.add_child(_ring((metres - float(lvl - 1) * 20000.0) / 20000.0, 84, 9, str(lvl), "LEVEL", ACC, 34, 0.1))
	var nc := VBoxContainer.new()
	nc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	nc.alignment = BoxContainer.ALIGNMENT_CENTER
	nc.add_theme_constant_override("separation", 0)
	top.add_child(nc)
	_name_edit = LineEdit.new()
	_name_edit.text = GameState.rider_name
	_name_edit.max_length = 16
	_name_edit.flat = true
	_name_edit.add_theme_font_override("font", UITheme.display_font(900, 0.0))
	_name_edit.add_theme_font_size_override("font_size", 46)
	_name_edit.add_theme_color_override("font_color", C_TXT)
	_name_edit.add_theme_color_override("caret_color", ACC)
	_name_edit.tooltip_text = "Click to rename"
	_name_edit.text_submitted.connect(func(_t): _commit_name())
	_name_edit.focus_exited.connect(_commit_name)
	nc.add_child(_name_edit)
	nc.add_child(_cap("%s%s" % [rank, ("  ·  " + Steam.player_name.to_upper()) if Steam.player_name != "" else ""], C_SOFT))
	var sp := Control.new(); sp.size_flags_vertical = Control.SIZE_EXPAND_FILL; sp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(sp)
	var cust := _pill("CUSTOMIZE RIDER", func(): if on_customize.is_valid(): on_customize.call(), false, Tokens.T_LG, true)
	cust.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	vb.add_child(cust)
	# the XP bar along the bottom, under the rider
	var xr := HBoxContainer.new()
	xr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	xr.add_theme_constant_override("separation", Tokens.S3)
	xr.add_child(_num("LV %d" % lvl, Tokens.T_XL))
	var xp := _bar((metres - float(lvl - 1) * 20000.0) / 20000.0, 0.3, 12)
	xp.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	xr.add_child(xp)
	xr.add_child(_num("LV %d" % (lvl + 1), Tokens.T_XL, C_FAINT))
	vb.add_child(xr)
	vb.add_child(_cap("%.1f KM TO THE NEXT LEVEL" % ((float(lvl) * 20000.0 - metres) / 1000.0)))
	return st

func _commit_name() -> void:
	if _name_edit == null or not is_instance_valid(_name_edit): return
	var t := _name_edit.text.strip_edges().to_upper()
	GameState.rider_name = t if t != "" else "RIDER"
	_name_edit.text = GameState.rider_name
	GameState.touch_records()

# ---------------------------------------------------------------- right: tabs, wallet top right
func _top_bar() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", Tokens.S2)
	for i in TABS.size():
		var b := _pill(TABS[i], func(): _show(i), i == 0, Tokens.T_MD)
		row.add_child(b)
		_tab_btns.append(b)
	var sp := Control.new(); sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL; row.add_child(sp)
	# the wallet, top right corner
	var w := _pill("", func(): _show(T_WALLET), false, Tokens.T_LG)
	var wr := HBoxContainer.new()
	wr.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	wr.alignment = BoxContainer.ALIGNMENT_CENTER
	wr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wr.add_theme_constant_override("separation", Tokens.S2)
	_wallet_l = _num(_money(GameState.money), Tokens.T_XL)
	wr.add_child(_wallet_l)
	w.custom_minimum_size = Vector2(190, 46)
	w.add_child(wr)
	row.add_child(w)
	_shown_money = GameState.money
	_count(_wallet_l, float(GameState.money), func(v: float): return _money(int(v)), 0.15, 1.1)
	row.add_child(_pill("CLOSE", _close, false, Tokens.T_LG))
	return row

func _show(i: int) -> void:
	_tab = i
	for k in _tab_btns.size():
		var b: Button = _tab_btns[k]
		var lit := k == i
		for st in ["normal", "hover", "pressed", "focus"]:
			var sb := StyleBoxFlat.new()
			sb.bg_color = Tokens.FILL if st == "hover" else Color(0, 0, 0, 0)
			sb.set_corner_radius_all(0)
			sb.border_width_bottom = 3
			sb.border_color = ACC if lit else Color(0, 0, 0, 0)
			sb.content_margin_left = 18; sb.content_margin_right = 18; sb.content_margin_top = 12; sb.content_margin_bottom = 10
			b.add_theme_stylebox_override(st, sb)
		for fk in ["font_color", "font_pressed_color", "font_focus_color"]:
			b.add_theme_color_override(fk, C_TXT if lit else C_SOFT)
		b.add_theme_color_override("font_hover_color", C_TXT)
	for c in _content.get_children():
		_content.remove_child(c); c.queue_free()
	match i:
		0: _page_overview()
		T_SKILLS: _page_skills()
		T_GOALS: _page_goals()
		3: _page_badges()
		T_WALLET: _page_wallet()

func _refresh() -> void:   # after a claim: the wallet counts up, the page is built again
	var from := _shown_money
	_shown_money = GameState.money
	var tw := _wallet_l.create_tween()
	tw.tween_method(func(v: float): _wallet_l.text = _money(int(v)), float(from), float(GameState.money), 0.8).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_show(_tab)

const STROKES := [Tokens.ACCENT]

func _tile(cap: String, count_to: float, fmt: Callable, delay := 0.0, idx := 0) -> Control:
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", -6)
	var l := _num("", 34)
	v.add_child(l)
	_count(l, count_to, fmt, delay)
	v.add_child(_cap(cap, C_SOFT, Tokens.T_XS))
	var bar := ColorRect.new()   # a short coloured slash under each stat
	bar.color = STROKES[idx % STROKES.size()]
	bar.custom_minimum_size = Vector2(46, 4)
	bar.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	v.add_child(bar)
	return v

# ---------------------------------------------------------------- OVERVIEW
## the rider's ratings, 0..99 like a sports-game player card: from what they have actually done
func _attributes() -> Array:
	var r: Dictionary = GameState.records
	var air := (float(r.longest) / 60.0 + float(r.highest) / 12.0 + float(r.air) / 5.0) / 3.0
	return [
		["SPEED", clampi(roundi(float(r.top_speed) / 90.0 * 99.0), 1, 99)],
		["AIR", clampi(roundi(air * 99.0), 1, 99)],
		["ENDURANCE", clampi(roundi(float(r.distance) / 200000.0 * 99.0), 1, 99)],
		["CONSISTENCY", clampi(roundi(float(maxi(int(r.best_streak), GameState.day_streak())) / 14.0 * 99.0), 1, 99)],
		["STYLE", clampi(roundi(float(GameState.tricks_seen.size()) / 8.0 * 99.0), 1, 99)],
	]

func _page_overview() -> void:
	var mi: bool = Settings.get_v("units") == 1
	var unit := 1609.344 if mi else 1000.0
	var un := "MI" if mi else "KM"
	var spd := 0.621371 if mi else 1.0
	var wk := GameState.week_totals()
	var rides_all := 0
	var active := 0
	for d in GameState.days:
		rides_all += int(GameState.days[d][1])
		if float(GameState.days[d][0]) > 0.0: active += 1
	var r: Dictionary = GameState.records
	# a headline that says something about today (+ a button when cash waits)
	var cnt := Goals.claimable()
	var msg := "RIDER STATUS"
	var sub := "%s  ·  LEVEL %d" % [GameState.rider_name, GameState.level_for(float(r.distance))]
	if cnt > 0:
		msg = "REWARDS AVAILABLE"
		sub = "%d GOAL%s READY TO CLAIM" % [cnt, "" if cnt == 1 else "S"]
	elif GameState.day_streak() > 0 and not GameState.claimed.has("d%d" % GameState.today()):
		msg = "STREAK ACTIVE"
		sub = "%d DAYS IN A ROW  ·  RIDE TODAY TO HOLD IT" % GameState.day_streak()
	elif GameState.day_streak() > 0:
		msg = "ON TRACK"
		sub = "%d DAYS IN A ROW  ·  TODAY'S RIDE LOGGED" % GameState.day_streak()
	var top := HBoxContainer.new()
	var head := VBoxContainer.new()
	head.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_theme_constant_override("separation", 0)
	head.add_child(UITheme.display(msg, 46, C_TXT, 0.0, 900))
	head.add_child(_cap(sub, C_SOFT, Tokens.T_MD))
	top.add_child(head)
	if cnt > 0:
		var og := _pill("OPEN GOALS", func(): _show(T_GOALS), false, Tokens.T_MD, true)
		og.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		top.add_child(og)
	_content.add_child(top)
	_appear([top], 0.0)
	# the athlete card: overall rating + five attributes, then this week and the streak
	var hero := HBoxContainer.new()
	hero.add_theme_constant_override("separation", Tokens.S4)
	_content.add_child(hero)
	var attrs := _attributes()
	var tot := 0
	for a in attrs: tot += int(a[1])
	var ovr := roundi(float(tot) / attrs.size())
	var ta := _titled("OVERALL RATING  ·  %s" % String(LEVEL_NAMES[clampi(ovr / 17, 0, 5)]), C_CARD2)
	var ac: PanelContainer = ta[0]
	ac.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ac.size_flags_vertical = Control.SIZE_EXPAND_FILL
	ac.size_flags_stretch_ratio = 1.8
	var ah := HBoxContainer.new()
	ah.size_flags_vertical = Control.SIZE_EXPAND_FILL
	ah.add_theme_constant_override("separation", Tokens.S6)
	var ol := UITheme.display("0", 84, C_TXT, 0.0, 900)
	ol.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	ol.custom_minimum_size.x = 120
	ah.add_child(ol)
	_count(ol, float(ovr), func(v: float): return str(roundi(v)), 0.1, 1.0)
	var rows := VBoxContainer.new()
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	rows.add_theme_constant_override("separation", 0)
	for i in attrs.size():
		var rw := HBoxContainer.new()
		rw.add_theme_constant_override("separation", Tokens.S3)
		var nm := _cap(String(attrs[i][0]), C_SOFT, Tokens.T_XS)
		nm.custom_minimum_size.x = 104
		nm.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		rw.add_child(nm)
		var br := _bar(float(attrs[i][1]) / 99.0, 0.2 + i * 0.07, 8, ACC if attrs[i][1] >= 70 else Tokens.INK_SOFT)
		br.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		rw.add_child(br)
		var nv := _num("0", 20)
		nv.custom_minimum_size = Vector2(36, 28)
		nv.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		nv.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		rw.add_child(nv)
		_count(nv, float(attrs[i][1]), func(v: float): return str(roundi(v)), 0.2 + i * 0.07, 0.8)
		rows.add_child(rw)
	ah.add_child(rows)
	ta[1].add_child(ah)
	hero.add_child(ac)
	var wt := Goals.week_target_m()
	var tb := _titled("THIS WEEK")
	var a: PanelContainer = tb[0]
	a.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	a.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var rr := HBoxContainer.new()
	rr.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rr.add_theme_constant_override("separation", Tokens.S5)
	var ring := _ring(float(wk.metres) / wt, 92, 8, "%d%%" % roundi(minf(float(wk.metres) / wt, 9.99) * 100.0), "", ACC, 22, 0.1)
	ring.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	rr.add_child(ring)
	var at := VBoxContainer.new()
	at.alignment = BoxContainer.ALIGNMENT_CENTER
	at.add_theme_constant_override("separation", 0)
	var al := _num("", 32)
	at.add_child(al)
	_count(al, float(wk.metres) / unit, func(v: float): return "%.1f %s" % [v, un], 0.1)
	at.add_child(_cap("%d RIDES  ·  %d DAYS LEFT" % [int(wk.rides), Goals.days_left_week()], C_SOFT, Tokens.T_XS))
	rr.add_child(at)
	tb[1].add_child(rr)
	hero.add_child(a)
	var tc := _titled("DAILY STREAK")
	var b: PanelContainer = tc[0]
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var bl := _num("", 36)
	tc[1].add_child(bl)
	var ds := GameState.day_streak()
	_count(bl, float(ds), func(v: float): return "%d DAY%s" % [roundi(v), "" if roundi(v) == 1 else "S"], 0.15, 0.7)
	var dots := HBoxContainer.new()
	dots.add_theme_constant_override("separation", Tokens.S3)
	for i in 7: dots.add_child(_check_dot(i < mini(ds, 7), 24.0))
	tc[1].add_child(dots)
	tc[1].add_child(_cap("WEEK STREAK %d  ·  BEST %d DAYS" % [GameState.week_streak(), int(r.best_streak)], C_SOFT, Tokens.T_XS))
	hero.add_child(b)
	_appear([ac, a, b], 0.08, 0.05)
	# stats as open typography
	var tiles: Array = [
		_tile("TOTAL DISTANCE", float(r.distance) / unit, func(v: float): return "%d %s" % [roundi(v), un], 0.05, 0),
		_tile("TOP SPEED", float(r.top_speed) * spd, func(v: float): return "%d %s" % [roundi(v), "MPH" if mi else "KM/H"], 0.08, 1),
		_tile("LONGEST JUMP", float(r.longest), func(v: float): return "%d M" % roundi(v), 0.11, 2),
		_tile("HIGHEST AIR", float(r.highest), func(v: float): return "%.1f M" % v, 0.14, 3),
		_tile("BEST AIR TIME", float(r.air), func(v: float): return "%.1f S" % v, 0.17, 4),
		_tile("JUMPS LANDED", float(int(r.jumps)), func(v: float): return str(roundi(v)), 0.20, 5),
		_tile("RIDES", float(rides_all), func(v: float): return str(roundi(v)), 0.23, 0),
		_tile("ACTIVE DAYS", float(active), func(v: float): return str(roundi(v)), 0.26, 1),
		_tile("BADGES", float(GameState.achieved.size()), func(v: float): return "%d / %d" % [roundi(v), Steam.ACHIEVEMENTS.size()], 0.29, 2),
	]
	var grid := GridContainer.new()
	grid.columns = 5
	grid.add_theme_constant_override("h_separation", Tokens.S5)
	grid.add_theme_constant_override("v_separation", Tokens.S3)
	for t in tiles: grid.add_child(t)
	_content.add_child(grid)
	_appear(tiles, 0.025, 0.25)
	var box := VBoxContainer.new()
	box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", Tokens.S2)
	box.add_child(_cap("DISTANCE · LAST %d WEEKS (%s)" % [WEEKS, un]))
	var ch := WeekChart.new()
	ch.size_flags_vertical = Control.SIZE_EXPAND_FILL
	ch.custom_minimum_size.y = 80
	ch.unit = unit
	var w0 := GameState.week_of(GameState.today())
	var v := PackedFloat32Array()
	for k in WEEKS: v.append(0.0)
	for d in GameState.days:
		var idx := WEEKS - 1 - (w0 - GameState.week_of(int(d)))
		if idx >= 0 and idx < WEEKS: v[idx] += float(GameState.days[d][0])
	ch.vals = v
	box.add_child(ch)
	_content.add_child(box)
	_appear([box], 0.0, 0.4)
	ch.grow = 0.0
	ch.create_tween().tween_property(ch, "grow", 1.0, 0.9).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT).set_delay(0.45)

class WeekChart extends Control:
	var vals := PackedFloat32Array()
	var unit := 1000.0
	var grow := 1.0:
		set(v):
			grow = v
			queue_redraw()
	func _draw() -> void:
		var f := UITheme.display_font(700)
		var n := vals.size()
		if n == 0: return
		var mx := 1.0
		for v in vals: mx = maxf(mx, v)
		var base := size.y - 22.0
		var top := 22.0
		var bw := size.x / n
		for i in n:
			var h := (base - top) * vals[i] / mx * grow
			var cur := i == n - 1
			var rc := Rect2(i * bw + bw * 0.16, base - maxf(h, 3.0), bw * 0.68, maxf(h, 3.0))
			draw_rect(rc, Tokens.ACCENT if cur else Tokens.LINE)
			if vals[i] > 0.0 and grow > 0.85:
				var s := "%.0f" % (vals[i] / unit)
				var w := f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
				draw_string(f, Vector2(rc.position.x + (rc.size.x - w) * 0.5, rc.position.y - 5.0), s, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Tokens.INK if cur else Tokens.INK_SOFT)
			var back := n - 1 - i
			var lab := "NOW" if cur else ("%dW" % back if back % 2 == 0 else "")
			if lab != "":
				var lw := f.get_string_size(lab, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
				draw_string(f, Vector2(rc.position.x + (rc.size.x - lw) * 0.5, size.y - 5.0), lab, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Tokens.INK_FAINT)
		draw_line(Vector2(0, base), Vector2(size.x, base), Tokens.LINE, 1.0)

# ---------------------------------------------------------------- SKILLS
## the rider's skills like the motocross games' rider card: each is a level 1..10 earned from what has really been
## done on the bike (records, tricks landed), with a segmented meter and what the next level needs.
## [name, what it is read from, value, level thresholds (level n = n thresholds reached), formatter of a value]
func _skills() -> Array:
	var r: Dictionary = GameState.records
	var mi: bool = Settings.get_v("units") == 1
	var dk := 1.0 / 1609.344 if mi else 0.001
	var du := "MI" if mi else "KM"
	var sk := 0.621371 if mi else 1.0
	var su := "MPH" if mi else "KM/H"
	var m_fmt := func(v: float) -> String: return "%d M" % roundi(v)
	return [
		["TOP SPEED", "FASTEST YOU HAVE GONE", float(r.top_speed) * sk,
			[0, 30, 45, 55, 65, 75, 85, 95, 105, 120].map(func(x): return x * sk), func(v: float) -> String: return "%d %s" % [roundi(v), su]],
		["JUMPING", "LONGEST JUMP", float(r.longest),
			[0, 5, 10, 15, 20, 30, 40, 50, 65, 80], m_fmt],
		["BIG AIR", "HIGHEST ABOVE THE GROUND", float(r.highest),
			[0, 0.5, 1, 2, 3, 4, 6, 8, 10, 12], func(v: float) -> String: return "%.1f M" % v],
		["HANG TIME", "BEST TIME IN THE AIR", float(r.air),
			[0, 0.5, 1, 1.5, 2, 2.5, 3, 4, 5, 6], func(v: float) -> String: return "%.1f S" % v],
		["STYLE", "TRICKS LANDED", float(GameState.tricks_seen.size()),
			[0, 1, 2, 3, 4, 5, 6, 7, 8, 9], func(v: float) -> String: return "%d OF %d" % [roundi(v), Collection.TRICK_KEYS.size()]],
		["EXPERIENCE", "JUMPS LANDED", float(int(r.jumps)),
			[0, 5, 20, 50, 100, 200, 400, 700, 1000, 2000], func(v: float) -> String: return str(roundi(v))],
		["ENDURANCE", "TOTAL DISTANCE RIDDEN", float(r.distance) * dk,
			[0, 5, 15, 30, 60, 100, 150, 250, 400, 600], func(v: float) -> String: return "%d %s" % [roundi(v), du]],
		["CONSISTENCY", "DAYS IN A ROW", float(maxi(int(r.best_streak), GameState.day_streak())),
			[0, 1, 2, 3, 5, 7, 10, 14, 21, 30], func(v: float) -> String: return "%d DAYS" % roundi(v)],
	]

## level 1..10 and the way to the next one (0..1) for a value against its thresholds
static func _skill_level(v: float, th: Array) -> Array:
	var lv := 0
	for t in th:
		if v + 1e-6 >= float(t): lv += 1
	lv = clampi(lv, 1, th.size())
	var frac := 1.0
	if lv < th.size():
		var a := float(th[lv - 1])
		var b := float(th[lv])
		frac = clampf((v - a) / maxf(b - a, 1e-6), 0.0, 1.0)
	return [lv, frac]

func _skill_card(s: Array, delay: float) -> Control:
	var th: Array = s[3]
	var fm: Callable = s[4]
	var lf := _skill_level(float(s[2]), th)
	var lv: int = lf[0]
	var maxed := lv >= th.size()
	var pc := _card(Tokens.S5, C_CARD)
	pc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", Tokens.S2)
	pc.add_child(col)
	var top := HBoxContainer.new()
	col.add_child(top)
	var nm := VBoxContainer.new()
	nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nm.add_theme_constant_override("separation", -2)
	nm.add_child(UITheme.display(String(s[0]), 30, C_TXT, 0.0, 900))
	nm.add_child(_cap(String(s[1]), C_FAINT, Tokens.T_XS))
	top.add_child(nm)
	var lb := VBoxContainer.new()
	lb.alignment = BoxContainer.ALIGNMENT_CENTER
	lb.add_theme_constant_override("separation", -6)
	var ln := _num("0", 44, ACC if lv >= 7 else C_TXT)
	ln.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	lb.add_child(ln)
	_count(ln, float(lv), func(v: float): return str(roundi(v)), delay + 0.1, 0.7)
	var ll := _cap("MAX LEVEL" if maxed else "LEVEL", C_SOFT, Tokens.T_XS)
	ll.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	lb.add_child(ll)
	top.add_child(lb)
	# ten pips like a games' skill meter: full for each level reached, the next one filling
	var pips := HBoxContainer.new()
	pips.add_theme_constant_override("separation", 4)
	for i in th.size():
		var p := ProgressBar.new()
		p.show_percentage = false
		p.min_value = 0.0; p.max_value = 1.0
		p.custom_minimum_size = Vector2(0, 12)
		p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var fg := StyleBoxFlat.new(); fg.bg_color = ACC
		var bgs := StyleBoxFlat.new(); bgs.bg_color = C_LINE
		p.add_theme_stylebox_override("fill", fg); p.add_theme_stylebox_override("background", bgs)
		var to := 1.0 if i < lv else (float(lf[1]) if i == lv else 0.0)
		var tw := p.create_tween()
		tw.tween_interval(delay + 0.15 + i * 0.04)
		tw.tween_property(p, "value", to, 0.45).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		pips.add_child(p)
	col.add_child(pips)
	var info := "BEST  %s" % fm.call(float(s[2]))
	info += "   ·   MAXED OUT" if maxed else "   ·   NEXT LEVEL  %s" % fm.call(float(th[lv]))
	col.add_child(_cap(info, C_SOFT, Tokens.T_XS))
	return pc

func _page_skills() -> void:
	var sk := _skills()
	var tot := 0
	for s in sk: tot += int(_skill_level(float(s[2]), s[3])[0])
	var ovr := roundi(float(tot) / sk.size() * 10.0)   # the average level, 10..100
	var top := HBoxContainer.new()
	var head := VBoxContainer.new()
	head.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_theme_constant_override("separation", 0)
	head.add_child(UITheme.display("RIDER SKILLS", 46, C_TXT, 0.0, 900))
	head.add_child(_cap("%s  ·  %s  ·  EVERY LEVEL IS EARNED BY RIDING" % [GameState.rider_name, String(LEVEL_NAMES[clampi(ovr / 17, 0, 5)])], C_SOFT, Tokens.T_MD))
	top.add_child(head)
	var ob := VBoxContainer.new()
	ob.alignment = BoxContainer.ALIGNMENT_CENTER
	ob.add_theme_constant_override("separation", -8)
	var ov := UITheme.display("0", 64, ACC, 0.0, 900)
	ov.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	ob.add_child(ov)
	_count(ov, float(ovr), func(v: float): return str(roundi(v)), 0.1, 1.0)
	var oc := _cap("OVERALL", C_SOFT, Tokens.T_XS)
	oc.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	ob.add_child(oc)
	top.add_child(ob)
	_content.add_child(top)
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_content.add_child(sc)
	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", Tokens.S4)
	sc.add_child(body)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", Tokens.S4)
	grid.add_theme_constant_override("v_separation", Tokens.S4)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(grid)
	var cards: Array = []
	for i in sk.size():
		var c := _skill_card(sk[i], 0.05 + i * 0.05)
		grid.add_child(c)
		cards.append(c)
	# the tricks: landed ones lit, the rest still to learn
	var tt := _titled("TRICKS  ·  %d OF %d LANDED" % [GameState.tricks_seen.size(), Collection.TRICK_KEYS.size()])
	var tc: PanelContainer = tt[0]
	tc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(tc)
	var chips := HFlowContainer.new()
	chips.add_theme_constant_override("h_separation", Tokens.S2)
	chips.add_theme_constant_override("v_separation", Tokens.S2)
	const NAMES := {"back": "BACKFLIP", "front": "FRONTFLIP", "flip": "FLIP", "360": "360", "720": "720", "whip": "WHIP", "table": "TABLETOP", "scrub": "SCRUB"}
	for key in Collection.TRICK_KEYS.values():
		var got: bool = GameState.tricks_seen.has(key)
		var chip := _card(Tokens.S3, ACC if got else C_CARD2)
		var cl := UITheme.display(String(NAMES.get(key, String(key).to_upper())), 22, C_TXT if got else C_FAINT, 0.0, 900)
		chip.add_child(cl)
		chips.add_child(chip)
	tt[1].add_child(chips)
	cards.append(tc)
	_appear(cards, 0.04, 0.05)

# ---------------------------------------------------------------- GOALS
func _page_goals() -> void:
	_content.add_child(_streak_card())
	var all := Goals.list()
	var made: Array = []
	for kind in ["week", "month"]:
		var left := Goals.days_left_week() if kind == "week" else Goals.days_left_month()
		_content.add_child(_cap("%s GOALS  ·  %d DAY%s LEFT" % ["WEEKLY" if kind == "week" else "MONTHLY", left, "" if left == 1 else "S"], C_SOFT, Tokens.T_MD))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", Tokens.S4)
		row.size_flags_vertical = Control.SIZE_EXPAND_FILL
		_content.add_child(row)
		var i := 0
		for g in all:
			if g.kind != kind: continue
			var c := _goal_card(g, 0.1 + i * 0.1)
			row.add_child(c)
			made.append(c)
			i += 1
	_appear(made, 0.07, 0.1)

func _streak_card() -> Control:
	var card := _card(CARD_PAD, C_CARD)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", Tokens.S6)
	card.add_child(row)
	var n := GameState.day_streak()
	# left: header, then one row: the number and its seven days, centred on the same line
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", Tokens.S4)
	left.add_child(_cap("DAILY STREAK", C_SOFT, Tokens.T_SM))
	var lb := HBoxContainer.new()
	lb.add_theme_constant_override("separation", Tokens.S5)
	var big := _num("", 46)
	big.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	lb.add_child(big)
	_count(big, float(n), func(v: float): return "%d DAY%s" % [roundi(v), "" if roundi(v) == 1 else "S"], 0.1, 0.7)
	var dots := HBoxContainer.new()
	dots.add_theme_constant_override("separation", Tokens.S3)
	dots.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	for i in 7: dots.add_child(_check_dot(i < mini(n, 7), 32.0))
	lb.add_child(dots)
	left.add_child(lb)
	left.add_child(_cap("BEST  %d DAYS   ·   WEEK STREAK  %d" % [int(GameState.records.best_streak), GameState.week_streak()], C_SOFT, Tokens.T_XS))
	row.add_child(left)
	var sp := Control.new(); sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL; row.add_child(sp)
	# right: the same structure, aligned to the right edge
	var paid := GameState.claimed.has("d%d" % GameState.today())
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", Tokens.S4)
	var rh := HBoxContainer.new()
	rh.alignment = BoxContainer.ALIGNMENT_END
	rh.add_theme_constant_override("separation", Tokens.S2)
	if paid:
		var ck := _check_dot(true, 20.0)
		ck.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		rh.add_child(ck)
	rh.add_child(_cap("TODAY'S BONUS PAID" if paid else "RIDE 200 M TODAY TO EARN", C_GREEN if paid else C_SOFT, Tokens.T_SM))
	right.add_child(rh)
	var today_amt := GameState.DAILY_BASE + GameState.DAILY_STEP * mini(n + (0 if paid else 1), 10)
	var amt := _num(_money(GameState.DAILY_BASE + GameState.DAILY_STEP * mini(n, 10)) if paid else _money(today_amt), 46)
	amt.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	amt.size_flags_horizontal = Control.SIZE_SHRINK_END
	right.add_child(amt)
	var rf := _cap(("TOMORROW  " + _money(GameState.DAILY_BASE + GameState.DAILY_STEP * mini(n + 1, 10))) if paid else "BONUS FOR TODAY'S FIRST RIDE", C_SOFT, Tokens.T_XS)
	rf.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	rf.size_flags_horizontal = Control.SIZE_SHRINK_END
	right.add_child(rf)
	row.add_child(right)
	_appear([card], 0.0)
	return card

func _goal_card(g: Dictionary, delay: float) -> Control:
	var ready: bool = g.done and not g.claimed
	var pc := _card(CARD_PAD, Tokens.ACCENT_TINT if ready else C_CARD)
	pc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", Tokens.S4)
	pc.add_child(row)
	var frac := float(g.have) / maxf(float(g.want), 1.0)
	row.add_child(_ring(frac, 96, 10, "%d%%" % roundi(minf(frac, 9.99) * 100.0), "", C_GREEN if ready else (C_FAINT if g.claimed else ACC), 24, delay))
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", Tokens.S1)
	row.add_child(col)
	col.add_child(_num(String(g.title), 24, C_SOFT if g.claimed else C_TXT))
	var have: String
	var want: String
	if g.unit == "m":
		have = "%.1f KM" % (float(g.have) / 1000.0)
		want = "%.0f KM" % (float(g.want) / 1000.0)
	else:
		have = str(int(g.have))
		want = str(int(g.want))
	col.add_child(_cap("%s / %s" % [have, want], C_SOFT, Tokens.T_XS))
	var key: String = g.key
	if g.claimed: col.add_child(_cap("CLAIMED  ✓  " + _money(int(g.reward)), C_FAINT, Tokens.T_SM))
	elif g.done: col.add_child(_pill("CLAIM  +" + _money(int(g.reward)), func(): if Goals.claim(key): _refresh(), false, Tokens.T_MD, true))
	else: col.add_child(_cap("REWARD  " + _money(int(g.reward)), C_TXT, Tokens.T_SM))
	return pc

# ---------------------------------------------------------------- BADGES (3D medals)
class BadgeCell extends Control:
	signal picked(id: String)
	var id := ""
	var got := false
	var sel := false:
		set(v):
			sel = v
			queue_redraw()
	func _ready() -> void:
		custom_minimum_size = Vector2(118, 138)
		mouse_filter = Control.MOUSE_FILTER_STOP
		pivot_offset = custom_minimum_size * 0.5
		mouse_entered.connect(func(): create_tween().tween_property(self, "scale", Vector2(1.07, 1.07), 0.12))
		mouse_exited.connect(func(): create_tween().tween_property(self, "scale", Vector2.ONE, 0.12))
	func _gui_input(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT: picked.emit(id)
	func _draw() -> void:
		var c := Vector2(size.x * 0.5, 56.0)
		var tier: Color = Collection.TIERS[Collection.badge_tier(id)][1] if got else Color("c7ccd6")
		var enamel: Color = Collection.badge_colour(id) if got else Color("e2e5ec")
		var shp := String(Collection.badge_look(id).shape)
		var sh := func(k: float, off := Vector2.ZERO) -> PackedVector2Array:
			var pts := Collection.shape_points(shp, k)
			var out := PackedVector2Array()
			for p in pts: out.append(c + off + Vector2(p.x, -p.y))
			return out
		if sel: draw_colored_polygon(sh.call(88.0), Color(1, 0.82, 0.12, 0.25))
		draw_colored_polygon(sh.call(78.0), tier.darkened(0.35))
		draw_colored_polygon(sh.call(74.0), tier)
		draw_colored_polygon(sh.call(60.0, Vector2(-3, -4)), tier.lightened(0.25))
		draw_colored_polygon(sh.call(58.0), enamel)
		var g := Collection.badge_glyph(id) if got else "?"
		var f := UITheme.font(true)
		var w := f.get_string_size(g, HORIZONTAL_ALIGNMENT_LEFT, -1, 40).x
		draw_string(f, Vector2(c.x - w * 0.5, c.y + 14), g, HORIZONTAL_ALIGNMENT_LEFT, -1, 40, Color(1, 1, 1, 0.9) if got else Color("9aa0ad"))
		var nm: String = String(Steam.ACHIEVEMENTS[id][0]).to_upper()
		var f2 := UITheme.display_font(900)
		var nw := f2.get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, size.x, 15).x
		draw_string(f2, Vector2((size.x - minf(nw, size.x)) * 0.5, 126.0), nm, HORIZONTAL_ALIGNMENT_LEFT, size.x, 15, Tokens.INK if got else Tokens.INK_FAINT)

func _fmt(rec: String, v: float) -> String:
	match rec:
		"distance": return "%.1f km" % (v / 1000.0)
		"top_speed": return "%d km/h" % roundi(v)
		"air": return "%.1f s" % v
		"longest", "highest": return "%.0f m" % v
	return str(int(v))

func _page_badges() -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", Tokens.S5)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_content.add_child(row)
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation", Tokens.S2)
	row.add_child(left)
	left.add_child(_cap("%d OF %d BADGES  ·  CLICK ONE, THEN DRAG IT TO SPIN" % [GameState.achieved.size(), Steam.ACHIEVEMENTS.size()]))
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left.add_child(sc)
	var grid := GridContainer.new()
	grid.columns = 5
	grid.add_theme_constant_override("h_separation", Tokens.S2)
	grid.add_theme_constant_override("v_separation", Tokens.S3)
	sc.add_child(grid)
	var ids: Array = Steam.ACHIEVEMENTS.keys()
	var order := ids.duplicate()
	order.sort_custom(func(a, b):
		var ea := GameState.achieved.has(a)
		var eb := GameState.achieved.has(b)
		if ea != eb: return ea
		if ea: return int(GameState.achieved[a]) > int(GameState.achieved[b])
		return ids.find(a) < ids.find(b))
	var side := VBoxContainer.new()
	side.custom_minimum_size.x = 330
	side.add_theme_constant_override("separation", Tokens.S2)
	row.add_child(side)
	var stage := CollectStage.new()
	stage.size_flags_vertical = Control.SIZE_EXPAND_FILL
	side.add_child(stage)
	var title := _num("", 30)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	side.add_child(title)
	var desc := _body("", C_SOFT, Tokens.T_MD)
	desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	side.add_child(desc)
	var meta := _cap("", C_TXT, Tokens.T_SM)
	meta.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	side.add_child(meta)
	var cells: Array = []
	var pick := func(id: String) -> void:
		_sel_badge = id
		var got := GameState.achieved.has(id)
		stage.show_badge(id, got)
		var a: Array = Steam.ACHIEVEMENTS[id]
		title.text = String(a[0]).to_upper()
		desc.text = String(a[1])
		var tier: String = Collection.TIERS[Collection.badge_tier(id)][0]
		if got: meta.text = "%s  ·  EARNED %s  ·  +%s" % [tier, Time.get_date_string_from_unix_time(int(GameState.achieved[id])), _money(Steam.reward(id))]
		elif a[2] == "rec": meta.text = "%s  ·  %s / %s  ·  +%s" % [tier, _fmt(String(a[3]), float(GameState.records.get(a[3], 0.0))), _fmt(String(a[3]), float(a[4])), _money(Steam.reward(id))]
		else: meta.text = "%s  ·  LOCKED  ·  +%s" % [tier, _money(Steam.reward(id))]
		for c in cells: (c as BadgeCell).sel = (c as BadgeCell).id == id
	for id in order:
		var c := BadgeCell.new()
		c.id = id
		c.got = GameState.achieved.has(id)
		c.picked.connect(pick)
		grid.add_child(c)
		cells.append(c)
	_appear(cells, 0.02)
	pick.call(_sel_badge if _sel_badge != "" and Steam.ACHIEVEMENTS.has(_sel_badge) else order[0])

# ---------------------------------------------------------------- WALLET
func _page_wallet() -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", Tokens.S4)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_content.add_child(row)
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_stretch_ratio = 0.8
	left.add_theme_constant_override("separation", Tokens.S3)
	row.add_child(left)
	var stats: Array = [
		_tile("EARNED · 7 DAYS", float(GameState.earned_since(7)), func(v: float): return _money(int(v)), 0.0, 0),
		_tile("EARNED · 30 DAYS", float(GameState.earned_since(30)), func(v: float): return _money(int(v)), 0.05, 1),
		_tile("EARNED · EVER", float(GameState.records.earned), func(v: float): return _money(int(v)), 0.10, 2),
	]
	for t in stats: left.add_child(t)
	var how := _card(CARD_PAD)
	var hv := VBoxContainer.new()
	hv.add_theme_constant_override("separation", Tokens.S2)
	hv.add_child(_cap("HOW TO EARN"))
	for l in ["RIDE  ·  %s per km, paid as you go" % _money(int(GameState.RIDE_RATE * 1000.0)),
			"DAILY BONUS  ·  the first ride each day, bigger every day in a row",
			"GOALS  ·  claim weekly and monthly goals",
			"BADGES + CARDS  ·  cash for every one"]:
		hv.add_child(_body(l, C_TXT, Tokens.T_SM))
	how.add_child(hv)
	left.add_child(how)
	left.add_child(_pill("SPEND IT IN THE SHOP", func(): if on_customize.is_valid(): on_customize.call("shop"), false, Tokens.T_MD, true))
	var card := _card(CARD_PAD)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", Tokens.S2)
	card.add_child(vb)
	vb.add_child(_cap("LEDGER"))
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vb.add_child(sc)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 0)
	sc.add_child(list)
	var log: Array = GameState.wallet_log.duplicate()
	log.reverse()
	if log.is_empty(): list.add_child(_body("Nothing yet. Ride to earn.", C_SOFT, Tokens.T_MD))
	for e in log:
		var r := HBoxContainer.new()
		r.add_theme_constant_override("separation", Tokens.S3)
		var d := _cap(Time.get_date_string_from_unix_time(int(e[0])), C_FAINT, Tokens.T_XS)
		d.custom_minimum_size.x = 96
		r.add_child(d)
		var why := _body(String(e[2]), C_TXT, Tokens.T_MD)
		why.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		why.clip_text = true
		r.add_child(why)
		var amt := int(e[1])
		r.add_child(_num(("+" if amt > 0 else "") + _money(amt), 24, C_GREEN if amt > 0 else C_RED))
		list.add_child(r)
		var line := ColorRect.new()
		line.color = C_LINE
		line.custom_minimum_size.y = 1
		list.add_child(line)
	row.add_child(card)
	_appear(stats + [how, card], 0.05)
