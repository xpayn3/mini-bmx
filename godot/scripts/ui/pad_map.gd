class_name PadMap
extends Control
## Settings › Controller: an Xbox controller drawn in the middle with a callout for every button,
## trigger and stick showing what it does. Click a callout (or the button on the pad) to put another
## action on it; sticks pick a role (Steer / Rider body / Camera / Nothing) and swap with the other
## stick. Buttons light up while pressed, the sticks follow the thumbs: a live pad tester too.

signal changed

const PAD := Vector2(360, 250)            # the controller drawing's own size
const ROW := 46.0
const LABEL_W := 196.0

const C_BODY := Color(0.86, 0.87, 0.89)
const C_EDGE := Color(0.55, 0.57, 0.6)
const C_DARK := Color(0.2, 0.21, 0.23)
const C_HOT := Color(0.12, 0.52, 1.0)
const FACE := {0: Color(0.33, 0.75, 0.3), 1: Color(0.86, 0.26, 0.24), 2: Color(0.25, 0.5, 0.92), 3: Color(0.95, 0.75, 0.16)}

## stick roles: [action, axis (0 = x, 1 = y), direction]
const ROLES := {
	"Steer": [["steer_left", 0, -1], ["steer_right", 0, 1]],
	"Rider body": [["body_fwd", 1, -1], ["body_back", 1, 1], ["body_left", 0, -1], ["body_right", 0, 1]],
	"Camera": [["cam_left", 0, -1], ["cam_right", 0, 1], ["cam_up", 1, -1], ["cam_down", 1, 1]],
	"Nothing": [],
}
const ROLE_NAMES := ["Steer", "Rider body", "Camera", "Nothing"]

## [id, label, kind ("btn" / "trig" / "stick"), index (button / axis / stick 0 left 1 right), pad point, side, row]
var controls := [
	["lt", "LT", "trig", JOY_AXIS_TRIGGER_LEFT, Vector2(108, 8), 0, 0],
	["lb", "LB", "btn", JOY_BUTTON_LEFT_SHOULDER, Vector2(100, 32), 0, 1],
	["view", "View", "btn", JOY_BUTTON_BACK, Vector2(152, 92), 0, 2],
	["ls", "Left stick", "stick", 0, Vector2(100, 92), 0, 3],
	["dup", "D-pad up", "btn", JOY_BUTTON_DPAD_UP, Vector2(140, 128), 0, 4],
	["dleft", "D-pad left", "btn", JOY_BUTTON_DPAD_LEFT, Vector2(124, 144), 0, 5],
	["dright", "D-pad right", "btn", JOY_BUTTON_DPAD_RIGHT, Vector2(156, 144), 0, 6],
	["ddown", "D-pad down", "btn", JOY_BUTTON_DPAD_DOWN, Vector2(140, 160), 0, 7],
	["rt", "RT", "trig", JOY_AXIS_TRIGGER_RIGHT, Vector2(252, 8), 1, 0],
	["rb", "RB", "btn", JOY_BUTTON_RIGHT_SHOULDER, Vector2(260, 32), 1, 1],
	["menu", "Menu", "btn", JOY_BUTTON_START, Vector2(208, 92), 1, 2],
	["y", "Y", "btn", JOY_BUTTON_Y, Vector2(262, 70), 1, 3],
	["b", "B", "btn", JOY_BUTTON_B, Vector2(286, 94), 1, 4],
	["x", "X", "btn", JOY_BUTTON_X, Vector2(238, 94), 1, 5],
	["a", "A", "btn", JOY_BUTTON_A, Vector2(262, 118), 1, 6],
	["rs", "Right stick", "stick", 1, Vector2(220, 144), 1, 7],
]

