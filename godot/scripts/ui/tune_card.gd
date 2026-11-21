class_name TuneCard
extends PanelContainer
## One card for every slider (right-hand side): RIDE (how the bike handles), RIDER (pose, movement and
## body physics), LOOK (kit colours) and SOUND (the freewheel's clicking + presets), each split into category tabs so only one group shows at a
## time. P / K / L open it on Ride / Rider / Look; the same key again closes it. Values save as they move.

## [id, tab label, [[category, [sources...]], ...]]. A source is "T:<Tune.DEFS group>", "R:<RideLayout page>"
## (the Ride tab, laid out by what each slider is for), "P:<RiderPanels.POSE_DEFS group>",
## "L:<RiderPanels.LOOK_ROWS group>", "L:kits", "seat" or "F:freewheel".
const TABS := [
	["ride", "Ride", [
		["Feel", ["R:feel"]],
		["Steering", ["R:steer"]],
		["Tyres", ["R:tyres"]],
		["Ground", ["R:ground"]],
		["Brakes", ["R:brakes"]],
		["Speed", ["R:speed"]],
		["Body", ["R:body"]],
		["Manual & pump", ["R:manual"]],
		["Suspension", ["R:susp"]],
		["Jumps", ["R:jumps"]],
		["Smoothing", ["R:smooth"]],
		["Demo", ["R:demo"]],
	]],
	["rider", "Rider", [
		["Body", ["P:Body position", "seat", "P:Pelvis"]],
		["Spine", ["P:Spine", "P:Chest"]],
		["Head", ["P:Head"]],
		["Arms", ["P:Shoulders & arms"]],
		["Legs", ["P:Legs & feet"]],
		["Motion", ["P:Movement"]],
		["Style", ["P:Style"]],
	]],
	["look", "Look", [
		["Kits", ["L:kits"]],
		["Helmet", ["L:Helmet", "L:Goggles"]],
		["Action cam", ["L:actioncam"]],
		["Clothes", ["L:Kit", "L:Belt", "L:Shoes"]],
	]],
	["sound", "Sound", [
		["Freewheel", ["F:freewheel"]],
	]],
	["light", "Light", [
		["Time", ["W:time"]],
		["Light", ["W:light"]],
	]],
	["dust", "Dust", [
		["Look", ["T:Dust look"]],
		["Trail", ["T:Dust trail"]],
		["Spray", ["T:Dust spray"]],
		["Grit", ["T:Dust grit"]],
	]],
]

static var last_cat := {"ride": 0, "rider": 0, "look": 0, "sound": 0, "light": 0, "dust": 0}   # remembered for the session

var game
var tab := "ride"
var pose: Dictionary
var pose_defaults: Dictionary
var look: Dictionary
var tab_row: HBoxContainer
var cat_row: HFlowContainer
var sub: Label
var list: VBoxContainer
var scroll: ScrollContainer


func _init(g) -> void:
	game = g


