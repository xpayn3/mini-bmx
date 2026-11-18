class_name RiderPanels
extends RefCounted
## The web version's rider panels: K = rider position / movement sliders (saved per bike),
## L = rider look (kits + a colour per part). Saved in user://rider.cfg.

const PATH := "user://rider.cfg"

const POSE_DEFS := [
	["Body position", [
		["hipX", "Hips forward / back", -0.25, 0.25, 0.005, "m"],
		["hipY", "Hips up / down", -0.2, 0.2, 0.005, "m"],
		["lean", "Chest lean forward", -0.4, 0.7, 0.01, "rad"],
		["torso", "Torso length", 0.36, 0.56, 0.005, "m"],
	]],
	["Arms & legs", [
		["elbowsOut", "Elbows out", -1.0, 1.0, 0.05, ""],
		["shoulders", "Shoulder width", 0.095, 0.235, 0.005, "m"],
		["kneesOut", "Knees out", -0.3, 0.7, 0.05, ""],
		["stance", "Hip width", -0.09, 0.04, 0.005, "m"],
	]],
	["Torso & hips", [
		["hipZ", "Hips side shift", -0.15, 0.15, 0.005, "m"],
		["pelvisTilt", "Pelvis tilt", -0.5, 0.5, 0.01, "rad"],
		["chestFwd", "Chest forward / back", -0.2, 0.2, 0.005, "m"],
		["chestUp", "Chest up / down", -0.2, 0.2, 0.005, "m"],
		["chestSide", "Chest side bend", -0.15, 0.15, 0.005, "m"],
		["twist", "Torso twist", -0.6, 0.6, 0.01, "rad"],
	]],
	["Head", [
		["headTilt", "Head tilt (+ looks down)", -0.5, 0.5, 0.01, "rad"],
		["lookAhead", "Head forward", -0.08, 0.12, 0.005, "m"],
		["neck", "Neck length", -0.06, 0.08, 0.005, "m"],
		["headYaw", "Head turn (fixed)", -0.8, 0.8, 0.01, "rad"],
		["headRoll", "Head roll", -0.5, 0.5, 0.01, "rad"],
		["headTurn", "Look into turns", 0.0, 2.0, 0.05, "×"],
	]],
	["Shoulders & arms", [
		["shoulderFwd", "Shoulders forward / back", -0.1, 0.1, 0.005, "m"],
		["shoulderUp", "Shoulders up / down", -0.1, 0.1, 0.005, "m"],
		["elbowsDown", "Elbows down / up", -1.0, 1.0, 0.05, ""],
		["elbowOutL", "Left elbow out", -1.0, 1.0, 0.05, ""],
		["elbowOutR", "Right elbow out", -1.0, 1.0, 0.05, ""],
		["wristRoll", "Wrist roll", -0.8, 0.8, 0.02, "rad"],
	]],
	["Legs & feet", [
		["kneesFwd", "Knees forward / back", -0.8, 0.8, 0.05, ""],
		["kneeOutL", "Left knee out", -0.5, 0.5, 0.05, ""],
		["kneeOutR", "Right knee out", -0.5, 0.5, 0.05, ""],
		["heelFwd", "Heels forward / back", -0.08, 0.08, 0.005, "m"],
		["heelUp", "Heels up / down", -0.06, 0.08, 0.005, "m"],
		["footAngle", "Foot angle (toes down)", -0.5, 0.5, 0.01, "rad"],
		["footOut", "Toes out", -0.4, 0.6, 0.01, "rad"],
	]],
	["Movement", [
		["crouch", "Crouch depth", 0.0, 2.0, 0.05, "×"],
		["standPedal", "Stand up to pedal", 0.0, 2.0, 0.05, "×"],
		["sway", "Body sway", 0.0, 2.0, 0.05, "×"],
		["bikeRock", "Bike rock (sprint)", 0.0, 2.0, 0.05, "×"],
		["upright", "Torso stays upright", 0.0, 1.0, 0.05, ""],
		["hipSway", "Hip sway", 0.0, 0.12, 0.005, "m"],
	]],
]