## the controller photo (background cut out by tools/cut_pad.py); without it the pad is drawn
const PHOTO_PATH := "res://assets/ui/xbox_pad.png"
## where each control sits on the photo, as a fraction of its width / height
const PHOTO_AT := {
	"lt": Vector2(0.223, 0.02), "lb": Vector2(0.279, 0.055), "rt": Vector2(0.777, 0.02), "rb": Vector2(0.721, 0.055),
	"view": Vector2(0.433, 0.263), "menu": Vector2(0.571, 0.263), "ls": Vector2(0.256, 0.266), "rs": Vector2(0.628, 0.475),
	"y": Vector2(0.746, 0.176), "x": Vector2(0.683, 0.263), "b": Vector2(0.810, 0.269), "a": Vector2(0.746, 0.359),
	"dup": Vector2(0.377, 0.43), "ddown": Vector2(0.377, 0.555), "dleft": Vector2(0.335, 0.491), "dright": Vector2(0.421, 0.491),
}
var _photo: Texture2D

var _hover := ""
var _popup: PopupMenu
var _popup_ctl: Array = []
var _popup_items: Array = []

func _ready() -> void:
	custom_minimum_size = Vector2(LABEL_W * 2 + PAD.x + 40, ROW * 8 + 30)
	if ResourceLoader.exists(PHOTO_PATH):
		_photo = load(PHOTO_PATH)
		var sz := _photo_size()
		for c in controls:
			c[4] = PHOTO_AT[c[0]] * sz
	mouse_filter = Control.MOUSE_FILTER_STOP
	_popup = PopupMenu.new()
	_popup.theme = UITheme.light_theme()
	add_child(_popup)
	_popup.id_pressed.connect(_picked)

func _process(_dt: float) -> void:
	if is_visible_in_tree(): queue_redraw()   # live: pressed buttons, stick positions

# ------------------------------------------------------------------ layout
func _pad_origin() -> Vector2:
	return Vector2((size.x - PAD.x) * 0.5, (size.y - PAD.y) * 0.5 + 6)

func _label_rect(c: Array) -> Rect2:
	var y: float = 8.0 + c[6] * ROW
	var x: float = 0.0 if c[5] == 0 else size.x - LABEL_W
	return Rect2(x, y, LABEL_W, ROW - 6)

func _hit(p: Vector2) -> String:
	for c in controls:
		if _label_rect(c).has_point(p): return c[0]
	var o := _pad_origin()
	for c in controls:
		if p.distance_to(o + c[4]) < (22.0 if c[2] == "stick" else 13.0): return c[0]
	return ""

func _ctl(id: String) -> Array:
	for c in controls:
		if c[0] == id: return c
	return []

# ------------------------------------------------------------------ what is bound where
static func _short(action: String) -> String:
	var n: String = Settings.ACTIONS[action][0]
	var i := n.find(" (")
	return n.substr(0, i) if i > 0 else n

func _actions_on(c: Array) -> Array:
	var out := []
	for a in Settings.ACTIONS:
		for e in InputMap.action_get_events(a):
			if c[2] == "btn" and e is InputEventJoypadButton and e.button_index == c[3]: out.append(a)
			elif c[2] == "trig" and e is InputEventJoypadMotion and e.axis == c[3]: out.append(a)
	return out

static func stick_axes(stick: int) -> Array:
	return [JOY_AXIS_LEFT_X, JOY_AXIS_LEFT_Y] if stick == 0 else [JOY_AXIS_RIGHT_X, JOY_AXIS_RIGHT_Y]

## the role a stick has now (what its X axis drives)
static func role_of(stick: int) -> String:
	var ax: Array = stick_axes(stick)
	for r in ROLE_NAMES:
		if r == "Nothing": continue
		var first: Array = ROLES[r][0]
		for e in InputMap.action_get_events(first[0]):
			if e is InputEventJoypadMotion and e.axis == ax[first[1]] and signf(e.axis_value) == first[2]: return r
	return "Nothing"

static func set_role(stick: int, role: String) -> void:
	var other := 1 - stick
	var old := role_of(stick)
	if role != "Nothing" and role_of(other) == role and old != role:
		_apply_role(other, old)   # swap: the other stick takes what this one had
	_apply_role(stick, role)