func _ready() -> void:
	theme = UITheme.get_theme()
	set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	offset_left = -420; offset_right = -14; offset_top = 64; offset_bottom = -90
	mouse_filter = Control.MOUSE_FILTER_STOP
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	add_child(vb)
	var head := HBoxContainer.new()
	var t := UITheme.label("TUNING", 18, UITheme.ACCENT, true)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	var rs := UITheme.button("Reset", _reset_category, 13)
	rs.tooltip_text = "Reset the sliders on this tab"
	rs.custom_minimum_size = Vector2(0, 30)
	head.add_child(rs)
	head.add_child(UITheme.close_button(func(): get_tree().call_group("hud", "close_sides")))
	vb.add_child(head)
	tab_row = HBoxContainer.new()
	tab_row.add_theme_constant_override("separation", 4)
	vb.add_child(tab_row)
	cat_row = HFlowContainer.new()
	cat_row.add_theme_constant_override("h_separation", 3)
	cat_row.add_theme_constant_override("v_separation", 4)
	vb.add_child(cat_row)
	sub = UITheme.label("", 12, UITheme.MUTED)
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(sub)
	scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	SmoothScroll.attach(scroll)
	vb.add_child(scroll)
	list = VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	visibility_changed.connect(func(): if not visible: FreewheelSound.preview_speed = 0.0)
	var grp := ButtonGroup.new()
	for d in TABS:
		var b := _tab_button(d[1], grp, 14)
		b.name = "T_" + d[0]
		b.pressed.connect(func(): show_tab(d[0]))
		tab_row.add_child(b)
	show_tab(tab)
	# Xbox, while the ride is paused (pause > Tuning): D-pad / stick rows, left / right values, A press,
	# LB / RB category (on into the next tab), B close. Riding, the pad rides: nothing in here keeps focus.
	process_mode = Node.PROCESS_MODE_ALWAYS
	nav = PadNav.attach(self, {"tabs": _pad_cat, "back": func(): get_tree().call_group("hud", "close_sides"), "style": "dark",
		"first": func(): return PadNav.find_focusable(list)})
	get_viewport().gui_focus_changed.connect(func(c):
		if c and is_ancestor_of(c) and not get_tree().paused: c.release_focus.call_deferred())

var nav: PadNav

## LB / RB: the next / previous category, on into the next / previous tab at the ends
func _pad_cat(d: int) -> void:
	var cats := _cats()
	var i: int = last_cat[tab] + d
	if i < 0 or i >= cats.size():
		var ti := 0
		for j in TABS.size():
			if TABS[j][0] == tab: ti = j
		ti = wrapi(ti + d, 0, TABS.size())
		last_cat[TABS[ti][0]] = 0 if d > 0 else TABS[ti][2].size() - 1
		show_tab(TABS[ti][0])
		return
	last_cat[tab] = i
	for k in cat_row.get_child_count():
		(cat_row.get_child(k) as Button).button_pressed = k == i
	_fill()


## open on a tab (re-reads every value, so nothing shows stale after a reset elsewhere)
func show_tab(id: String) -> void:
	tab = id
	var b := tab_row.get_node_or_null("T_" + id) as Button
	if b: b.button_pressed = true
	PosePresets.bike = GameState.bike_id
	pose_defaults = PosePresets.preset(PosePresets.get_active())   # Reset / slider marks: the chosen position
	pose = RiderPanels.load_pose(GameState.bike_id, GameState.BIKES[GameState.bike_id].pose)
	look = RiderPanels.load_look()
	for c in cat_row.get_children(): c.queue_free()
	var grp := ButtonGroup.new()
	var cats: Array = _cats()
	for i in cats.size():
		var cb := _tab_button(cats[i][0], grp, 12)
		cb.size_flags_horizontal = Control.SIZE_FILL
		cb.button_pressed = i == last_cat[tab]
		cb.pressed.connect(func(): last_cat[tab] = i; _fill())
		cat_row.add_child(cb)
	match tab:
		"ride": sub.text = "Start with Feel · each page in plain words · the tick = the preset · ☆ pins to Quick tune"
		"rider": sub.text = "%s · saved per bike" % GameState.BIKES[GameState.bike_id].label
		"look": sub.text = "Helmet, goggles, kit and shoes"
		"sound": sub.text = "Coast (or Preview) to hear it · presets save as you go"
		"light": sub.text = "Time of day, day / night cycle and the level's light"
		"dust": sub.text = "Tyre dust: how it looks, how long the trail hangs, how it sprays, the grains"
	if id != "sound": FreewheelSound.preview_speed = 0.0
	_fill()


func _cats() -> Array:
	for d in TABS:
		if d[0] == tab: return d[2]
	return []