const KITS := [
	["Classic", {}],   # = Rider.DEFAULT_LOOK
	["Stealth", {"shell": "#0c0d0f", "peak": "#1a1b1e", "goggleFrame": "#18191c", "lens": "#8a96a8", "strap": "#2a2c30",
		"jersey": "#2b2e33", "pants": "#111215", "gloves": "#3a3d42", "shoes": "#141518", "shoeAccent": "#3a3d42"}],
	["Race white", {"shell": "#f4f4f0", "peak": "#e8231f", "goggleFrame": "#e8231f", "lens": "#3fb6ff", "strap": "#e8231f",
		"jersey": "#f4f4f0", "pants": "#202227", "gloves": "#e8231f", "shoes": "#f4f4f0", "shoeAccent": "#e8231f"}],
	["Monster", {"shell": "#7ed321", "peak": "#111214", "goggleFrame": "#111214", "lens": "#7ed321", "strap": "#7ed321",
		"jersey": "#111214", "pants": "#2c2f33", "gloves": "#7ed321", "shoes": "#111214", "shoeAccent": "#7ed321"}],
	["Ocean", {"shell": "#1478d4", "peak": "#f4f4f0", "goggleFrame": "#f4f4f0", "lens": "#ff9f2e", "strap": "#1478d4",
		"jersey": "#11b3c9", "pants": "#0d2847", "gloves": "#f4f4f0", "shoes": "#0d2847", "shoeAccent": "#11b3c9"}],
	["Sunset", {"shell": "#ff7a1a", "peak": "#6a1b9a", "goggleFrame": "#6a1b9a", "lens": "#ffd21f", "strap": "#ff7a1a",
		"jersey": "#6a1b9a", "pants": "#2a2140", "gloves": "#ff7a1a", "shoes": "#2a2140", "shoeAccent": "#ff7a1a"}],
]
const SW := ["#f4f4f0", "#16171a", "#e8231f", "#ff7a1a", "#ffd21f", "#7ed321", "#11b3c9", "#1478d4", "#6a1b9a", "#ff5fa2"]
const LENS := ["#ff7a2a", "#ffd21f", "#3fb6ff", "#7ed321", "#ff5fa2", "#8a96a8", "#d0d4da"]
const LOOK_ROWS := [
	["Helmet", [["shell", "Shell", SW], ["peak", "Peak", SW]]],
	["Goggles", [["lens", "Lens tint", LENS], ["goggleFrame", "Frame", SW], ["strap", "Strap", SW]]],
	["Kit", [["jersey", "Jersey", SW], ["pants", "Pants", SW], ["gloves", "Gloves", SW], ["pads", "Shoulder pads", SW]]],
	["Shoes", [["shoes", "Upper", SW], ["shoeAccent", "Toe & collar", SW]]],
]

# ---------------------------------------------------------------- persistence
static func load_pose(bike_id: String, bike_pose: Dictionary) -> Dictionary:
	var p: Dictionary = Rider.NEUTRAL.duplicate()
	p.merge(bike_pose, true)
	var cf := ConfigFile.new()
	if cf.load(PATH) == OK and cf.has_section("pose_" + bike_id):
		for k in cf.get_section_keys("pose_" + bike_id):
			if p.has(k) and typeof(cf.get_value("pose_" + bike_id, k)) in [TYPE_FLOAT, TYPE_INT, TYPE_BOOL]:
				p[k] = cf.get_value("pose_" + bike_id, k)
	return p

static func save_pose(bike_id: String, p: Dictionary) -> void:
	var cf := ConfigFile.new(); cf.load(PATH)
	if cf.has_section("pose_" + bike_id): cf.erase_section("pose_" + bike_id)
	for k in p: cf.set_value("pose_" + bike_id, k, p[k])
	cf.save(PATH)

static func load_look() -> Dictionary:
	var l: Dictionary = Rider.DEFAULT_LOOK.duplicate()
	var cf := ConfigFile.new()
	if cf.load(PATH) == OK and cf.has_section("look"):
		for k in cf.get_section_keys("look"):
			if l.has(k): l[k] = str(cf.get_value("look", k))
	return l

static func save_look(l: Dictionary) -> void:
	var cf := ConfigFile.new(); cf.load(PATH)
	for k in l: cf.set_value("look", k, l[k])
	cf.save(PATH)

# ---------------------------------------------------------------- shared panel frame
static func _frame(title: String, sub: String, on_reset: Callable) -> Array:
	var p := PanelContainer.new()
	p.theme = UITheme.get_theme()
	p.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	p.offset_left = -360; p.offset_right = -14; p.offset_top = 64; p.offset_bottom = -90
	p.mouse_filter = Control.MOUSE_FILTER_STOP
	var vb := VBoxContainer.new()
	p.add_child(vb)
	var head := HBoxContainer.new()
	var t := UITheme.label(title, 18, UITheme.ACCENT, true)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	head.add_child(UITheme.button("Reset", on_reset, 14))
	head.add_child(UITheme.close_button(func(): p.get_tree().call_group("hud", "close_sides")))
	vb.add_child(head)
	vb.add_child(UITheme.label(sub, 12, UITheme.MUTED))
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vb.add_child(sc)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(list)
	return [p, list]