static func _apply_role(stick: int, role: String) -> void:
	var ax: Array = stick_axes(stick)
	Settings.clear_pad_axes(ax)
	for r in ROLES[role]:
		var e := InputEventJoypadMotion.new()
		e.axis = ax[r[1]]; e.axis_value = r[2]
		Settings.set_pad(r[0], e)

func _text_of(c: Array) -> String:
	if c[2] == "stick": return role_of(c[3])
	var acts := _actions_on(c)
	if acts.is_empty(): return "—"
	return ", ".join(acts.map(func(a): return _short(a)))

# ------------------------------------------------------------------ live state
func _pressed(c: Array) -> bool:
	var dev := Input.get_connected_joypads()
	if dev.is_empty(): return false
	var d: int = dev[0]
	if c[2] == "btn": return Input.is_joy_button_pressed(d, c[3])
	if c[2] == "trig": return Input.get_joy_axis(d, c[3]) > 0.3
	var ax: Array = stick_axes(c[3])
	return Vector2(Input.get_joy_axis(d, ax[0]), Input.get_joy_axis(d, ax[1])).length() > 0.3 \
		or Input.is_joy_button_pressed(d, JOY_BUTTON_LEFT_STICK if c[3] == 0 else JOY_BUTTON_RIGHT_STICK)

func _stick_off(stick: int) -> Vector2:
	var dev := Input.get_connected_joypads()
	if dev.is_empty(): return Vector2.ZERO
	var ax: Array = stick_axes(stick)
	return Vector2(Input.get_joy_axis(dev[0], ax[0]), Input.get_joy_axis(dev[0], ax[1])).limit_length(1.0) * 7.0

# ------------------------------------------------------------------ drawing
func _draw() -> void:
	var o := _pad_origin()
	draw_style_box(_box(Color("e9edf4"), UITheme.L_LINE), Rect2(Vector2.ZERO, size))   # soft backdrop so the white pad stands out
	var f := UITheme.font(true)
	var fr := UITheme.font(false)
	# callout lines first: the controller is drawn over them, only their ends show
	for c in controls:
		var r := _label_rect(c)
		var on: bool = _hover == c[0] or _pressed(c)
		var anchor: Vector2 = o + c[4]
		var edge := Vector2(r.end.x, r.get_center().y) if c[5] == 0 else Vector2(r.position.x, r.get_center().y)
		var mid := Vector2(anchor.x + (-26.0 if c[5] == 0 else 26.0), edge.y)
		if c[2] == "trig" or c[0] in ["lb", "rb"]: mid.x = anchor.x
		draw_polyline(PackedVector2Array([edge, mid, anchor]), C_HOT if on else Color(0.2, 0.25, 0.35, 0.3), 2.0 if on else 1.2, true)
	_draw_pad(o)
	for c in controls:
		var r := _label_rect(c)
		var hot: bool = _hover == c[0]
		var lit: bool = _pressed(c)
		var col := C_HOT if (hot or lit) else UITheme.L_LINE
		var bg := Color(1, 1, 1, 1.0 if hot else 0.85)
		if lit: bg = Color(0.85, 0.92, 1.0)
		draw_style_box(_box(bg, col), r)
		var al := HORIZONTAL_ALIGNMENT_RIGHT if c[5] == 0 else HORIZONTAL_ALIGNMENT_LEFT
		var tx := r.position.x + 10
		var tw := r.size.x - 20
		draw_string(f, Vector2(tx, r.position.y + 15), c[1].to_upper(), al, tw, 11, UITheme.L_MUTED)
		draw_string(fr, Vector2(tx, r.position.y + 33), _text_of(c), al, tw, 15, UITheme.L_INK if _text_of(c) != "—" else UITheme.L_MUTED)
	if Input.get_connected_joypads().is_empty():
		draw_string(fr, Vector2(0, size.y - 4), "No controller connected — plug one in to test the buttons live", HORIZONTAL_ALIGNMENT_CENTER, size.x, 13, UITheme.L_MUTED)
	else:
		draw_string(fr, Vector2(0, size.y - 4), Input.get_joy_name(Input.get_connected_joypads()[0]), HORIZONTAL_ALIGNMENT_CENTER, size.x, 13, UITheme.L_MUTED)