func _fill() -> void:
	for c in list.get_children(): c.queue_free()
	var cats: Array = _cats()
	var cat: Array = cats[clampi(last_cat[tab], 0, cats.size() - 1)]
	if tab == "rider":
		var sv := UITheme.button("Side view", func(): game.cam.set_mode("side"); game.flash("Side view"), 12)
		sv.custom_minimum_size = Vector2(0, 28)
		list.add_child(sv)
	for src: String in cat[1]:
		if (src.begins_with("T:") and not src.begins_with("T:Dust")) or src.begins_with("R:"):
			_preset_bar(TunePresets, "Ride preset")
			break
	for src: String in cat[1]:
		if src.begins_with("P:") or src == "seat":
			# a position may just have been picked: re-read the pose and ride with it
			PosePresets.bike = GameState.bike_id
			pose_defaults = PosePresets.preset(PosePresets.get_active())
			pose = RiderPanels.load_pose(GameState.bike_id, GameState.BIKES[GameState.bike_id].pose)
			game.rider.set_style(pose)
			game.phys.bike_rock = float(pose.get("bikeRock", 1.0))
			_preset_bar(PosePresets, "Riding position")
			break
	for src: String in cat[1]:
		var kind := src.substr(0, src.find(":")) if ":" in src else src
		var name := src.substr(src.find(":") + 1)
		match kind:
			"T": _tune_group(name)
			"R": _ride_page(name)
			"P": _pose_group(name)
			"seat": _seat_toggle()
			"L": _look_group(name)
			"F": _freewheel_group()
			"W": _light_group(name)
	scroll.scroll_vertical = 0


# ---------------------------------------------------------------- shared bits
func _tab_button(text: String, grp: ButtonGroup, size: int) -> Button:
	var mk := func(c: Color) -> StyleBoxFlat:
		var s := UITheme.box(c, 6, 4); s.content_margin_top = 4; s.content_margin_bottom = 4
		return s
	var b := Button.new()
	b.text = text; b.toggle_mode = true; b.button_group = grp
	b.focus_mode = Control.FOCUS_NONE
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.add_theme_font_size_override("font_size", size)
	b.add_theme_stylebox_override("normal", mk.call(UITheme.PANEL_LIGHT))
	b.add_theme_stylebox_override("hover", mk.call(Color(1, 1, 1, 0.22)))
	b.add_theme_stylebox_override("pressed", mk.call(UITheme.ACCENT))
	b.add_theme_stylebox_override("hover_pressed", mk.call(UITheme.ACCENT))
	b.add_theme_color_override("font_pressed_color", Color.BLACK)
	b.add_theme_color_override("font_hover_pressed_color", Color.BLACK)
	return b


func _header(text: String) -> void:
	list.add_child(UITheme.label(text.to_upper(), 13, UITheme.ACCENT, true))


## name / value / reset on one row, the slider full width below
func _slider(label: String, lo: float, hi: float, stp: float, val: float, def: float, fmt: Callable,
		on_change: Callable, pin: Button = null) -> HSlider:
	var hb := HBoxContainer.new()
	var l := UITheme.label(label, 13); l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.clip_text = true; l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	var s := HSlider.new()
	s.min_value = lo; s.max_value = hi; s.step = stp; s.value = val
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL; s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var vl := UITheme.label(fmt.call(val), 12, UITheme.MUTED)
	vl.custom_minimum_size.x = 70; vl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	s.value_changed.connect(func(v): vl.text = fmt.call(v); on_change.call(v))
	if pin: hb.add_child(pin)
	hb.add_child(l); hb.add_child(vl)
	hb.add_child(UITheme.reset_button(s, def))
	var box := VBoxContainer.new()   # name row + slider: one row for the pad's focus marker
	box.add_theme_constant_override("separation", 0)
	box.set_meta("nav_row", true)
	box.add_child(hb)
	box.add_child(s)
	list.add_child(box)
	s.set_meta("value_label", vl)
	s.set_meta("fmt", fmt)
	return s


static func _fmt_step(v: float, stp: float, unit: String) -> String:
	var d := clampi(ceili(-log(stp) / log(10.0) - 0.001), 0, 4)
	return (("%." + str(d) + "f") % v + " " + unit).strip_edges()


