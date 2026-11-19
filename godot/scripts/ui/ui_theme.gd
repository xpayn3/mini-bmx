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

static var _lcd: Font

## dot-matrix LCD type for the bike computer: Doto (OFL, assets/fonts/), heavy round dots;
## glyphs Doto lacks (°, …) fall back to the UI font
static func lcd_font() -> Font:
	if _lcd == null:
		var ff: FontFile = load("res://assets/fonts/Doto.ttf")
		var ts := TextServerManager.get_primary_interface()
		var v := FontVariation.new()
		v.base_font = ff
		v.variation_opentype = {ts.name_to_tag("wght"): 900, ts.name_to_tag("ROND"): 100}
		v.fallbacks = [font(true)]
		_lcd = v
	return _lcd

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

# ---------------------------------------------------------------- light (white, opaque) window theme
# Used by the Settings / Controls windows (MenuBase): a solid white card, ink text, yellow accent.
const L_INK := Color("151a23")
const L_MUTED := Color("6b7487")
const L_PAGE := Color("f3f5f9")
const L_LINE := Color("d3d9e4")
const L_BTN := Color("e7eaf1")
const L_BTN_HOT := Color("d6dce8")

static var _light: Theme

static func _blend(img: Image, x: int, y: int, c: Color, cov: float) -> void:
	if cov <= 0.0: return
	var o := img.get_pixel(x, y)
	var a := c.a * cov
	var oa := o.a * (1.0 - a)
	var na := a + oa
	if na <= 0.0: return
	var rgb := (Vector3(c.r, c.g, c.b) * a + Vector3(o.r, o.g, o.b) * oa) / na
	img.set_pixel(x, y, Color(rgb.x, rgb.y, rgb.z, na))

static func _disc(img: Image, cx: float, cy: float, r: float, fill: Color, ring: Color, ring_w: float) -> void:
	for y in img.get_height():
		for x in img.get_width():
			var d := Vector2(x + 0.5 - cx, y + 0.5 - cy).length()
			var outer := clampf(r - d + 0.5, 0.0, 1.0)
			if outer <= 0.0: continue
			var inner := clampf(r - ring_w - d + 0.5, 0.0, 1.0) if ring_w > 0.0 else 1.0
			_blend(img, x, y, ring.lerp(fill, inner) if ring_w > 0.0 else fill, outer)

static func tex_disc(d: int, fill: Color, ring: Color, ring_w: float) -> ImageTexture:
	var img := Image.create_empty(d, d, false, Image.FORMAT_RGBA8)
	_disc(img, d * 0.5, d * 0.5, d * 0.5, fill, ring, ring_w)
	return ImageTexture.create_from_image(img)

static func tex_toggle(on: bool) -> ImageTexture:
	var w := 46; var h := 26
	var img := Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
	var track := L_INK if on else Color("c6cdda")
	for y in h:
		for x in w:
			var px := clampf(x + 0.5, 13.0, 33.0)
			var d := Vector2(x + 0.5 - px, y + 0.5 - 13.0).length()
			_blend(img, x, y, track, clampf(13.0 - d + 0.5, 0.0, 1.0))
	_disc(img, 33.0 if on else 13.0, 13.0, 9.0, ACCENT if on else Color.WHITE, Color.WHITE, 0.0)
	return ImageTexture.create_from_image(img)

static func tex_chevron(col: Color) -> ImageTexture:
	var img := Image.create_empty(14, 14, false, Image.FORMAT_RGBA8)
	var pts := [Vector2(2.5, 4.5), Vector2(7, 9.5), Vector2(11.5, 4.5)]
	for y in 14:
		for x in 14:
			var p := Vector2(x + 0.5, y + 0.5)
			var d := minf(_seg_dist(p, pts[0], pts[1]), _seg_dist(p, pts[1], pts[2]))
			_blend(img, x, y, col, clampf(1.0 - d + 0.5, 0.0, 1.0))
	return ImageTexture.create_from_image(img)

