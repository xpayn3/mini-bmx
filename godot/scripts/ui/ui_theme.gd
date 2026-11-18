class_name UITheme
extends RefCounted
## The game's look: dark translucent glass panels, bold rounded type, yellow accent (from index.html).

const ACCENT := Color("ffd21f")
const NAVY := Color("1d2b64")
const PANEL := Color(0.08, 0.15, 0.2, 0.82)
const PANEL_LIGHT := Color(1, 1, 1, 0.10)
const TEXT := Color(1, 1, 1)
const MUTED := Color(1, 1, 1, 0.6)

static var _theme: Theme
static var _font: Font
static var _font_black: Font

static func font(black := false) -> Font:
	if _font == null:
		var f := SystemFont.new()
		f.font_names = PackedStringArray(["Segoe UI", "Helvetica Neue", "Arial", "Noto Sans"])
		f.font_weight = 700
		f.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
		_font = f
		var b := SystemFont.new()
		b.font_names = f.font_names
		b.font_weight = 900
		_font_black = b
	return _font_black if black else _font

static func box(bg: Color, radius := 12, pad := 10, border := Color(0, 0, 0, 0), bw := 0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(radius)
	s.content_margin_left = pad; s.content_margin_right = pad
	s.content_margin_top = pad * 0.6; s.content_margin_bottom = pad * 0.6
	if bw > 0:
		s.border_color = border; s.set_border_width_all(bw)
	s.anti_aliasing = true
	return s

static func get_theme() -> Theme:
	if _theme: return _theme
	var t := Theme.new()
	t.default_font = font()
	t.default_font_size = 17
	t.set_color("font_color", "Label", TEXT)
	t.set_color("font_shadow_color", "Label", Color(0, 0, 0, 0.35))
	t.set_constant("shadow_offset_y", "Label", 2)
	t.set_stylebox("panel", "PanelContainer", box(PANEL, 18, 18))
	t.set_stylebox("panel", "Panel", box(PANEL, 18, 18))
	# buttons
	t.set_stylebox("normal", "Button", box(PANEL_LIGHT, 10, 16))
	t.set_stylebox("hover", "Button", box(Color(1, 1, 1, 0.22), 10, 16))
	t.set_stylebox("pressed", "Button", box(ACCENT, 10, 16))
	t.set_stylebox("focus", "Button", box(Color(0, 0, 0, 0), 10, 16, ACCENT, 2))
	t.set_stylebox("disabled", "Button", box(Color(1, 1, 1, 0.05), 10, 16))
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_hover_color", "Button", TEXT)
	t.set_color("font_pressed_color", "Button", NAVY)
	t.set_color("font_focus_color", "Button", TEXT)
	t.set_color("font_hover_pressed_color", "Button", NAVY)
	t.set_stylebox("hover_pressed", "Button", box(ACCENT, 10, 16))
	# option / check / spin / line edit
	for c in ["OptionButton", "LineEdit", "SpinBox"]:
		t.set_stylebox("normal", c, box(Color(1, 1, 1, 0.12), 8, 10))
		t.set_stylebox("hover", c, box(Color(1, 1, 1, 0.2), 8, 10))
		t.set_stylebox("focus", c, box(Color(0, 0, 0, 0), 8, 10, ACCENT, 2))
		t.set_stylebox("pressed", c, box(Color(1, 1, 1, 0.25), 8, 10))
		t.set_color("font_color", c, TEXT)
	t.set_stylebox("read_only", "LineEdit", box(Color(1, 1, 1, 0.06), 8, 10))
	t.set_color("font_color", "CheckButton", TEXT)
	t.set_color("font_hover_color", "CheckButton", TEXT)
	t.set_color("font_pressed_color", "CheckButton", TEXT)
	t.set_color("font_hover_pressed_color", "CheckButton", TEXT)
	t.set_color("font_focus_color", "CheckButton", TEXT)
	for st in ["normal", "hover", "pressed", "hover_pressed"]:
		t.set_stylebox(st, "CheckButton", box(Color(0, 0, 0, 0), 8, 6))
	t.set_stylebox("focus", "CheckButton", box(Color(0, 0, 0, 0), 8, 6, ACCENT, 2))
	# sliders
	var groove := box(Color(1, 1, 1, 0.18), 4, 0); groove.content_margin_top = 3; groove.content_margin_bottom = 3
	var fill := box(ACCENT, 4, 0); fill.content_margin_top = 3; fill.content_margin_bottom = 3
	t.set_stylebox("slider", "HSlider", groove)
	t.set_stylebox("grabber_area", "HSlider", fill)
	t.set_stylebox("grabber_area_highlight", "HSlider", fill)
	# tabs
	t.set_stylebox("tab_selected", "TabContainer", box(ACCENT, 10, 16))
	t.set_stylebox("tab_unselected", "TabContainer", box(PANEL_LIGHT, 10, 16))
	t.set_stylebox("tab_hovered", "TabContainer", box(Color(1, 1, 1, 0.22), 10, 16))
	t.set_stylebox("tab_focus", "TabContainer", box(Color(0, 0, 0, 0), 10, 16, ACCENT, 2))
	t.set_stylebox("panel", "TabContainer", box(Color(0, 0, 0, 0), 0, 4))
	t.set_color("font_selected_color", "TabContainer", NAVY)
	t.set_color("font_unselected_color", "TabContainer", TEXT)
	t.set_color("font_hovered_color", "TabContainer", TEXT)
	t.set_constant("side_margin", "TabContainer", 0)
	# popup menus (option buttons)
	t.set_stylebox("panel", "PopupMenu", box(Color(0.08, 0.14, 0.19, 0.97), 10, 8))
	t.set_stylebox("hover", "PopupMenu", box(ACCENT, 6, 8))
	t.set_color("font_color", "PopupMenu", TEXT)
	t.set_color("font_hover_color", "PopupMenu", NAVY)
	t.set_stylebox("panel", "TooltipPanel", box(Color(0.06, 0.1, 0.14, 0.95), 8, 8))
	t.set_color("font_color", "TooltipLabel", TEXT)
	# scrollbars
	t.set_stylebox("scroll", "VScrollBar", box(Color(1, 1, 1, 0.06), 4, 2))
	t.set_stylebox("grabber", "VScrollBar", box(Color(1, 1, 1, 0.3), 4, 2))
	t.set_stylebox("grabber_highlight", "VScrollBar", box(Color(1, 1, 1, 0.45), 4, 2))
	t.set_stylebox("grabber_pressed", "VScrollBar", box(ACCENT, 4, 2))
	_theme = t
	return t

static func label(text: String, size := 17, color := TEXT, black := false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if black: l.add_theme_font_override("font", font(true))
	return l

static func button(text: String, cb: Callable, size := 19) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", size)
	b.pressed.connect(cb)
	b.custom_minimum_size = Vector2(0, 44)
	return b


## Keep a panel centred on screen whatever its size (grows out from the middle).
static func centre(c: Control) -> void:
	c.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	c.grow_horizontal = Control.GROW_DIRECTION_BOTH
	c.grow_vertical = Control.GROW_DIRECTION_BOTH