# ---------------------------------------------------------------- RIDE + rider physics (Tune)
func _tune_group(group: String) -> void:
	for g in Tune.DEFS:
		if g[0] != group: continue
		_header("Body physics" if group == "Legs & body" else group)
		for row in g[1]:
			var key: String = row[0]
			var pin := Button.new()
			pin.text = "★" if key in Tune.pins else "☆"
			pin.tooltip_text = "Pin to the Quick tune card"
			pin.focus_mode = Control.FOCUS_NONE; pin.flat = true
			pin.add_theme_color_override("font_color", UITheme.ACCENT if key in Tune.pins else UITheme.MUTED)
			pin.pressed.connect(func(): Tune.toggle_pin(key); _fill())
			var stp: float = row[5]
			_slider(row[1], row[3], row[4], stp, Tune.base[key], TunePresets.value_of(key),
				func(v): return _fmt_step(v, stp, row[6]), func(v): Tune.set_value(key, v); _refresh_mod(TunePresets), pin)


# ---------------------------------------------------------------- RIDE tab (RideLayout pages)
static var ride_all := false   # Simple (the sliders that matter most) / All, remembered for the session

func _pin_button(key: String) -> Button:
	var pin := Button.new()
	pin.text = "★" if key in Tune.pins else "☆"
	pin.tooltip_text = "Pin to the Quick tune card"
	pin.focus_mode = Control.FOCUS_NONE; pin.flat = true
	pin.add_theme_color_override("font_color", UITheme.ACCENT if key in Tune.pins else UITheme.MUTED)
	pin.pressed.connect(func(): Tune.toggle_pin(key); _fill())
	return pin


func _ride_page(id: String) -> void:
	if id == "feel":
		_header("Feel")
		var intro := UITheme.label("The big picture. Each moves a set of the detail sliders on the other pages (they keep their own settings).", 12, UITheme.MUTED)
		intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		list.add_child(intro)
		for r in RideLayout.FEEL:
			var key: String = r[0]
			var tr: Array = Tune.row(key)
			var moves: Array = []
			for dk in Tune.MACROS[key]:
				var dr: Array = Tune.row(dk)
				if not dr.is_empty() and moves.size() < 4: moves.append(str(RideLayout.LABELS.get(dk, dr[1])).to_lower())
			var ts := TuneSlider.make(tr[1], [tr[3], tr[4], tr[5]], Tune.base[key], TunePresets.value_of(key),
				func(v): return "as set" if absf(v - 1.0) < 0.01 else "%+d %%" % roundi((v - 1.0) * 100.0),
				[r[2], r[3]], r[1], _pin_button(key), true)
			ts.tooltip_text = "Moves: " + ", ".join(moves)
			ts.changed.connect(func(v): Tune.set_value(key, v); _refresh_mod(TunePresets))
			list.add_child(ts)
		return
	var p := RideLayout.page(id)
	if p.is_empty(): return
	# Simple / All
	var sw := HBoxContainer.new()
	sw.add_theme_constant_override("separation", 4)
	var grp := ButtonGroup.new()
	for opt in [[false, "Simple"], [true, "All sliders"]]:
		var b := _tab_button(opt[1], grp, 12)
		b.button_pressed = ride_all == opt[0]
		b.pressed.connect(func(): ride_all = opt[0]; _fill())
		sw.add_child(b)
	list.add_child(sw)
	var blurb := UITheme.label(p[2], 12, UITheme.MUTED)
	blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	list.add_child(blurb)
	for sec in p[3]:
		var rows: Array = []
		for r in sec[1]:
			if ride_all or str(r[0]).begins_with("*"): rows.append(r)
		if rows.is_empty(): continue
		_header(sec[0])
		for r in rows:
			var key: String = str(r[0]).trim_prefix("*")
			var tr: Array = Tune.row(key)
			if tr.is_empty(): continue
			var stp: float = tr[5]
			var hint: String = r[1]
			var mk := Tune.macro_k(key)
			if absf(mk - 1.0) > 0.005: hint += ("  " if hint != "" else "") + "Feel ×%.2f" % mk
			var ts := TuneSlider.make(str(RideLayout.LABELS.get(key, tr[1])), [tr[3], tr[4], stp], Tune.base[key],
				TunePresets.value_of(key), func(v): return _fmt_step(v, stp, tr[6]), [r[2], r[3]], hint, _pin_button(key))
			ts.changed.connect(func(v): Tune.set_value(key, v); _refresh_mod(TunePresets))
			list.add_child(ts)