static func _seg_dist(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var t := clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
	return p.distance_to(a + ab * t)

static func light_theme() -> Theme:
	if _light: return _light
	var t := Theme.new()
	t.default_font = font()
	t.default_font_size = 17
	t.set_color("font_color", "Label", L_INK)
	t.set_color("font_shadow_color", "Label", Color(0, 0, 0, 0))
	t.set_constant("shadow_offset_y", "Label", 0)
	t.set_stylebox("panel", "PanelContainer", box(Color.WHITE, 22, 22, L_INK, 3))
	# buttons
	t.set_stylebox("normal", "Button", box(L_BTN, 10, 16))
	t.set_stylebox("hover", "Button", box(L_BTN_HOT, 10, 16))
	t.set_stylebox("pressed", "Button", box(ACCENT, 10, 16, L_INK, 2))
	t.set_stylebox("hover_pressed", "Button", box(ACCENT, 10, 16, L_INK, 2))
	t.set_stylebox("focus", "Button", box(Color(0, 0, 0, 0), 10, 16, L_INK, 2))
	t.set_stylebox("disabled", "Button", box(Color("f0f2f6"), 10, 16))
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
		t.set_color(c, "Button", L_INK)
	t.set_color("font_disabled_color", "Button", Color("a4acbb"))
	# fields
	for c in ["OptionButton", "LineEdit", "SpinBox"]:
		t.set_stylebox("normal", c, box(Color.WHITE, 10, 12, L_LINE, 2))
		t.set_stylebox("hover", c, box(Color.WHITE, 10, 12, L_INK, 2))
		t.set_stylebox("pressed", c, box(Color("fff6cf"), 10, 12, L_INK, 2))
		t.set_stylebox("focus", c, box(Color(0, 0, 0, 0), 10, 12, L_INK, 2))
		for fc in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
			t.set_color(fc, c, L_INK)
	t.set_stylebox("read_only", "LineEdit", box(L_PAGE, 10, 12, L_LINE, 2))
	t.set_icon("arrow", "OptionButton", tex_chevron(L_INK))
	t.set_constant("arrow_margin", "OptionButton", 8)
	# toggles
	for st in ["normal", "hover", "pressed", "hover_pressed"]:
		t.set_stylebox(st, "CheckButton", box(Color(0, 0, 0, 0), 8, 6))
	t.set_stylebox("focus", "CheckButton", box(Color(0, 0, 0, 0), 8, 6, L_INK, 2))
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
		t.set_color(c, "CheckButton", L_INK)
	var on := tex_toggle(true); var off := tex_toggle(false)
	for n in ["checked", "checked_mirrored", "checked_disabled", "checked_disabled_mirrored"]: t.set_icon(n, "CheckButton", on)
	for n in ["unchecked", "unchecked_mirrored", "unchecked_disabled", "unchecked_disabled_mirrored"]: t.set_icon(n, "CheckButton", off)
	# sliders
	var groove := box(Color("d9dee8"), 4, 0); groove.content_margin_top = 4; groove.content_margin_bottom = 4
	var fill := box(ACCENT, 4, 0); fill.content_margin_top = 4; fill.content_margin_bottom = 4
	t.set_stylebox("slider", "HSlider", groove)
	t.set_stylebox("grabber_area", "HSlider", fill)
	t.set_stylebox("grabber_area_highlight", "HSlider", fill)
	var g := tex_disc(24, ACCENT, L_INK, 3.5)
	for n in ["grabber", "grabber_highlight", "grabber_disabled"]: t.set_icon(n, "HSlider", g)
	# tabs: pills; the open one is yellow with an ink outline
	t.set_stylebox("tab_selected", "TabContainer", box(ACCENT, 12, 18, L_INK, 2))
	t.set_stylebox("tab_unselected", "TabContainer", box(L_BTN, 12, 18, Color(0, 0, 0, 0), 2))
	t.set_stylebox("tab_hovered", "TabContainer", box(L_BTN_HOT, 12, 18, Color(0, 0, 0, 0), 2))
	t.set_stylebox("tab_focus", "TabContainer", box(Color(0, 0, 0, 0), 12, 18, L_INK, 2))
	t.set_stylebox("panel", "TabContainer", box(L_PAGE, 16, 14))
	for c in ["font_selected_color", "font_unselected_color", "font_hovered_color"]:
		t.set_color(c, "TabContainer", L_INK)
	t.set_constant("side_margin", "TabContainer", 0)
	t.set_font("font", "TabContainer", font(true))
	t.set_font_size("font_size", "TabContainer", 16)
	# popups (option lists, the pad remap menu)
	t.set_stylebox("panel", "PopupMenu", box(Color.WHITE, 12, 8, L_LINE, 2))
	t.set_stylebox("hover", "PopupMenu", box(ACCENT, 8, 8))
	t.set_color("font_color", "PopupMenu", L_INK)
	t.set_color("font_hover_color", "PopupMenu", L_INK)
	t.set_constant("v_separation", "PopupMenu", 6)
	var rc := tex_disc(16, ACCENT, L_INK, 3.0); var ru := tex_disc(16, Color.WHITE, L_LINE, 2.0)
	t.set_icon("radio_checked", "PopupMenu", rc); t.set_icon("checked", "PopupMenu", rc)
	t.set_icon("radio_unchecked", "PopupMenu", ru); t.set_icon("unchecked", "PopupMenu", ru)
	t.set_stylebox("panel", "TooltipPanel", box(L_INK, 8, 8))
	t.set_color("font_color", "TooltipLabel", Color.WHITE)
	# scrollbars
	t.set_stylebox("scroll", "VScrollBar", box(Color("e3e7ef"), 5, 3))
	t.set_stylebox("grabber", "VScrollBar", box(Color("a9b1c2"), 5, 3))
	t.set_stylebox("grabber_highlight", "VScrollBar", box(Color("7d879b"), 5, 3))
	t.set_stylebox("grabber_pressed", "VScrollBar", box(L_INK, 5, 3))
	_light = t
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


## a small ✕ for a panel's title row
static func close_button(cb: Callable) -> Button:
	var b := button("✕", cb, 15)
	b.custom_minimum_size = Vector2(34, 30)
	b.focus_mode = Control.FOCUS_NONE
	b.tooltip_text = "Close"
	return b


## a small ↺ next to a slider: puts it back to its default (and fires value_changed like a drag would)
static func reset_button(s: Range, default_value: float, muted := MUTED, hot := ACCENT) -> Button:
	var b := Button.new()
	b.text = "↺"
	b.flat = true
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 15)
	b.add_theme_color_override("font_color", muted)
	b.add_theme_color_override("font_hover_color", hot)
	if s != null: bind_reset(b, s, default_value)
	return b

static func bind_reset(b: Button, s: Range, default_value: float) -> void:
	b.tooltip_text = "Reset to default (%s)" % str(snappedf(default_value, 0.0001))
	b.pressed.connect(func(): s.value = default_value)


## Keep a panel centred on screen whatever its size (grows out from the middle).
static func centre(c: Control) -> void:
	c.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	c.grow_horizontal = Control.GROW_DIRECTION_BOTH
	c.grow_vertical = Control.GROW_DIRECTION_BOTH