func _box(bg: Color, border: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg; s.border_color = border
	s.set_border_width_all(1); s.set_corner_radius_all(7)
	return s

func _ell(c: Vector2, r: Vector2, rot: float, n := 28) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in n:
		var a := TAU * i / n
		pts.append(c + Vector2(cos(a) * r.x, sin(a) * r.y).rotated(rot))
	return pts

func _rrect(rc: Rect2, rad: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var cs := [Vector2(rc.end.x - rad, rc.position.y + rad), Vector2(rc.end.x - rad, rc.end.y - rad),
		Vector2(rc.position.x + rad, rc.end.y - rad), Vector2(rc.position.x + rad, rc.position.y + rad)]
	for k in 4:
		for i in 7:
			var a := -PI * 0.5 + (k + i / 6.0) * PI * 0.5
			pts.append(cs[k] + Vector2(cos(a), sin(a)) * rad)
	return pts

## the shell: a wide body and two grips swept down and out, drawn as overlapping shapes (edge first)
func _shell(o: Vector2, grow: float, col: Color) -> void:
	draw_colored_polygon(_rrect(Rect2(o + Vector2(52, 38) - Vector2.ONE * grow, Vector2(256, 118) + Vector2.ONE * grow * 2), 52 + grow), col)
	draw_colored_polygon(_ell(o + Vector2(92, 168), Vector2(52, 76) + Vector2.ONE * grow, 0.42), col)
	draw_colored_polygon(_ell(o + Vector2(268, 168), Vector2(52, 76) + Vector2.ONE * grow, -0.42), col)

func _photo_size() -> Vector2:
	var ts := _photo.get_size()
	return Vector2(PAD.x, PAD.x * ts.y / ts.x)

## the photo with what's pressed / hovered glowing on top, and a ring following each thumb
func _draw_photo(o: Vector2) -> void:
	draw_texture_rect(_photo, Rect2(o, _photo_size()), false)
	for c in controls:
		var on: bool = _pressed(c) or _hover == c[0]
		var p: Vector2 = o + c[4]
		if c[2] == "stick":
			var k: Vector2 = p + _stick_off(c[3]) * 1.4
			if on: draw_circle(k, 17, Color(C_HOT.r, C_HOT.g, C_HOT.b, 0.45))
			draw_arc(k, 17, 0, TAU, 32, C_HOT if on else Color(1, 1, 1, 0.0), 2.0, true)
		elif on:
			var r := 9.0 if c[0].begins_with("d") or c[0] in ["view", "menu"] else 12.0
			if c[2] == "trig" or c[0] in ["lb", "rb"]: r = 14.0
			draw_circle(p, r, Color(C_HOT.r, C_HOT.g, C_HOT.b, 0.5))
			draw_arc(p, r, 0, TAU, 28, C_HOT, 2.0, true)

func _draw_pad(o: Vector2) -> void:
	if _photo:
		_draw_photo(o)
		return
	# triggers + bumpers behind the shell
	for c in [_ctl("lt"), _ctl("rt")]:
		var x: float = c[4].x
		draw_colored_polygon(_rrect(Rect2(o + Vector2(x - 34, -2), Vector2(68, 30)), 10), C_HOT if (_pressed(c) or _hover == c[0]) else C_DARK)
	for c in [_ctl("lb"), _ctl("rb")]:
		var x: float = c[4].x
		draw_colored_polygon(_rrect(Rect2(o + Vector2(x - 50, 22), Vector2(100, 26)), 11), C_HOT if (_pressed(c) or _hover == c[0]) else Color(0.32, 0.33, 0.36))
	_shell(o, 2.5, C_EDGE)
	_shell(o, 0.0, C_BODY)
	# guide button
	draw_circle(o + Vector2(180, 62), 15, Color(0.32, 0.33, 0.36))
	draw_circle(o + Vector2(180, 62), 11, Color(0.75, 0.77, 0.8))
	draw_arc(o + Vector2(180, 62), 7, 0, TAU, 20, Color(0.32, 0.33, 0.36), 2.0, true)
	# view / menu
	for id in ["view", "menu"]:
		var c := _ctl(id)
		draw_circle(o + c[4], 8, C_HOT if (_pressed(c) or _hover == id) else C_DARK)
	# sticks
	for id in ["ls", "rs"]:
		var c := _ctl(id)
		var p: Vector2 = o + c[4]
		draw_circle(p, 25, Color(0.6, 0.62, 0.65))
		draw_circle(p, 22, Color(0.12, 0.12, 0.13))
		var k: Vector2 = p + _stick_off(c[3])
		draw_circle(k, 16, C_HOT if (_pressed(c) or _hover == id) else Color(0.24, 0.25, 0.27))
		draw_arc(k, 11, 0, TAU, 24, Color(0.08, 0.08, 0.09), 1.5, true)
	# d-pad
	var dc: Vector2 = o + Vector2(140, 144)
	draw_circle(dc, 26, Color(0.75, 0.77, 0.8))
	draw_rect(Rect2(dc + Vector2(-7, -22), Vector2(14, 44)), C_DARK)
	draw_rect(Rect2(dc + Vector2(-22, -7), Vector2(44, 14)), C_DARK)
	for id in ["dup", "ddown", "dleft", "dright"]:
		var c := _ctl(id)
		if _pressed(c) or _hover == id:
			draw_rect(Rect2(o + c[4] - Vector2(7, 7), Vector2(14, 14)), C_HOT)
	# face buttons
	for id in ["a", "b", "x", "y"]:
		var c := _ctl(id)
		var p: Vector2 = o + c[4]
		var lit: bool = _pressed(c) or _hover == id
		draw_circle(p, 13, C_DARK)
		draw_circle(p, 11, (FACE[c[3]] as Color).lightened(0.35) if lit else C_DARK.lightened(0.08))
		var fb := UITheme.font(true)
		var ts := fb.get_string_size(c[1], HORIZONTAL_ALIGNMENT_LEFT, -1, 14)
		draw_string(fb, p + Vector2(-ts.x * 0.5, fb.get_ascent(14) * 0.5 - 1), c[1], HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color.WHITE if lit else FACE[c[3]])

# ------------------------------------------------------------------ input
func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseMotion:
		var h := _hit(e.position)
		if h != _hover:
			_hover = h
			mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if h != "" else Control.CURSOR_ARROW
			tooltip_text = "Click to change what this does" if h != "" else ""
	elif e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
		var h := _hit(e.position)
		if h != "":
			_open(_ctl(h), get_global_mouse_position())
			accept_event()

func _open(c: Array, at: Vector2) -> void:
	_popup.clear()
	_popup_ctl = c
	_popup_items = []
	if c[2] == "stick":
		var cur := role_of(c[3])
		for r in ROLE_NAMES:
			_popup.add_radio_check_item(r, _popup_items.size())
			_popup.set_item_checked(_popup_items.size(), r == cur)
			_popup_items.append(r)
	else:
		var cur := _actions_on(c)
		for a in Settings.ACTIONS:
			if a.begins_with("body_") or a.begins_with("cam_"): continue   # stick roles
			_popup.add_radio_check_item(_short(a), _popup_items.size())
			_popup.set_item_checked(_popup_items.size(), a in cur)
			_popup_items.append(a)
	_popup.reset_size()
	_popup.position = Vector2i(at)
	_popup.popup()

func _picked(id: int) -> void:
	if _popup_ctl.is_empty() or id >= _popup_items.size(): return
	var c := _popup_ctl
	if c[2] == "stick":
		set_role(c[3], _popup_items[id])
	elif c[2] == "trig":
		var e := InputEventJoypadMotion.new(); e.axis = c[3]; e.axis_value = 1.0
		Settings.set_pad(_popup_items[id], e)
	else:
		var e := InputEventJoypadButton.new(); e.button_index = c[3]
		Settings.set_pad(_popup_items[id], e)
	changed.emit()
	queue_redraw()