# ---------------------------------------------------------------- RIDER pose
func _pose_group(group: String) -> void:
	for g in RiderPanels.POSE_DEFS:
		if g[0] != group: continue
		_header(group)
		for row in g[1]:
			var key: String = row[0]
			var stp: float = row[4]
			_slider(row[1], row[2], row[3], stp, float(pose.get(key, 0.0)), float(pose_defaults.get(key, 0.0)),
				func(v): return _fmt_step(v, stp, row[5]), func(v): pose[key] = v; _apply_pose())


## the one pose setting that is a switch, not a slider
func _seat_toggle() -> void:
	var c := CheckButton.new()
	c.text = "Keep hips above the saddle"
	c.tooltip_text = "Never let the rider sink into the seat when sitting back"
	c.button_pressed = bool(pose.get("seatFloor", false))
	c.add_theme_font_size_override("font_size", 13)
	c.toggled.connect(func(on): pose.seatFloor = on; _apply_pose())
	list.add_child(c)


func _apply_pose() -> void:
	game.rider.set_style(pose)
	game.phys.bike_rock = float(pose.get("bikeRock", 1.0))
	RiderPanels.save_pose(GameState.bike_id, pose)
	PosePresets.pose_changed(pose)
	_refresh_mod(PosePresets)


# ---------------------------------------------------------------- LOOK
func _look_group(group: String) -> void:
	if group == "actioncam":   # the helmet camera: mount, model, lens, housing, mic, top accessory
		_header("Action cam")
		list.add_child(UITheme.label("Mount", 13))
		list.add_child(RiderPanels.cam_mount_picker(str(look.get("camMount", "top")), func(id):
			look.camMount = id; _apply_look(); _fill()))
		for r in ActionCam.GEAR_ROWS:
			var lk: String = ActionCam.GEAR_LOOK[r[0]]
			list.add_child(UITheme.label(r[1], 13))
			list.add_child(RiderPanels.choice_picker(r[2], str(look.get(lk, ActionCam.GEAR_DEFAULT[r[0]])), func(id):
				look[lk] = id; _apply_look(); _fill()))
		return
	if group == "kits":
		_header("Kits")
		var kits := GridContainer.new(); kits.columns = 3
		kits.add_theme_constant_override("h_separation", 6); kits.add_theme_constant_override("v_separation", 6)
		for k in RiderPanels.KITS:
			var b := UITheme.button(k[0], func():
				var cur := look
				look = Rider.DEFAULT_LOOK.duplicate(); look.merge(k[1], true)
				for key in RiderPanels.NON_KIT:   # a kit changes the clothes, not the head / plate
					if cur.has(key): look[key] = cur[key]
				_apply_look(); _fill(), 13)
			b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			kits.add_child(b)
		list.add_child(kits)
		return
	var textured: bool = str(look.get("helmet", "glory")) != "glory"   # the textured helmets carry their own paint + goggles
	for g in RiderPanels.LOOK_ROWS:
		if g[0] != group: continue
		if textured and group == "Goggles": return
		_header(group)
		if group == "Helmet":
			list.add_child(UITheme.label("Model (textured ones come with their goggles)", 13))
			list.add_child(RiderPanels.helmet_picker(RiderPanels.helmet_choice(look), func(id):
				RiderPanels.helmet_set(look, id); _apply_look(); _fill()))
			list.add_child(UITheme.label("Hair style", 13))
			list.add_child(RiderPanels.hair_style_picker(str(look.get("hairStyle", "long")), func(id):
				look.hairStyle = id; _apply_look(); _fill()))
		if group == "Kit":
			list.add_child(UITheme.label("Knee pads design", 13))
			list.add_child(RiderPanels.pad_style_picker(str(look.get("padStyle", "enduro")), func(id):
				look.padStyle = id; _apply_look(); _fill()))
			list.add_child(UITheme.label("Pants fabric", 13))
			list.add_child(RiderPanels.choice_picker(PantsLook.FABRICS, str(look.get("pantsFabric", PantsLook.DEFAULT_FABRIC)), func(id):
				look.pantsFabric = id; _apply_look(); _fill(), 13, 3))
			list.add_child(UITheme.label("Pants pattern", 13))
			list.add_child(RiderPanels.choice_picker(PantsLook.PATTERNS, str(look.get("pantsPattern", PantsLook.DEFAULT_PATTERN)), func(id):
				look.pantsPattern = id; _apply_look(); _fill(), 13, 3))
		if group == "Belt":
			list.add_child(UITheme.label("Belt style", 13))
			list.add_child(RiderPanels.belt_style_picker(str(look.get("beltStyle", "webbing")), func(id):
				look.beltStyle = id; _apply_look(); _fill()))
		for row in g[1]:
			if textured and group == "Helmet" and row[0] != "hair": continue
			var key: String = row[0]
			list.add_child(UITheme.label(row[1], 13))
			var hb := HFlowContainer.new()
			hb.add_theme_constant_override("h_separation", 4); hb.add_theme_constant_override("v_separation", 4)
			for hex in row[2]:
				var b := Button.new()
				b.custom_minimum_size = Vector2(22, 22)
				var on: bool = str(look[key]).to_lower() == str(hex).to_lower()
				b.add_theme_stylebox_override("normal", UITheme.box(Color(hex), 11, 0, Color.WHITE if on else Color(1, 1, 1, 0.2), 2 if on else 1))
				b.add_theme_stylebox_override("hover", UITheme.box(Color(hex), 11, 0, UITheme.ACCENT, 2))
				b.add_theme_stylebox_override("pressed", UITheme.box(Color(hex), 11, 0, UITheme.ACCENT, 2))
				b.add_theme_stylebox_override("focus", UITheme.box(Color(0, 0, 0, 0), 11, 0, UITheme.ACCENT, 3))
				b.pressed.connect(func(): look[key] = hex; _apply_look(); _fill())
				hb.add_child(b)
			var cp := ColorPickerButton.new()
			cp.color = Color(look[key]); cp.edit_alpha = false
			cp.custom_minimum_size = Vector2(30, 22)
			cp.focus_mode = Control.FOCUS_NONE   # (the pad uses the swatches)
			cp.tooltip_text = "Any colour"
			cp.color_changed.connect(func(c): look[key] = "#" + c.to_html(false); _apply_look())
			hb.add_child(cp)
			list.add_child(hb)