# ---------------------------------------------------------------- K: rider position
class PosePanel extends Control:
	var game
	var pose: Dictionary
	var defaults: Dictionary
	var list: VBoxContainer
	func _init(g) -> void:
		game = g
		set_anchors_preset(Control.PRESET_FULL_RECT)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		defaults = Rider.NEUTRAL.duplicate(); defaults.merge(GameState.BIKES[GameState.bike_id].pose, true)
		pose = RiderPanels.load_pose(GameState.bike_id, GameState.BIKES[GameState.bike_id].pose)
		var f := RiderPanels._frame("RIDER POSITION", "%s · saved per bike · K closes" % GameState.BIKES[GameState.bike_id].label,
			func(): pose = defaults.duplicate(); _apply(); _fill())
		add_child(f[0]); list = f[1]
		_fill()
	func _fill() -> void:
		for c in list.get_children(): c.queue_free()
		var side := UITheme.button("Side view", func(): game.cam.set_mode("side"); game.flash("Side view"), 14)
		list.add_child(side)
		for g in RiderPanels.POSE_DEFS:
			list.add_child(UITheme.label(g[0].to_upper(), 13, UITheme.ACCENT, true))
			for row in g[1]:
				_slider(row)
	func _slider(row: Array) -> void:
		var key: String = row[0]
		var hb := HBoxContainer.new()
		var l := UITheme.label(row[1], 13); l.size_flags_horizontal = Control.SIZE_EXPAND_FILL; l.clip_text = true
		var s := HSlider.new()
		s.min_value = row[2]; s.max_value = row[3]; s.step = row[4]; s.value = float(pose.get(key, 0.0))
		s.size_flags_horizontal = Control.SIZE_EXPAND_FILL; s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		s.focus_mode = Control.FOCUS_NONE
		var vl := UITheme.label(_fmt(s.value, row[4], row[5]), 12, UITheme.MUTED)
		vl.custom_minimum_size.x = 64; vl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		s.value_changed.connect(func(v): vl.text = _fmt(v, row[4], row[5]); pose[key] = v; _apply())
		hb.add_child(l); hb.add_child(vl)
		hb.add_child(UITheme.reset_button(s, float(defaults.get(key, 0.0))))
		list.add_child(hb)
		list.add_child(s)
	func _fmt(v: float, stp: float, unit: String) -> String:
		var d := clampi(ceili(-log(stp) / log(10.0)), 0, 4)
		return ("%." + str(d) + "f %s") % [v, unit]
	func _apply() -> void:
		game.rider.set_style(pose)
		game.phys.bike_rock = float(pose.get("bikeRock", 1.0))
		RiderPanels.save_pose(GameState.bike_id, pose)

# ---------------------------------------------------------------- L: rider look
class LookPanel extends Control:
	var game
	var look: Dictionary
	var list: VBoxContainer
	func _init(g) -> void:
		game = g
		set_anchors_preset(Control.PRESET_FULL_RECT)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		look = RiderPanels.load_look()
		var f := RiderPanels._frame("RIDER LOOK", "Helmet, goggles, kit and shoes · L closes",
			func(): look = Rider.DEFAULT_LOOK.duplicate(); _apply(); _fill())
		add_child(f[0]); list = f[1]
		_fill()
	func _fill() -> void:
		for c in list.get_children(): c.queue_free()
		list.add_child(UITheme.label("KITS", 13, UITheme.ACCENT, true))
		var kits := GridContainer.new(); kits.columns = 3
		kits.add_theme_constant_override("h_separation", 6); kits.add_theme_constant_override("v_separation", 6)
		for k in RiderPanels.KITS:
			var b := UITheme.button(k[0], func():
				look = Rider.DEFAULT_LOOK.duplicate(); look.merge(k[1], true); _apply(); _fill(), 13)
			b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			kits.add_child(b)
		list.add_child(kits)
		for g in RiderPanels.LOOK_ROWS:
			list.add_child(UITheme.label(g[0].to_upper(), 13, UITheme.ACCENT, true))
			for row in g[1]:
				var key: String = row[0]
				var hb := HBoxContainer.new()
				var l := UITheme.label(row[1], 13); l.custom_minimum_size.x = 92
				hb.add_child(l)
				for hex in row[2]:
					var b := Button.new()
					b.custom_minimum_size = Vector2(20, 20)
					var on: bool = str(look[key]).to_lower() == str(hex).to_lower()
					b.add_theme_stylebox_override("normal", UITheme.box(Color(hex), 10, 0, Color.WHITE if on else Color(1, 1, 1, 0.2), 2 if on else 1))
					b.add_theme_stylebox_override("hover", UITheme.box(Color(hex), 10, 0, UITheme.ACCENT, 2))
					b.add_theme_stylebox_override("pressed", UITheme.box(Color(hex), 10, 0, UITheme.ACCENT, 2))
					b.focus_mode = Control.FOCUS_NONE
					b.pressed.connect(func(): look[key] = hex; _apply(); _fill())
					hb.add_child(b)
				var cp := ColorPickerButton.new()
				cp.color = Color(look[key]); cp.edit_alpha = false
				cp.custom_minimum_size = Vector2(26, 20)
				cp.color_changed.connect(func(c): look[key] = "#" + c.to_html(false); _apply())
				hb.add_child(cp)
				list.add_child(hb)
	func _apply() -> void:
		game.rider.set_look(look)
		RiderPanels.save_look(look)
