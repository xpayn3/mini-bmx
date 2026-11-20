class_name PadKeyboard
extends CanvasLayer
## On-screen keyboard for a LineEdit on a gamepad (console style). PadNav opens it when A is pressed on a
## focused LineEdit with the pad: D-pad / stick move over the keys, A types, X deletes, Y adds a space,
## Menu (Start) or DONE accepts (fires text_submitted, like Enter), B cancels (puts the old text back).
## Works in any viewport (the paper sheets' pages too): it is added to the field's own viewport.

const ROWS := ["1234567890", "QWERTYUIOP", "ASDFGHJKL-", "ZXCVBNM_.#"]

var field: LineEdit
var _old := ""
var _shown: Label
var _done := false

static var _open: PadKeyboard

static func is_open() -> bool:
	return is_instance_valid(_open)

static func open(le: LineEdit) -> PadKeyboard:
	if is_instance_valid(_open): return _open
	var k := PadKeyboard.new()
	k.field = le
	le.get_viewport().add_child(k)
	_open = k
	return k


func _ready() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group(&"nav_modal")   # a paper sheet keeps B for us (cancel) instead of folding
	_old = field.text
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.45)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var root := Control.new()   # PadNav root: the newest PadNav in the viewport is the only one navigating
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", UITheme.card_style(Tokens.PAPER, Tokens.R_XL, Tokens.S6))
	card.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	card.grow_horizontal = Control.GROW_DIRECTION_BOTH
	card.grow_vertical = Control.GROW_DIRECTION_BEGIN
	card.offset_bottom = -Tokens.S8
	root.add_child(card)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", Tokens.S2)
	card.add_child(vb)
	var title := field.placeholder_text if field.placeholder_text != "" else "ENTER TEXT"
	vb.add_child(UITheme.caption(title.to_upper(), Tokens.INK_SOFT, Tokens.T_SM))
	_shown = UITheme.display("", Tokens.T_2XL, Tokens.INK, 0.0)
	_shown.custom_minimum_size.y = Tokens.S8
	vb.add_child(_shown)
	var first: Button
	for r in ROWS:
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", Tokens.S2)
		for ch in r:
			var b := _key(ch, _type.bind(ch))
			if first == null: first = b
			hb.add_child(b)
		vb.add_child(hb)
	var last := HBoxContainer.new()
	last.add_theme_constant_override("separation", Tokens.S2)
	for it in [["SPACE  (Y)", _type.bind(" "), 4], ["DELETE  (X)", _del, 3], ["DONE  (MENU)", _accept, 3]]:
		var b := _key(it[0], it[1])
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.size_flags_stretch_ratio = it[2]
		last.add_child(b)
	vb.add_child(last)
	vb.add_child(UITheme.text("A type  ·  X delete  ·  Y space  ·  MENU done  ·  B cancel", Tokens.INK_SOFT, Tokens.T_XS))
	_refresh()
	PadNav.attach(root, {"back": _cancel, "first": func(): return first})
	first.grab_focus.call_deferred()


func _key(text: String, cb: Callable) -> Button:
	var b := UITheme.make_button(text, cb, "chip", Tokens.T_LG)
	b.custom_minimum_size = Vector2(52, 48)
	return b


func _input(e: InputEvent) -> void:
	if _done: return
	if e is InputEventJoypadButton and e.pressed:
		match e.button_index:
			JOY_BUTTON_X: _del()
			JOY_BUTTON_Y: _type(" ")
			JOY_BUTTON_START: _accept()
			_: return
		get_viewport().set_input_as_handled()
	elif e is InputEventKey and e.pressed and not e.echo:   # a keyboard still works while it's up
		if e.keycode == KEY_ENTER or e.keycode == KEY_KP_ENTER: _accept()
		elif e.keycode == KEY_BACKSPACE: _del()
		elif e.unicode >= 32: _type(char(e.unicode))
		else: return
		get_viewport().set_input_as_handled()


func _type(ch: String) -> void:
	if field.max_length > 0 and field.text.length() >= field.max_length: return
	_put_text(field.text + ch)

func _del() -> void:
	if field.text != "": _put_text(field.text.substr(0, field.text.length() - 1))

func _put_text(t: String) -> void:
	field.text = t
	field.caret_column = t.length()
	field.text_changed.emit(t)
	_refresh()

func _refresh() -> void:
	_shown.text = field.text + "_"


func _accept() -> void:
	_close()
	field.text_submitted.emit(field.text)

func _cancel() -> void:
	if field.text != _old: _put_text(_old)
	_close()

func _close() -> void:
	if _done: return
	_done = true
	if is_instance_valid(field): field.grab_focus.call_deferred()
	queue_free()