func _apply_look() -> void:
	game.rider.set_look(look)
	RiderPanels.save_look(look)


# ---------------------------------------------------------------- presets (shared by Ride and Sound)
var _preset_mod: Label

## preset picker + Delete (own presets) + "changed" note + Save as. store: TunePresets or FreewheelSound
## (same static API: names / is_builtin / get_active / builtin_count / select / save_as / delete / modified)
func _preset_bar(store, title := "Preset") -> void:
	_header(title)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 4)
	var ob := OptionButton.new()
	ob.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ob.add_theme_font_size_override("font_size", 13)
	var names: Array = store.names()
	var act: String = store.get_active()
	for i in names.size():
		var n: String = names[i]
		if i == store.builtin_count(): ob.add_separator("Yours")
		ob.add_item(n if store.is_builtin(n) else "★ " + n, i)
		if n == act: ob.select(ob.get_item_index(i))
	ob.item_selected.connect(func(idx):
		var n: String = names[ob.get_item_id(idx)]
		store.select(n); game.flash(n); _fill())
	hb.add_child(ob)
	if not store.is_builtin(act):
		var del := UITheme.button("Delete", func():
			store.delete(act); game.flash("Deleted \"%s\"" % act); _fill(), 12)
		del.custom_minimum_size = Vector2(0, 28)
		del.tooltip_text = "Delete this preset of yours"
		hb.add_child(del)
	list.add_child(hb)
	_preset_mod = UITheme.label("Changed from \"%s\" — Save as to keep it" % act, 12, UITheme.MUTED)
	_preset_mod.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	list.add_child(_preset_mod)
	_refresh_mod(store)
	var sv := HBoxContainer.new()
	sv.add_theme_constant_override("separation", 4)
	var le := LineEdit.new()
	le.placeholder_text = "New preset name"
	le.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	le.add_theme_font_size_override("font_size", 13)
	var save := func():
		var n: String = store.save_as(le.text)
		game.flash("Saved \"%s\"" % n)
		_fill.call_deferred()
	le.text_submitted.connect(func(_t): save.call())
	sv.add_child(le)
	var sb := UITheme.button("Save as", save, 12)
	sb.custom_minimum_size = Vector2(0, 28)
	sb.tooltip_text = "Save these sliders as your own preset"
	sv.add_child(sb)
	list.add_child(sv)


func _refresh_mod(store) -> void:
	if is_instance_valid(_preset_mod):
		_preset_mod.visible = store.is_builtin(store.get_active()) and store.modified()


# ---------------------------------------------------------------- LIGHT: time of day + light
const LIGHT_TIME_KEYS := ["time", "day_min", "sun_turn"]
var _clock_l: Label
var _time_s: HSlider   # follows the clock while the cycle runs

func _light_group(which: String) -> void:
	LightSettings.ensure_loaded()
	_preset_bar(LightSettings, "Light preset")
	var base := LightSettings.preset(LightSettings.get_active())
	if which == "time":
		_clock_l = UITheme.label("", 22, Color.WHITE, true)
		_clock_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		list.add_child(_clock_l)
		_tick_clock()
		var cy := CheckButton.new()
		cy.text = "Day / night cycle (the clock runs)"
		cy.button_pressed = LightSettings.get_value("cycle") > 0.5
		cy.add_theme_font_size_override("font_size", 13)
		cy.toggled.connect(func(on):
			if on: LightSettings.current.time = game.tod   # carry on from the time shown now
			LightSettings.set_value("cycle", 1.0 if on else 0.0); _refresh_mod(LightSettings))
		list.add_child(cy)
	_header("Time of day" if which == "time" else "Light")
	for row in LightSettings.PARAMS:
		var key: String = row[0]
		if key == "cycle" or (key in LIGHT_TIME_KEYS) != (which == "time"): continue
		var stp: float = row[5]
		var fmt := (func(v): return LightSettings.clock(v)) if key == "time" else (func(v): return _fmt_step(v, stp, row[6]))
		var sl := _slider(row[1], row[3], row[4], stp, LightSettings.get_value(key), float(base[key]), fmt,
			func(v):
				LightSettings.set_value(key, v)
				_refresh_mod(LightSettings))
		if key == "time": _time_s = sl


func _tick_clock() -> void:
	if is_instance_valid(_clock_l):
		var cyc := LightSettings.get_value("cycle") > 0.5
		var e := Game.sun_elev_deg(game.tod)
		var part := "night" if e < -3.0 else ("golden hour" if e < 20.0 else "day")
		_clock_l.text = LightSettings.clock(game.tod) + "  ·  " + part + ("  ·  cycle on" if cyc else "")
		if cyc and is_instance_valid(_time_s):   # the time slider moves with the running clock
			_time_s.set_value_no_signal(game.tod)
			(_time_s.get_meta("value_label") as Label).text = LightSettings.clock(game.tod)


func _process(_dt: float) -> void:
	if nav: nav.enabled = get_tree().paused   # riding (P / K / L) the pad rides the bike, not this card
	if visible and tab == "light": _tick_clock()


# ---------------------------------------------------------------- SOUND: freewheel
func _freewheel_group() -> void:
	FreewheelSound.ensure_loaded()
	_preset_bar(FreewheelSound)
	var pv := CheckButton.new()
	pv.text = "Preview (spin the wheel while standing)"
	pv.button_pressed = FreewheelSound.preview_speed > 0.0
	pv.add_theme_font_size_override("font_size", 13)
	list.add_child(pv)
	var pspeed := [FreewheelSound.preview_speed if FreewheelSound.preview_speed > 0.0 else 4.0]
	pv.toggled.connect(func(on): FreewheelSound.preview_speed = pspeed[0] if on else 0.0)
	_slider("Preview speed", 0.5, 22.0, 0.5, pspeed[0], 4.0, func(v): return "%.0f km/h" % (v * 3.6),
		func(v):
			pspeed[0] = v
			if FreewheelSound.preview_speed > 0.0: FreewheelSound.preview_speed = v)
	_header("Freewheel sound")
	var base := FreewheelSound.preset(FreewheelSound.active)
	for row in FreewheelSound.PARAMS:
		var key: String = row[0]
		var stp: float = row[5]
		_slider(row[1], row[3], row[4], stp, FreewheelSound.get_value(key), float(base[key]),
			func(v): return _fmt_step(v, stp, row[6]),
			func(v):
				FreewheelSound.set_value(key, v)
				_refresh_mod(FreewheelSound))


# ---------------------------------------------------------------- reset this category
func _reset_category() -> void:
	var cat: Array = _cats()[clampi(last_cat[tab], 0, _cats().size() - 1)]
	var pose_touched := false
	var look_touched := false
	for src: String in cat[1]:
		var name := src.substr(src.find(":") + 1)
		if src.begins_with("R:"):
			for k in RideLayout.page_keys(name): Tune.set_value(k, TunePresets.value_of(k))
		elif src.begins_with("T:"):
			for g in Tune.DEFS:
				if g[0] == name:
					for row in g[1]:   # back to the preset's value (dust: the default)
							Tune.set_value(row[0], Tune.defaults[row[0]] if str(row[0]).begins_with("dust") else TunePresets.value_of(row[0]))
		elif src.begins_with("P:"):
			for g in RiderPanels.POSE_DEFS:
				if g[0] == name:
					for row in g[1]: pose[row[0]] = pose_defaults.get(row[0], 0.0)
			pose_touched = true
		elif src == "seat":
			pose.seatFloor = pose_defaults.get("seatFloor", false); pose_touched = true
		elif src == "L:kits":
			look = Rider.DEFAULT_LOOK.duplicate(); look_touched = true
		elif src == "F:freewheel":
			FreewheelSound.reset()
		elif src.begins_with("W:"):
			LightSettings.reset()
		elif src == "L:actioncam":
			look.camMount = Rider.DEFAULT_LOOK.camMount
			for k in ActionCam.GEAR_LOOK.values(): look[k] = Rider.DEFAULT_LOOK[k]
			look_touched = true
		elif src.begins_with("L:"):
			for g in RiderPanels.LOOK_ROWS:
				if g[0] == name:
					for row in g[1]: look[row[0]] = Rider.DEFAULT_LOOK[row[0]]
					if name == "Kit": look.padStyle = Rider.DEFAULT_LOOK.padStyle
					if name == "Belt": look.beltStyle = Rider.DEFAULT_LOOK.beltStyle
					if name == "Helmet":
						look.helmet = Rider.DEFAULT_LOOK.helmet; look.hairStyle = Rider.DEFAULT_LOOK.hairStyle
			look_touched = true
	if pose_touched: _apply_pose()
	if look_touched: _apply_look()
	game.flash("%s reset" % cat[0])
	_fill()
